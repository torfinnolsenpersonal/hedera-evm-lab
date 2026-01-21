# Test Reports

This directory contains comprehensive test reports generated from Hedera EVM Lab smoke test runs.

## Report Format

Reports are named using the format:
```
YYYY-MM-DD_HH-MM-SS_[description].md
```

## Generating Reports

Reports are automatically generated when running the full test suite:

```bash
# Run all tests and generate report
./scripts/run-all.sh both

# Or manually generate a report
./scripts/generate-report.sh [hardhat_output] [foundry_output] [network]
```

## Report Contents

Each report includes:

1. **Executive Summary** - Pass/fail counts and rates for all frameworks and networks
2. **Environment** - System info, tool versions, repository commits
3. **Detailed Results** - Per-framework breakdown with timing analysis
4. **Failed Tests** - List of specific test failures with error context
5. **EVM Feature Coverage** - Matrix of tested EVM features
6. **Recommendations** - Actionable insights from test results

## Historical Reports

| Date | Networks | Summary |
|------|----------|---------|
| 2026-01-20 | Local Node, Solo | First full suite run - Solo: 89.8%, Local Node: 82.0% |

## Viewing Reports

Reports are Markdown files and can be viewed:
- Directly on GitHub
- In any Markdown viewer
- In VS Code with Markdown preview

## Contributing

When adding new test suites or making significant changes, run the full test suite and include the generated report in your PR.
