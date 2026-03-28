; =============================================================================
; Module: src/compiler/parser.asm (V5.6.1 - Clean NASM Syntax)
; Project: La Roca Rules Engine
; Responsibility: Route requests and trigger "Learn-on-the-fly" JIT Compilation.
; =============================================================================

section .bss
    global current_strategy
    current_strategy resq 1

section .text
    global parse_json_rule

    ; Global error handler (src/utils/errors.asm)
    extern eval_error

    ; Externs from Compiler layer (Analysis & JIT)
    extern clear_var_map, build_var_map, hash_rules_64
    extern is_compiling, init_compilation, finalize_compilation

    ; Externs from Engine layer (Execution)
    extern cache_lookup, vm_execute, engine_eval_and, engine_eval_or, stack_reset

; -----------------------------------------------------------------------------
; Function: parse_json_rule
; Responsibility: Parse HTTP payload, manage VarMap, and execute rules (JIT/VM).
; In:  RDI = Start of the HTTP request buffer.
; Out: RAX = 0 (True), 1 (False), 3 (Fatal Error).
; -----------------------------------------------------------------------------
parse_json_rule:
    push rbp                        ; Establish stack frame for stability
    mov rbp, rsp

    ; 1. Initialize request context
    call clear_var_map
    call stack_reset

    ; 2. Locate the HTTP Body (\r\n\r\n)
    mov rcx, 1024
    mov al, 0x0D                    ; Look for Carriage Return
.search_body:
    repne scasb
    test rcx, rcx
    jz .local_eval_error            ; If no body found, abort

    cmp byte [rdi], 0x0A            ; Line Feed?
    jne .search_body
    cmp byte [rdi+1], 0x0D          ; Second CR?
    jne .search_body
    cmp byte [rdi+2], 0x0A          ; Second LF?
    jne .search_body
    add rdi, 3                      ; RDI = Start of payload

    ; 3. Default Strategy: AND
    lea rax, [engine_eval_and]
    mov [current_strategy], rax

    ; 4. Check for 'MODE' override (e.g., MODE OR)
    cmp dword [rdi], 'MODE'
    jne .detect_payload_type
    add rdi, 5                      ; Skip 'MODE '

    cmp byte [rdi], 'O'             ; Check for 'OR'
    jne .skip_mode_line
    lea rax, [engine_eval_or]
    mov [current_strategy], rax

.skip_mode_line:
.find_nl:
    cmp byte [rdi], 0x0A            ; Scan until end of line
    je .next_line
    inc rdi
    jmp .find_nl
.next_line:
    inc rdi

.detect_payload_type:
    mov al, [rdi]
    cmp al, '-'                     ; Start of a rule?
    je .process_rules
    cmp al, '0'
    jl .scan_for_map
    cmp al, '9'
    jle .process_rules

.scan_for_map:
    push rdi                        ; Save current pointer
.scan_loop:
    mov al, [rdi]
    test al, al
    jz .pop_and_rules
    cmp al, 0x0A
    je .pop_and_map
    cmp al, '('
    je .pop_and_rules
    cmp al, '>'
    je .pop_and_rules
    cmp al, '<'
    je .pop_and_rules
    cmp al, '~'
    je .pop_and_rules
    cmp al, '^'
    je .pop_and_rules
    cmp al, '='
    je .check_rule_assign
    inc rdi
    jmp .scan_loop

.check_rule_assign:
    ; Check next char for complex operators (>=, <=, ==, !=, ^=)
    cmp byte [rdi+1], '>'
    je .pop_and_rules
    cmp byte [rdi+1], '<'
    je .pop_and_rules
    cmp byte [rdi+1], '='
    je .pop_and_rules
    cmp byte [rdi+1], '~'
    je .pop_and_rules
    cmp byte [rdi+1], '^'
    je .pop_and_rules
    inc rdi
    jmp .scan_loop

.pop_and_map:
    pop rdi
    call build_var_map
    jmp .skip_empty_lines

.pop_and_rules:
    pop rdi

.process_rules:
.skip_empty_lines:
    cmp byte [rdi], 0x0A
    jne .route_execution
    inc rdi
    jmp .skip_empty_lines

.route_execution:
    ; --- JIT / CACHE LOGIC ---
    push rdi                        ; [Stack: RulePtr]
    call hash_rules_64              ; RAX = 64-bit Hash
    push rax                        ; [Stack: RulePtr, Hash]

    mov rdi, rax
    call cache_lookup               ; Check if Compiled Plan exists
    test rax, rax
    jnz .cache_hit

.cache_miss:
    ; --- AUTO-LEARNING (JIT) ---
    mov byte [is_compiling], 1      ; Activate 'Compile' mode in Lexer
    call init_compilation           ; Reset Bytecode Buffer

    mov rdi, [rsp + 8]              ; Retrieve RulePtr from stack
    call [current_strategy]         ; Execute & Record -> RAX: 0, 1, or 3

    ; 🚨 PANIC CHECK: If evaluation failed (RAX=3), skip JIT finalization
    cmp rax, 3
    je .panic_abort_jit

    ; --- SUCCESS PATH (RAX 0 or 1) ---
    push rax                        ; Save result [Stack: RulePtr, Hash, RAX] (24 bytes)
    sub rsp, 8                      ; 🛡️ ALIGNMENT: 16-byte boundary (Total 32 bytes)

    mov rdi, [rsp + 16]             ; Retrieve Hash for indexing
    call finalize_compilation

    add rsp, 8                      ; Remove padding
    pop rax                         ; Restore Truth Result

    mov byte [is_compiling], 0
    add rsp, 16                     ; Clean stack (RulePtr, Hash)
    leave
    ret

.panic_abort_jit:
    ; If panic occurred, cleanup and exit safely without cache finalization
    mov byte [is_compiling], 0
    add rsp, 16                     ; Clean stack
    mov rax, 3                      ; Ensure we return the error code
    leave
    ret

.cache_hit:
    ; --- JIT FAST-PATH ---
    mov rdi, rax                    ; RAX = Pointer to Compiled Plan
    call vm_execute                 ; Run Virtual Machine
    add rsp, 16                     ; Clean stack
    leave
    ret

.local_eval_error:
    leave
    jmp eval_error                  ; Transfer control to global error handler