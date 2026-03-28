; =============================================================================
; Module: src/compiler/map_parser.asm
; Responsibility: Parse "key=value" pairs and populate the var_map.
; =============================================================================

section .bss
    global var_map
    var_map resb 4096       ; 256 entries * 16 bytes (Tag + Value)

section .text
    global build_var_map
    global clear_var_map
    extern hash_token_8
    extern parse_and_store_value
    extern eval_error

; -----------------------------------------------------------------------------
; Function: clear_var_map
; Responsibility: Zeroes out the variable map to prevent cross-request pollution.
; -----------------------------------------------------------------------------
clear_var_map:
    push rdi
    push rcx
    push rax
    lea rdi, [var_map]
    xor rax, rax
    mov rcx, 512            ; 512 * 8 bytes = 4096 bytes
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
    ; Si el primer carácter es un salto de línea, no hay mapa.
    cmp byte [rdi], 0x0A
    je .done

.map_loop:
    ; 1. Hashear el nombre de la variable (Token)
    ; hash_token_8 avanza RDI hasta encontrar un delimitador (ej: '=')
    call hash_token_8
    shl rax, 4              ; RAX = hash * 16 (tamaño del slot)
    lea r9, [var_map + rax] ; R9 = Puntero al slot en el mapa

    ; 2. Sincronizar con el símbolo '=' tolerando espacios
.find_equals:
    cmp byte [rdi], '='
    je .found_equals
    cmp byte [rdi], 0x0A    ; Error: llegamos al final de línea sin encontrar '='
    je eval_error
    cmp byte [rdi], 0       ; Error: fin de buffer inesperado
    je eval_error
    inc rdi
    jmp .find_equals

.found_equals:
    inc rdi                 ; Saltamos el '='

    ; 3. Parsear y guardar el valor (Float64 o String)
    ; R9 tiene el slot, RDI el inicio del valor.
    call parse_and_store_value

    ; 4. Determinar si hay más variables o si terminamos el mapa
    ; parse_and_store_value nos deja RDI en el siguiente delimitador (',' o '\n')

.check_delimiter:
    cmp byte [rdi], ','
    je .next_var
    cmp byte [rdi], 0x0A
    je .done

    ; Si hay un espacio después del valor pero antes del delimitador
    cmp byte [rdi], ' '
    jne eval_error
    inc rdi
    jmp .check_delimiter

.next_var:
    inc rdi                 ; Saltamos la coma
    jmp .map_loop

.done:
    ret