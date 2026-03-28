; =============================================================================
; Module: src/compiler/lexer_logic.asm (V7.7 - JIT Bailout)
; Project: La Roca Rules Engine
; Responsibility: Handle logic tokens and trigger Hybrid Fallback.
; =============================================================================

section .data
    log_lex_paren db "[DEBUG] [Lexer] Handling Parentheses: ", 0

section .text
    global handle_open_paren, handle_close_paren, handle_and, handle_or

    extern lexer_main_loop, log_msg_with_char
    extern stack_push_level, stack_pop_level, stack_update_result, stack_set_operator
    extern is_compiling

; -----------------------------------------------------------------------------
; Handler: Open Parenthesis '('
; -----------------------------------------------------------------------------
handle_open_paren:
    inc rdi
    push rdi
    sub rsp, 8

    lea rsi, [log_lex_paren]
    mov al, '('
    call log_msg_with_char

    call stack_push_level

    add rsp, 8
    pop rdi
    jmp lexer_main_loop

; -----------------------------------------------------------------------------
; Handler: Close Parenthesis ')'
; -----------------------------------------------------------------------------
handle_close_paren:
    inc rdi
    push rdi
    sub rsp, 8

    lea rsi, [log_lex_paren]
    mov al, ')'
    call log_msg_with_char

    call stack_pop_level
    movzx rax, al
    call stack_update_result

    add rsp, 8
    pop rdi
    jmp lexer_main_loop

; -----------------------------------------------------------------------------
; Handler: Logical AND
; -----------------------------------------------------------------------------
handle_and:
    add rdi, 4              ; Skip "AND "
    push rdi
    sub rsp, 8

    ; 🚨 HYBRID ENGINE BAILOUT
    ; Logic gates require deferred execution (Infix to Postfix).
    ; We instruct the engine to abort JIT and fall back to the Interpreter.
    mov byte [is_compiling], 0

    mov rsi, 0              ; AND operator
    call stack_set_operator

    add rsp, 8
    pop rdi
    jmp lexer_main_loop

; -----------------------------------------------------------------------------
; Handler: Logical OR
; -----------------------------------------------------------------------------
handle_or:
    add rdi, 3              ; Skip "OR "
    push rdi
    sub rsp, 8

    ; 🚨 HYBRID ENGINE BAILOUT
    mov byte [is_compiling], 0

    mov rsi, 1              ; OR operator
    call stack_set_operator

    add rsp, 8
    pop rdi
    jmp lexer_main_loop