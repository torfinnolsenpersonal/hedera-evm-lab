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

### Deploy benchmark (single contract, cold start)

```bash
# Full developer journey (wipes node_modules + artifacts)
./scripts/run-deploy-benchmark.sh anvil
./scripts/run-deploy-benchmark.sh localnode
./scripts/run-deploy-benchmark.sh solo
./scripts/run-deploy-benchmark.sh all

# Warm mode (skip install/compile)
./scripts/run-deploy-benchmark.sh --warm solo
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

Both report types store timing data in an accompanying `_timing-data/` directory with
JSON exports and raw timing entries.

## Historical Reports

| Date | Type | Networks | Summary |
|------|------|----------|---------|
| 2026-01-20 | Full suite | Local Node, Solo | First full suite run — Solo: 89.8%, Local Node: 82.0% |
| 2026-01-28 | Full suite | Local Node, Solo | Both networks — Hardhat 86-88%, Foundry 95.8% |

## Viewing Reports

Reports are Markdown files and can be viewed:
- Directly on GitHub
- In any Markdown viewer
- In VS Code with Markdown preview

## Contributing

When adding new test suites or making significant changes, run the full test suite and include the generated report in your PR.
