; =============================================================================
; Module: src/compiler/lexer_time.asm (V7.3)
; Project: La Roca Rules Engine
; Responsibility: Handle time tokens (NOW) with JIT/Interpreter Hybrid support.
; =============================================================================

section .data
    log_lex_now db "[DEBUG] [Lexer] Found Keyword: NOW", 0x0A, 0

section .text
    global handle_now

    ; Interpreter Externs
    extern lexer_main_loop, log_internal_str, is_compiling
    extern get_now_unix, internal_stack_push

    ; JIT Emitter Externs
    extern emit_push_now

; -----------------------------------------------------------------------------
; Handler: Built-in NOW
; -----------------------------------------------------------------------------
handle_now:
    add rdi, 3              ; Advance pointer past "NOW"

    ; 🛡️ STACK FRAME (16-byte alignment)
    ; Push RDI to preserve the rule pointer and subtract 8 to align the stack
    push rdi                ; -8 bytes
    sub rsp, 8              ; -16 bytes (ABI compliant for function calls)

    ; 1. Debug Logging
    lea rsi, [log_lex_now]
    call log_internal_str

    ; 2. JIT PATH (Optional)
    ; If compilation is active, emit the PUSH_NOW (0x04) opcode
    cmp byte [is_compiling], 1
    jne .interpreter_path
    call emit_push_now

; 3. INTERPRETER PATH (Required for first-run correctness)
.interpreter_path:
    call get_now_unix       ; RAX = Current Unix timestamp
    call internal_stack_push ; Push timestamp onto the Logic/VM stack

    ; --- CLEAN EXIT ---
    add rsp, 8              ; Restore stack alignment
    pop rdi                 ; Restore rule pointer
    jmp lexer_main_loop