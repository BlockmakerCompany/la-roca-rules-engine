; =============================================================================
; Module: src/engine/vm.asm (V2.5 - High-Performance Execution Core)
; Project: La Roca Rules Engine
; Responsibility: Execute 16-byte aligned bytecode plans at maximum speed.
; Format: [OpCode (1b)][Padding (7b)][Data/Argument (8b)]
; =============================================================================

section .bss
    ; Data Stack (32 slots * 8 bytes = 256 bytes)
    ; Used for SSE2 floating point calculations and string pointer staging.
    global vm_data_stack
    vm_data_stack   resq 32

    ; VM Stack Pointer: Points to the current top of vm_data_stack
    global vm_stack_ptr
    vm_stack_ptr    resq 1

section .text
    global vm_execute
    global stack_reset

    ; Logic and Utility Externs
    extern var_map, eval_error, get_now_unix
    extern eval_string_op   ; From src/core/strings.asm

; -----------------------------------------------------------------------------
; Function: stack_reset
; Responsibility: Re-initialize the VM Data Stack pointer.
; -----------------------------------------------------------------------------
stack_reset:
    lea rax, [vm_data_stack]
    mov [vm_stack_ptr], rax
    ret

; -----------------------------------------------------------------------------
; Function: vm_execute
; In: RDI = Pointer to the Bytecode Plan (Start of 16-byte chunks)
; Out: RAX = Boolean Result (0=True, 1=False)
; -----------------------------------------------------------------------------
vm_execute:
    push rbx
    push r12
    push r13                ; Reserved for auxiliary data

    call stack_reset        ; Ensure a clean stack for this execution

.dispatch:
    ; 1. Fetch OpCode
    movzx rbx, byte [rdi]

    ; 2. Check for End of Program (0x00)
    test rbx, rbx
    jz .finalize_execution

    ; 3. Jump Table / Dispatcher
    ; --- Data Loading (0x01 - 0x0F) ---
    cmp rbx, 0x01
    je .op_push_var
    cmp rbx, 0x02
    je .op_push_const
    cmp rbx, 0x04
    je .op_push_now

    ; --- Comparison Operators (0x10 - 0x1F) ---
    cmp rbx, 0x10
    je .op_cmp_gt
    cmp rbx, 0x11
    je .op_cmp_lt
    cmp rbx, 0x12
    je .op_cmp_eq
    cmp rbx, 0x13
    je .op_cmp_string       ; Handle ~, ^ via string ALU

    ; --- Arithmetic Operators (0x30 - 0x3F) ---
    cmp rbx, 0x30
    je .op_add
    cmp rbx, 0x31
    je .op_sub
    cmp rbx, 0x32
    je .op_mul
    cmp rbx, 0x33
    je .op_div
    cmp rbx, 0x34
    je .op_mod

    ; Unknown OpCode: Trigger Panic
    jmp eval_error

; --- 📦 HANDLERS: DATA LOADING ---

.op_push_var:
    mov rax, [rdi + 8]      ; Get Variable Hash from Bytecode
    shl rax, 4              ; Index * 16 (VarMap slot size)
    lea r8, [var_map + rax]
    movsd xmm0, [r8 + 8]    ; Load value (might be Float or String Ptr)
    call .stack_push
    add rdi, 16             ; Next Instruction
    jmp .dispatch

.op_push_const:
    movsd xmm0, [rdi + 8]   ; Load raw Float64 constant
    call .stack_push
    add rdi, 16
    jmp .dispatch

.op_push_now:
    call get_now_unix       ; Get current timestamp
    cvtsi2sd xmm0, rax      ; Convert to double
    call .stack_push
    add rdi, 16
    jmp .dispatch

; --- 🧮 HANDLERS: ARITHMETIC (LIFO Order) ---

.op_add:
    call .stack_pop         ; Pop Right
    movsd xmm1, xmm0
    call .stack_pop         ; Pop Left
    addsd xmm0, xmm1
    call .stack_push        ; Push Result
    add rdi, 16
    jmp .dispatch

.op_sub:
    call .stack_pop
    movsd xmm1, xmm0
    call .stack_pop
    subsd xmm0, xmm1
    call .stack_push
    add rdi, 16
    jmp .dispatch

.op_mul:
    call .stack_pop
    movsd xmm1, xmm0
    call .stack_pop
    mulsd xmm0, xmm1
    call .stack_push
    add rdi, 16
    jmp .dispatch

.op_div:
    call .stack_pop
    movsd xmm1, xmm0
    call .stack_pop
    divsd xmm0, xmm1
    call .stack_push
    add rdi, 16
    jmp .dispatch

.op_mod:
    call .stack_pop
    movsd xmm1, xmm0
    call .stack_pop
    movsd xmm2, xmm0
    divsd xmm0, xmm1
    cvttsd2si rax, xmm0
    cvtsi2sd xmm0, rax
    mulsd xmm0, xmm1
    subsd xmm2, xmm0
    movsd xmm0, xmm2
    call .stack_push
    add rdi, 16
    jmp .dispatch

; --- ⚖️ HANDLERS: COMPARISON & STRINGS ---

.op_cmp_gt:
    call .stack_pop         ; Right
    movsd xmm1, xmm0
    call .stack_pop         ; Left
    ucomisd xmm0, xmm1
    ja .set_true
    jmp .set_false

.op_cmp_lt:
    call .stack_pop
    movsd xmm1, xmm0
    call .stack_pop
    ucomisd xmm0, xmm1
    jb .set_true
    jmp .set_false

.op_cmp_eq:
    call .stack_pop
    movsd xmm1, xmm0
    call .stack_pop
    ucomisd xmm0, xmm1
    je .set_true
    jmp .set_false

.op_cmp_string:
    ; Logic for ~ and ^
    ; Strings are stored as pointers in the stack
    call .stack_pop
    mov r14, [vm_stack_ptr]
    mov r14, [r14]          ; R14 = Op2 (Right)

    call .stack_pop
    mov r12, [vm_stack_ptr]
    mov r12, [r12]          ; R12 = Op1 (Left)

    movzx rbx, byte [rdi]   ; Load operator for string ALU
    call eval_string_op     ; Returns RAX (0=True, 1=False)
    jmp .finalize_from_cmp

.set_true:
    xor rax, rax
    jmp .finalize_from_cmp

.set_false:
    mov rax, 1
    jmp .finalize_from_cmp

; --- 🛠️ STACK HELPERS (Internal) ---

.stack_push:
    mov r8, [vm_stack_ptr]
    movsd [r8], xmm0
    add qword [vm_stack_ptr], 8
    ret

.stack_pop:
    sub qword [vm_stack_ptr], 8
    mov r8, [vm_stack_ptr]
    movsd xmm0, [r8]
    ret

; --- 🏁 TERMINATION ---

.finalize_execution:
    ; Implicit Boolean Coercion: If the program ends without a comparison,
    ; evaluate the truthiness of the last value on stack.
    call .stack_pop
    pxor xmm1, xmm1
    ucomisd xmm0, xmm1
    je .set_false           ; 0.0 is False
    xor rax, rax            ; Non-zero is True

.finalize_from_cmp:
    pop r13
    pop r12
    pop rbx
    ret