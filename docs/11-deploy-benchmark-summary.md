# Deploy Benchmark Implementation Summary

## What Was Added

A **developer journey benchmark** that measures the full cost from zero to first read across five networks:

```
Hardhat (in-memory) → Anvil (local ETH) → Local Node (local Hedera) → Solo (local Hedera/k8s) → Hedera Testnet (remote)
```

### Timed Stages

The benchmark times six stages per network, capturing the real "cold start" cost:

| Stage | Description |
|-------|-------------|
| 1. npm install | Install Hardhat + dependencies (clean `node_modules` first) |
| 2. Tooling check | Verify anvil is installed (Anvil only) |
| 3. Compile contracts | `npx hardhat compile` (clean `artifacts/` + `cache/` first) |
| 4. Network startup | Start anvil / localnode / solo / validate testnet connectivity |
| 5. Contract benchmark | 6-step deploy/write/read/event test |
| 6. Network shutdown | Stop the local network |

Stages 1–3 simulate a fresh machine by cleaning build artifacts before each run. Stage 2 only applies to Anvil (Foundry install check).

### Run Modes

- **`--clean` (default)** — Full developer journey: removes `node_modules/`, `artifacts/`, `cache/` and re-installs/recompiles per network run.
- **`--warm`** — Skip install/compile steps; only runs network startup + contract benchmark. Useful for quick re-runs.
- **`--warm-cluster`** — Like `--warm`, but runs each network **twice** in a single invocation to produce a side-by-side comparison: a "1st start" and a "2nd start". For Solo, the kind cluster is preserved between runs (`stop-solo.sh --keep-cluster`), so the 2nd start skips `kind create cluster` — isolating the cost of `solo one-shot single deploy` + contract operations. For other networks (Anvil, Local Node, Hedera Testnet), both runs are effectively cold starts, confirming that those networks don't benefit from cluster persistence.

#### How `--warm-cluster` works

1. **1st start**: network starts from scratch (cluster created if needed), benchmark runs, network is shut down (Solo keeps its cluster)
2. **2nd start**: network starts again (Solo detects existing cluster, skips creation), benchmark runs, network is shut down (Solo keeps its cluster)
3. Report shows both runs side-by-side for direct timing comparison

#### What each mode measures (Solo)

| Stage | Cold (`--clean`) | Warm (`--warm`) | Warm Cluster 1st start | Warm Cluster 2nd start |
|-------|------------------|-----------------|------------------------|------------------------|
| npm install | Timed | Skipped | Skipped | Skipped |
| Compile | Timed | Skipped | Skipped | Skipped |
| kind create cluster | Timed | Timed | Timed (created) | Skipped (exists) |
| solo one-shot deploy | Timed | Timed | Timed | Timed |
| Health check | Timed | Timed | Timed | Timed |
| Contract ops | Timed | Timed | Timed | Timed |
| Shutdown | Full (cluster deleted) | Full (cluster deleted) | Partial (cluster kept) | Partial (cluster kept) |

---

## Files Created

| File | Purpose |
|------|---------|
| `examples/hardhat/contract-smoke/test/DeployBenchmark.test.ts` | 6-step benchmark test with per-step ms timing and summary table |
| `scripts/start-anvil.sh` | Start Anvil on port 8545, wait for RPC, write PID file |
| `scripts/stop-anvil.sh` | Kill Anvil by PID file or port lookup |
| `scripts/run-deploy-benchmark.sh` | Orchestrator: start/stop networks, run benchmarks, generate reports |

## Files Modified

| File | Changes |
|------|---------|
| `examples/hardhat/contract-smoke/hardhat.config.ts` | Added `anvil` (port 8545, chainId 31337, 30s timeout) and `hedera_testnet` (hashio.io, chainId 296, 180s timeout) networks with accounts |
| `examples/hardhat/contract-smoke/package.json` | Added 5 scripts: `benchmark`, `benchmark:anvil`, `benchmark:localnode`, `benchmark:solo`, `benchmark:hedera_testnet` |
| `examples/hardhat/contract-smoke/.env.example` | Added `HEDERA_TESTNET_RPC_URL` and `HEDERA_TESTNET_PRIVATE_KEY` |
| `scripts/run-hardhat-smoke.sh` | Added `anvil` (port 8545/chain 31337) and `hedera_testnet` (remote/chain 296) connectivity checks |
| `docs/08-notes-on-test-configs.md` | Expanded Quick Reference to 5 networks, added Deploy Benchmark, Anvil, and Hedera Testnet sections |
| `SMOKE-TESTS.md` | Extended networks table, added Deploy Benchmark section with steps and usage |

---

## Timing Configuration

| Parameter | Hardhat | Anvil | Local Node | Solo | Hedera Testnet |
|-----------|---------|-------|------------|------|----------------|
| Post-TX Wait | 0ms | 0ms | 500ms | 2500ms | 5000ms |
| Intermediate Wait | 0ms | 0ms | 300ms | 1500ms | 3000ms |
| Test Timeout | 10s | 30s | 40s | 90s | 120s |
| Network Timeout | N/A | 30s | 60s | 120s | 180s |

