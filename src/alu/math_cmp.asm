; =============================================================================
; Module: src/alu/math_cmp.asm
; Responsibility: Float comparisons (>, <, =) with EFLAGS protection.
; =============================================================================

section .data
    log_cmp_in     db "[DEBUG] [ALU/Math] Inside eval_math_op...", 0x0A, 0
    log_cmp_gt     db "[DEBUG] [ALU/Math] Executing GT (>)", 0x0A, 0
    log_cmp_lt     db "[DEBUG] [ALU/Math] Executing LT (<)", 0x0A, 0
    log_cmp_eq     db "[DEBUG] [ALU/Math] Executing EQ (=)", 0x0A, 0

section .text
    global eval_math_op
    extern log_internal_str

eval_math_op:
    ; Shield XMM registers and maintain 16-byte alignment
    sub rsp, 32
    movsd [rsp], xmm0
    movsd [rsp+16], xmm1
    push rbx
    push rbx

    lea rsi, [log_cmp_in]
    call log_internal_str

    pop rbx
    pop rbx
    movsd xmm0, [rsp]
    movsd xmm1, [rsp+16]
    add rsp, 32

    cmp bl, '>'
    je .do_gt
    cmp bl, '<'
    je .do_lt
    cmp bl, '='
    je .do_eq
    mov rax, 2
    ret

.do_gt:
    sub rsp, 8
    lea rsi, [log_cmp_gt]
    call log_internal_str
    add rsp, 8
    ucomisd xmm0, xmm1
    ja .t
    jmp .f

.do_lt:
    sub rsp, 8
    lea rsi, [log_cmp_lt]
    call log_internal_str
    add rsp, 8
    ucomisd xmm0, xmm1
    jb .t
    jmp .f

.do_eq:
    sub rsp, 8
    lea rsi, [log_cmp_eq]
    call log_internal_str
    add rsp, 8
    ucomisd xmm0, xmm1
    je .t
    jmp .f

.t:
    xor rax, rax
    ret
.f:
    mov rax, 1
    ret