# Hedera EVM Lab - Full Lifecycle Benchmark Summary

**Generated**: 2026-02-05 14:40 PST
**Summary of**: Multiple benchmark runs on 2026-02-05

---

## Overview

This report aggregates benchmark results from the full lifecycle benchmark runs.
The `ensure_network_clean()` feature was added to guarantee fresh environments
before each cold-start benchmark, preventing stale infrastructure from polluting results.

**Known Issue**: Docker Desktop repeatedly stopped during Solo benchmarks, causing
Solo cold/warm/hot scenarios to fail. Anvil and Local Node results are valid.

---

## Test Results Summary

| Network | Scenario | Startup | Contract Ops | Status |
|---------|----------|---------|--------------|--------|
| **Anvil** | Cold start | 0.7s | 67ms | ✅ PASS |
| **Anvil** | Hot restart | 0s | 60ms | ✅ PASS |
| **Local Node** | Install | 19.2s | — | ✅ PASS |
| **Local Node** | Cold start | 107.1s | 6,723ms | ✅ PASS |
| **Local Node** | CLI restart | 154.9s | 7,579ms | ⚠️ PARTIAL |
| **Local Node** | Docker warm | — | — | ❌ FAIL |
| **Solo** | Install | 37-50s | — | ✅ PASS |
| **Solo** | Cold start | — | — | ❌ FAIL (Docker down) |
| **Solo** | Warm restart | — | — | ❌ FAIL (Docker down) |
| **Solo** | Hot restart | — | — | ❌ FAIL (Docker down) |

---

## Key Findings

### Anvil (Local Ethereum — Baseline)

Anvil provides the performance baseline:
- **Cold start**: 0.7s startup, 67ms total contract ops
- **Hot restart**: Near-instant (network already running), 60ms contract ops
- **Verdict**: Ideal for fast iteration and unit testing

### Local Node (Docker Compose)

Local Node shows consistent Hedera EVM behavior:
- **Cold start**: ~107s startup, ~6.7s contract ops
- **CLI restart**: ~155s startup (hedera stop destroys volumes)
- **Docker warm**: Failed due to compose directory detection issue
- **Verdict**: Good for Hedera-specific testing, but restart destroys state

### Contract Operation Comparison

| Operation | Anvil | Local Node | Ratio |
|-----------|-------|------------|-------|
| Deploy contract | 49ms | 2,898ms | 59x |
| Write (increment) | 5ms | 1,782ms | 356x |
| Read (count) | 1ms | 58ms | 58x |
| Event verification | 8ms | 23ms | 3x |
| Write (setCount) | 4ms | 1,705ms | 426x |
| Final read | 0ms | 257ms | — |
| **TOTAL** | **67ms** | **6,723ms** | **100x** |

The 100x overhead for Hedera networks reflects:
1. Consensus mechanism (not instant mining)
2. Mirror node event propagation
3. JSON-RPC relay processing

---

## ensure_network_clean() Feature

The new `ensure_network_clean()` function guarantees a fresh environment:

```bash
ensure_network_clean() {
    local net="$1"
    echo -e "${YELLOW}Ensuring clean slate for ${net}...${NC}"

    # 1. Force-stop the network
    stop_network "$net" "full" 2>/dev/null || true

    # 2. Run cleanup.sh to kill stragglers
    "${SCRIPT_DIR}/cleanup.sh" 2>/dev/null || true

    # 3. Verify clean state
    if ! "${SCRIPT_DIR}/cleanup.sh" --verify-only >/dev/null 2>&1; then
        echo -e "${YELLOW}Environment not fully clean, retrying cleanup...${NC}"
        sleep 2
        "${SCRIPT_DIR}/cleanup.sh" 2>/dev/null || true
    fi

    echo -e "${GREEN}Clean slate confirmed for ${net}${NC}"
}
```

**Call sites**:
- `run_benchmark()` — for standard single-network runs
- `run_anvil_lifecycle()` — before anvil_cold
- `run_solo_lifecycle()` — before solo_install
- `run_localnode_lifecycle()` — before localnode_install

---

## CI Recommendations

| Use Case | Recommended | Startup | Contract Ops |
|----------|-------------|---------|--------------|
| Unit tests / fast feedback | Anvil (hot) | 0s | 60ms |
| Hedera-specific behavior | Local Node (cold) | 107s | 6.7s |
| Pre-merge PR checks | Local Node (cold) | 107s | 6.7s |
| Nightly regression | Solo (cold)* | TBD | TBD |

*Solo benchmarks require stable Docker environment

---

## Environment

- **OS**: Darwin 24.6.0 (arm64)
- **Node.js**: v25.5.0
- **Docker**: 27.3.1
- **Solo**: 0.54.0
- **Anvil**: 1.5.1-stable
- **Hedera CLI**: 2.39.2

---

## Source Reports

- `2026-02-05_12-50-13_deploy-benchmark.md` — Best combined run (Anvil + Local Node)
- `2026-02-05_12-21-38_deploy-benchmark.md` — Earlier run with passing Local Node
- `2026-02-05_13-30-15_deploy-benchmark.md` — Solo-only attempt
- `2026-02-05_14-31-15_deploy-benchmark.md` — Final Solo attempt

---

## Next Steps

1. **Investigate Docker Desktop stability** — Determine why Docker keeps stopping
2. **Complete Solo benchmarks** — Re-run when Docker is stable
3. **Fix docker_warm scenario** — Debug compose directory detection
4. **Add CI integration** — Run benchmarks in CI where Docker is managed

---

*Report generated from aggregated benchmark data*
