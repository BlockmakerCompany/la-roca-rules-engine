# 🪨 La Roca: High-Performance Rules Engine

[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-blockmaker/la--roca--rules--engine-blue?logo=docker&logoColor=white)](https://hub.docker.com/r/blockmaker/la-roca-rules-engine)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Binary Size](https://img.shields.io/badge/Binary%20Size-22KB-blue)
![Image Size](https://img.shields.io/badge/Docker%20Image-41.6KB-blue)
![Language](https://img.shields.io/badge/Language-Assembly%20x86__64-red)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey)
![Company](https://img.shields.io/badge/Backed%20By-BlockMaker%20S.R.L.-black)

> An ultra-low latency, zero-allocation, SSE2-accelerated logic evaluation engine written entirely in **x86_64 Linux Assembly**.

La Roca is a high-speed decision-making oracle. It bypasses the "Abstraction Tax" of interpreted rule engines (like Drools, Python-based engines, or JSON-logic) by evaluating business rules directly on the metal. Using SSE2 hardware instructions for $Float64$ math and a High-Performance JIT Compiler that targets a custom 16-byte aligned Virtual Machine (VM), it achieves sub-microsecond decision latency.

---

### 💡 Why La Roca Rules? (The "Why" behind the "Metal")

In high-frequency environments—like HFT risk checks, fraud detection, or real-time game state validation—waiting for a JVM garbage collector or a Python interpreter to evaluate `balance > 100.50` is a bottleneck. **La Roca eliminates the overhead.**

* **SSE2 Direct Math:** We don't use high-level libraries. We use $ucomisd$ and $cvtsi2sd$ to compare $Float64$ values directly in hardware registers.
* **O(1) Context Resolution:** Descriptive variables (e.g., `user_credit_score`) are resolved via an internal FNV-1a hash, mapping strings to memory offsets in constant time.
* **Fail-Fast Strategy:** The engine implements short-circuit logic at the register level. If the first rule in an `AND` block fails, the engine aborts and responds immediately.

**Perfect for:** High-Frequency Trading (HFT) risk filters, Real-time Fraud Detection, Dynamic Pricing Engines, and Low-latency Ad-Tech bidding.

---

## 📑 Table of Contents

- [💡 Why La Roca Rules?](#-why-la-roca-rules-the-why-behind-the-metal)
- [⚡ Core Engineering Principles](#-core-engineering-principles)
- [⚡ Performance & Benchmarks](#-performance--benchmarks)
- [📂 Project Structure](#-project-structure)
- [🚀 Quick Start](#-quick-start)
- [📡 API Reference](#-api-reference)
- [🧠 Architecture: SSE2 & High-Precision Math](#-architecture-sse2--high-precision-math)
- [🧪 Testing & Validation](#-testing--validation)
- [🏢 Backed by BlockMaker S.R.L.](#-backed-by-blockmaker-srl)

---

## ⚡ Core Engineering Principles

* **Zero-Allocation:** The engine never calls `malloc()` or `free()`. The execution context is stored in pre-allocated, 16-byte aligned "Tagged Unions" to maximize L1 cache hits.
* **Hardware Sympathy (SSE2):** All numerical evaluations are performed using **Streaming SIMD Extensions 2**. This guarantees $Float64$ (double precision) accuracy with hardware-level speed.
* **O(1) Lexer & Hashing:** Instead of expensive string comparisons during evaluation, we hash variable names into 256 memory slots using the **FNV-1a algorithm**, ensuring constant-time lookups.
* **Register-Based Routing:** HTTP routing is performed by directly comparing 64-bit registers, bypassing the overhead of standard string-parsing libraries.
* **Deterministic Latency:** By removing the Garbage Collector and the Heap, La Roca provides a "Hard Real-Time" response profile.

---

## ⚡ Performance & Benchmarks

La Roca is designed for extreme throughput and ultra-low latency. By combining a **Hybrid JIT/Interpreter architecture**, keeping operations within the CPU's L1/L2 cache, and entirely avoiding the operating system's dynamic memory allocator (no heap `mallocs` or Garbage Collection), the engine operates at the theoretical limits of the hardware.

### The 112k+ RPS Milestone
In a high-frequency stress test using persistent HTTP/1.1 connections (`Connection: keep-alive`) on a single CPU core, the engine comfortably processes over **112,000 requests per second** with zero errors, even when evaluating Context Maps, floating-point math, and hierarchical logic.

```text
🚀 Starting High-Frequency Benchmark (map-and)
Target: localhost:8080 | Concurrency: 100 | Duration: 10s
---------------------------------------------------------
✅ Benchmark Completed!
Total Requests: 1123879
Total Errors:   0
Throughput:     112387 Requests/sec
---------------------------------------------------------
```

### Architectural Pillars of Speed
This level of performance is achieved through a combination of extreme low-level systems engineering techniques:

1. **Hybrid JIT & VM Stack Machine:** Rules are compiled on-the-fly into a 16-byte aligned bytecode format. Subsequent evaluations bypass the Lexer entirely, executing directly on a custom Virtual Machine (VM) for maximum throughput. Complex hierarchical rules (e.g., nested parentheses) gracefully fall back to the native Interpreter via a tactical Bailout mechanism.
2. **O(1) 64-bit Cache Persistence:** Pre-compiled execution plans are hashed using the FNV-1a algorithm and stored in an O(1) RAM cache (backed by disk persistence in `.cache/`), enabling instantaneous bytecode retrieval.
3. **Epoll Keep-Alive Loop:** By reusing TCP sockets via Linux `epoll`, we completely bypass the kernel overhead of the TCP 3-way handshake and teardown (`FIN_WAIT`/`CLOSE_WAIT`). The CPU focuses 100% on rule evaluation.
4. **Zero-Copy Memory Mutation:** String literals are never allocated or copied. The engine mutates the raw network buffer in-place (replacing the closing quote `"` with a null-terminator `\0`) and passes the pointer directly to the ALU.
5. **SSE2 Hardware Acceleration:** Float64 mathematical operations (`+`, `-`, `*`, `/`, `%`, `>`, `<`, `=`) are routed directly to the CPU's SIMD registers (`XMM0`-`XMM15`) and evaluated using native `ucomisd` instructions.
6. **O(1) DJB2 Variable Map:** Variable lookups do not allocate strings. The parser computes an 8-bit hash on the fly and jumps directly to the memory offset in a pre-allocated 256-slot Context Map.

---

### 📂 Project Structure

```text
.
├── src/
│   ├── main.asm                # Entry point & bootstrapper
│   ├── net/                    # Network & Protocol Layer
│   │   ├── server.asm          # TCP Server & Epoll Event Loop (with Zero-Out buffers)
│   │   ├── handlers.asm        # Specific endpoint logic (e.g., /eval POST routing)
│   │   ├── router.asm          # Register-based HTTP routing
│   │   ├── liveness.asm        # Healthcheck handlers (/live, /ready)
│   │   └── utils.asm           # Standard HTTP Responses
│   ├── compiler/               # Lexical Analysis (Frontend)
│   │   ├── parser.asm          # Payload extraction orchestrator
│   │   ├── map_parser.asm      # Context Map builder & key-value extractor
│   │   ├── lexer.asm           # Main expression FSM & loop orchestrator
│   │   ├── lexer_logic.asm     # AND, OR, and Parentheses logic handlers
│   │   ├── lexer_math.asm      # Arithmetic handlers (+, -, *, /, %)
│   │   ├── lexer_time.asm      # Time-based token handlers (NOW)
│   │   ├── tokenizer.asm       # Lexical tokenization
│   │   ├── hashing.asm         # O(1) Variable Name Hashing (Whitespace tolerant)
│   │   ├── types.asm           # ASCII to Tagged Unions (Float64 / Strings)
│   │   └── emit_bytecode.asm   # JIT Bytecode emitter
│   ├── engine/                 # Orchestration & State (Brain)
│   │   ├── engine.asm          # Macro-Orchestrator (Fail-Fast / Succeed-Fast)
│   │   ├── vm.asm              # Virtual Machine execution loop
│   │   ├── vm_stack.asm        # VM Data Stack for arithmetic (Math Stack)
│   │   ├── stack.asm           # Logic Stack for hierarchical expressions (AND/OR)
│   │   └── cache.asm           # JIT Bytecode Cache Storage
│   ├── alu/                    # Execution & Processing (Muscle)
│   │   ├── evaluator.asm       # Type Dispatcher
│   │   ├── evaluator_dispatch.asm # ALU routing logic (Strings vs Math)
│   │   ├── math_ops.asm        # SSE2 Arithmetic operations (Addition, Subtraction, etc.)
│   │   ├── math_cmp.asm        # SSE2 Float64 Comparisons (<, >, =)
│   │   ├── operand.asm         # Variable lookup and operand resolution
│   │   └── strings.asm         # Zero-Copy String operations (Quote-Aware & Robust Contains)
│   └── utils/                  # Cross-cutting utilities
│       ├── errors.asm          # Panic recovery and fatal error handling
│       ├── logger.asm          # Standardized micro-logging system
│       └── time.asm            # Unix timestamp and OS time integration
├── tests/
│   ├── test.sh                 # E2E Bash suite (Hierarchical Logic & Precision)
│   └── bench.go                # High-Frequency Concurrency Benchmark
├── Makefile                    # Modular Toolchain (NASM + LD)
├── Dockerfile                  # Multi-stage 'scratch' image builder
└── docker-compose.yml          # Cloud-native deployment manifest
```

---

## 🚀 Quick Start

"La Roca" is delivered as an ultra-lightweight, zero-dependency container. You can run the oracle in seconds using Docker or Podman.

### 1. Run the Oracle (Docker)

The official image is a "scratch" build, containing only the 22KB statically-linked Assembly binary.

```bash
# Pull the 41.6KB image from Docker Hub
docker pull blockmaker/la-roca-rules-engine

# Start the engine on port 8080
# We map a local .cache folder to persist JIT execution plans
mkdir -p .cache
docker run -d \
  -p 8080:8080 \
  -v $(pwd)/.cache:/app/.cache \
  --name la-roca \
  blockmaker/la-roca-rules-engine
```

### 2. Verify Liveness

Check if the engine is ready to evaluate logic:

```bash
curl -i http://localhost:8080/live
# Expected: HTTP/1.1 200 OK
```

### 3. Evaluate your first Rule

Send a POST request with a **Context Map** (variables) and a **Logic Rule**.

```bash
curl -X POST http://localhost:8080/eval \
  -d 'points=250, status="vip"
      (points > 200 AND status = "vip")'
```

**Response:**
```text
True
```

### 4. Running the High-Frequency Benchmark

If you have Go installed, you can verify the **112k+ RPS** throughput on your own hardware:

```bash
# Clone the repo and run the stress tester
git clone [https://github.com/BlockmakerCompany/la-roca-rules-engine.git](https://github.com/BlockmakerCompany/la-roca-rules-engine.git)
cd la-roca-rules-engine
go run tests/bench.go map-and
```

---

### 🛠️ Manual Build (For Purists)

If you prefer to compile from source, you'll need `nasm` and `ld` (binutils).

```bash
# Compile and link the Assembly source
make clean && make

# Run natively (Linux x86_64 only)
./bin/rules-engine
```

> **Note on Persistence:** The `.cache/` directory stores binary `.plan` files. These are 512-byte JIT-compiled bytecode buffers. If you delete this folder, the engine will simply re-compile the rules on the next request with a negligible "first-hit" latency penalty.

---

## 📡 API Reference

The engine listens on port `8080`. Decision results are returned in `< 1ms` with standard HTTP status codes.

| Endpoint | Method | Description |
| :--- | :--- | :--- |
| `/live` | `GET` | Liveness probe. Returns `200 OK`. |
| `/ready` | `GET` | Readiness probe. Returns `200 OK`. |
| `/eval` | `POST` | Primary evaluation endpoint. Returns `True`, `False`, or `Error`. |

### 🧮 Supported Operators

The engine features a dynamic Type Dispatcher that automatically routes operations to the hardware SSE2 ALU (for numbers), the Zero-Copy Memory ALU (for strings), or the Zero-Allocation Stack (for complex boolean logic).

| Operator | Name | Supported Types | Example |
| :---: | :--- | :--- | :--- |
| `+` | Addition | `Float64` | `5 + 5` |
| `-` | Subtraction | `Float64` | `10 - 5` |
| `*` | Multiplication | `Float64` | `price * 1.21` |
| `/` | Division | `Float64` | `total / 4` |
| `%` | Modulo | `Float64` | `10 % 3` |
| `>` | Greater Than | `Float64` | `balance > 100` |
| `<` | Less Than | `Float64` | `age < 18` |
| `=` | Strict Equality | `Float64`, `String` | `role = "admin"` |
| `~` | Contains | `String` | `email ~ "blockmaker"` |
| `^` | Equals (Ignore Case)| `String` | `country ^ "us"` |
| `#` | Length (Unary) | `String` -> `Float64` | `#username > 5` |
| `NOW` | Current Unix Time | `Float64` | `NOW > expiry` |
| `( )` | Grouping | `Expression` | `(age > 18)` |
| `AND` | Logical AND | `Boolean` | `x > 1 AND y < 5` |
| `OR`  | Logical OR  | `Boolean` | `role = "A" OR role = "B"` |

### Example Decision Requests

La Roca supports mixed payloads. You can define a **Context Map** (input variables) followed by one or more **Logic Rules**. The engine is completely **whitespace tolerant**, meaning you can format your rules for maximum readability.

#### 1. Standard Comparison Evaluation
**Request:**
```http
POST /eval HTTP/1.1
Host: localhost:8080

user_balance=1500.75,min_threshold=1000.00
user_balance > min_threshold
user_balance > 0
```

#### 2. Advanced String Evaluation (Zero-Copy)
**Request:**
```http
POST /eval HTTP/1.1
Host: localhost:8080

email="admin@blockmaker.net",country="US"
email ~ "blockmaker"
country ^ "us"
#email > 10
```

#### 3. Arithmetic & Real-Time Evaluation (SSE2 Math)
**Request:**
```http
POST /eval HTTP/1.1
Host: localhost:8080

price=100,tax=1.21,last_seen=172800
(price * tax) > 120
(NOW - last_seen) > 86400
```

#### 4. Hierarchical & Complex Boolean Logic
**Request:**
```http
POST /eval HTTP/1.1
Host: localhost:8080

MODE=OR
  user_age = 25  ,  role = "editor"  ,  status = "active"

( user_age > 18 AND role = "admin" )
( status = "active" AND #role > 3 )
```

**Response:**
```http
HTTP/1.1 200 OK
Content-Length: 4

True
```

> **Engineering Note:** The engine automatically detects if the first line is a `MODE` selection or a `Map`. If no `MODE` is specified, it defaults to `AND` (Short-circuiting Fail-Fast). The `#` (Length) operator is evaluated dynamically: the Lexer scans the string, counts the characters until the `\0` terminator, converts the result to a `Float64` via `cvtsi2sd`, and delegates the rest of the rule to the SSE2 hardware ALU.
>
> Arithmetic operations (`+`, `-`, `*`, `/`, `%`) and the `NOW` keyword are executed directly on the CPU's FPU/SSE2 registers. Standalone math results are evaluated via **Implicit Boolean Coercion** (Non-Zero is `True`, Zero is `False` using `ucomisd`).
>
> Furthermore, hierarchical expressions `( )` are processed using a zero-allocation **Shunting-Yard stack** natively in the `.bss` section. If a malformed nested rule is detected, the engine executes a hardware-level **Stack Unwinding (Panic Recovery)**, safely aborting the operation and returning an HTTP 400 without dropping the Keep-Alive connection. All executed within an $O(1)$ memory footprint.

---

## 🧠 Architecture: SSE2 & High-Precision Math

Unlike engines that rely on high-level libraries (which might introduce floating-point drift), **La Roca** handles math at the silicon level.

### 1. Hardware-Level Comparison
We use the **Streaming SIMD Extensions 2 (SSE2)** instruction set. When the engine compares two values, it loads them into 128-bit XMM registers and executes:

$$ucomisd \ xmm8, \ xmm0$$

This instruction performs a **Unordered Compare Scalar Double-Precision** floating-point comparison, setting the CPU flags (`ZF`, `PF`, `CF`) which are then caught by `ja` (Greater), `jb` (Less), or `je` (Equal).

### 2. Zero-Allocation Tagged Unions
To handle different data types (Float64, and soon Strings) without dynamic memory, we use a **16-byte aligned Tagged Union** map.

| Offset | Size | Field | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | 8 B | **Type Tag** | `1` = Float64, `2` = String Reference. |
| `0x08` | 8 B | **Value** | The raw IEEE-754 double or a pointer to the heap. |



### 3. DJB2 O(1) Lexer
Variable resolution is achieved by hashing the variable name during the parsing phase. Instead of comparing strings like `is_account_active` every time a rule is evaluated, the engine computes an 8-bit hash:

$$hash = (hash \times 31) \oplus char$$

This maps the name to one of the **256 pre-allocated slots** in the `var_map`, ensuring that looking up a variable during evaluation is a single memory dereference.

### 4. Asynchronous Concurrency (The Epoll Event Loop)
Traditional threaded servers block the execution while waiting for network I/O. **La Roca** implements a purely asynchronous, single-threaded event loop using Linux `epoll`.



By allocating a `384-byte` event array in the `.bss` section, the engine asks the kernel to monitor up to 128 simultaneous file descriptors. When a batch of packets arrives, `sys_epoll_wait` wakes up the engine, which drains the network buffers in a tight loop. This architecture completely eliminates thread-context-switching overhead, achieving **>112,000 requests per second** on a single CPU core.

### 5. Zero-Copy String Evaluation
Handling strings dynamically in C or Assembly usually means calling `malloc()`, copying buffers, and eventually causing memory fragmentation. **La Roca entirely bypasses dynamic memory allocation for strings.**

When the Lexer encounters a string literal (e.g., `role="admin"`), it performs **In-Place Mutation**:
1. It records the memory pointer where the first letter (`a`) begins inside the original HTTP network buffer.
2. It scans for the closing quote (`"`) and overwrites it with a null-terminator (`\0`).

This zero-copy approach means the engine can evaluate thousands of string comparisons concurrently without allocating a single byte on the heap. String equality is then evaluated at hardware speed using `repe cmpsb` or tight register loops.

### 6. The Type Dispatcher & Pluggable ALUs
To support both `Float64` math and `String` logic without corrupting memory, La Roca implements a strict **Hardware-Level Type Dispatcher**.

Every variable is stored in a 16-byte **Tagged Union**:
* **Tag `1` (Float64):** The value is an 8-byte IEEE-754 double.
* **Tag `2` (String Pointer):** The value is a 64-bit memory address pointing to the mutated HTTP buffer.



When a rule is evaluated, the `evaluator.asm` acts as a strict router. It checks the tags of both operands. If they mismatch (e.g., `user_age > "admin"`), it aborts instantly with a Type Error, protecting the CPU from a Segmentation Fault.
If the types match, the execution branches to isolated, pluggable ALUs (Arithmetic Logic Units):
* `math.asm` for SSE2 hardware operations (`<`, `>`, `=`).
* `strings.asm` for memory-level operations (`=`).

This "Pluggable ALU" pattern allows infinite extensibility (e.g., adding `Dates` or `Arrays`) without bloating the core evaluation engine.

---

## 🧪 Testing & Validation

Reliability in a decision engine is non-negotiable. La Roca includes a multi-layered validation suite.

### 1. High-Precision Test Suite
We test boundary conditions where high-level languages often fail:
```bash
# Execute End-to-End Precision Tests
./tests/test.sh
```
* **Negative Floats:** `-10.5 < 0` (Validated).
* **Precision Boundaries:** `0.001 = 0` (False) vs `0 = 0` (True).
* **Descriptive Variables:** Full string name resolution via DJB2.

### 2. Concurrency Benchmark
To measure the raw throughput of the **Zero-LibC** architecture, we use a Go-based stress tester.
```bash
go run tests/bench.go map-and
```

---

## 🛣️ Roadmap

- [x] Epoll TCP Server & Zero-allocation HTTP Router.
- [x] SSE2 Hardware-level Float64 evaluation.
- [x] DJB2 / FNV-1a Descriptive variable Hashing (O(1)).
- [x] Fail-Fast (AND) and Succeed-Fast (OR) strategies.
- [x] **String Comparison (`user_role = "admin"`)** using native ALU routing.
- [x] **Boolean Logic Grouping:** Parentheses support for complex nesting and precedence.
- [x] **JIT Compilation & VM:** Compiling rules into 16-byte aligned bytecode with a hybrid fallback mechanism.
- [x] **Plan Caching:** O(1) RAM lookup and disk persistence (`.cache/`) for instantaneous bytecode retrieval.
- [ ] **Multi-Core Scaling:** Implementing a thread pool/worker system to scale the Epoll event loop across all available CPU cores.
- [ ] **Zero-Allocation JSON Parsing:** Supporting standard JSON payloads for context variables without triggering dynamic memory allocation.
- [ ] **Native Regex ALU:** Lightweight, hardware-accelerated regular expression matching for string context validation.

---

## 🤝 Contact & Collaboration

**Fernando E. Mancuso** - *Head of Engineering at Blockmaker S.R.L.*

* **LinkedIn**: [Fernando Ezequiel Mancuso](https://www.linkedin.com/in/fernando-ezequiel-mancuso-54a2737/)
* **Email**: [fernando.mancuso@blockmaker.net](mailto:fernando.mancuso@blockmaker.net)

---

## 🏢 Backed by BlockMaker S.R.L.

**La Roca Rules Engine** is an open-source contribution to the high-performance engineering community. We believe in software that respects the hardware it runs on.