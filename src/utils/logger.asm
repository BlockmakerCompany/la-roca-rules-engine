; =============================================================================
; Module: src/utils/logger.asm
; Responsibility: Low-level logging utilities using direct syscalls.
; =============================================================================

section .text
    global log_internal_str
    global log_internal_char
    global log_msg_with_char

; -----------------------------------------------------------------------------
; Function: log_internal_str (RSI = String Pointer)
; -----------------------------------------------------------------------------
log_internal_str:
    push rdi
    push rdx
    push rax
    mov rdi, rsi
    xor rdx, rdx
.count:
    cmp byte [rdi+rdx], 0
    je .write
    inc rdx
    jmp .count
.write:
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall
    pop rax
    pop rdx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; Function: log_internal_char (AL = Char)
; -----------------------------------------------------------------------------
log_internal_char:
    push rax            ; Put char on stack to get a pointer
    mov rdx, 1          ; length 1
    mov rdi, 1          ; stdout
    mov rsi, rsp        ; buffer is the stack address
    mov rax, 1          ; sys_write
    syscall

    ; Print Newline for readability
    mov byte [rsp], 0x0A
    mov rax, 1
    syscall

    pop rax
    ret

; -----------------------------------------------------------------------------
; Function: log_msg_with_char (RSI = Msg, AL = Char)
; -----------------------------------------------------------------------------
log_msg_with_char:
    push rax
    call log_internal_str
    pop rax
    call log_internal_char
    ret