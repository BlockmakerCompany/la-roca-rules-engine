; =============================================================================
; Module: src/compiler/lexer_math.asm (V9.5 - Absolute Pointer Protection)
; Project: La Roca Rules Engine
; Responsibility: Handle arithmetic tokens (+, -, *, /, %) with Hybrid Mode.
;                 Returns RAW Float64 to allow nested comparisons.
; =============================================================================

section .text
    global handle_math, handle_math_minus

    ; Core Lexer/Parser Externs
    extern lexer_main_loop
    extern lexer_panic_abort, resolve_comparison, stack_update_result
    extern get_operand, skip_spaces, do_math_operation, internal_stack_push
    extern is_compiling

    ; JIT Emitter Externs
    extern emit_math, emit_push_var, emit_push_const

; -----------------------------------------------------------------------------
; Handler: Math Operations (+, -, *, /, %)
; -----------------------------------------------------------------------------
handle_math:
    inc rdi                 ; Advance past the operator

    ; 🛡️ CONTEXT GUARD: Save RBX but ALLOW RDI TO MUTATE initially
    push rbx                ; -8 bytes
    movzx rbx, al           ; Store operator char (e.g., '+')
    sub rsp, 8              ; -16 bytes (Aligned for calls)

    ; --- 1. Fetch Right-hand Operand ---
    call skip_spaces
    call get_operand        ; RAX=Type, XMM0=Value, R12=Hash
                            ; 🚨 RDI IS ADVANCED HERE!

    cmp rax, 3              ; Check for Parser Panic
    je .panic_restore

    ; 🛡️ ABSOLUTE POINTER PROTECTION
    ; External calls (emit, do_math_operation) WILL clobber RDI (Volatile).
    ; We MUST save the advanced RDI now so we don't lose our place in the rule!
    push rdi                ; -24 bytes
    sub rsp, 8              ; -32 bytes (Aligned)

    ; --- 2. JIT PATH (Optional) ---
    cmp byte [is_compiling], 1
    jne .interpreter_path

    ; Preserve registers for the bytecode emitter
    push rax                ; -40
    push rbx                ; -48

    cmp rax, 2              ; Is it a Variable?
    jne .jit_const
    mov rax, r12            ; Use variable hash
    call emit_push_var
    jmp .jit_op
.jit_const:
    call emit_push_const    ; Use raw value in XMM0
.jit_op:
    mov rax, rbx            ; Pass operator char to AL
    call emit_math

    pop rbx                 ; -40
    pop rax                 ; -32

; --- 3. INTERPRETER PATH (Always executed during first-run) ---
.interpreter_path:
    ; A. Push operand to the VM Data Stack
    cmp rax, 2
    jne .push_val
    movq xmm0, r12          ; Load Variable Hash into XMM0 for the stack
.push_val:
    call internal_stack_push

    ; B. Execute Math ALU
    mov rsi, rbx
    mov rdi, rbx            ; Safety: pass operator to both RSI and RDI
    call do_math_operation  ; Result is returned in XMM0

    ; C. CRITICAL FIX: Push RAW result back to the Data Stack
    call internal_stack_push

    ; --- CLEAN EXIT ---
    add rsp, 8              ; Undo alignment (-24)
    pop rdi                 ; 🚨 RESTORE THE ADVANCED POINTER! (-16)

    add rsp, 8              ; Undo alignment (-8)
    pop rbx                 ; Restore original RBX (0)
    jmp lexer_main_loop

.panic_restore:
    ; Note: RDI wasn't pushed yet if we panic here!
    add rsp, 8
    pop rbx
    jmp lexer_panic_abort

; -----------------------------------------------------------------------------
; Handler: Minus Sign (Ambiguity: Subtraction vs Negative Literal)
; -----------------------------------------------------------------------------
handle_math_minus:
    cmp byte [rdi+1], ' '   ; Check for " - " (operator) vs "-5" (literal)
    je handle_math

    ; It is a negative literal: let the primary evaluator resolve it
    call resolve_comparison
    cmp rax, 3
    je lexer_panic_abort

    ; Since literals change the state, update the logic stack for standalone math
    push rdi
    push rax                ; Save RAX and maintain 16-byte alignment
    call stack_update_result
    pop rax
    pop rdi

    jmp lexer_main_loop