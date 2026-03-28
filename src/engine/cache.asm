; =============================================================================
; Module: src/engine/cache.asm (V3.2 - ABI Safe)
; Project: La Roca Rules Engine
; Responsibility: JIT Cache with Disk Persistence in .cache/ folder.
; Slot Structure: [8 bytes Hash] [512 bytes Bytecode]
; =============================================================================

section .data
    ; Directory prefix (Folder must exist: mkdir -p .cache)
    cache_dir       db ".cache/", 0
    plan_ext        db ".plan", 0

section .bss
    ; RAM Cache Table (For High-Performance 80k+ RPS)
    cache_table     resb 520 * 1024

    ; Path construction buffer: ".cache/HASH_HEX.plan"
    path_buffer     resb 128

    ; String Pool for literal persistence
    string_pool     resb 65536
    pool_ptr        resq 1

section .text
    global cache_lookup
    global cache_store_plan
    global cache_clear

; -----------------------------------------------------------------------------
; Function: cache_lookup
; Use Case: O(1) RAM lookup for a pre-compiled bytecode plan.
; In: RDI = 64-bit Hash of the rule string
; Out: RAX = Pointer to Bytecode (Plan) or 0 if Miss
; -----------------------------------------------------------------------------
cache_lookup:
    push rbx
    mov rbx, rdi            ; Save hash

    ; Calculate slot index: Index = Hash & 1023
    mov rax, rdi
    and rax, 1023

    ; Calculate Offset: Offset = Index * 520
    imul rax, rax, 520
    lea rdx, [cache_table + rax]

    ; Check if stored hash matches requested hash
    cmp [rdx], rbx
    jne .miss

    ; Cache Hit: Return pointer to bytecode area (Slot + 8)
    lea rax, [rdx + 8]
    pop rbx
    ret

.miss:
    xor rax, rax            ; Return NULL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Function: cache_store_plan
; Use Case: Persist a new plan in both RAM and Disk (.cache/ folder).
; In: RDI = 64-bit Hash, RSI = Source Bytecode Buffer (512 bytes)
; -----------------------------------------------------------------------------
cache_store_plan:
    push rdi                ; Save Hash
    push rsi                ; Save Source Ptr
    push rcx

    ; 1. RAM Persistence (Critical for performance)
    mov rax, rdi
    and rax, 1023
    imul rax, rax, 520
    lea r8, [cache_table + rax]
    mov [r8], rdi           ; Store Hash in slot

    lea rdi, [r8 + 8]       ; Destination: Slot Bytecode area
    mov rcx, 64             ; 512 bytes / 8
    cld
    rep movsq               ; RSI already points to source

    ; 2. DISCO Persistence (Debug/Evidence in .cache/)
    pop rsi                 ; Restore Source Ptr (Bytecode)
    pop rdi                 ; Restore Hash
    push rsi                ; Re-save for write syscall
    push rdi

    call save_to_disk_debug

    pop rdi
    pop rsi
    pop rcx
    ret

; -----------------------------------------------------------------------------
; Internal Routine: save_to_disk_debug
; In: RDI = Hash, RSI = Bytecode Buffer
; -----------------------------------------------------------------------------
save_to_disk_debug:
    ; 🛡️ REGISTER PROTECTION SHIELD (System V ABI)
    push r12                ; Preserve R12 (Used for Hash)
    push r13                ; Preserve R13 (Used for File Descriptor)
    push rsi                ; Preserve RSI (Bytecode Ptr) - Pushed LAST to be popped FIRST

    ; --- STEP A: Build Path ".cache/[HASH_HEX].plan" ---
    mov r12, rdi            ; R12 = Hash
    lea rdi, [path_buffer]
    lea rsi, [cache_dir]

    ; 1. Copy ".cache/" prefix
.copy_prefix:
    mov al, [rsi]
    mov [rdi], al
    inc rdi
    inc rsi
    test al, al
    jnz .copy_prefix
    dec rdi                 ; Backtrack over null terminator to append

    ; 2. Convert Hash to Hex string
    mov rax, r12
    call .hex_to_string     ; RDI advances as it writes hex chars

    ; 3. Copy ".plan" extension and null terminate
    lea rsi, [plan_ext]
.copy_ext:
    mov al, [rsi]
    mov [rdi], al
    inc rdi
    inc rsi
    test al, al
    jnz .copy_ext

    ; --- STEP B: File Syscalls ---
    ; sys_open (2) with O_CREAT (64) | O_WRONLY (1) | O_TRUNC (512)
    mov rax, 2              ; sys_open
    lea rdi, [path_buffer]
    mov rsi, 577            ; 64 | 1 | 512
    mov rdx, 0644o          ; Permissions rw-r--r--
    syscall

    test rax, rax
    js .fail                ; Abort if folder doesn't exist (rax < 0)

    mov r13, rax            ; 🚨 R13 = File Descriptor (Safe because we pushed it)

    ; sys_write (1)
    mov rax, 1              ; sys_write
    mov rdi, r13
    pop rsi                 ; 🚨 RESTORE BYTECODE POINTER (Stack now has R13, R12)
    mov rdx, 512            ; Plan size
    syscall

    ; sys_close (3)
    mov rax, 3              ; sys_close
    mov rdi, r13
    syscall

    ; 🛡️ CLEAN EXIT (Pop remaining registers in reverse order)
    pop r13                 ; Restore original R13
    pop r12                 ; Restore original R12
    ret

.fail:
    ; 🛡️ ERROR EXIT (Pop all 3 if we jump here before sys_write)
    pop rsi                 ; Restore RSI
    pop r13                 ; Restore R13
    pop r12                 ; Restore R12
    ret

; Helper: Convert RAX to Hex string at [RDI]
.hex_to_string:
    mov rcx, 16             ; 16 nibbles for 64 bits
.hex_loop:
    rol rax, 4              ; Rotate left to extract highest nibble
    mov rdx, rax
    and rdx, 0xF
    cmp dl, 9
    jbe .is_digit
    add dl, 7               ; Adjust for 'A'-'F'
.is_digit:
    add dl, '0'
    mov [rdi], dl
    inc rdi
    loop .hex_loop
    ret

; -----------------------------------------------------------------------------
; Function: cache_clear
; Use Case: Wipe RAM table and reset String Pool.
; -----------------------------------------------------------------------------
cache_clear:
    lea rdi, [cache_table]
    mov rcx, 66560          ; (520 * 1024) / 8
    xor rax, rax
    cld
    rep stosq               ; Zero out table

    lea rax, [string_pool]
    mov [pool_ptr], rax
    ret