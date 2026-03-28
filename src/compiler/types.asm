; =============================================================================
; Module: src/compiler/types.asm (V5.2.1 - Clean NASM Syntax)
; Project: La Roca Rules Engine
; Responsibility: Parse ASCII strings into Tagged Unions.
; =============================================================================

extern log_level
extern operand_error
extern get_now_unix

section .data
    align 16                    ; Force alignment for floating point constants
    float_ten     dq 10.0
    float_neg_one dq -1.0

    log_now       db "[TRACE] Types: Reserved word 'NOW' detected", 0x0A, 0
    l_now         equ $ - log_now

section .text
    global parse_and_store_value
    global parse_number

; -----------------------------------------------------------------------------
; Function: log_trace_types (Safe Syscall Wrapper)
; -----------------------------------------------------------------------------
log_trace_types:
    push rax
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    push r9
    push r11

    cmp byte [log_level], 2
    jne .skip
    mov rax, 1                  ; sys_write
    mov rdi, 2                  ; stderr
    syscall
.skip:
    pop r11
    pop r9
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; -----------------------------------------------------------------------------
; Function: parse_and_store_value
; In: RDI = Source String, R9 = Slot Pointer
; Out: RAX = Status (1=Float, 2=String, 3=Error), RDI advanced
; -----------------------------------------------------------------------------
parse_and_store_value:
.skip_leading_spaces:
    cmp byte [rdi], ' '
    jne .check_reserved
    inc rdi
    jmp .skip_leading_spaces

.check_reserved:
    cmp byte [rdi], 'N'
    jne .check_string

    ; Split lines to satisfy NASM
    cmp byte [rdi+1], 'O'
    jne .check_string
    cmp byte [rdi+2], 'W'
    jne .check_string

    ; Save volatile registers before external call
    push rdi
    push r9
    sub rsp, 8                  ; Align to 16 bytes
    call get_now_unix
    add rsp, 8
    pop r9
    pop rdi

    mov qword [r9], 1           ; Tag = Float
    movsd [r9+8], xmm0          ; Value from get_now_unix
    add rdi, 3
    mov rax, 1                  ; Success
    jmp .skip_trailing_spaces

.check_string:
    cmp byte [rdi], '"'
    je .is_string

    ; --- FLOAT64 Literals ---
    call parse_number           ; RAX = 1 or 3
    cmp rax, 3
    je .done                    ; Propagate error 3 immediately

    mov qword [r9], 1
    movsd [r9+8], xmm0
    jmp .skip_trailing_spaces

.is_string:
    mov qword [r9], 2
    inc rdi
    mov [r9+8], rdi

.scan_str_loop:
    mov al, [rdi]
    test al, al
    jz .failed
    cmp al, '"'
    je .close_string
    inc rdi
    jmp .scan_str_loop

.close_string:
    mov byte [rdi], 0
    inc rdi
    mov rax, 2
    jmp .skip_trailing_spaces

.failed:
    call operand_error          ; Returns 3
    ; Fall through with RAX=3

.skip_trailing_spaces:
    cmp byte [rdi], ' '
    jne .done
    inc rdi
    jmp .skip_trailing_spaces
.done:
    ret

; -----------------------------------------------------------------------------
; Function: parse_number (ASCII -> Float64)
; Out: XMM0 = Result, RAX = 1 (Success) or 3 (Error)
; -----------------------------------------------------------------------------
parse_number:
    pxor xmm0, xmm0
    pxor xmm1, xmm1
    movsd xmm2, [float_ten]
    xor r10, r10                ; Sign
    xor rcx, rcx                ; Digit count

    cmp byte [rdi], '-'
    jne .parse_int
    inc r10
    inc rdi

.parse_int:
    movzx rax, byte [rdi]
    cmp al, '0'
    jl .check_dot
    cmp al, '9'
    jg .check_dot

    sub rax, '0'
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm2
    addsd xmm0, xmm1
    inc rcx
    inc rdi
    jmp .parse_int

.check_dot:
    cmp byte [rdi], '.'
    jne .apply_sign
    inc rdi
    movsd xmm3, [float_ten]
.parse_frac:
    movzx rax, byte [rdi]
    cmp al, '0'
    jl .apply_sign
    cmp al, '9'
    jg .apply_sign

    sub rax, '0'
    cvtsi2sd xmm1, rax
    divsd xmm1, xmm3
    addsd xmm0, xmm1
    mulsd xmm3, xmm2
    inc rcx
    inc rdi
    jmp .parse_frac

.apply_sign:
    test rcx, rcx
    jz .num_error               ; No digits found

    test r10, r10
    jz .success
    mulsd xmm0, [float_neg_one]

.success:
    mov rax, 1
    ret

.num_error:
    call operand_error          ; RAX = 3
    ret