---

## How to Run

### Individual networks

```bash
cd examples/hardhat/contract-smoke

npm run benchmark                  # Hardhat (in-memory)
npm run benchmark:anvil            # Anvil (local Ethereum)
npm run benchmark:localnode        # Hiero Local Node
npm run benchmark:solo             # Solo
npm run benchmark:hedera_testnet   # Hedera Testnet (needs HEDERA_TESTNET_PRIVATE_KEY)
```

### Orchestrated runs with report generation

```bash
# Default: full clean journey (simulates fresh machine)
./scripts/run-deploy-benchmark.sh anvil            # Single network
./scripts/run-deploy-benchmark.sh local            # anvil + localnode + solo
./scripts/run-deploy-benchmark.sh all              # All four networks

# Warm mode: skip install/compile, only network + contract ops
./scripts/run-deploy-benchmark.sh --warm anvil
./scripts/run-deploy-benchmark.sh --warm local

# Warm cluster: two-run comparison per network (cluster preserved for Solo)
./scripts/run-deploy-benchmark.sh --warm-cluster solo        # solo (1st start) + solo (2nd start)
./scripts/run-deploy-benchmark.sh --warm-cluster local       # two runs each for anvil, localnode, solo
./scripts/run-deploy-benchmark.sh --warm-cluster all         # two runs each for all four networks

# Explicit clean (same as default)
./scripts/run-deploy-benchmark.sh --clean all

# Stop Solo but keep the kind cluster running (standalone)
./scripts/stop-solo.sh --keep-cluster
```

Reports are saved to `reports/YYYY-MM-DD_HH-MM-SS_deploy-benchmark.md`.

### Example report table (clean mode)

```markdown
| Stage | Anvil | Local Node | Solo | Hedera Testnet |
|-------|-------|------------|------|----------------|
| npm install | 12.3s | 12.3s | 12.3s | 12.3s |
| Compile contracts | 4.1s | 4.1s | 4.1s | 4.1s |
| Network startup | 0.8s | 57s | 711s | N/A (remote) |
| Deploy contract | 12ms | 3200ms | 8500ms | 12000ms |
| Write (increment) | 1ms | 2800ms | 7200ms | 8500ms |
| Read (count) | <1ms | 15ms | 45ms | 200ms |
| Event verification | <1ms | 520ms | 2600ms | 5100ms |
| Write (setCount) | 1ms | 2900ms | 7100ms | 8200ms |
| Final read | <1ms | 12ms | 38ms | 180ms |
| **Contract ops total** | **~15ms** | **~9.4s** | **~25.5s** | **~34.2s** |
| Network shutdown | 0.1s | 5.2s | 12.8s | — |
```

---

## Verification (Hardhat in-memory)

All 6 tests pass. Output from `npm run benchmark`:

```
  Deploy Benchmark

╔══════════════════════════════════════════════════════════╗
║         DEPLOY BENCHMARK - hardhat                     ║
╠══════════════════════════════════════════════════════════╣
║  Default Wait:   0ms                                   ║
║  Intermediate:   0ms                                   ║
║  Timeout:        10000ms                               ║
╚══════════════════════════════════════════════════════════╝

    ✔ Step 1: Deploy Counter contract
    ✔ Step 2: Write - increment()
    ✔ Step 3: Read - count()
    ✔ Step 4: Event verification - CountChanged
    ✔ Step 5: Write - setCount(42)
    ✔ Step 6: Final read - verify count() == 42

╔══════════════════════════════════════════════════════════╗
║         DEPLOY BENCHMARK - hardhat                     ║
╠══════════════════════════════════════════════════════════╣
║  Deploy contract                                   8ms ║
║  Write (increment)                                 1ms ║
║  Read (count)                                      2ms ║
║  Event verification                                7ms ║
║  Write (setCount)                                  1ms ║
║  Final read                                        0ms ║
╠══════════════════════════════════════════════════════════╣
║  TOTAL                                            19ms ║
╚══════════════════════════════════════════════════════════╝

  6 passing (820ms)
```

---

## Key Design Decisions

- **Counter contract only** — no new Solidity needed; reuses existing `Counter.sol`
- **Anvil on port 8545** — no conflict with Hedera networks on 7546
- **Hedera Testnet requires `HEDERA_TESTNET_PRIVATE_KEY`** — script refuses without it
- **Separate from full smoke tests** — `run-deploy-benchmark.sh` is independent from `run-all.sh`
- **Only Counter (pure EVM)** — works identically on all networks; no HTS/precompile tests included
- **Clean mode by default** — simulates a developer starting from scratch; `--warm` available for quick iterations
- **Per-network install/compile** — each network run gets its own timed npm install and compile to capture the real cold-start cost
