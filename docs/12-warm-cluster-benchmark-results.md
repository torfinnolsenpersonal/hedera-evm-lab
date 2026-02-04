# Warm-Cluster Benchmark Results: Solo 1st Start vs 2nd Start

**Date**: 2026-02-04
**Report ID**: 2026-02-04_08-52-42
**Raw data**: `reports/2026-02-04_08-52-42_timing-data/`

---

## Purpose

Measure how much of Solo's startup cost is one-time infrastructure (kind cluster creation, Kubernetes resource provisioning) versus the repeatable cost of deploying the Hedera network and running contract operations. In a real development loop, the cluster persists between iterations — the developer only pays the deploy cost after the first run.

This benchmark runs Solo **twice** in a single invocation:

1. **1st start** — no cluster exists. Creates the kind cluster from scratch, deploys the full Solo network, runs the contract benchmark, then shuts down Solo but **preserves the cluster**.
2. **2nd start** — cluster already exists with the Solo network still running. Skips cluster creation and network deployment entirely, runs the contract benchmark, shuts down Solo (cluster preserved).

The side-by-side comparison isolates one-time costs from repeatable costs.

---

## Results Summary

| Metric | 1st start (cold) | 2nd start (warm) | Difference |
|--------|-------------------|-------------------|------------|
| **Network startup** | 884.6s | 30.6s | **-853.9s (96.5%)** |
| **Contract ops total** | 38.1s | 26.8s | **-11.3s (29.7%)** |
| **Benchmark run** | 41.2s | 34.6s | **-6.5s (15.8%)** |
| **Shutdown** | 3.5s | 2.5s | -1.0s |
| **Total wall time** | 929.6s | 67.9s | **-861.6s (92.7%)** |

Both runs: **6/6 tests passing** (100%).

---

## Detailed Contract Operations

| Step | 1st start | 2nd start | Change |
|------|-----------|-----------|--------|
| Deploy contract | 14,910ms | 8,803ms | -6,107ms (41%) |
| Write — `increment()` | 10,510ms | 9,014ms | -1,496ms (14%) |
| Read — `count()` | 3,458ms | 137ms | -3,321ms (96%) |
| Event verification — `CountChanged` | 927ms | 33ms | -894ms (96%) |
| Write — `setCount(42)` | 7,118ms | 8,377ms | +1,259ms (18%) |
| Final read — `count() == 42` | 1,226ms | 481ms | -745ms (61%) |
| **Total** | **38,149ms** | **26,845ms** | **-11,304ms (30%)** |

Key observations:

- **Reads are dramatically faster on the warm network** — `count()` drops from 3.5s to 137ms (96% reduction). The mirror node and relay caches are primed from the 1st run.
- **Deploy is ~40% faster** — 14.9s → 8.8s. The Kubernetes cluster and Hedera services are already warm, reducing scheduling and networking overhead.
- **Writes are similar** — `increment()` and `setCount()` both take 7-10s on both runs. Write latency is dominated by consensus + mirror node propagation, which doesn't benefit from caching.
- **Event verification drops from 927ms to 33ms** — event indexing is already up to date on the warm network.

---

## What the 1st Start Includes (884.6s)

The 1st start creates everything from scratch:

| Phase | Approximate time |
|-------|-----------------|
| kind create cluster | ~30s |
| Solo one-shot deploy: Kubernetes CRDs, operators | ~5s |
| Solo one-shot deploy: consensus node | ~60s |
| Solo one-shot deploy: mirror node (Postgres, Importer, REST, GRPC, Web3, Monitor) | ~8min |
| Solo one-shot deploy: JSON-RPC relay | ~45s |
| Solo one-shot deploy: Explorer | ~10s |
| Health check (wait for JSON-RPC relay to respond) | ~5s |
| Stabilization sleep | 30s |

The bulk of the time (~8 minutes) is mirror node pods reaching ready state (especially Postgres at 7m6s and GRPC at 7m10s).

## What the 2nd Start Includes (30.6s)

The 2nd start detects the existing cluster and running pods:

| Phase | Time |
|-------|------|
| Preflight port check | <1s |
| Detect existing kind cluster + Running pods | <1s |
| `start-solo.sh` exits (network already up) | <1s |
| Stabilization sleep | 30s |

The `--keep-cluster` flag on shutdown preserves both the kind cluster and all Kubernetes resources. The `start-solo.sh` script detects the running network and exits immediately. The entire 30.6s is dominated by the fixed stabilization sleep.

---

## Methodology

### Prerequisites

- macOS (Darwin 24.6.0, arm64)
- Docker Desktop 27.3.1
- Solo CLI 0.54.0 (`brew install hiero-ledger/tools/solo`)
- kind (Kubernetes in Docker)
- kubectl
- Node.js (v25.5.0 used, though Hardhat warns about compatibility)

### How to Reproduce

```bash
# 1. Clone the repository
git clone <repo-url>
cd hedera-evm-lab

# 2. Ensure prerequisites are installed
command -v docker && command -v solo && command -v kind && command -v kubectl

# 3. Ensure no stale clusters exist
kind get clusters              # should be empty
./scripts/stop-solo.sh         # full cleanup if needed

# 4. Run the warm-cluster benchmark
./scripts/run-deploy-benchmark.sh --warm-cluster solo
```

