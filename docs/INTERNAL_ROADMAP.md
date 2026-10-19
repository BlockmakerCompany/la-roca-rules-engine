# 🪨 La Roca — Internal Roadmap (Findings and Fix Plan)

> Internal working document. Records the problems found during the code
> review (v1.0.0, commit `a8286d2`) and the order in which they should be
> attacked. This is not marketing material; this is where the broken stuff
> gets written down.

---

## Executive summary

The engine is impressive as an engineering exercise (x86_64 assembly, epoll,
hybrid JIT/VM), but it has **two silent-correctness bugs** and a series of
performance and robustness problems that contradict the README claims.
Priority:

1. **Correctness** (it can return the wrong result without warning).
2. **Performance** (unconditional logging in the hot path).
3. **Network robustness** (fixed buffer, no timeouts, no method validation).
4. **Language correctness** (2-character operators).
5. **Documentation** (false claims and dead code).

---

## 🔴 P0 — Correctness (wrong results without an error)

### BUG-1: Variable map with an 8-bit hash and no collision resolution — ✅ RESOLVED (Phase A)

- **Where:**
  - `src/compiler/hashing.asm:65` → `and rax, 0xFF` (256-slot hash).
  - `src/compiler/map_parser.asm:47-49` → writes straight into the slot.
  - `src/alu/operand.asm:64-66` → reads straight from the slot, without comparing the name.
- **What happens:** the variable name is hashed to 8 bits and used as a direct
  index. **The stored name is never checked against the one being looked up.**
  Two colliding variables overwrite each other and the lookup returns the wrong
  value **without any error**.
- **Impact:** by the birthday paradox, with ~16 variables there is already a
  ~40% chance of collision; with ~23, ~65%. A production context map (20-30
  keys) will collide almost certainly. In a rules engine this means **wrong
  decisions in normal operation**, not in an edge case.
- **Aggravating factor:** `map_parser.asm` does not check whether the slot was
  already taken, so the collision is both read wrong and written wrong.
- **Fix applied (Phase A):**
  - `src/compiler/hashing.asm`: `hash_name` replaces `hash_token_8`; it returns
    a 64-bit FNV-1a hash, the length, and a pointer to the name.
  - `src/compiler/map_parser.asm`: `var_map` moves to 32-byte slots
    `[name_ptr 8][name_len 8][tag 8][value 8]` (256 slots, 8192 bytes) with
    *open addressing* (linear probing) and name verification on store.
  - `src/alu/operand.asm`: `lookup_var` (helper) resolves by name with full
    verification (length + `repe cmpsb`); used by variable and by `#`.
  - Collision test in `tests/test.sh` (section 6b): `ba` and `iz` collide under
    the legacy DJB2-8 hash (both → 3) and now resolve independently.
- **Pending (Phase B):** the compiled path (`vm.asm .op_push_var`) still
  indexes `var_map` by the index baked into the bytecode; it is dead code in
  practice (see BUG-8) and needs to be aligned with the new layout.

### BUG-2: JIT cache validates only the hash, not the rule — ✅ RESOLVED (cache disabled)

- **Where:** `src/engine/cache.asm:48` → `cmp [rdx], rbx` (64-bit hash only).
- **What happens:** `cache_lookup` treats it as a "hit" when the hash matches,
  without re-comparing the original rule string. FNV-1a is not cryptographic:
  collisions are generable. A false hit returns another rule's bytecode.
- **Persistence:** `cache_store_plan` writes to disk at `.cache/<hash>.plan`
  (`cache.asm:135-153`), so a collision **survives restarts**.
- **Fix applied:** the JIT cache was **disabled** (`cache_lookup` always
  returns miss, `cache_store_plan` is a no-op). See BUG-8 for the root cause.
  With the cache off, BUG-2 has no effect (there is never a hit).

### BUG-8: The JIT cache bakes resolved variable values (stale data) — ✅ RESOLVED (cache disabled)

