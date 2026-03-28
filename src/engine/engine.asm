; =============================================================================
; Module: src/core/engine.asm (V3.0 - JIT Orchestrator)
; Project: La Roca Rules Engine
; Responsibility: Orchestrate Cache, Compiler, and VM for maximum RPS.
; =============================================================================

section .text
    global engine_eval_and
    global engine_eval_or

    ; Frontend / Lexer
    extern evaluate_expression, advance_to_next_rule, is_compiling

    ; Cache & Hashing
    extern hash_rules_64, cache_lookup

    ; VM & Compiler
    extern vm_execute, init_compilation, finalize_compilation

; -----------------------------------------------------------------------------
; Strategy: AND (Fail-Fast)
; -----------------------------------------------------------------------------
engine_eval_and:
.loop:
    ; --- ⚡️ JIT / CACHE LAYER ---
    push rdi                ; Save current rule pointer
    call hash_rules_64      ; RAX = 64-bit Hash of the rule string
    mov rdi, rax            ; RDI = Hash for lookup
    call cache_lookup       ; RAX = Puntero a Bytecode o 0
    pop rdi                 ; Restore rule pointer

    test rax, rax
    jnz .cache_hit

.cache_miss:
    ; 1. Prepare Emitter
    push rdi
    call init_compilation
    mov byte [is_compiling], 1
    pop rdi

    ; 2. Run Lexer (In Compile Mode)
    call evaluate_expression ; Result in RAX, also fills compile_buffer

    ; 3. Finalize and Store in Cache
    push rax                ; Save result
    push rdi                ; Save rule pointer
    call hash_rules_64      ; We need the hash again to store it
    mov rdi, rax            ; RDI = Hash
    call finalize_compilation ; Persists the buffer into cache_table
    mov byte [is_compiling], 0
    pop rdi
    pop rax                 ; Restore evaluation result
    jmp .check_result

.cache_hit:
    mov rdi, rax            ; RDI = Pointer to cached Bytecode
    call vm_execute         ; RAX = Result (0=True, 1=False)
    ; Note: VM doesn't return 3 (Panic) because bytecode is pre-validated

.check_result:
    ; 🚨 PRIORITY 1: Check for Fatal Error (3)
    cmp rax, 3
    je .done

    ; 🚨 PRIORITY 2: Check for False (1)
    test rax, rax
    jnz .return_false

    ; 🚨 PRIORITY 3: Check for more rules
    call advance_to_next_rule
    test al, al
    jnz .loop

.return_true:
    xor rax, rax
    ret

.return_false:
    mov rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; Strategy: OR (Succeed-Fast)
; -----------------------------------------------------------------------------
engine_eval_or:
.loop:
    ; --- ⚡️ JIT / CACHE LAYER ---
    push rdi
    call hash_rules_64
    mov rdi, rax
    call cache_lookup
    pop rdi

    test rax, rax
    jnz .cache_hit

.cache_miss:
    push rdi
    call init_compilation
    mov byte [is_compiling], 1
    pop rdi

    call evaluate_expression

    push rax
    push rdi
    call hash_rules_64
    mov rdi, rax
    call finalize_compilation
    mov byte [is_compiling], 0
    pop rdi
    pop rax
    jmp .check_result

.cache_hit:
    mov rdi, rax
    call vm_execute

.check_result:
    cmp rax, 3
    je .done

    test rax, rax
    jz .return_true             ; Succeed immediately

    call advance_to_next_rule
    test al, al
    jnz .loop

.return_false:
    mov rax, 1
    ret

.return_true:
    xor rax, rax
.done:
    ret