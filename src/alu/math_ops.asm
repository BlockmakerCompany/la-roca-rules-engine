; =============================================================================
; Module: src/alu/math_ops.asm
; Responsibility: SSE2 Arithmetic Operations (+, -, *, /, %).
; =============================================================================

section .data
    log_math_op    db "[DEBUG] [ALU/Math] Executing operation: ", 0
    log_math_val   db "[DEBUG] [ALU/Math] Popped values for operation", 0x0A, 0

section .text
    global do_math_operation
    extern internal_stack_push, internal_stack_pop
    extern log_internal_str, log_msg_with_char

; -----------------------------------------------------------------------------
; Function: do_math_operation
; In: RSI = Operator char
; -----------------------------------------------------------------------------
do_math_operation:
    push rbp
    mov rbp, rsp
    push rsi                ; Save operator char for logging

    ; 1. Log the operation
    lea rsi, [log_math_op]
    mov al, [rsp]           ; Get operator char back from stack
    call log_msg_with_char

    ; 2. Pop operands (B first, then A)
    call internal_stack_pop
    movsd xmm1, xmm0        ; Value B
    call internal_stack_pop ; Value A

    lea rsi, [log_math_val]
    call log_internal_str

    ; 3. Dispatch based on operator
    pop rsi                 ; Restore operator char into RSI

    cmp sil, '+'
    je .add
    cmp sil, '-'
    je .sub
    cmp sil, '*'
    je .mul
    cmp sil, '/'
    je .div
    cmp sil, '%'
    je .mod
    jmp .done

.add:
    addsd xmm0, xmm1
    jmp .push_res

.sub:
    subsd xmm0, xmm1
    jmp .push_res

.mul:
    mulsd xmm0, xmm1
    jmp .push_res

.div:
    divsd xmm0, xmm1
    jmp .push_res

.mod:
    ; A % B = A - (trunc(A/B) * B)
    movsd xmm2, xmm0        ; Keep original A in XMM2
    divsd xmm0, xmm1        ; A / B
    cvttsd2si rax, xmm0     ; Truncate to integer
    cvtsi2sd xmm0, rax      ; Back to float
    mulsd xmm0, xmm1        ; result * B
    subsd xmm2, xmm0        ; A - result
    movsd xmm0, xmm2
    jmp .push_res

.push_res:
    call internal_stack_push

.done:
    leave
    ret