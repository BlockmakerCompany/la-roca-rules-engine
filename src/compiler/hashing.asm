; =============================================================================
; Module: src/compiler/hashing.asm
; Project: La Roca Rules Engine
; Responsibility: String hashing for Variable Map (8-bit) and JIT Cache (64-bit).
; =============================================================================

section .text
    global hash_token_8
    global hash_rules_64

; -----------------------------------------------------------------------------
; Function: hash_token_8 (DJB2 Algorithm)
; Use Case: Fast hashing for the Variable Map (Small collision-tolerant table).
; In: RDI = Pointer to string start
; Out: RAX = 8-bit Hash (0-255), RDI = Advanced to the delimiter
; -----------------------------------------------------------------------------
hash_token_8:
    ; 1. Skip leading whitespace
.skip_leading:
    cmp byte [rdi], ' '
    jne .init
    inc rdi
    jmp .skip_leading

.init:
    xor rax, rax
.h_loop:
    movzx rdx, byte [rdi]

    ; Token delimiters (Ends variable name hashing)
    cmp dl, ' '
    je .h_done
    cmp dl, '('
    je .h_done
    cmp dl, ')'
    je .h_done
    cmp dl, '='
    je .h_done
    cmp dl, '>'
    je .h_done
    cmp dl, '<'
    je .h_done
    cmp dl, '~'
    je .h_done
    cmp dl, '^'
    je .h_done
    cmp dl, ','
    je .h_done
    cmp dl, 0x0A            ; Newline
    je .h_done
    test dl, dl             ; Null terminator
    jz .h_done

    ; DJB2 Algorithm: hash = ((hash << 5) + hash) + char
    mov rdx, rax
    shl rax, 5
    add rax, rdx
    movzx rdx, byte [rdi]
    add rax, rdx

    inc rdi
    jmp .h_loop

.h_done:
    and rax, 0xFF           ; Mask the result to 8 bits (256 slots)
    ret

; -----------------------------------------------------------------------------
; Function: hash_rules_64 (FNV-1a Algorithm)
; Use Case: High-entropy hashing for JIT Bytecode Cache (Rule fingerprinting).
; In: RDI = Pointer to the rules block start
; Out: RAX = 64-bit Hash
; -----------------------------------------------------------------------------
hash_rules_64:
    push rbx
    push rdi                ; Preserve RDI so the original position isn't lost

    mov rax, 0xcbf29ce484222325 ; FNV offset basis
    mov r8, 0x100000001b3       ; FNV prime

.loop:
    movzx rbx, byte [rdi]
    test bl, bl             ; End of payload (\0)?
    jz .done

    xor rax, rbx            ; Hash = Hash XOR byte
    mul r8                  ; Hash = Hash * FNV_prime

    inc rdi
    jmp .loop

.done:
    pop rdi                 ; Restore original RDI
    pop rbx
    ret