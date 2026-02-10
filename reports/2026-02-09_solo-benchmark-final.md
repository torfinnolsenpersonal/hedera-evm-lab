# Solo Network Benchmark Report - Final Results

**Date**: 2026-02-09
**Solo Version**: 0.54.0
**Platform**: macOS Darwin 24.6.0 (arm64)
**Node.js**: v25.5.0
**Docker**: 27.3.1

---

## Executive Summary

| Metric | Time | Status |
|--------|------|--------|
| **Install Time** | 39 seconds | PASS |
| **Cold Start Time** | 530 seconds (8m 50s) | PASS |
| **Warm Start Time** | N/A | NOT SUPPORTED |
| **Shutdown Time** | <1 second | PASS |
| **EVM Test Run** | 40 seconds | PASS |
| **HAPI Test Run** | 6 seconds | PASS |

---

## Definitions

### Install Time
**Definition**: Time from a completely clean machine (no Docker images, no node_modules) to "ready to start" state.

**Solo Method**: `brew reinstall solo`

**What was measured**: The time to reinstall Solo via Homebrew, which downloads and installs the Solo CLI and all its dependencies. This simulates a developer setting up Solo on a fresh machine.

### Cold Start Time
**Definition**: Time from Solo one-shot start with no existing volumes (fresh database, genesis blockchain state) to SDK transaction-ready.

**Solo Method**: `solo one-shot single deploy --quiet-mode`

**What was measured**: Starting from a completely clean Docker environment (no images, no volumes, no kind cluster), the time for Solo to:
1. Create a kind Kubernetes cluster
2. Deploy the consensus node (Hedera network node)
3. Deploy the mirror node (REST API, gRPC, importer)
4. Deploy the JSON-RPC relay
5. Deploy the explorer
6. Create 30 test accounts
7. Establish port-forwards for all services

The measurement ends when all services are healthy and SDK transactions can be executed.

### Warm Start Time
**Definition**: Time for Stop followed by Start with preserved volumes (existing database, blockchain state) to SDK transaction-ready.

**Solo Status**: **NOT SUPPORTED**

**Finding**: Solo does not support true warm restarts on the same Kubernetes cluster. When attempting to redeploy after stopping:
- Cluster-scoped Helm resources (ClusterRoles) conflict between deployments
- The `solo one-shot single deploy` command creates a new namespace each time
- Previous deployment's cluster resources cause Helm upgrade failures

**Workaround**: The only restart option is a full cold start (destroy kind cluster and redeploy from scratch).

### Shutdown Time
**Definition**: Time from running state to all containers stopped/removed.

**Solo Method**: `./scripts/stop-solo.sh --keep-cluster` (preserves cluster) or `kind delete cluster` (full destruction)

**What was measured**:
- With `--keep-cluster`: <1 second (only stops port-forwards)
- Full destruction (`kind delete cluster`): ~2-3 seconds

### HAPI Test Run
**Definition**: Create 3 accounts, Create FT Token, Mint Token, Transfer token. All tests run sequentially after confirmation in mirror node.

**Solo Method**: `npx hardhat test test/HAPIBenchmark.test.ts --network solo`

**What was measured**: Using the Hedera SDK (@hashgraph/sdk) directly via gRPC (port 50211):
1. Create 3 new accounts using `AccountCreateTransaction`
2. Create a fungible token using `TokenCreateTransaction`
3. Associate token with accounts using `TokenAssociateTransaction`
4. Mint tokens using `TokenMintTransaction`
5. Transfer tokens between accounts using `TransferTransaction`
6. Verify balances via Mirror Node REST API
7. Verify balances via SDK `AccountBalanceQuery`

### EVM Test Run
**Definition**: Create 3 accounts, Deploy ERC20 contract, Create Token, Mint Token, Transfer Token. All tests run sequentially after confirmation from eth_call.

