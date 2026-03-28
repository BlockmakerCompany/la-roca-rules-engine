; =============================================================================
; Module: src/utils/time.asm
; Responsibility: System clock interface.
; =============================================================================

section .text
    global get_now_unix

get_now_unix:
    sub rsp, 16
    mov rax, 228            ; sys_clock_gettime
    mov rdi, 0              ; CLOCK_REALTIME
    mov rsi, rsp
    syscall
    mov rax, [rsp]
    cvtsi2sd xmm0, rax
    add rsp, 16
    ret