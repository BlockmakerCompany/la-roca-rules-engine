; =============================================================================
; Module: src/core/router.asm
; Project: La Roca Rules Engine
; Responsibility: Fast HTTP Routing using string comparison (repe cmpsb).
; =============================================================================
extern handle_live
extern handle_ready
extern handle_eval

section .data
    path_live    db "/live "
    len_p_live   equ $ - path_live

    path_ready   db "/ready "
    len_p_ready  equ $ - path_ready

    path_eval    db "/eval "
    len_p_eval   equ $ - path_eval

    ; Default 404 Response
    msg_404      db "HTTP/1.1 404 Not Found", 0x0D, 0x0A, "Content-Length: 9", 0x0D, 0x0A, 0x0D, 0x0A, "Not Found"
    len_404      equ $ - msg_404

section .text
    global router_match

; -----------------------------------------------------------------------------
; Function: router_match
; Responsibility: Inspects the HTTP request line and routes to the correct handler.
; In: RDI = Pointer to the start of the HTTP network buffer.
; Out: RSI = Pointer to response string, RDX = Response length.
; -----------------------------------------------------------------------------
router_match:
    ; Receives the main buffer pointer in RDI
    cld

    ; Check GET /live (skip "GET ", check from offset 4)
    push rdi
    add rdi, 4
    lea rsi, [path_live]
    mov rcx, len_p_live
    repe cmpsb
    pop rdi
    je .go_live

    ; Check GET /ready (skip "GET ", check from offset 4)
    push rdi
    add rdi, 4
    lea rsi, [path_ready]
    mov rcx, len_p_ready
    repe cmpsb
    pop rdi
    je .go_ready

    ; Check POST /eval (skip "POST ", check from offset 5)
    push rdi
    add rdi, 5
    lea rsi, [path_eval]
    mov rcx, len_p_eval
    repe cmpsb
    pop rdi
    je .go_eval

    ; If no match, prepare 404 response
    lea rsi, [msg_404]
    mov rdx, len_404
    ret

.go_live:
    call handle_live
    ret

.go_ready:
    call handle_ready
    ret

.go_eval:
    call handle_eval
    ret