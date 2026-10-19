; =============================================================================
; Module: src/compiler/map_parser.asm
; Responsibility: Parse "key=value" pairs and populate the var_map.
; =============================================================================

section .bss
    global var_map
    ; 256 slots * 32 bytes = 8192 bytes
    ; Slot layout: [name_ptr 8][name_len 8][tag 8][value 8]
    ;   tag: 0 = empty, 1 = Float64, 2 = String pointer
    var_map resb 8192

section .text
    global build_var_map
    global clear_var_map
    extern hash_name
    extern parse_and_store_value
    extern eval_error

; -----------------------------------------------------------------------------
; Function: clear_var_map
; Responsibility: Zeroes out the variable map to prevent cross-request pollution.
; -----------------------------------------------------------------------------
clear_var_map:
    push rdi                ; Preserve RDI (pointer to the caller's HTTP buffer)
    push rcx
    push rax
    lea rdi, [var_map]
    xor rax, rax
    mov rcx, 1024           ; 8192 bytes / 8
    cld
    rep stosq
    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; Function: build_var_map
; In: RDI = Pointer to the start of the context map
; Out: RDI = Advanced to the first character of the rules block
; -----------------------------------------------------------------------------
build_var_map:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    ; If the first character is a newline, there is no map.
    cmp byte [rdi], 0x0A
    je .done

.map_loop:
    ; 1. Hash the variable name (RAX=hash, RCX=len, RDX=name_start).
    ;    hash_name advances RDI up to the delimiter (e.g. '=' or a space).
    call hash_name
    mov rbx, rax            ; RBX = hash
    mov r12, rcx            ; R12 = name length
    mov r13, rdx            ; R13 = name start pointer

    ; 2. Sync up to the '=' symbol, tolerating spaces.
.find_equals:
    cmp byte [rdi], '='
    je .found_equals
    cmp byte [rdi], 0x0A    ; Error: end of line without '='
    je .error
    cmp byte [rdi], 0       ; Error: unexpected end of buffer
    je .error
    inc rdi
    jmp .find_equals

.found_equals:
    inc rdi                 ; Skip the '='

    ; 3. Open addressing: find the slot by name (with full verification).
    mov rax, rbx
    and rax, 255
    shl rax, 5              ; index * 32
    lea r14, [var_map + rax] ; R14 = candidate slot
    xor r8, r8              ; probing counter (max 256)

.probe:
    mov rax, [r14]          ; slot.name_ptr
    test rax, rax
    jz .insert              ; Empty slot -> insert

    cmp [r14 + 8], r12      ; Does the length match?
    jne .next_slot

    ; Compare the name byte by byte (name_len bytes).
    push rdi                ; Preserve RDI (start of the value)
    mov rsi, rax            ; stored name
    mov rdi, r13            ; queried name
    mov rcx, r12            ; length
    cld
    repe cmpsb
    pop rdi                 ; Restore RDI
    je .store_value         ; Same name -> reuse slot

.next_slot:
    add r14, 32
    lea rax, [var_map + 8192]
    cmp r14, rax
    jb .no_wrap
    lea r14, [var_map]
.no_wrap:
    inc r8
    cmp r8, 256
    jae .error              ; Table full (should not happen)
    jmp .probe

.insert:
    mov [r14], r13          ; Save pointer to the name
    mov [r14 + 8], r12      ; Save name length

.store_value:
    ; 4. Parse and store the value (tag at +16, value at +24).
    lea r9, [r14 + 16]
    call parse_and_store_value

    ; 5. Determine whether there are more variables or the map is done.
    ;    parse_and_store_value leaves RDI at the next delimiter (',' or '\n').
.check_delimiter:
    cmp byte [rdi], ','
    je .next_var
    cmp byte [rdi], 0x0A
    je .done

    cmp byte [rdi], ' '
    jne .error
    inc rdi
    jmp .check_delimiter

.next_var:
    inc rdi                 ; Skip the comma
    jmp .map_loop

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.error:
    call eval_error         ; RAX = 3
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
