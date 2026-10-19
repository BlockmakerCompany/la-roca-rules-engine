; =============================================================================
; Module: src/alu/operand.asm (V7.0 - Collision-Safe Lookup)
; Project: La Roca Rules Engine
; Responsibility: Extract values from context or literals (Numbers, Strings, #).
; =============================================================================

section .data
    ; Error messages for the internal logger
    log_err_var    db "[ERROR] [Operand] Variable lookup failed or undefined", 0x0A, 0
    log_err_type   db "[ERROR] [Operand] Length operator '#' requires a string", 0x0A, 0

section .text
    global get_operand
    global skip_spaces

    ; External Utilities from the Engine and Compiler layers
    extern var_map, hash_name, parse_and_store_value, eval_error
    extern log_internal_str

; -----------------------------------------------------------------------------
; Function: skip_spaces
; In:  RDI = String pointer
; Out: RDI = First non-space character pointer
; -----------------------------------------------------------------------------
skip_spaces:
    cmp byte [rdi], ' '
    jne .done
    inc rdi
    jmp skip_spaces
.done:
    ret

; -----------------------------------------------------------------------------
; Function: lookup_var (module-local)
; Responsibility: Open-addressing probe with full name verification.
; In:  RAX = 64-bit hash, RCX = name length, RDX = name pointer
; Out: RDX = slot pointer, or 0 if not found
; Preserves: RDI, RBX, RBP, R12-R15. Clobbers: RAX, RCX, R8, R9, RSI, R11.
; -----------------------------------------------------------------------------
lookup_var:
    and rax, 255
    shl rax, 5              ; index * 32
    lea r8, [var_map + rax] ; R8 = candidate slot
    mov r11, rcx            ; Preserve length across cmpsb
    xor r9, r9              ; probing counter

.loop:
    mov rax, [r8]           ; slot.name_ptr
    test rax, rax
    jz .not_found           ; Empty slot -> not found

    cmp [r8 + 8], r11       ; does the length match?
    jne .next

    ; Compare name byte by byte.
    push rdi                ; Preserve caller's RDI (delimiter)
    mov rsi, rax            ; stored name
    mov rdi, rdx            ; queried name
    mov rcx, r11            ; length
    cld
    repe cmpsb
    pop rdi                 ; Restore RDI
    je .found

.next:
    add r8, 32
    lea rax, [var_map + 8192]
    cmp r8, rax
    jb .no_wrap
    lea r8, [var_map]
.no_wrap:
    inc r9
    cmp r9, 256
    jae .not_found
    jmp .loop

.found:
    mov rdx, r8
    ret

.not_found:
    xor rdx, rdx
    ret

; -----------------------------------------------------------------------------
; Function: get_operand
; Responsibility: Resolves a token into a Float (XMM0) or String (R12).
; In:  RDI = Pointer to token start.
; Out: RAX = Status/Tag (1: Float, 2: String, 3: Fatal Error).
; -----------------------------------------------------------------------------
get_operand:
    push rbp
    mov rbp, rsp

    mov al, [rdi]
    test al, al
    jz .var_error           ; Abort if string is empty

    ; --- 1. Detect Literal Type ---
    cmp al, '"'
    je .is_literal_str      ; Starts with quote: String Literal
    cmp al, '-'
    je .is_literal_num      ; Starts with minus: Negative Number
    cmp al, '#'
    je .is_length_op        ; Starts with hash: Length Operator

    ; --- 2. Check if it's a Numeric Digit ---
    cmp al, '0'
    jl .check_var           ; If < '0', it might be a variable name
    cmp al, '9'
    jle .is_literal_num     ; If between '0'-'9', it's a positive number

.check_var:
    ; --- 3. Resolve Variable from VarMap (name-verified) ---
    call hash_name          ; RAX=hash, RCX=len, RDX=name_start, RDI at delimiter
    call lookup_var         ; RDX = slot pointer, or 0
    test rdx, rdx
    jz .var_error

    mov rax, [rdx + 16]     ; Load the Tag (0:Empty, 1:Float, 2:String)
    test rax, rax
    jz .var_error           ; Tag 0 means variable doesn't exist

    cmp rax, 1
    je .load_float
    cmp rax, 2
    je .load_string
    jmp .var_error          ; Unknown tag safety check

.load_float:
    movsd xmm0, [rdx + 24]  ; Load 64-bit float into XMM0
    mov rax, 1
    jmp .exit

.load_string:
    mov r12, [rdx + 24]     ; Load string pointer into R12
    mov rax, 2
    jmp .exit

.is_length_op:
    ; --- 4. Resolve '#' Operator (String Length) ---
    inc rdi                 ; Skip the '#' character
    call hash_name
    call lookup_var
    test rdx, rdx
    jz .var_error

    cmp qword [rdx + 16], 2 ; The variable MUST be a String (Tag 2)
    jne .type_error

    mov rcx, [rdx + 24]     ; RCX = Start of the actual string
    xor rax, rax            ; RAX = Length counter
.len_loop:
    cmp byte [rcx + rax], 0 ; Scan for null terminator
    je .len_done
    inc rax
    jmp .len_loop
.len_done:
    cvtsi2sd xmm0, rax      ; Convert integer length to Float64 in XMM0
    mov rax, 1              ; Result of '#' is always a Number
    jmp .exit

.is_literal_num:
    ; --- 5. Parse Number Literal ---
    sub rsp, 16             ; Allocate 16 bytes for local output
    mov r9, rsp             ; R9 = Target for parse_and_store_value
    call parse_and_store_value

    cmp rax, 3
    je .literal_err_cleanup ; Propagate panic if parsing failed

    mov rax, 1              ; Explicitly return Float tag
    movsd xmm0, [rsp + 8]   ; Load the parsed result
    add rsp, 16
    jmp .exit

.is_literal_str:
    ; --- 6. Parse String Literal ---
    sub rsp, 16
    mov r9, rsp
    call parse_and_store_value

    cmp rax, 3
    je .literal_err_cleanup

    mov rax, 2
    mov r12, [rsp + 8]      ; Load pointer to the parsed string
    add rsp, 16
    jmp .exit

.literal_err_cleanup:
    add rsp, 16             ; Clean stack before propagating error
    jmp .exit               ; RAX is already 3

.exit:
    leave                   ; Clean RBP frame
    ret

; -----------------------------------------------------------------------------
; --- Error Handlers (Clean Return Path) ---
; -----------------------------------------------------------------------------

.var_error:
    lea rsi, [log_err_var]
    call log_internal_str
    call eval_error         ; RAX = 3
    leave
    ret

.type_error:
    lea rsi, [log_err_type]
    call log_internal_str
    call eval_error         ; RAX = 3
    leave
    ret
