// ============================================================================
// Module: tests/bench.go
// Project: La Roca Rules Engine
// Responsibility: High-frequency stress tester using raw TCP sockets and
//                 Goroutines to bypass client-side HTTP allocation overhead.
//                 Provides metrics for engine throughput across strategies.
//                 Optimized for HTTP Keep-Alive persistent connections.
// ============================================================================

package main

import (
	"fmt"
	"net"
	"os"
	"sync/atomic"
	"time"
)

const (
	targetAddr  = "localhost:8080"
	concurrency = 100 // Number of simultaneous TCP connections
	duration    = 10  // Benchmark duration in seconds
)

// Pre-baked HTTP wire-format payloads to minimize per-request overhead
var (
	reqProbe        []byte
	reqSimple       []byte
	reqMapAnd       []byte
	reqMapOr        []byte
	reqMath         []byte
	reqHierarchical []byte
)

var (
	opsCount uint64 // Atomic counter for successful requests
	errCount uint64 // Atomic counter for failed requests
)

func init() {
	// -------------------------------------------------------------------------
	// Pre-assemble the payloads. We do this in init() so string allocations
	// do not pollute the benchmark's CPU or memory metrics.
	// -------------------------------------------------------------------------

	// 1. Probe (Raw HTTP GET routing speed with Keep-Alive)
	reqProbe = []byte("GET /live HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n")

	// 2. Simple literal rule (No map parsing overhead)
	bodySimple := "7>2"
	reqSimple = []byte(fmt.Sprintf(
		"POST /eval HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\nContent-Length: %d\r\n\r\n%s",
		len(bodySimple), bodySimple,
	))

	// 3. AND Strategy with Context Map
	bodyMapAnd := "MODE=AND\nx=8,y=2,z=5\nx>y\nz<x\ny=2"
	reqMapAnd = []byte(fmt.Sprintf(
		"POST /eval HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\nContent-Length: %d\r\n\r\n%s",
		len(bodyMapAnd), bodyMapAnd,
	))

	// 4. OR Strategy with Context Map
	bodyMapOr := "MODE=OR\na=1,b=9\na>b\nb>a\n2=2"
	reqMapOr = []byte(fmt.Sprintf(
		"POST /eval HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\nContent-Length: %d\r\n\r\n%s",
		len(bodyMapOr), bodyMapOr,
	))

	// 5. Math Strategy (SSE2 ALU Stress Test)
	// Tests variable resolution + floating point math + comparison
	bodyMath := "MODE=AND\nbase=5,multiplier=2\n(base + base) * multiplier = 20"
	reqMath = []byte(fmt.Sprintf(
		"POST /eval HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\nContent-Length: %d\r\n\r\n%s",
		len(bodyMath), bodyMath,
	))

	// 6. Hierarchical Logic (Logic Stack & Parentheses Stress Test)
	// Tests the "Rescue OR" and deep stack propagation
	bodyHierarchical := "MODE=AND\npoints=250,status=\"vip\"\n(points < 200) OR (status = \"vip\")"
	reqHierarchical = []byte(fmt.Sprintf(
		"POST /eval HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\nContent-Length: %d\r\n\r\n%s",
		len(bodyHierarchical), bodyHierarchical,
	))
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	mode := os.Args[1]
	var payload []byte

	switch mode {
	case "probe":
		payload = reqProbe
	case "simple":
		payload = reqSimple
	case "map-and":
		payload = reqMapAnd
	case "map-or":
		payload = reqMapOr
	case "math":
		payload = reqMath
	case "hierarchical":
		payload = reqHierarchical
	default:
		printUsage()
		os.Exit(1)
	}

	fmt.Printf("🚀 Starting High-Frequency Benchmark (%s)\n", mode)
	fmt.Printf("Target: %s | Concurrency: %d | Duration: %ds\n", targetAddr, concurrency, duration)
	fmt.Println("---------------------------------------------------------")

	// Spawn worker goroutines (The Hammer)
	for i := 0; i < concurrency; i++ {
		go hammer(payload)
	}

	// Run for the specified duration
	time.Sleep(time.Duration(duration) * time.Second)

	finalOps := atomic.LoadUint64(&opsCount)
	finalErr := atomic.LoadUint64(&errCount)
	rps := finalOps / uint64(duration)

	fmt.Printf("✅ Benchmark Completed!\n")
	fmt.Printf("Total Requests: %d\n", finalOps)
	fmt.Printf("Total Errors:   %d\n", finalErr)
	fmt.Printf("Throughput:     %d Requests/sec\n", rps)
	fmt.Println("---------------------------------------------------------")
	os.Exit(0)
}

func printUsage() {
	fmt.Println("Usage: go run tests/bench.go [probe|simple|map-and|map-or|math|hierarchical]")
}

func hammer(payload []byte) {
	// Small buffer for reading L7 responses
	readBuf := make([]byte, 1024)

	// 1. Open the connection ONLY ONCE per Goroutine
	conn, err := net.Dial("tcp", targetAddr)
	if err != nil {
		fmt.Println("Error connecting to target:", err)
		return
	}
	defer conn.Close()

for {
    _, err = conn.Write(payload)
    if err != nil {
        atomic.AddUint64(&errCount, 1)
        conn.Close()
        conn, err = net.Dial("tcp", targetAddr) // 🚨 FIX: Check the reconnect error
        if err != nil {
            time.Sleep(10 * time.Millisecond) // Backoff
        }
        continue
    }

    _, err = conn.Read(readBuf)
    if err != nil {
        atomic.AddUint64(&errCount, 1)
        conn.Close()
        conn, err = net.Dial("tcp", targetAddr)
        if err != nil {
            time.Sleep(10 * time.Millisecond)
        }
    } else {
        atomic.AddUint64(&opsCount, 1)
    }
}
}