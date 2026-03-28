; =============================================================================
; Module: src/utils/utils.asm (V3.0 - Decoupled & Clean)
; Project: La Roca Rules Engine
; Responsibility: Shared logic terminators and payload navigation.
; =============================================================================
extern log_level

section .text
    global eval_true
    global eval_false
    global advance_to_next_rule
    global trace_log

; -----------------------------------------------------------------------------
; Function: trace_log
; Responsibility: Writes to stderr if log_level is set to TRACE (2).
; -----------------------------------------------------------------------------
trace_log:
    push rax
    push rdi
    push rcx                ; Save RCX (Destroyed by syscall)
    push r11                ; Save R11 (Destroyed by syscall)

    cmp byte [log_level], 2
    jne .skip

    mov rax, 1              ; sys_write
    mov rdi, 2              ; stderr
    syscall

.skip:
    pop r11                 ; Restore R11
    pop rcx                 ; Restore RCX
    pop rdi
    pop rax
    ret

; -----------------------------------------------------------------------------
; Function: advance_to_next_rule
; Responsibility: Skips characters until a newline or end of payload is found.
; Out: AL = 1 (More rules found), AL = 0 (End of payload reached)
; -----------------------------------------------------------------------------
advance_to_next_rule:
.loop:
    mov al, [rdi]
    test al, al
    jz .end                 ; Null terminator -> End of payload
    cmp al, 0x0A            ; Newline?
    je .newline
    inc rdi
    jmp .loop
.newline:
    inc rdi
    cmp byte [rdi], 0       ; Is it a trailing newline?
    jz .end
    mov al, 1               ; More rules exist
    ret
.end:
    xor rax, rax            ; No more rules (Return 0)
    ret

; -----------------------------------------------------------------------------
; Result Handlers: Standardize the logic returns for the Engine.
; -----------------------------------------------------------------------------
eval_true:
    xor rax, rax            ; Set RAX = 0 (True)
    ret

eval_false:
    mov rax, 1              ; Set RAX = 1 (False)
    ret