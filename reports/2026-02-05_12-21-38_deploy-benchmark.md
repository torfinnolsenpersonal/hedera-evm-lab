# Hedera EVM Lab - Full Lifecycle Benchmark Report

**Generated**: 2026-02-05 12:33:10 PST
**Report ID**: 2026-02-05_12-21-38
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
| Run ID | 2026-02-05_12-21-38 |
| Evidence file | `2026-02-05_12-21-38_timing-data/2026-02-05_12-21-38_evidence.json` |

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
| localnode (CLI restart) | CLI restart (hedera start after full stop) | PASS |

---

## Executive Summary

| Scenario | Startup | Passed | Failed | Status |
|----------|---------|--------|--------|--------|
| anvil (cold start) | .9s | 6 | 0 | PASS |
| anvil (hot restart) | 0s | 6 | 0 | PASS |
| solo (install) | 53.1s | 0 | 0 | PASS |
| solo (cold start) | 30.8s | 0 | 6 | FAIL |
| solo (warm restart) | 30.6s | 0 | 6 | FAIL |
| solo (hot restart) | 0s | 0 | 6 | FAIL |
| localnode (install) | 20.5s | 0 | 0 | PASS |
| localnode (cold start) | 117.2s | 6 | 0 | PASS |
| localnode (CLI restart) | 97.8s | 6 | 0 | PASS |
| localnode_docker (warm restart) | .1s | 0 | 0 | FAIL |

---

## Startup Time Comparison

| Scenario | anvil (cold start) | anvil (hot restart) | solo (install) | solo (cold start) | solo (warm restart) | solo (hot restart) | localnode (install) | localnode (cold start) | localnode (CLI restart) | localnode_docker (warm restart) |
|----------|------|------|------|------|------|------|------|------|------|------|
| Network startup | .9s | 0s | 53.1s | 30.8s | 30.6s | 0s | 20.5s | 117.2s | 97.8s | .1s |
| Benchmark run | 1.1s | .9s | N/A | 91.4s | 91.4s | 91.7s | N/A | 20.8s | 17.8s | N/A |
| Shutdown | — | .7s | — | .1s | — | 3.5s | — | 11.5s | .2s | — |

---

## Contract Operations Comparison

| Step | anvil (cold start) | anvil (hot restart) | solo (cold start) | solo (warm restart) | solo (hot restart) | localnode (cold start) | localnode (CLI restart) | localnode_docker (warm restart) |
|------|------|------|------|------|------|------|------|------|
| Deploy contract | 48ms | 57ms | N/A | N/A | N/A | 7950ms | 7134ms | N/A |
| Write (increment) | 6ms | 5ms | N/A | N/A | N/A | 3092ms | 6175ms | N/A |
| Read (count) | 2ms | 2ms | N/A | N/A | N/A | 414ms | 505ms | N/A |
| Event verification | 9ms | 5ms | N/A | N/A | N/A | 63ms | 81ms | N/A |
| Write (setCount) | 7ms | 5ms | N/A | N/A | N/A | 6087ms | 1866ms | N/A |
| Final read | 1ms | 1ms | N/A | N/A | N/A | 259ms | 88ms | N/A |
| **TOTAL** | **73ms** | **75ms** | **0ms** | **0ms** | **0ms** | **17865ms** | **15849ms** | **N/A** |

---

## Per-Scenario Details

### anvil (cold start)

**Status**: PASS
**Tests**: 6 passed, 0 failed

| Phase | Duration |
|-------|----------|
| Startup | .9s |
| Benchmark | 1.1s |

| Step | Duration |
|------|----------|
| Deploy contract | 48ms |
| Write (increment) | 6ms |
| Read (count) | 2ms |
| Event verification | 9ms |
| Write (setCount) | 7ms |
| Final read | 1ms |
| **TOTAL** | **73ms** |

---

### anvil (hot restart)

**Status**: PASS
**Tests**: 6 passed, 0 failed

| Phase | Duration |
|-------|----------|
| Startup | 0s |
| Benchmark | .9s |
| Shutdown | .7s |

| Step | Duration |
|------|----------|
| Deploy contract | 57ms |
| Write (increment) | 5ms |
| Read (count) | 2ms |
| Event verification | 5ms |
| Write (setCount) | 5ms |
| Final read | 1ms |
| **TOTAL** | **75ms** |

---

### solo (install)

**Status**: PASS
**Install time**: 53.1s

---

### solo (cold start)

**Status**: FAIL
**Tests**: 0 passed, 6 failed

| Phase | Duration |
|-------|----------|
| Startup | 30.8s |
| Benchmark | 91.4s |
| Shutdown | .1s |

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

### solo (warm restart)

**Status**: FAIL
**Tests**: 0 passed, 6 failed

| Phase | Duration |
|-------|----------|
| Startup | 30.6s |
| Benchmark | 91.4s |

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

### solo (hot restart)

**Status**: FAIL
**Tests**: 0 passed, 6 failed

| Phase | Duration |
|-------|----------|
| Startup | 0s |
| Benchmark | 91.7s |
| Shutdown | 3.5s |

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
**Install time**: 20.5s

---

### localnode (cold start)

**Status**: PASS
**Tests**: 6 passed, 0 failed

| Phase | Duration |
|-------|----------|
| Startup | 117.2s |
| Benchmark | 20.8s |
| Shutdown | 11.5s |

| Step | Duration |
|------|----------|
| Deploy contract | 7950ms |
| Write (increment) | 3092ms |
| Read (count) | 414ms |
| Event verification | 63ms |
| Write (setCount) | 6087ms |
| Final read | 259ms |
| **TOTAL** | **17865ms** |

---

### localnode (CLI restart)

**Status**: PASS
**Tests**: 6 passed, 0 failed

| Phase | Duration |
|-------|----------|
| Startup | 97.8s |
| Benchmark | 17.8s |
| Shutdown | .2s |

| Step | Duration |
|------|----------|
| Deploy contract | 7134ms |
| Write (increment) | 6175ms |
| Read (count) | 505ms |
| Event verification | 81ms |
| Write (setCount) | 1866ms |
| Final read | 88ms |
| **TOTAL** | **15849ms** |

---

### localnode_docker (warm restart)

**Status**: FAIL
**Tests**: 0 passed, 0 failed

| Phase | Duration |
|-------|----------|
| Startup | .1s |
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
| Solo | Homebrew, Docker, kubectl, kind, helm | `brew tap hiero-ledger/tools && brew install solo` | 53.1s |
| Local Node | Docker, Docker Compose, Node.js 20+ | `npm install -g @hashgraph/hedera-local` | 20.5s |
| Hedera Testnet | HEDERA_TESTNET_PRIVATE_KEY | N/A (remote) | N/A |

---

## Developer Loop Comparison

Fastest retest path for each network (after initial setup):

| Network | Fastest Retest | Startup Time | Contract Ops |
|---------|---------------|-------------|-------------|
| anvil | anvil (hot restart) | 0s | 75ms |
| solo | solo (hot restart) | 0s | 0ms |
| localnode | localnode (CLI restart) | 97.8s | 15849ms |

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

Timing data: `2026-02-05_12-21-38_timing-data/`
