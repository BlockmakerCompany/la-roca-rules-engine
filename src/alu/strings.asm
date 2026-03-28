; =============================================================================
; Module: src/core/strings.asm (V2.4 - The LIFO Fix)
; Project: La Roca Rules Engine
; Responsibility: String operations (=, ~, ^)
; =============================================================================
section .text
    global eval_string_op

; -----------------------------------------------------------------------------
; Function: eval_string_op
; In: BL = Operator Char, R14 = Right Operand, R12 = Left Operand
; Out: RAX = Result (0 = True, 1 = False, 2 = Unknown Operator)
; -----------------------------------------------------------------------------
eval_string_op:
    ; 🛡️ POINTER SHIELD: Save the Lexer's string pointer (RDI) and RSI
    push rdi
    push rsi

    cmp bl, '='
    je .do_equal
    cmp bl, '~'
    je .do_contains
    cmp bl, '^'
    je .do_equals_ignore_case

    mov rax, 2              ; Error: Unknown string operator
    jmp .exit               ; 🚨 Jump to the centralized exit to restore pointers

.do_equal:
    mov rsi, r12            ; Left Operand
    mov rdi, r14            ; Right Operand
    call string_compare
    jmp .exit

.do_contains:
    ; 🎯 THE LIFO FIX: R12 is the Left Operand (Haystack), R14 is Right (Needle)
    mov rsi, r12            ; RSI = Haystack (e.g. "admin@blockmaker.net")
    mov rdi, r14            ; RDI = Needle (e.g. "blockmaker")
    call string_contains
    jmp .exit

.do_equals_ignore_case:
    mov rsi, r12            ; Left Operand
    mov rdi, r14            ; Right Operand
    call string_compare_nocase
    jmp .exit

.exit:
    ; 🛡️ RESTORE POINTERS EXACTLY AS THEY WERE
    pop rsi
    pop rdi
    ret

; -----------------------------------------------------------------------------
; Subroutine: string_compare (Strict =)
; -----------------------------------------------------------------------------
string_compare:
    push rbx                ; 🛡️ ABI COMPLIANCE SHIELD
.loop:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .not_equal
    test al, al
    jz .equal
    inc rsi
    inc rdi
    jmp .loop
.not_equal:
    mov rax, 1              ; False
    pop rbx
    ret
.equal:
    xor rax, rax            ; True (0)
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Subroutine: string_compare_nocase (IgnoreCase ^)
; -----------------------------------------------------------------------------
string_compare_nocase:
    push rbx                ; 🛡️ ABI COMPLIANCE SHIELD
.loop_nc:
    mov al, [rsi]
    mov bl, [rdi]

    ; Convert AL to lowercase if it's within 'A'-'Z'
    cmp al, 'A'
    jl .skip_al
    cmp al, 'Z'
    jg .skip_al
    or al, 0x20
.skip_al:
    ; Convert BL to lowercase if it's within 'A'-'Z'
    cmp bl, 'A'
    jl .skip_bl
    cmp bl, 'Z'
    jg .skip_bl
    or bl, 0x20
.skip_bl:

    cmp al, bl
    jne .not_equal_nc
    test al, al
    jz .equal_nc
    inc rsi
    inc rdi
    jmp .loop_nc
.not_equal_nc:
    mov rax, 1              ; False
    pop rbx
    ret
.equal_nc:
    xor rax, rax            ; True (0)
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Subroutine: string_contains (Contains ~) Quote-Aware & Robust
; Searches for Needle (RDI) within Haystack (RSI), ignoring bounding quotes
; -----------------------------------------------------------------------------
string_contains:
    push rbx                ; 🛡️ ABI COMPLIANCE SHIELD
    push rcx                ; Save RCX for haystack iteration

    ; Ignore opening quote in the Needle (Substring)
    cmp byte [rdi], '"'
    jne .check_empty
    inc rdi

.check_empty:
    mov al, [rdi]
    test al, al
    jz .found               ; Empty needle matches automatically
    cmp al, '"'
    je .found               ; Needle is just '""' -> automatic match

    ; Ignore opening quote in the Haystack (Full text)
    cmp byte [rsi], '"'
    jne .search_outer
    inc rsi

.search_outer:
    mov al, [rsi]           ; Read next character from haystack
    test al, al
    jz .not_found           ; Reached end of haystack -> no match
    cmp al, '"'
    je .not_found           ; Reached closing quote of haystack -> no match

    ; Try matching starting from this specific position
    mov rcx, rsi            ; Save current haystack position
    mov rdx, rdi            ; Reset needle position to start

.search_inner:
    mov bl, [rdx]           ; Read needle character
    cmp bl, '"'             ; Is it a closing quote?
    je .found_inner         ; Yes -> reached end of needle successfully!
    test bl, bl             ; Is it a null terminator?
    jz .found_inner         ; Yes -> reached end of needle successfully!

    mov al, [rcx]           ; Read haystack character
    cmp al, '"'             ; Is it a closing quote?
    je .mismatch            ; Yes -> haystack ended before needle
    test al, al             ; Is it a null terminator?
    jz .mismatch            ; Yes -> haystack ended before needle

    cmp al, bl              ; Do characters match?
    jne .mismatch           ; No -> abort inner loop, try next haystack char

    inc rcx                 ; Advance haystack pointer
    inc rdx                 ; Advance needle pointer
    jmp .search_inner

.mismatch:
    inc rsi                 ; Advance to next starting character in haystack
    jmp .search_outer

.found_inner:
.found:
    xor rax, rax            ; Return 0 (True)
    pop rcx
    pop rbx
    ret

.not_found:
    mov rax, 1              ; Return 1 (False)
    pop rcx
    pop rbx
    ret