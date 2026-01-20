# Hedera EVM Lab

A complete local workspace for Hedera EVM development and testing using **Hiero Local Node** and **Solo**, integrated with **Hardhat** and **Foundry**.

## Quick Start

```bash
# 1. Check prerequisites
./scripts/doctor.sh

# 2. Start Local Node (simpler, recommended for development)
./scripts/start-local-node.sh

# 3. Run smoke tests
./scripts/run-hardhat-smoke.sh
./scripts/run-foundry-smoke.sh --fork

# 4. Stop when done
./scripts/stop-local-node.sh
```

## Important: Shared Proxy Port

**Both Local Node and Solo use port 7546 for the JSON-RPC relay.**

- **Do not run both simultaneously** - port conflict will occur
- Stop one network before starting the other
- Use `lsof -i :7546` to check what's using the port

## Repository Structure

```
hedera-evm-lab/
├── repos/                          # Cloned repositories
│   ├── solo/                       # Hiero Solo
│   ├── hiero-local-node/           # Hiero Local Node
│   ├── hardhat/                    # Hardhat (reference)
│   └── foundry/                    # Foundry (reference)
├── docs/
│   ├── 01-setup-and-prereqs.md     # Installation guide
│   ├── 02-solo-vs-local-node-gap-analysis.md
│   ├── 03-hardhat-integration.md
│   ├── 04-foundry-integration.md
│   ├── 05-sample-test-plan.md
│   └── 06-troubleshooting.md
├── examples/
│   ├── hardhat/contract-smoke/     # Hardhat sample project
│   └── foundry/contract-smoke/     # Foundry sample project
├── scripts/
│   ├── doctor.sh                   # Check prerequisites
│   ├── clone-repos.sh              # Clone all repos
│   ├── start-local-node.sh         # Start Local Node
│   ├── stop-local-node.sh          # Stop Local Node
│   ├── start-solo.sh               # Start Solo
│   ├── stop-solo.sh                # Stop Solo
│   ├── run-hardhat-smoke.sh        # Run Hardhat tests
│   ├── run-foundry-smoke.sh        # Run Foundry tests
│   └── run-all.sh                  # Run all tests
├── .env.example
└── README.md
```

## Repository Commit SHAs

| Repository | Commit SHA |
|------------|------------|
| solo | 8e0f0075a53dfd9a0a3d191add9f136f573ee3e4 |
| hiero-local-node | b92cdb897403f358e1bad34c368a13fd7215f586 |
| hardhat | b1156c90176e69fc3fab61f7adea30e256e36ec5 |
| foundry | f613d83e3057040643a97ec1aad0e0c909163cf5 |

## Prerequisites

### Minimum (Local Node only)
- Node.js >= 20.11.0
- Docker >= 27.3.1
- Docker Compose >= 2.29.7
- 8 GB RAM, 6 CPU cores

### Full Setup (including Solo)
- Node.js >= 22.0.0
- Docker >= 27.3.1
- kubectl, kind, helm
- 12 GB RAM, 6 CPU cores

Run `./scripts/doctor.sh` to verify your setup.

## Network Comparison

| Feature | Local Node | Solo |
|---------|------------|------|
| Setup | Simple (Docker) | Complex (Kubernetes) |
| Startup Time | ~2-3 min | ~5-10 min |
| Memory | 8 GB min | 12 GB min |
| Multi-node | Limited | Full support |
| CI/CD | Excellent | Good |
| Use Case | Development | Production-like testing |

See `docs/02-solo-vs-local-node-gap-analysis.md` for detailed comparison.

## Network Endpoints

Both networks expose these endpoints:

| Service | URL |
|---------|-----|
| JSON-RPC Relay | http://127.0.0.1:7546 |
| WebSocket | ws://127.0.0.1:8546 |
| Mirror Node REST | http://127.0.0.1:5551 |
| Mirror Node gRPC | 127.0.0.1:5600 |
| Chain ID | 298 (0x12a) |

## Test Accounts (Local Node)

Pre-funded accounts (10,000 HBAR each):

| Address | Private Key |
|---------|-------------|
| 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69 | 0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524 |
| 0x05FbA803Be258049A27B820088bab1cAD2058871 | 0x2e1d968b041d84dd120a5860cee60cd83f9374ef527ca86996317ada3d0d03e7 |

## Workflows

### Local Node Workflow

```bash
# Start
./scripts/start-local-node.sh

# Deploy with Hardhat
cd examples/hardhat/contract-smoke
npm install
npx hardhat run scripts/deploy.ts --network localnode

# Deploy with Foundry
cd examples/foundry/contract-smoke
source .env
forge script script/Deploy.s.sol:DeployCounter --rpc-url $RPC_URL --broadcast

# Stop
./scripts/stop-local-node.sh
```

### Solo Workflow

```bash
# Prerequisites (Homebrew - recommended)
brew tap hiero-ledger/tools
brew install solo
# Or pin a specific version:
# brew install hiero-ledger/tools/solo@<version>

# Alternative (npm - not recommended)
# npm install -g @hashgraph/solo

# Start
./scripts/start-solo.sh

# Create accounts (Solo doesn't auto-create test accounts)
solo ledger account create --deployment solo-deployment --hbar-amount 1000 --generate-ecdsa-key

# Run tests
./scripts/run-hardhat-smoke.sh solo

# Stop
./scripts/stop-solo.sh
```

### Full Test Suite

```bash
# Test against Local Node only (default)
./scripts/run-all.sh localnode

# Test against Solo only
./scripts/run-all.sh solo

# Test against both (sequentially - they share port 7546)
./scripts/run-all.sh both
```

## Verification Commands

```bash
# Check network is running
curl -s http://127.0.0.1:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Expected: {"jsonrpc":"2.0","id":1,"result":"0x12a"}

# Check balance
cast balance 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69 --rpc-url http://127.0.0.1:7546
```

## Troubleshooting

### Connection Refused
```bash
# Check if network is running
./scripts/doctor.sh
lsof -i :7546
```

### Port Conflict
```bash
# Stop all networks
./scripts/stop-local-node.sh
./scripts/stop-solo.sh
```

### Full Reset
```bash
# Local Node
docker rm -f $(docker ps -aq --filter name=hedera)
docker volume prune -f

# Solo
rm -rf ~/.solo
kind delete clusters --all
```

See `docs/06-troubleshooting.md` for comprehensive troubleshooting guide.

## Documentation

- [Setup and Prerequisites](docs/01-setup-and-prereqs.md)
- [Solo vs Local Node Gap Analysis](docs/02-solo-vs-local-node-gap-analysis.md)
- [Hardhat Integration](docs/03-hardhat-integration.md)
- [Foundry Integration](docs/04-foundry-integration.md)
- [Sample Test Plan](docs/05-sample-test-plan.md)
- [Troubleshooting](docs/06-troubleshooting.md)

## Assumptions

1. **Default path**: `~/hedera-evm-lab` (configurable via clone location)
2. **Primary OS**: macOS/Linux (WSL2 for Windows)
3. **Local Node preferred** for quick development
4. **Solo** for production-like testing or multi-node scenarios
5. **PowerShell scripts** provided for Windows native (but WSL2 recommended)

## Customization

Edit `.env` (copy from `.env.example`) to customize:
- RPC URLs
- Private keys
- Solo cluster names
- Network configuration
