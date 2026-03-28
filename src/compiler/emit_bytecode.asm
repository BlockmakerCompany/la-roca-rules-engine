; =============================================================================
; Module: src/compiler/emit_bytecode.asm
; Project: La Roca Rules Engine
; Responsibility: Serialize VM instructions into a buffer during compilation.
; Format: [1 byte OpCode][7 bytes Alignment/Padding][8 bytes Argument/Data]
; =============================================================================

section .bss
    ; Temporary compilation buffer (32 instructions * 16 bytes = 512 bytes)
    compile_buffer  resb 512
    compile_ptr     resq 1

section .text
    global init_compilation
    global emit_push_var
    global emit_push_const
    global emit_push_now
    global emit_math
    global emit_comparison
    global emit_logic
    global finalize_compilation

    extern cache_store_plan

; -----------------------------------------------------------------------------
; Function: init_compilation
; In/Out: Resets the write pointer to the start of the buffer.
; -----------------------------------------------------------------------------
init_compilation:
    lea rax, [compile_buffer]
    mov [compile_ptr], rax

    ; Fast Zero-fill buffer to avoid stale instructions
    push rdi
    mov rdi, rax
    xor rax, rax
    mov rcx, 64             ; 64 quadwords = 512 bytes
    cld
    rep stosq
    pop rdi
    ret

; -----------------------------------------------------------------------------
; Helper: check_bounds (Internal)
; Responsibility: Ensure we don't write past the 512-byte buffer.
; -----------------------------------------------------------------------------
check_bounds:
    lea rax, [compile_buffer + 496] ; Last safe slot (512 - 16)
    cmp [compile_ptr], rax
    jae .overflow
    ret
.overflow:
    add rsp, 8              ; Pop return address to abort caller
    ret                     ; Silent abort (Rule will fail gracefully)

; -----------------------------------------------------------------------------
; Emitters: Stack Operations
; -----------------------------------------------------------------------------
emit_push_var:              ; OpCode 0x01 | Arg: 64-bit Hash
    call check_bounds
    mov rdx, [compile_ptr]
    mov byte [rdx], 0x01
    mov [rdx + 8], rax
    add qword [compile_ptr], 16
    ret

emit_push_const:            ; OpCode 0x02 | Arg: Raw Float64
    call check_bounds
    mov rdx, [compile_ptr]
    mov byte [rdx], 0x02
    movsd [rdx + 8], xmm0
    add qword [compile_ptr], 16
    ret

emit_push_now:              ; OpCode 0x04 | Arg: None
    call check_bounds
    mov rdx, [compile_ptr]
    mov byte [rdx], 0x04
    add qword [compile_ptr], 16
    ret

; -----------------------------------------------------------------------------
; Emitters: ALU Operations
; -----------------------------------------------------------------------------
emit_math:                  ; OpCodes 0x30 - 0x33 | In: AL = Char
    call check_bounds
    mov rdx, [compile_ptr]
    cmp al, '+'
    je .is_add
    cmp al, '-'
    je .is_sub
    cmp al, '*'
    je .is_mul
    cmp al, '/'
    je .is_div
    ret

.is_add:
    mov byte [rdx], 0x30
    jmp .done
.is_sub:
    mov byte [rdx], 0x31
    jmp .done
.is_mul:
    mov byte [rdx], 0x32
    jmp .done
.is_div:
    mov byte [rdx], 0x33

.done:
    add qword [compile_ptr], 16
    ret

emit_comparison:            ; OpCodes 0x10 - 0x14 | In: AL = Char
    call check_bounds
    mov rdx, [compile_ptr]
    cmp al, '>'
    je .is_gt
    cmp al, '<'
    je .is_lt
    cmp al, '='
    je .is_eq
    cmp al, '~'
    je .is_contains
    cmp al, '^'
    je .is_icase
    ret

.is_gt:
    mov byte [rdx], 0x10
    jmp .comp_done
.is_lt:
    mov byte [rdx], 0x11
    jmp .comp_done
.is_eq:
    mov byte [rdx], 0x12
    jmp .comp_done
.is_contains:
    mov byte [rdx], 0x13
    jmp .comp_done
.is_icase:
    mov byte [rdx], 0x14

.comp_done:
    add qword [compile_ptr], 16
    ret

emit_logic:                 ; OpCodes 0x20 - 0x21 | In: RAX (0=AND, 1=OR)
    call check_bounds
    mov rdx, [compile_ptr]
    test rax, rax
    jz .is_and
    mov byte [rdx], 0x21    ; OR
    jmp .log_done
.is_and:
    mov byte [rdx], 0x20    ; AND
.log_done:
    add qword [compile_ptr], 16
    ret

; -----------------------------------------------------------------------------
; Function: finalize_compilation
; Responsibility: Cap the bytecode and persist it in the global cache.
; -----------------------------------------------------------------------------
finalize_compilation:
    ; Write OpCode 0x00 (END/RET)
    mov rdx, [compile_ptr]
    mov byte [rdx], 0x00

    ; Store in cache: RDI already contains Rule Hash
    lea rsi, [compile_buffer]
    call cache_store_plan
    ret