- **Where:**
  - `src/compiler/lexer_math.asm:53-59`: if `get_operand` returns a float, it
    emits `emit_push_const` with the **already-resolved value** (not the reference).
  - `src/engine/cache.asm` + `src/compiler/parser.asm`: the cache is keyed
    **only by rule hash** (`cache_lookup(hash)`), without the context.
  - `cache_clear` is never called: the plan persists in RAM for the whole
    process and on disk (`.cache/*.plan`).
- **What happens:** an arithmetic rule with variables (e.g. `(total / parts) = 25`)
  compiles on the first request baking in the values of `total` and `parts`. On
  the second request with a different context, the cache hit reuses those stale
  values and returns the **wrong** result.
- **Impact:** correctness in normal operation for any cached arithmetic rule
  with variables.
- **Tracing note:** `emit_push_var` (opcode 0x01) is only emitted for *string*
  variables (RAX==2), and passes `R12` (pointer, not hash) as the argument: it
  is a broken/dead path. *Float* variables go through `emit_push_const`. That
  is why `vm.asm .op_push_var` is never exercised in practice.
- **Fix applied (stopgap):** the JIT cache was **disabled** in
  `src/engine/cache.asm` (`cache_lookup` → always miss, `cache_store_plan` →
  no-op). Every request is interpreted fresh and returns the correct result.
  Regression tests added in `tests/test.sh` (section 15).
- **Root cause (for the rework):**
  - `emit_comparison` and `emit_logic` **are never called**; the compiled plan
    only contains arithmetic (push_const/push_var/push_now + math ops).
  - Pure comparison rules (e.g. `7>2`) compile to an empty `[END]` plan; on a
    cache hit, `vm_execute` reads garbage from the stack as a "dangling" value
    and always returns `true`.
  - Float variables are baked as constants (`emit_push_const`), so the plan
    reuses stale values on the next request.
- **Definitive fix (future):** emit the full plan (comparisons + logic) and
  resolve variables by name at VM runtime (string pool), or don't cache rules
  that reference variables.

---

## 🟠 P1 — Performance

### BUG-3: Unconditional logging in the hot path

- **Where:** `src/utils/logger.asm:14-32` (`log_internal_str` always does
  `sys_write`, ignoring `log_level`). Only `types.asm:36` and `net/utils.asm:24`
  respect the level.
- **What happens:** there are 20+ logging calls per evaluation (lexer,
  evaluator, `evaluator_dispatch.asm`, `math_ops.asm`, `math_cmp.asm`,
  `operand.asm`). Each one is a `sys_write` — a syscall — per request.
- **Impact:** contradicts the 112k RPS claim (`BENCHMARKS.md`). With dozens of
  logging syscalls per request, that number is not reachable on the real path.
- **Proposed fix:** gate `log_internal_str` by `log_level` (only emit
  trace/debug if the level calls for it), and/or compile the logs out of the
  hot path.

---

## 🟡 P2 — Network robustness

### BUG-4: Fixed 1024-byte buffer + a single `read`

- **Where:** `src/net/server.asm:8` (`buffer resb 1024`) and `server.asm:126-130`
  (a single `sys_read` of up to 1024 bytes).
- **What happens:**
  - A request >1 KB or fragmented by TCP is processed **partially**.
  - If the `read` returns exactly 1024 bytes, the buffer is left without a
    null-terminator and the scanners (`hashing.asm`, `types.asm`, `strings.asm`)
    read past the buffer.
- **Proposed fix:** read loop until `\r\n\r\n` + `Content-Length`, or a circular
  buffer with an explicit limit.

### BUG-5: No timeouts, no connection limit

- **Where:** `src/net/server.asm` in full (epoll without `EPOLLOUT`, without timers).
- **What happens:** a client that opens a connection and sends nothing leaves
  it hanging forever; N idle connections = trivial DoS.
