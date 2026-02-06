# Hedera EVM Lab - Full Lifecycle Benchmark Report

**Generated**: 2026-02-05 13:33:35 PST
**Report ID**: 2026-02-05_13-30-15
**Test Mode**: full-lifecycle
**Networks**: solo
**Run Type**: Full Lifecycle (install → cold start → warm restart → hot restart)

---

## Evidence & Verification

| Field | Value |
|-------|-------|
| Git commit | `6ebcb94` |
| Git branch | `main` |
| Working tree | clean |
| Run ID | 2026-02-05_13-30-15 |
| Evidence file | `2026-02-05_13-30-15_timing-data/2026-02-05_13-30-15_evidence.json` |

---

## Test Matrix

### Solo (Kubernetes/kind — 3-layer architecture)

| Run | What It Tests | Result |
|-----|---------------|--------|
| solo (install) | CLI install timing (brew reinstall) | PASS |
| solo (cold start) | Full cold start (kind create + deploy) | FAIL |
| solo (warm restart) | Warm restart (redeploy on existing cluster) | FAIL |
| solo (hot restart) | Hot restart (health check only) | FAIL |

---

## Executive Summary

| Scenario | Startup | Passed | Failed | Status |
|----------|---------|--------|--------|--------|
| solo (install) | 40.4s | 0 | 0 | PASS |
| solo (cold start) | 31.1s | 0 | 1 | FAIL |
| solo (warm restart) | 31.4s | 0 | 1 | FAIL |
| solo (hot restart) | 77.9s | 0 | 6 | FAIL |

---

## Startup Time Comparison

| Scenario | solo (install) | solo (cold start) | solo (warm restart) | solo (hot restart) |
|----------|------|------|------|------|
| Network startup | 40.4s | 31.1s | 31.4s | 77.9s |
| Benchmark run | N/A | 1.2s | 1.0s | 2.2s |
| Shutdown | — | .2s | — | 1.6s |

---

## Contract Operations Comparison

| Step | solo (cold start) | solo (warm restart) | solo (hot restart) |
|------|------|------|------|
| Deploy contract | N/A | N/A | N/A |
| Write (increment) | N/A | N/A | N/A |
| Read (count) | N/A | N/A | N/A |
| Event verification | N/A | N/A | N/A |
| Write (setCount) | N/A | N/A | N/A |
| Final read | N/A | N/A | N/A |
| **TOTAL** | **0ms** | **0ms** | **0ms** |

---

## Per-Scenario Details

### solo (install)

**Status**: PASS
**Install time**: 40.4s

---

### solo (cold start)

**Status**: FAIL
**Tests**: 0 passed, 1 failed

| Phase | Duration |
|-------|----------|
| Startup | 31.1s |
| Benchmark | 1.2s |
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
| Startup | 31.4s |
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
| Startup | 77.9s |
| Benchmark | 2.2s |
| Shutdown | 1.6s |

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

## Setup Requirements

| Network | Prerequisites | Install Command | Measured Install Time |
|---------|--------------|-----------------|----------------------|
| Anvil | Foundry | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` | N/A |
| Solo | Homebrew, Docker, kubectl, kind, helm | `brew tap hiero-ledger/tools && brew install solo` | 40.4s |
| Local Node | Docker, Docker Compose, Node.js 20+ | `npm install -g @hashgraph/hedera-local` | N/A |
| Hedera Testnet | HEDERA_TESTNET_PRIVATE_KEY | N/A (remote) | N/A |

---

## Developer Loop Comparison

Fastest retest path for each network (after initial setup):

| Network | Fastest Retest | Startup Time | Contract Ops |
|---------|---------------|-------------|-------------|
| solo | solo (cold start) | 31.1s | 0ms |

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

Timing data: `2026-02-05_13-30-15_timing-data/`
