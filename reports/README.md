# Test Reports

This directory contains comprehensive test reports generated from Hedera EVM Lab smoke test runs.

## Report Format

Reports are named using the format:
```
YYYY-MM-DD_HH-MM-SS_[description].md
```

## Generating Reports

### Full smoke test suite

```bash
./scripts/run-all.sh both
./scripts/generate-report.sh [hardhat_output] [foundry_output] [network]
```

### Deploy benchmark (single contract)

```bash
# Full developer journey (wipes node_modules + artifacts)
./scripts/run-deploy-benchmark.sh anvil
./scripts/run-deploy-benchmark.sh localnode
./scripts/run-deploy-benchmark.sh solo
./scripts/run-deploy-benchmark.sh all

# Warm mode (skip install/compile)
./scripts/run-deploy-benchmark.sh --warm solo

# Warm cluster (two-run comparison: 1st start vs 2nd start with cluster preserved)
./scripts/run-deploy-benchmark.sh --warm-cluster solo
./scripts/run-deploy-benchmark.sh --warm-cluster local    # anvil + localnode + solo
./scripts/run-deploy-benchmark.sh --warm-cluster all

# Full lifecycle (install → cold → warm → hot for Solo; cold → restart → docker warm for Local Node)
./scripts/run-deploy-benchmark.sh --full-lifecycle solo
./scripts/run-deploy-benchmark.sh --full-lifecycle localnode
./scripts/run-deploy-benchmark.sh --full-lifecycle local    # anvil + localnode + solo
```

## Report Types

### Full Test Suite (`_*-test-report.md`)

Multi-contract smoke tests across Hardhat and Foundry frameworks.

- **Executive Summary** — pass/fail counts and rates for all frameworks and networks
- **Gaps Analysis** — compatibility issues between Ethereum tooling and Hedera EVM
- **Startup Timing** — network startup breakdowns with phase-level detail
- **Environment** — system info, tool versions
- **Failed Tests** — per-framework failure lists with error context

### Deploy Benchmark (`_deploy-benchmark.md`)

Single-contract cold-start benchmark timing the full developer journey.

- **Executive Summary** — pass/fail per network
- **Timing Results** — npm install, compile, network startup, 6 contract operations, shutdown
- **Per-Network Details** — individual operation timings and orchestrator phase breakdowns
- **Environment** — system info, tool versions

### Full Lifecycle Benchmark (`_deploy-benchmark.md` with `--full-lifecycle`)

Cross-platform comparison of restart strategies across the complete developer journey.

- **Test Matrix** — Solo (install, cold, warm, hot) vs Local Node (cold, restart, docker warm)
- **Executive Summary** — pass/fail and startup times per scenario
- **Startup Time Comparison** — side-by-side table across all scenarios
- **Contract Operations Comparison** — per-step timings across all scenarios
- **Per-Scenario Details** — individual breakdown for each run
- **Architecture Analysis** — commentary on how Kubernetes (3-layer) vs Docker Compose (2-layer) affects restart strategies

All report types store timing data in an accompanying `_timing-data/` directory with
JSON exports and raw timing entries.

## Historical Reports

| Date | Type | Networks | Summary |
|------|------|----------|---------|
| 2026-01-20 | Full suite | Local Node, Solo | First full suite run — Solo: 89.8%, Local Node: 82.0% |
| 2026-01-28 | Full suite | Local Node, Solo | Both networks — Hardhat 86-88%, Foundry 95.8% |
| 2026-02-04 | Deploy benchmark (warm-cluster) | Solo | Two-run comparison: startup 884s → 31s (96.5% reduction), contract ops 38s → 27s (30% faster) |

## Viewing Reports

Reports are Markdown files and can be viewed:
- Directly on GitHub
- In any Markdown viewer
- In VS Code with Markdown preview

## Contributing

When adding new test suites or making significant changes, run the full test suite and include the generated report in your PR.
