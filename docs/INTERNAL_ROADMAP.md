# 🪨 La Roca — Internal Roadmap (Hallazgos y Plan de Arreglos)

> Documento interno de trabajo. Registra los problemas encontrados en la
> revisión de código (v1.0.0, commit `a8286d2`) y el orden en que conviene
> atacarlos. No es material de marketing; acá se anota lo que está roto.

---

## Resumen ejecutivo

El motor es impresionante como ejercicio de ingeniería (assembly x86_64,
epoll, JIT/VM híbrido), pero tiene **dos bugs de corrección silenciosa** y
una serie de problemas de rendimiento y robustez que contradicen los claims
del README. Prioridad:

1. **Corrección** (puede devolver el resultado equivocado sin avisar).
2. **Rendimiento** (logging incondicional en el hot path).
3. **Robustez de red** (buffer fijo, sin timeouts, sin validar método).
4. **Correctitud del lenguaje** (operadores de 2 caracteres).
5. **Documentación** (claims falsos y código muerto).

---

## 🔴 P0 — Corrección (resultados incorrectos sin error)

### BUG-1: Mapa de variables con hash de 8 bits, sin resolución de colisiones — ✅ RESUELTO (Fase A)

- **Dónde:**
  - `src/compiler/hashing.asm:65` → `and rax, 0xFF` (hash de 256 slots).
  - `src/compiler/map_parser.asm:47-49` → escribe directo en el slot.
  - `src/alu/operand.asm:64-66` → lee directo del slot, sin comparar el nombre.
- **Qué pasa:** el nombre de la variable se hashea a 8 bits y se usa como
  índice directo. **Nunca se verifica que el nombre guardado sea el que se
  busca.** Dos variables que colisionan se pisan mutuamente y el lookup
  devuelve el valor equivocado **sin ningún error**.
- **Impacto:** por la paradoja del cumpleaños, con ~16 variables ya hay ~40%
  de probabilidad de colisión; con ~23, ~65%. Un context map de producción
  (20-30 claves) colisiona casi seguro. En un motor de reglas esto significa
  **decisiones incorrectas en operación normal**, no en un caso extremo.
- **Agrava:** `map_parser.asm` no valida si el slot ya estaba ocupado, así que
  la colisión además de leerse mal queda escrita mal.
- **Fix aplicado (Fase A):**
  - `src/compiler/hashing.asm`: `hash_name` reemplaza a `hash_token_8`; devuelve
    hash FNV-1a de 64 bits, longitud y puntero al nombre.
  - `src/compiler/map_parser.asm`: `var_map` pasa a slots de 32 bytes
    `[name_ptr 8][name_len 8][tag 8][value 8]` (256 slots, 8192 bytes) con
    *open addressing* (linear probing) y verificación de nombre en el store.
  - `src/alu/operand.asm`: `lookup_var` (helper) resuelve por nombre con
    verificación completa (longitud + `repe cmpsb`); usado por variable y por `#`.
  - Test de colisión en `tests/test.sh` (sección 6b): `ba` y `iz` colisionan
    bajo el hash DJB2-8 legado (ambos → 3) y ahora se resuelven independientes.
- **Pendiente (Fase B):** el camino compilado (`vm.asm .op_push_var`) todavía
  indexa `var_map` por el índice horneado en el bytecode; es código muerto en la
  práctica (ver BUG-8) y hay que alinearlo con el nuevo layout.

### BUG-2: Cache JIT valida solo el hash, no la regla — ✅ RESUELTO (cache desactivado)

- **Dónde:** `src/engine/cache.asm:48` → `cmp [rdx], rbx` (solo hash de 64 bits).
- **Qué pasa:** `cache_lookup` considera "hit" si el hash coincide, sin
  re-comparar el string original de la regla. FNV-1a no es criptográfico:
  colisiones generables. Un hit falso devuelve el bytecode de otra regla.
- **Persistencia:** `cache_store_plan` escribe a disco en `.cache/<hash>.plan`
  (`cache.asm:135-153`), así que una colisión **sobrevive entre reinicios**.
- **Fix aplicado:** el cache JIT quedó **desactivado** (`cache_lookup` devuelve
  siempre miss, `cache_store_plan` es no-op). Ver BUG-8 para la causa raíz.
  Con el cache apagado, BUG-2 queda sin efecto (nunca hay hit).

