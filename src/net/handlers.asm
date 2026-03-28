; =============================================================================
; Module: src/net/handlers.asm (V3.2 - Connection Close)
; Project: La Roca Rules Engine
; Responsibility: Bridge between HTTP /eval and the Rules Engine logic.
; =============================================================================

section .data
    ; Success Response (True) -> 16 bytes payload
    resp_true  db "HTTP/1.1 200 OK", 0x0D, 0x0A
               db "Content-Type: application/json", 0x0D, 0x0A
               db "Content-Length: 16", 0x0D, 0x0A, 0x0D, 0x0A
               db '{"result":true}', 0x0A
    len_true   equ $ - resp_true

    ; Success Response (False) -> 17 bytes payload
    resp_false db "HTTP/1.1 200 OK", 0x0D, 0x0A
               db "Content-Type: application/json", 0x0D, 0x0A
               db "Content-Length: 17", 0x0D, 0x0A, 0x0D, 0x0A
               db '{"result":false}', 0x0A
    len_false  equ $ - resp_false

    ; Error Response (400 Bad Request)
    ; 🚨 NUEVO: "Connection: close" fuerza al OS a vaciar el socket inmediatamente
    resp_error db "HTTP/1.1 400 Bad Request", 0x0D, 0x0A
               db "Content-Type: text/plain", 0x0D, 0x0A
               db "Connection: close", 0x0D, 0x0A
               db "Content-Length: 6", 0x0D, 0x0A, 0x0D, 0x0A
               db "Error", 0x0A
    len_error  equ $ - resp_error

    ; Debug Logs
    log_hand_err db "[DEBUG] [Handlers] Panic detected. Sending 400 Bad Request...", 0x0A, 0

section .text
    global handle_eval
    global panic_exit           ; Export the exit door for the Panic system

    extern parse_json_rule
    extern log_internal_str

; -----------------------------------------------------------------------------
; Function: handle_eval
; Responsibility: Route /eval POST requests to the engine and return HTTP.
; -----------------------------------------------------------------------------
handle_eval:
    push rbp
    mov rbp, rsp
    ; Stack is now 16-byte aligned (RET address + RBP)

    ; 1. Execute Engine.
    ; Returns: RAX = 0 (True), 1 (False), 3 (Fatal Error)
    call parse_json_rule

    ; 2. Dispatch based on result code
    cmp rax, 2
    jae .is_error       ; If RAX >= 2 (Error 3), jump to 400 response

    cmp rax, 1
    je .is_false        ; If RAX == 1, jump to False

.is_true:               ; RAX == 0
    lea rsi, [resp_true]
    mov rdx, len_true
    jmp eval_done

.is_false:
    lea rsi, [resp_false]
    mov rdx, len_false
    jmp eval_done

; --- PANIC TARGET ---
.is_error:
panic_exit:             ; Any fatal engine error lands here
    ; 🛡️ ABI ALIGNMENT SHIELD
    ; When we enter here, RAX is 3. We must keep the stack 16-byte aligned
    ; before calling 'log_internal_str'.
    push rax            ; Align -8
    sub rsp, 8          ; Align -16 (Total 16 bytes pushed)

    lea rsi, [log_hand_err]
    call log_internal_str

    add rsp, 8          ; Restore alignment
    pop rax             ; Restore RAX=3

    lea rsi, [resp_error]
    mov rdx, len_error

eval_done:
    leave               ; Standard cleanup: mov rsp, rbp; pop rbp
    ret