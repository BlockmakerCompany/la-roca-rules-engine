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
    push rdi                ; Preservar RDI (puntero al buffer HTTP del caller)
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

    ; Si el primer carácter es un salto de línea, no hay mapa.
    cmp byte [rdi], 0x0A
    je .done

.map_loop:
    ; 1. Hashear el nombre de la variable (RAX=hash, RCX=len, RDX=name_start).
    ;    hash_name avanza RDI hasta el delimitador (ej: '=' o un espacio).
    call hash_name
    mov rbx, rax            ; RBX = hash
    mov r12, rcx            ; R12 = name length
    mov r13, rdx            ; R13 = name start pointer

    ; 2. Sincronizar con el símbolo '=' tolerando espacios.
.find_equals:
    cmp byte [rdi], '='
    je .found_equals
    cmp byte [rdi], 0x0A    ; Error: fin de línea sin '='
    je .error
    cmp byte [rdi], 0       ; Error: fin de buffer inesperado
    je .error
    inc rdi
    jmp .find_equals

.found_equals:
    inc rdi                 ; Saltamos el '='

    ; 3. Open addressing: buscar el slot por nombre (con verificación completa).
    mov rax, rbx
    and rax, 255
    shl rax, 5              ; index * 32
    lea r14, [var_map + rax] ; R14 = slot candidato
    xor r8, r8              ; contador de probing (máx 256)

.probe:
    mov rax, [r14]          ; slot.name_ptr
    test rax, rax
    jz .insert              ; Slot vacío -> insertar

    cmp [r14 + 8], r12      ; ¿coincide la longitud?
    jne .next_slot

    ; Comparar el nombre byte a byte (name_len bytes).
    push rdi                ; Preservar RDI (inicio del valor)
    mov rsi, rax            ; nombre almacenado
    mov rdi, r13            ; nombre consultado
    mov rcx, r12            ; longitud
    cld
    repe cmpsb
    pop rdi                 ; Restaurar RDI
    je .store_value         ; Mismo nombre -> reutilizar slot

.next_slot:
    add r14, 32
    lea rax, [var_map + 8192]
    cmp r14, rax
    jb .no_wrap
    lea r14, [var_map]
.no_wrap:
    inc r8
    cmp r8, 256
    jae .error              ; Tabla llena (no debería pasar)
    jmp .probe

.insert:
    mov [r14], r13          ; Guardar puntero al nombre
    mov [r14 + 8], r12      ; Guardar longitud del nombre

.store_value:
    ; 4. Parsear y guardar el valor (tag en +16, value en +24).
    lea r9, [r14 + 16]
    call parse_and_store_value

    ; 5. Determinar si hay más variables o terminamos el mapa.
    ;    parse_and_store_value deja RDI en el siguiente delimitador (',' o '\n').
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
    inc rdi                 ; Saltamos la coma
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