### BUG-8: El cache JIT hornea valores resueltos de variables (datos viejos) — ✅ RESUELTO (cache desactivado)

- **Dónde:**
  - `src/compiler/lexer_math.asm:53-59`: si `get_operand` devuelve un float,
    se emite `emit_push_const` con el **valor ya resuelto** (no la referencia).
  - `src/engine/cache.asm` + `src/compiler/parser.asm`: el cache se indexa
    **solo por hash de regla** (`cache_lookup(hash)`), sin el contexto.
  - `cache_clear` nunca se llama: el plan persiste en RAM todo el proceso y en
    disco (`.cache/*.plan`).
- **Qué pasa:** una regla aritmética con variables (ej. `(total / parts) = 25`)
  compila en el primer request horneando los valores de `total` y `parts`. En el
  segundo request con un contexto distinto, el cache hit reusa esos valores
  viejos y devuelve el resultado **incorrecto**.
- **Impacto:** correctness en operación normal para cualquier regla aritmética
  cacheada con variables.
- **Nota de trazado:** `emit_push_var` (opcode 0x01) solo se emite para
  variables *string* (RAX==2), y pasa `R12` (puntero, no hash) como argumento:
  es una ruta rota/muerta. Las variables *float* van por `emit_push_const`.
  Por eso `vm.asm .op_push_var` no se ejerce en la práctica.
- **Fix aplicado (stopgap):** el cache JIT quedó **desactivado** en
  `src/engine/cache.asm` (`cache_lookup` → siempre miss, `cache_store_plan` →
  no-op). Cada request se interpreta fresco y devuelve el resultado correcto.
  Tests de regresión agregados en `tests/test.sh` (sección 15).
- **Causa raíz (para el rework):**
  - `emit_comparison` y `emit_logic` **nunca se llaman**; el plan compilado solo
    contiene aritmética (push_const/push_var/push_now + ops matemáticas).
  - Las reglas de comparación pura (ej. `7>2`) compilan a un plan vacío `[END]`;
    en el cache hit, `vm_execute` lee basura del stack como valor "dangling" y
    devuelve `true` siempre.
  - Las variables float se hornean como constantes (`emit_push_const`), así que
    el plan reusa valores viejos en el siguiente request.
- **Fix definitivo (futuro):** emitir el plan completo (comparaciones + lógica)
  y resolver variables por nombre en tiempo de ejecución del VM (string pool),
  o no cachear reglas que referencien variables.

---

## 🟠 P1 — Rendimiento

### BUG-3: Logging incondicional en el hot path

- **Dónde:** `src/utils/logger.asm:14-32` (`log_internal_str` hace `sys_write`
  siempre, ignora `log_level`). Solo `types.asm:36` y `net/utils.asm:24`
  respetan el nivel.
- **Qué pasa:** hay 20+ llamadas de logging por evaluación (lexer, evaluator,
  `evaluator_dispatch.asm`, `math_ops.asm`, `math_cmp.asm`, `operand.asm`).
  Cada una es un `sys_write` — una syscall — por request.
- **Impacto:** contradice el claim de 112k RPS (`BENCHMARKS.md`). Con decenas
  de syscalls de logging por request, ese número no es alcanzable en la ruta
  real.
- **Fix propuesto:** gatear `log_internal_str` por `log_level` (solo emitir
  trace/debug si el nivel lo pide), y/o compilar los logs fuera del hot path.

---

## 🟡 P2 — Robustez de red

### BUG-4: Buffer fijo de 1024 bytes + un único `read`

- **Dónde:** `src/net/server.asm:8` (`buffer resb 1024`) y `server.asm:126-130`
  (un solo `sys_read` de hasta 1024 bytes).
- **Qué pasa:**
  - Un request >1 KB o fragmentado por TCP se procesa **a medias**.
  - Si el `read` devuelve exactamente 1024 bytes, el buffer queda sin
    null-terminator y los scanners (`hashing.asm`, `types.asm`, `strings.asm`)
    leen fuera del buffer.
- **Fix propuesto:** loop de lectura hasta `\r\n\r\n` + `Content-Length`, o
  buffer circular con límite explícito.

### BUG-5: Sin timeouts, sin límite de conexiones

- **Dónde:** `src/net/server.asm` completo (epoll sin `EPOLLOUT`, sin timers).
- **Qué pasa:** un cliente que abre conexión y no envía nada la deja colgada
  para siempre; N conexiones inactivas = DoS trivial.
