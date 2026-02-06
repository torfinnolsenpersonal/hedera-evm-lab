# Hedera EVM Lab - Full Lifecycle Benchmark Report

**Generated**: 2026-02-05 13:00:46 PST
**Report ID**: 2026-02-05_12-50-13
**Test Mode**: full-lifecycle
**Networks**: anvil localnode solo
**Run Type**: Full Lifecycle (install → cold start → warm restart → hot restart)

---

## Evidence & Verification

| Field | Value |
|-------|-------|
| Git commit | `b92cdb8` |
| Git branch | `main` |
| Working tree | clean |
| Run ID | 2026-02-05_12-50-13 |
| Evidence file | `2026-02-05_12-50-13_timing-data/2026-02-05_12-50-13_evidence.json` |

---

## Test Matrix

### Anvil (local Ethereum — baseline)

| Run | What It Tests | Result |
|-----|---------------|--------|
| anvil (cold start) | Cold start (start anvil + benchmark) | PASS |
| anvil (hot restart) | Hot restart (already running, health check only) | PASS |

### Solo (Kubernetes/kind — 3-layer architecture)

| Run | What It Tests | Result |
|-----|---------------|--------|
| solo (install) | CLI install timing (brew reinstall) | PASS |
| solo (cold start) | Full cold start (kind create + deploy) | FAIL |
| solo (warm restart) | Warm restart (redeploy on existing cluster) | FAIL |
| solo (hot restart) | Hot restart (health check only) | FAIL |

### Local Node (Docker Compose — 2-layer architecture)

| Run | What It Tests | Result |
|-----|---------------|--------|
| localnode (install) | CLI install timing (npm install -g) | PASS |
| localnode (cold start) | Full cold start (hedera start) | PASS |
| localnode (CLI restart) | CLI restart (hedera start after full stop) | PARTIAL |

---

## Executive Summary

| Scenario | Startup | Passed | Failed | Status |
|----------|---------|--------|--------|--------|
| anvil (cold start) | .7s | 6 | 0 | PASS |
| anvil (hot restart) | 0s | 6 | 0 | PASS |
| solo (install) | 37.3s | 0 | 0 | PASS |
| solo (cold start) | 31.0s | 0 | 1 | FAIL |
| solo (warm restart) | 31.1s | 0 | 1 | FAIL |
| solo (hot restart) | 96.3s | 0 | 6 | FAIL |
| localnode (install) | 19.2s | 0 | 0 | PASS |
| localnode (cold start) | 107.1s | 6 | 0 | PASS |
| localnode (CLI restart) | 154.9s | 5 | 1 | PARTIAL |
| localnode_docker (warm restart) | 0s | 0 | 0 | FAIL |

---

## Startup Time Comparison

| Scenario | anvil (cold start) | anvil (hot restart) | solo (install) | solo (cold start) | solo (warm restart) | solo (hot restart) | localnode (install) | localnode (cold start) | localnode (CLI restart) | localnode_docker (warm restart) |
|----------|------|------|------|------|------|------|------|------|------|------|
| Network startup | .7s | 0s | 37.3s | 31.0s | 31.1s | 96.3s | 19.2s | 107.1s | 154.9s | 0s |
| Benchmark run | .8s | .7s | N/A | 1.1s | 1.0s | 92.3s | N/A | 8.3s | 10.3s | N/A |
| Shutdown | — | .6s | — | .2s | — | .9s | — | 8.8s | .1s | — |

---

## Contract Operations Comparison

| Step | anvil (cold start) | anvil (hot restart) | solo (cold start) | solo (warm restart) | solo (hot restart) | localnode (cold start) | localnode (CLI restart) | localnode_docker (warm restart) |
|------|------|------|------|------|------|------|------|------|
| Deploy contract | 49ms | 43ms | N/A | N/A | N/A | 2898ms | 3775ms | N/A |
| Write (increment) | 5ms | 5ms | N/A | N/A | N/A | 1782ms | 1910ms | N/A |
| Read (count) | 1ms | 1ms | N/A | N/A | N/A | 58ms | 80ms | N/A |
| Event verification | 8ms | 6ms | N/A | N/A | N/A | 23ms | 37ms | N/A |
| Write (setCount) | 4ms | 4ms | N/A | N/A | N/A | 1705ms | 1777ms | N/A |
| Final read | 0ms | 1ms | N/A | N/A | N/A | 257ms | N/A | N/A |
| **TOTAL** | **67ms** | **60ms** | **0ms** | **0ms** | **0ms** | **6723ms** | **7579ms** | **N/A** |

