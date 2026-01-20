# Proposal: Streamlined Solo README

**Date:** 2026-01-20
**Status:** Proposal (LOCAL ONLY - not for direct submission)

## Summary

This proposal provides a streamlined README.md for Solo that:
1. Leads with the quickest path to a running network (one-shot command)
2. Prioritizes Homebrew installation for macOS
3. Reduces cognitive load by moving detailed tables to linked documentation
4. Improves developer experience for first-time users

## Rationale

The current README is comprehensive but can overwhelm new users with version matrices and detailed setup instructions before they see what Solo can do. A "quick start first" approach improves:

1. **Time to first successful deployment** - Users can have a running network faster
2. **Confidence** - Seeing it work builds trust before diving into details
3. **Adoption** - Lower barrier to entry means more users try Solo

## Proposed README Structure

```markdown
> New to Solo? Start with `solo one-shot single deploy` - it handles everything!

# Solo

[![NPM Version](https://img.shields.io/npm/v/%40hashgraph%2Fsolo?logo=npm)](https://www.npmjs.com/package/@hashgraph/solo)
[![GitHub License](https://img.shields.io/github/license/hiero-ledger/solo?logo=apache&logoColor=red)](LICENSE)

An opinionated CLI tool to deploy and manage standalone Hedera test networks.

## Quick Start

Get a local Hedera network running in under 5 commands:

### 1. Prerequisites

- Docker Desktop with **12GB+ memory** and **6+ CPU cores**
- Node.js 22+ (for npm install) or Homebrew (macOS)

### 2. Install Solo

**macOS (Homebrew - Recommended):**
```bash
brew tap hiero-ledger/tools
brew install solo
```

**npm (Cross-platform):**
```bash
npm install -g @hashgraph/solo
```

### 3. Deploy a Network

```bash
solo one-shot single deploy
```

That's it! You now have:
- A single Hedera consensus node
- Mirror node with REST API
- JSON-RPC relay at `http://localhost:7546`
- Explorer at `http://localhost:8080`

### 4. Verify It's Running

```bash
curl -s http://localhost:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Expected: {"jsonrpc":"2.0","id":1,"result":"0x12a"}
```

### 5. Clean Up

```bash
solo one-shot single destroy
```

## Network Endpoints

| Service | URL |
|---------|-----|
| JSON-RPC Relay | http://localhost:7546 |
| Mirror Node REST | http://localhost:8081/api/v1 |
| Mirror Node gRPC | localhost:5600 |
| Explorer | http://localhost:8080 |
| Consensus Node | localhost:50211 |

**Chain ID:** 298 (0x12a)

## Common Tasks

### Create a Funded Account

```bash
solo ledger account create \
  --deployment solo-deployment \
  --hbar-amount 1000 \
  --generate-ecdsa-key
```

### Check Pod Status

```bash
kubectl get pods -n solo
```

### View Logs

```bash
kubectl logs -n solo <pod-name>
```

## Documentation

- **[Full User Guide](https://solo.hiero.org/)** - Detailed setup, configuration, multi-node deployments
- **[CLI Reference](https://solo.hiero.org/main/docs/solo-commands/)** - All available commands
- **[Step-by-Step Guide](https://solo.hiero.org/main/docs/step-by-step-guide/)** - Manual deployment walkthrough

## Requirements

| Software | Version | Notes |
|----------|---------|-------|
| Node.js | >= 22.0.0 | For npm install |
| Docker | Latest | With 12GB+ RAM, 6+ CPUs |
| kubectl | >= 1.27.3 | Auto-installed by kind |
| kind | >= 0.29.0 | Kubernetes in Docker |
| helm | >= 3.14.2 | Package manager |

See [releases documentation](docs/legacy-versions.md) for version compatibility matrix.

## Version Pinning (CI/CD)

For reproducible environments:

```bash
# Homebrew
brew install hiero-ledger/tools/solo@0.52.0

# npm
npm install -g @hashgraph/solo@0.52.0
```

## Contributing

Contributions welcome! See the [contributing guide](https://github.com/hiero-ledger/.github/blob/main/CONTRIBUTING.md).

## License

[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
```

## Key Changes from Current README

| Aspect | Current | Proposed |
|--------|---------|----------|
| Lead content | Version matrix table | Quick start commands |
| Installation | npm only | Homebrew-first, npm alternative |
| One-shot command | Mentioned in banner | Featured as primary workflow |
| Version matrix | In README | Linked to docs |
| Badges | 8 badges | 2 essential badges |
| Prerequisites | Scattered | Consolidated |
| First command | `npm install` | `solo one-shot single deploy` |

## Benefits

1. **Faster onboarding** - New users can deploy in < 2 minutes
2. **Less intimidating** - Reduced information overload
3. **Action-oriented** - Commands come before explanations
4. **Maintainable** - Detailed version info lives in dedicated docs

## Migration Notes

- Move detailed version matrix to `docs/releases.md` or the documentation site
- Keep current README accessible at `docs/detailed-readme.md` for reference
- Update documentation site links to point to new structure

## Files

- `02-solo-streamlined-readme-proposal.md` - This proposal
- `02-solo-streamlined-readme.md` - Full proposed README content