- **Proposed fix:** idle timeout (re-armable) and backlog/connection limit.

### BUG-6: The router does not validate the HTTP method

- **Where:** `src/net/router.asm` (skips 4/5 bytes and compares the path).
- **What happens:** `XXXXX/eval`, `DELETE/eval`, etc. match the same as
  `POST /eval`. The doc says "POST /eval".
- **Proposed fix:** validate the first bytes of the request against `POST`.

---

## 🟢 P3 — Language correctness

### BUG-7: 2-character operators not implemented — 📝 Not documented

- **Where:** `src/alu/evaluator.asm` (advances 1 byte with `inc rdi` upon
  detecting a comparison operator). `parser.asm:109-121` *does* recognize `>=`,
  `<=`, `==`, `!=`, `^=` when deciding map vs rule (unfinished intent).
- **What happens:** `==`, `!=`, `>=`, `<=` are not processed correctly; the
  second character is left as noise for the parser.
- **Status:** the README (`Supported Operators`) **does not document** these
  operators, so it is not a bug of an advertised feature. If they are to be
  supported, the evaluator must consume both bytes and they must be documented.

---

## ⚪ P4 — Documentation / false claims and dead code

- **FNV-1a vs DJB2:** `README.md:47` says the variable hash uses FNV-1a;
  `hashing.asm:12-66` implements **DJB2** (`hash = hash*33 + char`). The real
  FNV-1a is in `hash_rules_64` (cache), not in the variable map.
- **"Zero floating-point drift":** the engine uses `addsd`/`mulsd`/`divsd`
  (IEEE-754 doubles). Drift exists; the claim is false.
- **"Zero-copy strings":** `types.asm:117` (`mov byte [rdi], 0`) mutates the
  buffer to terminate the strings; it is not zero-copy.
- **Dead code:** `tokenize_and_store` (`src/compiler/tokenizer.asm`) is exported
  but the string parsing is a broken placeholder; nothing references it other
  than its own `global`.
- **Performance claim:** the "112k+ RPS" (README and `BENCHMARKS.md`) is not
  reproducible with the current logging enabled (see BUG-3).

---

## Proposed action plan

| # | Task | Priority | Risk |
|---|-------|----------|------|
| 1 | ✅ Redesign `var_map` with open addressing + name verification | P0 | High (touches internal ABI) |
| 2 | ✅ Collision test (ba/iz) in `tests/test.sh` | P0 | Low |
| 2b | ✅ Disable broken JIT cache (BUG-2 + BUG-8) with regression tests | P0 | Low |
| 3 | ✅ (absorbed into 2b) JIT cache validation | P0 | Medium |
| 4 | Gate logging by `log_level` | P1 | Low |
| 5 | Read loop + buffer limit in the server | P2 | Medium |
| 6 | Idle timeout and connection limit | P2 | Medium |
| 7 | Validate `POST` method in the router | P2 | Low |
| 8 | 2-character operators (`==`, `!=`, `>=`, `<=`) — not documented | P3 | Medium |
| 9 | Fix/clean README and BENCHMARKS (false claims, DJB2) | P4 | Low |
| 10 | Remove or finish `tokenize_and_store` | P4 | Low |

---

## Implementation notes

- **Open addressing** (fix BUG-1): keep the hash fast, but lower the collision
  probability to negligible levels (64-bit hash) and add the verification
  *strcmp*. The cost of a short `strcmp` per lookup is negligible compared to
  the syscalls that will be removed in BUG-3.
- **Tests:** the repo has `tests/test.sh` (E2E suite). Add a case that forces an
  8-bit hash collision (two distinct names with the same 256-slot hash) and
  verify it returns the correct value.
- **Don't touch the network ABI without benchmarks:** the P0/P1 changes are the
  ones that move the needle most; P2 changes the connection model and deserves
  its own load-test cycle (`tests/bench.go`).