---

## Per-Scenario Details

### anvil (cold start)

**Status**: PASS
**Tests**: 6 passed, 0 failed

| Phase | Duration |
|-------|----------|
| Startup | .7s |
| Benchmark | .8s |

| Step | Duration |
|------|----------|
| Deploy contract | 49ms |
| Write (increment) | 5ms |
| Read (count) | 1ms |
| Event verification | 8ms |
| Write (setCount) | 4ms |
| Final read | 0ms |
| **TOTAL** | **67ms** |

---

### anvil (hot restart)

**Status**: PASS
**Tests**: 6 passed, 0 failed

| Phase | Duration |
|-------|----------|
| Startup | 0s |
| Benchmark | .7s |
| Shutdown | .6s |

| Step | Duration |
|------|----------|
| Deploy contract | 43ms |
| Write (increment) | 5ms |
| Read (count) | 1ms |
| Event verification | 6ms |
| Write (setCount) | 4ms |
| Final read | 1ms |
| **TOTAL** | **60ms** |

---

### solo (install)

**Status**: PASS
**Install time**: 37.3s

---

### solo (cold start)

**Status**: FAIL
**Tests**: 0 passed, 1 failed

| Phase | Duration |
|-------|----------|
| Startup | 31.0s |
| Benchmark | 1.1s |
| Shutdown | .2s |

| Step | Duration |
|------|----------|
| Deploy contract | N/A |
| Write (increment) | N/A |
| Read (count) | N/A |
| Event verification | N/A |
| Write (setCount) | N/A |
| Final read | N/A |
| **TOTAL** | **0ms** |

**Failed Tests**:
```
    1) "before all" hook for "Step 1: Deploy Counter contract"
  1) Deploy Benchmark
```

---

### solo (warm restart)

**Status**: FAIL
**Tests**: 0 passed, 1 failed

| Phase | Duration |
|-------|----------|
| Startup | 31.1s |
| Benchmark | 1.0s |

| Step | Duration |
|------|----------|
| Deploy contract | N/A |
| Write (increment) | N/A |
| Read (count) | N/A |
| Event verification | N/A |
| Write (setCount) | N/A |
| Final read | N/A |
| **TOTAL** | **0ms** |

**Failed Tests**:
```
    1) "before all" hook for "Step 1: Deploy Counter contract"
  1) Deploy Benchmark
```

---

### solo (hot restart)

**Status**: FAIL
**Tests**: 0 passed, 6 failed

| Phase | Duration |
|-------|----------|
| Startup | 96.3s |
| Benchmark | 92.3s |
| Shutdown | .9s |

| Step | Duration |
|------|----------|
| Deploy contract | N/A |
| Write (increment) | N/A |
| Read (count) | N/A |
| Event verification | N/A |
| Write (setCount) | N/A |
| Final read | N/A |
| **TOTAL** | **0ms** |

**Failed Tests**:
```
    1) Step 1: Deploy Counter contract
    2) Step 2: Write - increment()
    3) Step 3: Read - count()
    4) Step 4: Event verification - CountChanged
    5) Step 5: Write - setCount(42)
    6) Step 6: Final read - verify count() == 42
  1) Deploy Benchmark
  2) Deploy Benchmark
  3) Deploy Benchmark
  4) Deploy Benchmark
  5) Deploy Benchmark
  6) Deploy Benchmark
```

---

### localnode (install)

**Status**: PASS
**Install time**: 19.2s

---

### localnode (cold start)

**Status**: PASS
**Tests**: 6 passed, 0 failed

| Phase | Duration |
|-------|----------|
| Startup | 107.1s |
| Benchmark | 8.3s |
| Shutdown | 8.8s |

| Step | Duration |
|------|----------|
| Deploy contract | 2898ms |
| Write (increment) | 1782ms |
| Read (count) | 58ms |
| Event verification | 23ms |
| Write (setCount) | 1705ms |
| Final read | 257ms |
| **TOTAL** | **6723ms** |

---

### localnode (CLI restart)

**Status**: PARTIAL
**Tests**: 5 passed, 1 failed

| Phase | Duration |
|-------|----------|
| Startup | 154.9s |
| Benchmark | 10.3s |
| Shutdown | .1s |

| Step | Duration |
|------|----------|
| Deploy contract | 3775ms |
| Write (increment) | 1910ms |
| Read (count) | 80ms |
| Event verification | 37ms |
| Write (setCount) | 1777ms |
| Final read | N/A |
| **TOTAL** | **7579ms** |