- **Fix propuesto:** timeout de idle (rearmable) y backlog/limite de conexiones.

### BUG-6: El router no valida el método HTTP

- **Dónde:** `src/net/router.asm` (salta 4/5 bytes y compara el path).
- **Qué pasa:** `XXXXX/eval`, `DELETE/eval`, etc. matchean igual que
  `POST /eval`. La doc dice "POST /eval".
- **Fix propuesto:** validar los primeros bytes del request contra `POST`.

---

## 🟢 P3 — Correctitud del lenguaje

### BUG-7: Operadores de 2 caracteres sin implementar — 📝 No documentado

- **Dónde:** `src/alu/evaluator.asm` (avanza 1 byte con `inc rdi` al detectar
  un operador de comparación). `parser.asm:109-121` *sí* reconoce `>=`, `<=`,
  `==`, `!=`, `^=` al decidir mapa vs regla (intención no completada).
- **Qué pasa:** `==`, `!=`, `>=`, `<=` no se procesan correctamente; el segundo
  carácter queda como ruido para el parser.
- **Estado:** el README (`Supported Operators`) **no documenta** estos
  operadores, así que no es un bug de feature anunciada. Si se quieren
  soportar, hay que consumir los dos bytes en el evaluador y documentarlos.

---

## ⚪ P4 — Documentación / claims falsos y código muerto

- **FNV-1a vs DJB2:** `README.md:47` dice que el hash de variables usa FNV-1a;
  `hashing.asm:12-66` implementa **DJB2** (`hash = hash*33 + char`). El FNV-1a
  real está en `hash_rules_64` (cache), no en el mapa de variables.
- **"Zero floating-point drift":** el motor usa `addsd`/`mulsd`/`divsd`
  (IEEE-754 doubles). El drift existe; el claim es falso.
- **"Zero-copy strings":** `types.asm:117` (`mov byte [rdi], 0`) muta el buffer
  para cerrar las cadenas; no es zero-copy.
- **Código muerto:** `tokenize_and_store` (`src/compiler/tokenizer.asm`) está
  exportado pero el parseo de strings es un placeholder roto; no lo referencia
  nada más que su propio `global`.
- **Claim de rendimiento:** el "112k+ RPS" (README y `BENCHMARKS.md`) no es
  reproducible con el logging actual encendido (ver BUG-3).

---

## Plan de acción propuesto

| # | Tarea | Prioridad | Riesgo |
|---|-------|-----------|--------|
| 1 | ✅ Rediseñar `var_map` con open addressing + verificación de nombre | P0 | Alto (toca ABI interna) |
| 2 | ✅ Test de colisión (ba/iz) en `tests/test.sh` | P0 | Bajo |
| 2b | ✅ Desactivar cache JIT roto (BUG-2 + BUG-8) con tests de regresión | P0 | Bajo |
| 3 | ✅ (absorbido en 2b) Validación del cache JIT | P0 | Medio |
| 4 | Gatear logging por `log_level` | P1 | Bajo |
| 5 | Loop de lectura + límite de buffer en el server | P2 | Medio |
| 6 | Timeout de idle y límite de conexiones | P2 | Medio |
| 7 | Validar método `POST` en el router | P2 | Bajo |
| 8 | Operadores de 2 caracteres (`==`, `!=`, `>=`, `<=`) — no documentados | P3 | Medio |
| 9 | Corregir/limpiar README y BENCHMARKS (claims falsos, DJB2) | P4 | Bajo |
| 10 | Eliminar o terminar `tokenize_and_store` | P4 | Bajo |

---

## Notas de implementación

- **Open addressing** (fix BUG-1): mantener el hash rápido, pero bajar la
  probabilidad de colisión a niveles despreciables (hash de 64 bits) y agregar
  el *strcmp* de verificación. El costo de un `strcmp` corto por lookup es
  despreciable frente a las syscalls que se van a eliminar en BUG-3.
- **Tests:** el repo tiene `tests/test.sh` (suite E2E). Agregar un caso que
  fuerce una colisión de hash de 8 bits (dos nombres distintos con el mismo
  hash de 256 slots) y verificar que devuelve el valor correcto.
- **No tocar el ABI de red sin benchmarks:** los cambios de P0/P1 son los que
  más mueven la aguja; P2 cambia el modelo de conexiones y merece su propio
  ciclo de pruebas de carga (`tests/bench.go`).
