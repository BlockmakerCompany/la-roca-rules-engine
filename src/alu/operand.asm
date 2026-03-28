; =============================================================================
; Module: src/alu/operand.asm (V6.2 - Panic Proof)
; Project: La Roca Rules Engine
; Responsibility: Extract values from context or literals (Numbers, Strings, #).
; =============================================================================

section .data
    ; Error messages for the internal logger
    log_err_var    db "[ERROR] [Operand] Variable lookup failed or undefined", 0x0A, 0
    log_err_type   db "[ERROR] [Operand] Length operator '#' requires a string", 0x0A, 0

section .text
    global get_operand
    global skip_spaces

    ; External Utilities from the Engine and Compiler layers
    extern var_map, hash_token_8, parse_and_store_value, eval_error
    extern log_internal_str

; -----------------------------------------------------------------------------
; Function: skip_spaces
; In:  RDI = String pointer
; Out: RDI = First non-space character pointer
; -----------------------------------------------------------------------------
skip_spaces:
    cmp byte [rdi], ' '
    jne .done
    inc rdi
    jmp skip_spaces
.done:
    ret

; -----------------------------------------------------------------------------
; Function: get_operand
; Responsibility: Resolves a token into a Float (XMM0) or String (R12).
; In:  RDI = Pointer to token start.
; Out: RAX = Status/Tag (1: Float, 2: String, 3: Fatal Error).
; -----------------------------------------------------------------------------
get_operand:
    ; 🛡️ Establish stack frame (keeps stack 16-byte aligned for sub-calls)
    push rbp
    mov rbp, rsp

    mov al, [rdi]
    test al, al
    jz .var_error           ; Abort if string is empty

    ; --- 1. Detect Literal Type ---
    cmp al, '"'
    je .is_literal_str      ; Starts with quote: String Literal
    cmp al, '-'
    je .is_literal_num      ; Starts with minus: Negative Number
    cmp al, '#'
    je .is_length_op        ; Starts with hash: Length Operator

    ; --- 2. Check if it's a Numeric Digit ---
    cmp al, '0'
    jl .check_var           ; If < '0', it might be a variable name
    cmp al, '9'
    jle .is_literal_num     ; If between '0'-'9', it's a positive number

.check_var:
    ; --- 3. Resolve Variable from VarMap ---
    call hash_token_8       ; RAX = Hash Index, RDI advanced past name
    shl rax, 4              ; Multiply by 16 (size of VarMap slot)
    lea rdx, [var_map + rax]

    mov rax, [rdx]          ; Load the Tag (0:Empty, 1:Float, 2:String)
    test rax, rax
    jz .var_error           ; Tag 0 means variable doesn't exist

    cmp rax, 1
    je .load_float
    cmp rax, 2
    je .load_string
    jmp .var_error          ; Unknown tag safety check

.load_float:
    movsd xmm0, [rdx + 8]   ; Load 64-bit float into XMM0
    mov rax, 1              ; Ensure RAX returns the Float tag
    jmp .exit

.load_string:
    mov r12, [rdx + 8]      ; Load string pointer into R12
    mov rax, 2              ; Ensure RAX returns the String tag
    jmp .exit

.is_length_op:
    ; --- 4. Resolve '#' Operator (String Length) ---
    inc rdi                 ; Skip the '#' character
    call hash_token_8       ; Resolve the variable name following '#'
    shl rax, 4
    lea rdx, [var_map + rax]

    cmp qword [rdx], 2      ; The variable MUST be a String (Tag 2)
    jne .type_error         ; Otherwise, throw a type error

    mov rcx, [rdx + 8]      ; RCX = Start of the actual string
    xor rax, rax            ; RAX = Length counter
.len_loop:
    cmp byte [rcx + rax], 0 ; Scan for null terminator
    je .len_done
    inc rax
    jmp .len_loop
.len_done:
    cvtsi2sd xmm0, rax      ; Convert integer length to Float64 in XMM0
    mov rax, 1              ; Result of '#' is always a Number
    jmp .exit

.is_literal_num:
    ; --- 5. Parse Number Literal ---
    sub rsp, 16             ; Allocate 16 bytes for local output
    mov r9, rsp             ; R9 = Target for parse_and_store_value
    call parse_and_store_value ; Updates RDI and returns Status in RAX

    cmp rax, 3
    je .literal_err_cleanup ; Propagate panic if parsing failed

    mov rax, 1              ; Explicitly return Float tag
    movsd xmm0, [rsp + 8]   ; Load the parsed result
    add rsp, 16             ; Clean local stack
    jmp .exit

.is_literal_str:
    ; --- 6. Parse String Literal ---
    sub rsp, 16
    mov r9, rsp
    call parse_and_store_value ; Returns RAX=2 or RAX=3

    cmp rax, 3
    je .literal_err_cleanup

    mov rax, 2              ; Explicitly return String tag
    mov r12, [rsp + 8]      ; Load pointer to the parsed string
    add rsp, 16
    jmp .exit

.literal_err_cleanup:
    add rsp, 16             ; Clean stack before propagating error
    jmp .exit               ; RAX is already 3

.exit:
    leave                   ; Clean RBP frame
    ret

; -----------------------------------------------------------------------------
; --- Error Handlers (Clean Return Path) ---
; -----------------------------------------------------------------------------

.var_error:
    lea rsi, [log_err_var]
    call log_internal_str
    call eval_error         ; RAX = 3
    leave                   ; 🛡️ CRITICAL: Clean the RBP before returning!
    ret                     ; Return RAX=3 to the Evaluator safely

.type_error:
    lea rsi, [log_err_type]
    call log_internal_str
    call eval_error         ; RAX = 3
    leave
    ret