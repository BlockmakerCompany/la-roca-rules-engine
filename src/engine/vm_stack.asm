; =============================================================================
; Module: src/engine/vm_stack.asm (V6.2 - Atomic Reset)
; Responsibility: Manage the internal VM data stack and ensure clean resets.
; =============================================================================

section .data
    log_err_stk    db "[CRITICAL] [ALU/Stack] Stack Underflow detected!", 0x0A, 0

section .text
    global internal_stack_push
    global internal_stack_pop
    global math_stack_reset

    ; External variables and functions
    extern vm_stack_ptr, vm_data_stack, eval_error, log_internal_str

; -----------------------------------------------------------------------------
; Function: math_stack_reset
; Responsibility: Hard-reset the VM stack pointer and clear stale data.
; -----------------------------------------------------------------------------
math_stack_reset:
    lea rax, [vm_data_stack]
    mov [vm_stack_ptr], rax

    ; 🛡️ ZERO-OUT: Clear the first slot to prevent stale data leaks
    ; from previous failed requests (like the '$' operator error).
    mov qword [rax], 0
    ret

; -----------------------------------------------------------------------------
; Function: internal_stack_push
; In: XMM0 = Float64 value to push onto the VM stack.
; -----------------------------------------------------------------------------
internal_stack_push:
    mov r8, [vm_stack_ptr]
    movsd [r8], xmm0
    add qword [vm_stack_ptr], 8
    ret

; -----------------------------------------------------------------------------
; Function: internal_stack_pop
; Out: XMM0 = Popped value, RAX = 1 (Success) or 3 (Fatal Error).
; -----------------------------------------------------------------------------
internal_stack_pop:
    lea r8, [vm_data_stack]
    cmp [vm_stack_ptr], r8
    jbe .stack_error        ; If pointer <= base, we have a stack underflow

    sub qword [vm_stack_ptr], 8
    mov r8, [vm_stack_ptr]
    movsd xmm0, [r8]
    mov rax, 1              ; Success status
    ret

.stack_error:
    ; 🛡️ SAFE ERROR PROPAGATION:
    ; Instead of jumping, we call the logger and propagate RAX=3.
    push rsi                ; Save RDI/RSI if necessary for ABI
    lea rsi, [log_err_stk]
    call log_internal_str
    pop rsi

    call eval_error         ; This utility sets RAX to 3
    ret                     ; Return to Evaluator/ALU to handle the panic