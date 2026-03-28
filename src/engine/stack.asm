; =============================================================================
; Module: src/core/stack.asm (V2.0 - Logic & Fall-through Fixed)
; Project: La Roca Rules Engine
; Responsibility: Dedicated stack for nested boolean evaluation (parentheses).
; =============================================================================

section .bss
    ; We'll support up to 64 levels of nested parentheses.
    ; Each level stores: [1 byte for partial_result] [1 byte for pending_op]
    eval_stack      resb 128
    stack_ptr       resq 1          ; Current depth pointer

section .text
    global stack_init
    global stack_push_level
    global stack_pop_level
    global stack_update_result
    global stack_set_operator       ; [FIX] Exported to allow Lexer access

; -----------------------------------------------------------------------------
; Function: stack_init
; Responsibility: Reset the stack pointer to the base.
; -----------------------------------------------------------------------------
stack_init:
    lea rax, [eval_stack]
    mov [stack_ptr], rax
    mov byte [rax], 0       ; [FIX] 0 represents TRUE in this engine
    mov byte [rax+1], 0     ; Default op = NONE / AND (0)
    ret

; -----------------------------------------------------------------------------
; Function: stack_push_level
; Responsibility: Called when '(' is found. Saves current state and
;                 prepares a clean level for the sub-expression.
; -----------------------------------------------------------------------------
stack_push_level:
    mov rdx, [stack_ptr]
    add rdx, 2              ; Move to next 2-byte slot
    mov [stack_ptr], rdx

    mov byte [rdx], 0       ; [FIX] 0 represents TRUE in this engine
    mov byte [rdx+1], 0     ; New level starts with NO operator
    ret

; -----------------------------------------------------------------------------
; Function: stack_pop_level
; Responsibility: Called when ')' is found. Returns the final result of the
;                 sub-expression in AL.
; -----------------------------------------------------------------------------
stack_pop_level:
    mov rdx, [stack_ptr]
    mov al, [rdx]           ; Capture the result of the level we are closing

    sub rdx, 2              ; Move back to the parent level
    mov [stack_ptr], rdx
    ret

; -----------------------------------------------------------------------------
; Function: stack_set_operator
; In: RSI = Operator (0 = AND, 1 = OR)
; Responsibility: Sets the pending operator for the current level.
; -----------------------------------------------------------------------------
stack_set_operator:
    mov rdx, [stack_ptr]
    mov [rdx+1], sil        ; SIL is the lower 8 bits of RSI (0 or 1)
    ret                     ; [FIX] Added missing return to prevent fall-through

; -----------------------------------------------------------------------------
; Function: stack_update_result
; In: AL = Result of the last comparison (0=True, 1=False)
; Responsibility: Merges the new result with the current level's partial result
;                 based on the active operator (AND/OR).
; -----------------------------------------------------------------------------
stack_update_result:
    mov rdx, [stack_ptr]
    mov cl, [rdx]           ; CL = Current partial result
    mov ch, [rdx+1]         ; CH = Pending operator (0=AND, 1=OR)

    test ch, ch
    jz .do_and

.do_or:
    ; Logic for OR: If either is True (0), result is True (0)
    and al, cl              ; True (0) if AL=0 OR CL=0
    mov [rdx], al
    ret

.do_and:
    ; Logic for AND: If either is False (1), result is False (1)
    or al, cl               ; False (1) if AL=1 OR CL=1
    mov [rdx], al
    ret