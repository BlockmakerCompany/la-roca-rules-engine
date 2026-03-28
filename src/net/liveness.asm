; =============================================================================
; Module: src/core/liveness.asm
; Responsibility: Handle Kubernetes/Docker Liveness and Readiness HTTP probes.
; =============================================================================

section .data
    ; HTTP Response for /live endpoint
    msg_live  db "HTTP/1.1 200 OK", 0x0D, 0x0A, "Content-Length: 5", 0x0D, 0x0A, 0x0D, 0x0A, "Alive"
    len_live  equ $ - msg_live

    ; HTTP Response for /ready endpoint
    msg_ready db "HTTP/1.1 200 OK", 0x0D, 0x0A, "Content-Length: 5", 0x0D, 0x0A, 0x0D, 0x0A, "Ready"
    len_ready equ $ - msg_ready

section .text
    global handle_live
    global handle_ready

; -----------------------------------------------------------------------------
; Function: handle_live
; Out: RSI = Pointer to HTTP response string, RDX = Response length
; -----------------------------------------------------------------------------
handle_live:
    lea rsi, [msg_live]
    mov rdx, len_live
    ret

; -----------------------------------------------------------------------------
; Function: handle_ready
; Out: RSI = Pointer to HTTP response string, RDX = Response length
; -----------------------------------------------------------------------------
handle_ready:
    lea rsi, [msg_ready]
    mov rdx, len_ready
    ret