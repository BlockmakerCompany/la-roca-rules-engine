; =============================================================================
; Module: src/compiler/hashing.asm
; Project: La Roca Rules Engine
; Responsibility: String hashing for the Variable Map (64-bit) and JIT Cache (64-bit).
; =============================================================================

section .text
    global hash_name
    global hash_rules_64

; -----------------------------------------------------------------------------
; Function: hash_name (FNV-1a Algorithm, 64-bit)
; Use Case: Hashing variable names for the open-addressing Variable Map.
; In: RDI = Pointer to the name start (leading whitespace tolerated)
; Out: RAX = 64-bit Hash
;      RCX = Name length in bytes (0 if empty)
;      RDX = Pointer to the first character of the name (after leading spaces)
;      RDI = Advanced to the first delimiter (points AT it, not past)
; Delimiters: space, ( ) = > < ~ ^ , newline, NUL
; -----------------------------------------------------------------------------
hash_name:
.skip_leading:
    cmp byte [rdi], ' '
    jne .init
    inc rdi
    jmp .skip_leading

.init:
    mov rdx, rdi                    ; RDX = name start
    mov rax, 0xcbf29ce484222325     ; FNV-1a offset basis
    mov r8,  0x100000001b3          ; FNV-1a prime
    xor rcx, rcx                    ; length = 0

.loop:
    movzx r9, byte [rdi]

    ; Token delimiters (ends variable name hashing)
    cmp r9b, ' '
    je .done
    cmp r9b, '('
    je .done
    cmp r9b, ')'
    je .done
    cmp r9b, '='
    je .done
    cmp r9b, '>'
    je .done
    cmp r9b, '<'
    je .done
    cmp r9b, '~'
    je .done
    cmp r9b, '^'
    je .done
    cmp r9b, ','
    je .done
    cmp r9b, 0x0A                  ; Newline
    je .done
    test r9b, r9b                  ; Null terminator
    jz .done

    ; FNV-1a: hash = (hash XOR byte) * prime
    xor rax, r9
    imul rax, r8

    inc rcx
    inc rdi
    jmp .loop

.done:
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
