; =============================================================================
; Module: src/compiler/lexer.asm (V7.11 - JIT-Free Exit)
; Project: La Roca Rules Engine
; Responsibility: Orchestrate parsing. JIT Finalization moved to Engine.
; =============================================================================

section .data
    global is_compiling
    global lexer_panic_abort
    is_compiling db 0

    log_lex_start  db "[TRACE] [Lexer] Starting expression evaluation...", 0x0A, 0
    log_lex_res    db "[DEBUG] [Lexer] Evaluator returned. Updating logic stack...", 0x0A, 0
    log_lex_loop   db "[DEBUG] [Lexer] Logic stack updated. Jumping to next loop...", 0x0A, 0
    log_lex_done   db "[DEBUG] [Lexer] End of string reached. Finalizing logic...", 0x0A, 0
    log_lex_finish db "[DEBUG] [Lexer] Expression evaluated completely!", 0x0A, 0
    log_lex_panic  db "[FATAL] [Lexer] Evaluator panic detected! Aborting loop...", 0x0A, 0

    ; 🚨 NEW LOG: For debugging dangling math coercion
    log_lex_coerce db "[DEBUG] [Lexer] Coercing dangling math result to Boolean...", 0x0A, 0

    ; Diagnostic Micro-Logs
    dbg_rem_1 db "[DEBUG] [Lexer] -> About to resolve: [", 0
    dbg_rem_2 db "]", 0x0A, 0

section .text
    global evaluate_expression
    global lexer_main_loop

    ; Logic Stack Externs
    extern stack_init, stack_pop_level, resolve_comparison, stack_update_result

    ; Math/VM Externs
    extern math_stack_reset
    extern vm_stack_ptr, vm_data_stack   ; Access to VM Data Stack

    ; Handler Externs
    extern handle_math, handle_now, handle_and, handle_or
    extern handle_open_paren, handle_close_paren, handle_math_minus

    ; Utility Externs
    extern log_internal_str

; -----------------------------------------------------------------------------
; Function: evaluate_expression
; -----------------------------------------------------------------------------
evaluate_expression:
    push rbx
    push r12
    push rbp

    lea rsi, [log_lex_start]
    call log_internal_str

    call stack_init
    call math_stack_reset

lexer_main_loop:
    mov al, [rdi]

    test al, al
    jz .done
    cmp al, 0x0A            ; '\n'
    je .done
    cmp al, 0x0D            ; '\r'
    je .skip_char
    cmp al, ' '
    je .skip_char

    ; --- Dispatch Table ---
    cmp al, '('
    je handle_open_paren
    cmp al, ')'
    je handle_close_paren
    cmp al, '+'
    je handle_math
    cmp al, '-'
    je handle_math_minus
    cmp al, '*'
    je handle_math
    cmp al, '/'
    je handle_math
    cmp al, '%'
    je handle_math

    ; Keywords
    mov eax, [rdi]
    and eax, 0x00FFFFFF
    cmp eax, 'NOW'
    je handle_now

    cmp dword [rdi], 'AND '
    je handle_and
    cmp word [rdi], 'OR'
    je handle_or

    ; --- Default Case: Comparison or Literals ---
    push rdi
    lea rsi, [dbg_rem_1]
    call log_internal_str
    pop rdi

    push rdi
    mov rsi, rdi
    call log_internal_str
    pop rdi

    lea rsi, [dbg_rem_2]
    call log_internal_str

    call resolve_comparison

    cmp rax, 3
    je lexer_panic_abort

    push rdi
    push rax
    call stack_update_result
    pop rax
    pop rdi

    jmp lexer_main_loop

.skip_char:
    inc rdi
    jmp lexer_main_loop

; -----------------------------------------------------------------------------
; EXIT SEQUENCE: Finalize and Clean RAX
; -----------------------------------------------------------------------------
.done:
    lea rsi, [log_lex_done]
    call log_internal_str

    ; 🚨 TRUTHINESS COERCION FOR STANDALONE MATH
    ; If the rule is just "10 - 10", the result (0.0) is dangling on the VM stack.
    ; We must pop it and coerce it to a boolean before finalizing.
    mov rcx, [vm_stack_ptr]
    lea rdx, [vm_data_stack]
    cmp rcx, rdx
    je .math_empty

    ; Stack is not empty! Log and Coerce the top value.
    push rdi
    lea rsi, [log_lex_coerce]
    call log_internal_str
    pop rdi

    ; Pop the dangling float
    mov rcx, [vm_stack_ptr]
    sub rcx, 8
    movsd xmm0, [rcx]
    mov [vm_stack_ptr], rcx

    ; Evaluate Truthiness (0.0 == False)
    pxor xmm1, xmm1
    ucomisd xmm0, xmm1
    je .math_is_false
    mov rax, 0              ; True (0)
    jmp .apply_truth
.math_is_false:
    mov rax, 1              ; False (1)
.apply_truth:
    ; Apply this coerced boolean to the logic stack
    push rdi
    push rax
    call stack_update_result
    pop rax
    pop rdi

.math_empty:
    ; 🚨 FIX: JIT Finalization completely removed from here!
    ; Engine.asm handles `finalize_compilation` now.

    ; CAPTURE FINAL RESULT
    call stack_pop_level
    movzx rax, al

    ; Log finish
    push rax
    push rax
    lea rsi, [log_lex_finish]
    call log_internal_str
    pop rax
    pop rax

    pop rbp
    pop r12
    pop rbx
    ret

lexer_panic_abort:
    lea rsi, [log_lex_panic]
    call log_internal_str
    call stack_pop_level
    mov rax, 3
    pop rbp
    pop r12
    pop rbx
    ret