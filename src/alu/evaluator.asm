; =============================================================================
; Module: src/alu/evaluator.asm (V7.2.1 - Clean Syntax)
; Project: La Roca Rules Engine
; Responsibility: Orchestrate comparisons. Delegates execution to dispatchers.
; =============================================================================

section .data
    log_rule_start db "[TRACE] [Evaluator] Starting new comparison...", 0x0A, 0
    log_err_type   db "[ERROR] [Evaluator] Type mismatch detected", 0x0A, 0
    log_op1_float  db "[DEBUG] [Evaluator] Op1 resolved as FLOAT", 0x0A, 0
    log_op1_str    db "[DEBUG] [Evaluator] Op1 resolved as STRING", 0x0A, 0
    log_arith_esc  db "[DEBUG] [Evaluator] Arithmetic/Group detected. Escaping.", 0x0A, 0
    log_comp_exec  db "[DEBUG] [Evaluator] Comparison operator found. Resolving Op2...", 0x0A, 0

section .text
    global resolve_comparison

    ; External fetchers and stack managers
    extern get_operand, skip_spaces, internal_stack_push
    extern eval_error, log_internal_str

    ; Handlers from evaluator_dispatch.asm
    extern execute_math_dispatch, execute_string_dispatch

; -----------------------------------------------------------------------------
; Function: resolve_comparison
; -----------------------------------------------------------------------------
resolve_comparison:
    ; 🛡️ ALIGNMENT: 6 pushes + 8 padding = 56 + 8 (Return) = 64 bytes
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8

    lea rsi, [log_rule_start]
    call log_internal_str

    call skip_spaces
    movzx r15, byte [rdi]

    ; --- 1. Fetch Op1 (Implicit or Explicit) ---
    cmp r15b, '>'
    je .implicit_op1
    cmp r15b, '<'
    je .implicit_op1
    cmp r15b, '='
    je .implicit_op1
    cmp r15b, '~'
    je .implicit_op1
    cmp r15b, '^'
    je .implicit_op1

    ; Explicit Op1
    call get_operand        ; RAX = Tag, XMM0 = Float, R12 = String

    ; 🚨 FIX: Intercept errors from operand.asm
    cmp rax, 3              ; 3 = FATAL ERROR
    je .propagate_error

    cmp rax, 2              ; 2 = String
    jne .push_op1
    movq xmm0, r12
.push_op1:
    call internal_stack_push
    mov r13, rax            ; Save Tag

    cmp rax, 1
    je .log_op1_f
    lea rsi, [log_op1_str]
    jmp .do_log_op1
.log_op1_f:
    lea rsi, [log_op1_float]
.do_log_op1:
    call log_internal_str

    call skip_spaces
    movzx r15, byte [rdi]
    jmp .check_escape

.implicit_op1:
    mov r13, 1              ; Math results are always Floats (Tag 1)
    lea rsi, [log_op1_float]
    call log_internal_str

    ; --- 2. Check Operator & Escape Hatch ---
.check_escape:
    cmp r15b, '+'
    je .exit_arith
    cmp r15b, '-'
    je .exit_arith
    cmp r15b, '*'
    je .exit_arith
    cmp r15b, '/'
    je .exit_arith
    cmp r15b, '%'
    je .exit_arith
    cmp r15b, ')'
    je .exit_arith

    cmp r15b, '>'
    je .do_comparison
    cmp r15b, '<'
    je .do_comparison
    cmp r15b, '='
    je .do_comparison
    cmp r15b, '~'
    je .do_comparison
    cmp r15b, '^'
    je .do_comparison

    jmp .exit_arith

    ; --- 3. Resolve Op2 and Dispatch ---
.do_comparison:
    inc rdi                 ; Skip operator
    lea rsi, [log_comp_exec]
    call log_internal_str

    push r15
    push r15                ; Shield Operator
    call skip_spaces
    call get_operand
    pop r15
    pop r15

    ; 🚨 FIX: Intercept errors from Op2
    cmp rax, 3
    je .propagate_error

    mov rbx, r15            ; Store Operator into RBX

    cmp r13, rax
    jne .type_error

    cmp rax, 1
    je .dispatch_math

.dispatch_string:
    call execute_string_dispatch
    jmp .done

.dispatch_math:
    call execute_math_dispatch
    jmp .done

.type_error:
    lea rsi, [log_err_type]
    call log_internal_str
    ; 🚨 FIX: Cleanly propagate instead of jumping to eval_error
    jmp .propagate_error

.exit_arith:
    lea rsi, [log_arith_esc]
    call log_internal_str
    xor rax, rax
    jmp .done

; --- 🚨 NEW ESCAPE BLOCK ---
.propagate_error:
    mov rax, 3              ; Keep error code at 3

.done:
    add rsp, 8              ; Remove alignment padding
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret