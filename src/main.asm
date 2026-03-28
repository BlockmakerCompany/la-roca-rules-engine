; =============================================================================
; Module: src/main.asm
; Responsibility: Bootstrapper and Environment configuration.
; =============================================================================
extern server_start
global log_level

section .bss
    log_level resb 1

section .data
    log_env_key  db "LOG_LEVEL="

section .text
    global _start

_start:
    cld
    ; --- ENVIRONMENT PARSING ---
    ; Get argc from the stack to calculate the position of the environment variables
    mov r8, [rsp]
    lea r9, [rsp + 16 + r8*8]
env_loop:
    mov rsi, [r9]
    test rsi, rsi
    jz env_done             ; End of environment variables reached
    lea rdi, [log_env_key]
    mov rcx, 10             ; Length of "LOG_LEVEL="
    push rsi
    repe cmpsb              ; Check if current variable starts with our key
    pop rsi
    jne next_env

    ; If match found, check the first letter of the value
    mov al, [rsi + 10]
    cmp al, 't'             ; 't' for trace
    je set_trace
    cmp al, 'e'             ; 'e' for error
    je set_error
    jmp next_env
set_trace:
    mov byte [log_level], 2
    jmp env_done
set_error:
    mov byte [log_level], 1
    jmp env_done
next_env:
    add r9, 8               ; Point to the next environment variable string
    jmp env_loop
env_done:

    ; Hand over control to the Network Server
    call server_start

    ; Exit (Security fallback if the server ever stops)
    mov rax, 60
    xor rdi, rdi
    syscall