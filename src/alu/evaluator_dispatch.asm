; =============================================================================
; Module: src/alu/evaluator_dispatch.asm
; Project: La Roca Rules Engine
; Responsibility: Safely dispatch operands to the correct ALU with micro-tracing.
; =============================================================================

section .data
    log_alu_math   db "[DEBUG] [Evaluator] Dispatching to Math ALU...", 0x0A, 0
    log_dbg_pop    db "[DEBUG] [Evaluator] Popping Op1 from VM Stack...", 0x0A, 0
    log_dbg_call   db "[DEBUG] [Evaluator] Jumping into eval_math_op...", 0x0A, 0
    log_dbg_ret    db "[DEBUG] [Evaluator] Returned successfully from eval_math_op!", 0x0A, 0
    log_alu_str    db "[DEBUG] [Evaluator] Dispatching to String ALU...", 0x0A, 0

section .text
    global execute_math_dispatch
    global execute_string_dispatch

    extern eval_math_op, eval_string_op
    extern internal_stack_pop
    extern log_internal_str

; -----------------------------------------------------------------------------
; Subroutine: execute_math_dispatch
; -----------------------------------------------------------------------------
execute_math_dispatch:
    push rbp
    mov rbp, rsp

    ; 🛡️ Shield XMM0 (Op2) before logging
    sub rsp, 16
    movsd [rsp], xmm0

    lea rsi, [log_alu_math]
    call log_internal_str

    lea rsi, [log_dbg_pop]
    call log_internal_str

    ; Move Op2 to XMM1
    movsd xmm1, [rsp]
    add rsp, 16

    ; Fetch Op1 to XMM0
    call internal_stack_pop

    ; 🛡️ Shield BOTH Operands before calling the ALU
    sub rsp, 32
    movsd [rsp], xmm0
    movsd [rsp+16], xmm1

    lea rsi, [log_dbg_call]
    call log_internal_str

    movsd xmm0, [rsp]
    movsd xmm1, [rsp+16]
    add rsp, 32

    call eval_math_op

    ; 🛡️ Shield Result (RAX)
    push rax
    push rax
    lea rsi, [log_dbg_ret]
    call log_internal_str
    pop rax
    pop rax

    leave
    ret

; -----------------------------------------------------------------------------
; Subroutine: execute_string_dispatch
; -----------------------------------------------------------------------------
execute_string_dispatch:
    push rbp
    mov rbp, rsp

    push r12
    push r12                ; Shield String Pointer
    lea rsi, [log_alu_str]
    call log_internal_str
    pop r12
    pop r12

    mov r14, r12            ; Op2
    call internal_stack_pop
    movq r12, xmm0          ; Op1
    call eval_string_op

    leave
    ret