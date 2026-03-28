; =============================================================================
; Module: src/net/server.asm (V2.5 - Ghostbuster Edition)
; Responsibility: TCP Epoll Server and connection lifecycle (Keep-Alive).
; =============================================================================

section .bss
    global buffer
    buffer resb 1024
    epoll_events resb 384     ; 32 events * 12 bytes

section .data
    sockaddr dw 2, 0x901F, 0, 0, 0, 0, 0, 0
    log_start_m  db "[INFO] Rules Engine Started (Epoll Keep-Alive) on port 8080", 0x0A
    log_start_l  equ $ - log_start_m
    log_srv_call   db "[DEBUG] [Server] Routing request to Business Logic...", 0x0A, 0
    log_srv_ret    db "[DEBUG] [Server] Logic returned. RSI=", 0
    log_srv_write  db "[DEBUG] [Server] Attempting sys_write to FD: ", 0
    log_srv_done   db "[DEBUG] [Server] sys_write completed successfully.", 0x0A, 0

    ev_ptr:
        dd 1            ; EPOLLIN
        dq 0            ; data.fd

section .text
    global server_start
    extern router_match, log_internal_str, log_msg_with_char

server_start:
    ; --- LOG STARTUP ---
    mov rax, 1
    mov rdi, 2
    lea rsi, [log_start_m]
    mov rdx, log_start_l
    syscall

    ; --- SERVER SETUP ---
    mov rax, 41                 ; sys_socket
    mov rdi, 2                  ; AF_INET
    mov rsi, 1                  ; SOCK_STREAM
    mov rdx, 0
    syscall
    mov r12, rax                ; r12 = Server Socket

    mov rax, 49                 ; sys_bind
    mov rdi, r12
    lea rsi, [sockaddr]
    mov rdx, 16
    syscall

    mov rax, 50                 ; sys_listen
    mov rdi, r12
    mov rsi, 128                ; Backlog
    syscall

    ; --- EPOLL SETUP ---
    mov rax, 291                ; sys_epoll_create1
    mov rdi, 0
    syscall
    mov r14, rax                ; r14 = Epoll FD

    mov dword [ev_ptr], 1       ; EPOLLIN
    mov qword [ev_ptr + 4], r12
    mov rax, 233                ; sys_epoll_ctl
    mov rdi, r14
    mov rsi, 1                  ; EPOLL_CTL_ADD
    mov rdx, r12
    lea r10, [ev_ptr]
    syscall

epoll_loop:
    mov rax, 232                ; sys_epoll_wait
    mov rdi, r14
    lea rsi, [epoll_events]
    mov rdx, 32                 ; Max events
    mov r10, -1                 ; Infinite timeout
    xor r8, r8
    syscall

    mov r15, rax                ; r15 = Ready events count
    test r15, r15
    js epoll_loop               ; If interrupted, retry

    xor rbx, rbx                ; rbx = current event index
process_events:
    cmp rbx, r15
    jge epoll_loop              ; All events processed, wait for more

    imul rcx, rbx, 12
    lea rdx, [epoll_events + rcx]
    mov r13d, [rdx + 4]         ; r13 = Triggered FD

    cmp r13, r12
    je handle_accept            ; Is it the server socket? (New connection)

    jmp handle_client           ; It's a client socket (Data ready)

handle_accept:
    mov rax, 43                 ; sys_accept
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    syscall
    mov r13, rax                ; r13 = New Client FD

    mov dword [ev_ptr], 1       ; EPOLLIN
    mov qword [ev_ptr + 4], r13
    mov rax, 233                ; sys_epoll_ctl
    mov rdi, r14
    mov rsi, 1                  ; EPOLL_CTL_ADD
    mov rdx, r13
    lea r10, [ev_ptr]
    syscall

    jmp next_event

handle_client:
    ; 🛡️ 1. GHOSTBUSTER: ZERO-OUT THE ENTIRE NETWORK BUFFER FAST
    ; This ensures previous HTTP bodies do not bleed into the next request.
    cld                         ; Clear direction flag (auto-increment RDI)
    lea rdi, [buffer]           ; Start of buffer
    mov rcx, 128                ; 128 quadwords = 1024 bytes
    xor rax, rax                ; We want to fill with zeros
    rep stosq                   ; Atomic, lightning-fast zero-fill

    ; 2. Read incoming data from network
    mov rax, 0                  ; sys_read
    mov rdi, r13                ; r13 = client FD
    lea rsi, [buffer]           ; Target buffer (now sparkling clean)
    mov rdx, 1024               ; Max bytes to read
    syscall

    test rax, rax
    jle close_client            ; If read 0 bytes, client disconnected

    ; --- ABI STATE SHIELD ---
    ; We must preserve the Epoll loop state (R12-R15, RBX) before diving into
    ; the business logic, which will use these registers heavily.
    push r12
    push r13
    push r14
    push r15
    push rbx

    lea rsi, [log_srv_call]
    call log_internal_str

    lea rdi, [buffer]           ; Point RDI to the fresh request
    call router_match           ; Returns RSI (Response Pointer), RDX (Length)

    ; 🛡️ SHIELD: Protect the Response pointers from the state restoration pops
    push rsi                    ; Save Response Pointer
    push rdx                    ; Save Response Length

    pop rdx                     ; Restore Response Length
    pop rsi                     ; Restore Response Pointer
    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    ; ------------------------

    ; 🕵️‍♂️ TRACE: Is the response valid?
    test rsi, rsi
    jz close_client             ; Safety: Don't sys_write from NULL

    ; 3. Send HTTP Response back to client
    mov rax, 1                  ; sys_write
    mov rdi, r13                ; r13 = client FD
    ; RSI and RDX are already correctly set by the shield pops
    syscall

    lea rsi, [log_srv_done]
    call log_internal_str

    jmp next_event

close_client:
    mov rax, 3                  ; sys_close
    mov rdi, r13
    syscall

next_event:
    inc rbx
    jmp process_events