**Failed Tests**:
```
    1) Step 6: Final read - verify count() == 42
  1) Deploy Benchmark
```

---

### localnode_docker (warm restart)

**Status**: FAIL
**Tests**: 0 passed, 0 failed

| Phase | Duration |
|-------|----------|
| Startup | 0s |
| Benchmark | N/A |

| Step | Duration |
|------|----------|
| Deploy contract | N/A |
| Write (increment) | N/A |
| Read (count) | N/A |
| Event verification | N/A |
| Write (setCount) | N/A |
| Final read | N/A |
| **TOTAL** | **N/A** |

---

## Setup Requirements

| Network | Prerequisites | Install Command | Measured Install Time |
|---------|--------------|-----------------|----------------------|
| Anvil | Foundry | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` | N/A |
| Solo | Homebrew, Docker, kubectl, kind, helm | `brew tap hiero-ledger/tools && brew install solo` | 37.3s |
| Local Node | Docker, Docker Compose, Node.js 20+ | `npm install -g @hashgraph/hedera-local` | 19.2s |
| Hedera Testnet | HEDERA_TESTNET_PRIVATE_KEY | N/A (remote) | N/A |

---

## Developer Loop Comparison

Fastest retest path for each network (after initial setup):

| Network | Fastest Retest | Startup Time | Contract Ops |
|---------|---------------|-------------|-------------|
| anvil | anvil (hot restart) | 0s | 60ms |
| solo | solo (cold start) | 31.0s | 0ms |
| localnode | localnode (cold start) | 107.1s | 6723ms |

---

## CI Recommendations

| CI Use Case | Recommended Network | Why |
|------------|-------------------|-----|
| Unit tests / fast feedback | Anvil | Near-instant startup, full EVM compatibility |
| Hedera-specific behavior | Solo (warm) or Local Node | Hedera EVM with mirror node; Solo warm avoids cluster creation overhead |
| Pre-merge PR checks | Local Node (cold) | Deterministic from-scratch environment, moderate startup |
| Nightly / full regression | Solo (cold) | Full Kubernetes deployment, closest to production topology |
| Testnet integration | Hedera Testnet | Real network validation before mainnet deploy |

---

## Architecture Analysis

### Anvil (local Ethereum — baseline)

Anvil is a local Ethereum node from the Foundry toolkit. It starts in under a second
and provides full EVM compatibility. It serves as the performance baseline — any Hedera-specific
overhead shows up as the delta between Anvil and the Hedera networks.

### Solo (Kubernetes / kind — 3-layer architecture)

Solo's architecture has three layers: **CLI install → Kubernetes cluster → Hedera network**.
This creates distinct restart strategies:

- **Cold start**: Creates kind cluster + deploys all Hedera components. Slowest path.
- **Warm restart**: Reuses existing cluster, only redeploys Hedera network. Cluster creation is skipped.
- **Hot restart**: Network is already running. Only a health check is needed. Fastest path.

The 3-layer architecture means Solo can preserve infrastructure (cluster) while redeploying
application (network), giving developers a fast inner loop once the cluster is up.

### Local Node (Docker Compose — 2-layer architecture)

Local Node's architecture has two layers: **CLI install → Docker containers**.
The `hedera` CLI always runs `docker compose down -v` on stop, which destroys volumes.

- **Cold start**: Full `hedera start` from scratch.
- **CLI restart**: `hedera start` after `hedera stop` — always a cold start because volumes are destroyed.
- **Docker warm** (experimental): Bypasses CLI with raw `docker compose stop/start` to preserve volumes.
  This tests whether Docker's volume persistence gives any startup benefit.

The 2-layer architecture is simpler but offers fewer restart strategies.
`hedera stop` is all-or-nothing — there's no equivalent to Solo's `--keep-cluster`.

### Hedera Testnet (remote network)

Hedera Testnet is a remote network — no local infrastructure to manage.
Startup time is just connection validation. Contract operations reflect real network latency
and gas pricing. Useful for integration testing before mainnet deployment.

## Environment

- **OS**: Darwin 24.6.0
- **Architecture**: arm64
- **Node.js**: v25.5.0
- **Docker**: 27.3.1
- **Solo**: Version			: 0.54.0
- **Anvil**: anvil Version: 1.5.1-stable
- **Hedera CLI**: 2.39.2

---

*Report generated by run-deploy-benchmark.sh --full-lifecycle*

Timing data: `2026-02-05_12-50-13_timing-data/`
