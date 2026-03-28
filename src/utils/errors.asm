; =============================================================================
; Module: src/utils/errors.asm (V4.1 - The Magic Number 3)
; Project: La Roca Rules Engine
; Responsibility: Flag an error state and return to caller gracefully.
; =============================================================================

section .data
    log_panic db "[FATAL] Operand Error: Aborting current evaluation...", 0x0A, 0

section .text
    global eval_error
    global operand_error
    extern log_internal_str

; -----------------------------------------------------------------------------
; Function: eval_error / operand_error
; Responsibility: Flag an error state (RAX=3) and return to caller gracefully.
; -----------------------------------------------------------------------------
eval_error:
operand_error:
    lea rsi, [log_panic]
    call log_internal_str

    ; 🚨 THE FIX: Return 3 (Fatal Error) instead of 2 (String Tag)
    ; This ensures the Evaluator knows the engine is panicking.
    mov rax, 3

    ; We return normally to whoever called us (operand.asm, etc.)
    ; They will see RAX=3 and start the clean propagation upwards.
    ret