**Solo Method**: `npx hardhat test test/EVMBenchmark.test.ts --network solo`

**What was measured**: Using ethers.js via JSON-RPC relay (port 7546):
1. Use 3 pre-funded ECDSA accounts from Solo's account creation
2. Deploy a standard ERC20 contract
3. Mint tokens to the deployer account
4. Transfer tokens from deployer to account 1
5. Transfer tokens from deployer to account 2
6. Verify all balances using `eth_call` (balanceOf)

---

## Detailed Timing Breakdown

### Install Time: 39 seconds

```
brew reinstall solo
==> Reinstalling hiero-ledger/tools/solo
🍺 /opt/homebrew/Cellar/solo/0.54.0: 27,049 files, 261.4MB, built in 31 seconds
```

### Cold Start Time: 530 seconds (8m 50s)

| Phase | Duration | Description |
|-------|----------|-------------|
| Dependencies check | 0.3s | Verify helm, kubectl, kind |
| Chart manager setup | 5s | Initialize Helm chart manager |
| Kind cluster creation | 43s | Create Kubernetes cluster in Docker |
| Cluster configuration | 1s | Set up cluster reference and deployment config |
| MinIO operator | 1s | Install object storage operator |
| Key generation | 1s | Generate gossip and TLS keys |
| Consensus network deploy | 72s | Deploy network node pod + proxies |
| Consensus node setup | 15s | Fetch platform software, configure node |
| Consensus node start | 38s | Start node, wait for ACTIVE status |
| Mirror node add | 220s | Deploy postgres, importer, REST, gRPC, web3 |
| Explorer add | 20s | Deploy Hedera explorer |
| Relay add | 51s | Deploy JSON-RPC relay |
| Account creation | 16s | Create 30 test accounts |
| **Total** | **530s** | |

### EVM Test Run: 40 seconds

| Step | Duration | Description |
|------|----------|-------------|
| Deploy ERC20 | 13.7s | Deploy BenchToken contract |
| Mint tokens | 8.2s | Mint 10,000 tokens to account[0] |
| Transfer to account[1] | 8.0s | Transfer 1,000 tokens |
| Transfer to account[2] | 8.0s | Transfer 1,000 tokens |
| Confirm balances | 0.3s | Verify via eth_call |
| **Total** | **38.2s** | (plus test overhead: 40s) |

**Evidence**:
- Contract address: `0x23f5e49569A835d7bf9AefD30e4f60CdD570f225`
- Deploy TX: `0x4cf88ee5786014af810199867ec8c273459aed673176e426430c8adf8c5a4da9`

### HAPI Test Run: 6 seconds

| Step | Duration | Description |
|------|----------|-------------|
| Create 3 accounts | 0.9s | AccountCreateTransaction x3 |
| Create FT token | 0.4s | TokenCreateTransaction |
| Associate token | 0.5s | TokenAssociateTransaction x2 |
| Mint tokens | 0.3s | TokenMintTransaction |
| Transfer tokens | 0.3s | TransferTransaction x2 |
| Mirror node confirm | 3.1s | REST API balance verification |
| SDK query confirm | 0.04s | AccountBalanceQuery x3 |
| **Total** | **5.4s** | (plus test overhead: 6s) |

**Evidence**:
- Token ID: `0.0.1036`
- Accounts: `0.0.1033`, `0.0.1034`, `0.0.1035`
- Operator: `0.0.2`

---

## Test Environment

### Solo Network Configuration
- **Cluster**: kind (Kubernetes in Docker)
- **Kubernetes**: v1.35.0
- **Namespace**: solo-{hash}
- **Consensus Node**: 1 node (node1)
- **Chain ID**: 298 (0x12a)

### Ports Used
| Service | Port |
|---------|------|
| JSON-RPC Relay | 7546 |
| gRPC (Consensus) | 50211 |
| Mirror REST API | 8081 |
| Explorer | 8080 |

