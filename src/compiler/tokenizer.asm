; =============================================================================
; Module: src/core/tokenizer.asm (V2.0 - Safety First)
; Project: La Roca Rules Engine
; Responsibility: Detect data types and safely delegate parsing.
; =============================================================================

section .text
    global tokenize_and_store
    extern parse_number, operand_error

; -----------------------------------------------------------------------------
; Function: tokenize_and_store
; In:  RDI = Source string pointer
;      R9  = Target memory slot (VarMap)
; Out: RAX = Status (1=Success/Float, 2=String, 3=Fatal Error)
; -----------------------------------------------------------------------------
tokenize_and_store:
    ; 1. Detect String (Starts with ")
    cmp byte [rdi], '"'
    je .is_string

    ; 2. Check if it's a Number (Starts with 0-9, '-', or '.')
    mov al, [rdi]
    cmp al, '0'
    jl .check_numeric_prefix
    cmp al, '9'
    jle .is_number

.check_numeric_prefix:
    cmp al, '-'
    je .is_number
    cmp al, '.'
    je .is_number

    ; 3. If it's none of the above, it's an UNKNOWN token (like '$')
    ; In a more advanced version, we would check for Variable Names here.
    jmp operand_error       ; Returns RAX=3 and jumps back to the Lexer

.is_number:
    ; Note: We don't set the Tag [r9]=1 yet.
    ; We let parse_number confirm success first.
    call parse_number

    ; If parse_number returned 3 (Fatal), RAX is already 3.
    ; We simply return and let the Lexer/Engine handle the propagation.
    ret

.is_string:
    ; (String logic placeholder - Returns RAX=2)
    mov rax, 2
    ret