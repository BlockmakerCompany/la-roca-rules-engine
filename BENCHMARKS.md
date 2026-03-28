# 📈 Performance Benchmarks: La Roca Rules Engine (V1.0)

This document details the stress tests and performance analysis of **La Roca Rules Engine** running in a production-grade Kubernetes environment. Our goal was to measure the throughput of the **JIT/VM Hybrid architecture** and identify the limits of the x86_64 Assembly networking stack.

## 🖥️ Test Environment

To ensure deterministic results, the benchmarks were conducted on bare-metal hardware, isolating the Assembly core from virtualization overhead.

| Component | Specification |
| :--- | :--- |
| **Infrastructure** | Bare Metal Kubernetes Node |
| **Host Hardware** | 120 Cores / 2TB RAM / 10Gbps NIC |
| **Operating System** | Ubuntu 22.04 LTS (Kernel 5.15.0) |
| **Runtime Architecture** | **Zero-Libc / x86_64 Assembly** |
| **Testing Tool** | Distributed Go Stress-Tester (`tests/bench.go`) |

---

## 🚀 Execution 01: Single-Core Throughput (The Fast-Path)
**Status:** ✅ SUCCESS | **ID:** `STRESS-01-JIT`  
**Objective:** Measure the peak performance of the JIT-compiled bytecode on a single throttled CPU core.

### 🏗️ Infrastructure Profile
| Component | Configuration | Engineering Context |
| :--- | :--- | :--- |
| **Replicas** | 1 Pod | Isolated single-threaded execution. |
| **CPU Limit** | **1000m (1 Core)** | Full core allocation for the Epoll loop. |
| **JIT State** | Warm (Cached) | Rules pre-compiled into 16-byte aligned bytecode. |

### 📊 Performance Results
| Metric | Value | Observation |
| :--- | :--- | :--- |
| **Total Requests** | 1,123,455 | Over 1 million evaluations in 10s. |
| **Throughput** | **112,345 req/s** | Theoretical limit of the single-core TCP stack. |
| **Error Rate** | **0.00%** | Zero TCP drops or logic panics. |
| **Latency (Avg)** | < 1 ms | Response time dominated by network round-trip. |

> **BlockMaker Analysis:** > We achieved a throughput of $~112k \text{ RPS}$. In this state, the **SSE2 ALU** is processing comparisons in cycles. The bottleneck is no longer the logic evaluation, but the **Kernel's interrupt handling** for the incoming TCP packets. We are effectively saturating the single-core `sys_epoll_wait` loop.

---

## ⚠️ Execution 02: The JIT "Cold Start" Penalty
**Status:** ✅ VALIDATED | **ID:** `STRESS-02-COLD`  
**Objective:** Measure the impact of the Lexer and JIT Compiler before a rule is cached.

### 🏗️ Test Scenario
We sent 10,000 unique rules (different hashes) to force the engine to compile each one from scratch, bypassing the `.cache/` folder.

| Phase | Throughput | Engineering Context |
| :--- | :--- | :--- |
| **First Hit (JIT Compile)** | ~45,000 req/s | Lexer FSM + Bytecode Emitter overhead. |
| **Subsequent Hits (VM)** | **112,000+ req/s** | Execution of the 16-byte aligned bytecode. |

> **BlockMaker Analysis:** > The JIT compilation phase is approximately $2.5\times$ slower than direct VM execution. However, thanks to the **O(1) FNV-1a Hashing**, the lookup penalty for a cached plan is nearly zero ($O(1)$).

---

## 📈 Execution 03: Scaled Hierarchical Logic (The Hybrid Trap)
**Status:** ✅ STABLE | **ID:** `STRESS-03-HYBRID`  
**Objective:** Evaluate performance when rules contain complex parentheses, triggering the **Tactical Bailout** to the native Interpreter.

### 🏗️ Test Rule
`((points > 100 AND status = "vip") OR (NOW - last_login < 86400))`

### 📊 Comparative Results
| Mode | Throughput | Observation |
| :--- | :--- | :--- |
| **Pure JIT (Linear)** | 112k req/s | Maximum efficiency. |
| **Hybrid (Interpreter)** | **111k req/s** | Negligible drop (<1%) due to the "Bailout". |

> **BlockMaker Analysis:** > This is a major victory. The **Native Assembly Interpreter** (which uses the physical `RSP` stack for recursion) is so efficient that even when we abort the JIT Fast-Path for complex logic, the performance drop is statistically insignificant. We have eliminated the "Complexity Tax."

---

## ⚖️ Execution 04: The Kubernetes Throttling Paradox
**Status:** 📉 THROTTLED | **ID:** `STRESS-04-QUOTA`  
**Objective:** Observe behavior under strict 500m (half-core) Cgroup quotas.

### 📊 Performance Results
| Metric | Value | Technical Analysis |
| :--- | :--- | :--- |
| **Throughput** | 56,200 req/s | Linear reduction based on available cycles. |
| **P99 Latency** | 120 ms | High jitter due to CFS Throttling. |

### 🔍 Analysis: The "Too Fast" Problem
In **La Roca**, the engine finishes processing a batch of epoll events so quickly that the Kubernetes `Completely Fair Scheduler (CFS)` detects "idle" time and throttles the process to stay within the 500m quota. This introduces **artificial latency**.

> **The BlockMaker Verdict:** > To unleash the 112k RPS potential, **La Roca** should be deployed on "Uncaged" bare metal or with `CPU Manager` policy set to `static` in Kubernetes to avoid context-switching and throttling "taxes."

---

## 🏁 Final Technical Conclusion

The V1.0 benchmarks confirm that moving the logic to **x86_64 Assembly** and using **SSE2 hardware registers** has effectively removed the software layer as a bottleneck.

### Key Takeaways:
1. **Zero-Libc Dominance:** No Garbage Collection or Heap fragmentation means $0.00\%$ error rates even under 100% CPU saturation.
2. **JIT Efficiency:** The 16-byte instruction alignment ensures that the Bytecode VM stays entirely within the CPU's **L1 Instruction Cache**.
3. **Hardware-Level Precision:** By using `ucomisd`, we provide mathematical results with zero floating-point drift at a speed that high-level languages cannot match.

**La Roca is no longer a tool; it is a hardware extension for business logic.**

---
*End of Report | Lead Architect: Fernando Ezequiel Mancuso | 2026*

---