### Test Accounts
Solo creates 30 test accounts at startup:
- 10 ECDSA Alias Accounts (EVM compatible)
- 10 ED25519 Accounts
- 10 ECDSA Accounts (not EVM compatible)

Each account is funded with 10,000 HBAR.

---

## Known Limitations

### Warm Start Not Supported
Solo's architecture creates cluster-scoped Kubernetes resources (ClusterRoles, ClusterRoleBindings) that are tied to specific namespace names. When redeploying:
- A new namespace is created with a new hash
- Old cluster resources conflict with new deployment
- Helm cannot import resources from different namespaces

**Error encountered**:
```
ClusterRole "mirror-ingress-controller" in namespace "" exists and cannot be
imported into the current release: invalid ownership metadata; annotation
validation error: key "meta.helm.sh/release-namespace" must equal "solo-{new}"
current value is "solo-{old}"
```

### Docker Disk Space
Solo requires significant Docker disk space (~10-15GB) for container images. Running out of disk space causes `ImagePullBackOff` errors:
```
no space left on device
```

**Recommendation**: Ensure at least 20GB free Docker disk space before running Solo.

---

## Comparison Notes

### Solo vs Local Node Architecture

| Aspect | Solo | Local Node |
|--------|------|------------|
| Container orchestration | Kubernetes (kind) | Docker Compose |
| Warm restart | Not supported | Supported (volumes preserved) |
| Complexity | Higher (3-layer: CLI → k8s → network) | Lower (2-layer: CLI → containers) |
| Production similarity | Closer to mainnet topology | Simpler development setup |

### Recommended Use Cases

| Use Case | Recommendation |
|----------|----------------|
| Rapid iteration / TDD | Local Node (faster warm restarts) |
| Full network simulation | Solo (closer to production) |
| CI/CD cold starts | Either (similar cold start times) |
| HAPI/SDK development | Solo (native gRPC support) |
| EVM development | Either (both support JSON-RPC) |

---

## Reproducibility

To reproduce these benchmarks:

```bash
# Clean environment
docker system prune -af --volumes
kind delete clusters --all

# Install Solo
brew reinstall solo

# Cold start (measure this)
time solo one-shot single deploy --quiet-mode

# Run EVM test
cd examples/hardhat/contract-smoke
npx hardhat test test/EVMBenchmark.test.ts --network solo

# Run HAPI test
npx hardhat test test/HAPIBenchmark.test.ts --network solo

# Shutdown
kind delete cluster --name solo-cluster
```

---

## Appendix: Raw Test Output

### EVM Benchmark Results
```
╔══════════════════════════════════════════════════════════╗
║         EVM BENCHMARK RESULTS - solo                   ║
╠══════════════════════════════════════════════════════════╣
║  Deploy ERC20                                    13.7s ║
║  Mint tokens                                      8.2s ║
║  Transfer to acc[1]                               8.0s ║
║  Transfer to acc[2]                               8.0s ║
║  Confirm balances                                 0.3s ║
╠══════════════════════════════════════════════════════════╣
║  TOTAL                                           38.2s ║
╚══════════════════════════════════════════════════════════╝
```

### HAPI Benchmark Results
```
╔══════════════════════════════════════════════════════════╗
║         HAPI BENCHMARK RESULTS                           ║
╠══════════════════════════════════════════════════════════╣
║  Create 3 accounts                                0.9s ║
║  Create FT token                                  0.4s ║
║  Associate token                                  0.5s ║
║  Mint tokens                                      0.3s ║
║  Transfer tokens                                  0.3s ║
║  Mirror confirm                                   3.1s ║
║  SDK query confirm                                0.0s ║
╠══════════════════════════════════════════════════════════╣
║  TOTAL                                            5.4s ║
╚══════════════════════════════════════════════════════════╝
```

---

*Report generated: 2026-02-09*
*Benchmark script: `scripts/run-deploy-benchmark.sh`*