This single command:
1. Compiles contracts once up front (warm mode — skips npm install)
2. Runs Solo benchmark **1st start**: creates cluster, deploys Solo, runs 6-step contract test, shuts down Solo with `--keep-cluster`
3. Runs Solo benchmark **2nd start**: detects existing cluster, runs the same 6-step contract test, shuts down with `--keep-cluster`
4. Generates a Markdown report in `reports/` with side-by-side timing columns

### What `--warm-cluster` Does

The flag changes three things relative to `--warm`:

1. **Two runs per network** — each network in the benchmark is run twice (labeled "1st start" and "2nd start") instead of once.
2. **Solo shutdown preserves the cluster** — calls `stop-solo.sh --keep-cluster`, which runs `solo one-shot single destroy` but skips `kind delete cluster` and Docker container cleanup.
3. **Report shows both runs** — the generated report has separate columns for each run, enabling direct comparison.

For non-Solo networks (Anvil, Local Node), both runs are effectively cold starts since there is no persistent cluster to preserve. Running `--warm-cluster local` (which includes Anvil + Local Node + Solo) would confirm that only Solo benefits from cluster persistence.

### The Benchmark Test

The contract benchmark (`test/DeployBenchmark.test.ts`) runs 6 steps against a `Counter.sol` contract:

1. **Deploy** — deploy the Counter contract
2. **Write** — call `increment()`
3. **Read** — call `count()`, verify it equals 1
4. **Event** — verify `CountChanged` event was emitted
5. **Write** — call `setCount(42)`
6. **Read** — call `count()`, verify it equals 42

Each step is individually timed in milliseconds. The test uses Solo-specific wait parameters (2500ms post-TX wait, 1500ms intermediate wait) to account for consensus and mirror node propagation delays.

### Cleanup After Testing

```bash
# Remove everything (cluster + containers)
./scripts/stop-solo.sh

# Or keep the cluster for another run
./scripts/stop-solo.sh --keep-cluster
```

---

## Environment

| Component | Version |
|-----------|---------|
| OS | Darwin 24.6.0 (macOS, arm64) |
| Docker | 27.3.1 |
| Solo CLI | 0.54.0 |
| Node.js | v25.5.0 |
| Hardhat | (from contract-smoke package.json) |
| Anvil | 1.5.1-stable |

---

## Raw Timing Data

### 1st start — orchestrator phases

```json
{
  "network": "solo_1st",
  "total_duration_ms": 929550,
  "phases": {
    "solo_1st_startup":   { "duration_ms": 884571 },
    "solo_1st_benchmark": { "duration_ms": 41167 },
    "solo_1st_shutdown":  { "duration_ms": 3517 }
  }
}
```

### 2nd start — orchestrator phases

```json
{
  "network": "solo_2nd",
  "total_duration_ms": 67943,
  "phases": {
    "solo_2nd_startup":   { "duration_ms": 30640 },
    "solo_2nd_benchmark": { "duration_ms": 34649 },
    "solo_2nd_shutdown":  { "duration_ms": 2478 }
  }
}
```

### 1st start — contract operations

```
╔══════════════════════════════════════════════════════════╗
║         DEPLOY BENCHMARK - solo                        ║
╠══════════════════════════════════════════════════════════╣
║  Deploy contract                               14910ms ║
║  Write (increment)                             10510ms ║
║  Read (count)                                   3458ms ║
║  Event verification                              927ms ║
║  Write (setCount)                               7118ms ║
║  Final read                                     1226ms ║
╠══════════════════════════════════════════════════════════╣
║  TOTAL                                         38149ms ║
╚══════════════════════════════════════════════════════════╝
  6 passing (38s)
```

### 2nd start — contract operations

```
╔══════════════════════════════════════════════════════════╗
║         DEPLOY BENCHMARK - solo                        ║
╠══════════════════════════════════════════════════════════╣
║  Deploy contract                                8803ms ║
║  Write (increment)                              9014ms ║
║  Read (count)                                    137ms ║
║  Event verification                               33ms ║
║  Write (setCount)                               8377ms ║
║  Final read                                      481ms ║
╠══════════════════════════════════════════════════════════╣
║  TOTAL                                         26845ms ║
╚══════════════════════════════════════════════════════════╝
  6 passing (27s)
```

---

## Conclusions

1. **Solo's cold-start cost is dominated by Kubernetes resource provisioning** — 884s for the full deploy, of which ~30s is cluster creation and ~8 minutes is pod scheduling. In a development loop where the cluster persists, this cost is paid once.

2. **The warm-cluster developer experience is 92.7% faster** — total wall time drops from 929s to 68s. The developer only pays for the contract benchmark itself (35s) plus a fixed stabilization sleep (30s).

3. **Read operations benefit most from a warm network** — `count()` drops 96% (3.5s → 137ms) because the mirror node caches are primed. Write operations show minimal improvement since they're bounded by consensus latency.

4. **Contract deployment is ~40% faster on a warm network** — likely due to reduced Kubernetes scheduling overhead and warmer JVM/relay caches.

5. **The `--warm-cluster` flag captures the realistic developer experience** — after the initial setup, a developer iterating on contracts against Solo pays ~35s per cycle (contract compile + deploy + test), not 15 minutes.
