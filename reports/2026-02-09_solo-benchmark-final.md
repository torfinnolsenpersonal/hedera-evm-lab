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
| **Install Time** | 61 seconds | PASS |
| **Cold Start Time** | 530 seconds (8m 50s) | PASS |
| **Warm Start Time** | ~3 seconds | PASS |
| **Shutdown Time** | 129 seconds (2m 9s) | PASS |
| **EVM Test Run** | 40 seconds | PASS |
| **HAPI Test Run** | 6 seconds | PASS |

> **Note**: Install Time and Cold Start Time are measured separately. Warm Start assumes network is running but port-forwards need to be re-established (e.g., after closing terminal).

---

## Definitions

### Install Time
**Definition**: Time from a completely clean machine (no Docker images, no node_modules) to "ready to start" state.

**Solo Method**:
```bash
brew tap hiero-ledger/tools
brew update
brew install solo
```

**What was measured**: The complete installation process on a machine that has never had Solo installed:
1. Add the Hiero Homebrew tap
2. Update Homebrew formulas
3. Install Solo and its dependencies (sqlite, zstd, node)

This simulates a developer setting up Solo on a completely fresh machine.

### Cold Start Time
**Definition**: Time from `solo one-shot single deploy` with no existing volumes (fresh database, genesis blockchain state) to SDK transaction-ready. Assumes Solo is already installed.

**Solo Method**:
```bash
solo one-shot single deploy --quiet-mode
```

**What was measured**: Starting from a completely clean Docker environment (no images, no volumes, no kind cluster), with Solo CLI already installed, the time for Solo to:
1. Create a kind Kubernetes cluster
2. Deploy the consensus node (Hedera network node)
3. Deploy the mirror node (REST API, gRPC, importer)
4. Deploy the JSON-RPC relay
5. Deploy the explorer
6. Create 30 test accounts
7. Establish port-forwards for all services

**Total Cold Start Time**: **530 seconds (8m 50s)**

The measurement ends when all services are healthy and SDK transactions can be executed.

### Warm Start Time
**Definition**: Time for reconnecting to a running Solo network after closing terminal (port-forwards lost) to SDK transaction-ready.

**Solo Method**: Re-establish kubectl port-forwards to existing services

```bash
# Network is already running, just need to reconnect
NAMESPACE="solo-{deployment-id}"
kubectl port-forward -n $NAMESPACE svc/network-node1-svc 50211:50211 &
kubectl port-forward -n $NAMESPACE svc/relay-hedera-json-rpc-relay 7546:7546 &
```

**What was measured**: The time to re-establish port-forwards to a Solo network that is already running in Kubernetes. This simulates:
1. Developer has Solo running
2. Closes terminal (port-forwards die)
3. Opens new terminal and reconnects

**Total Warm Start Time**: **~3 seconds**

**Note**: Solo's `init` command is deprecated and does not reconnect to existing networks. Reconnection requires manually setting up port-forwards or running a Solo command that triggers temporary port-forwards.

### Shutdown Time
**Definition**: Time from running state to all Hedera network components removed and kind cluster destroyed.

**Solo Method**:
```bash
solo one-shot single destroy --quiet-mode
kind delete cluster --name solo-cluster  # Required - Solo does not delete the cluster
```

**What was measured**: The complete shutdown process:
1. `solo one-shot single destroy` - Removes all Hedera components (explorer, relay, mirror node, consensus node, charts)
2. `kind delete cluster` - Removes the Kubernetes cluster from Docker

| Step | Duration | Description |
|------|----------|-------------|
| solo one-shot single destroy | 125s | Remove Hedera components, uninstall Helm charts, delete secrets |
| kind delete cluster | 4s | Remove kind Kubernetes cluster |
| **TOTAL** | **129s** | |

> **Note**: `solo one-shot single destroy` does NOT delete the kind cluster. This requires a separate `kind delete cluster` command. Solo leaves the cluster intact to allow potential redeployment, but due to ClusterRole conflicts (see Known Limitations), a fresh cold start requires destroying the cluster anyway.

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

### Install Time: 61 seconds

```bash
brew tap hiero-ledger/tools
# Tapped 9 formulae

brew update
# Already up-to-date

brew install solo
# ==> Installing dependencies for hiero-ledger/tools/solo: sqlite, zstd and node
# ==> Installing hiero-ledger/tools/solo
# 🍺 /opt/homebrew/Cellar/solo/0.54.0: 27,049 files, 261.4MB, built in 37 seconds
```

| Step | Duration | Description |
|------|----------|-------------|
| brew tap | ~5s | Add hiero-ledger/tools tap |
| brew update | ~3s | Update Homebrew formulas |
| Install dependencies | ~16s | sqlite, zstd, node |
| Install Solo | ~37s | Solo CLI via npm |
| **Total** | **61s** | |

### Cold Start Time: 530 seconds (8m 50s)

*Assumes Solo is already installed. See Install Time above for installation timing.*

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
| **TOTAL** | **530s** | |

### Warm Start Time: ~3 seconds

*Network already running in Kubernetes; only port-forwards need to be re-established.*

```bash
# Reconnect to existing Solo network
kubectl port-forward -n solo-{id} svc/network-node1-svc 50211:50211 &
kubectl port-forward -n solo-{id} svc/relay-hedera-json-rpc-relay 7546:7546 &
# Wait for ports to establish
sleep 2
```

| Step | Duration | Description |
|------|----------|-------------|
| kubectl port-forward (gRPC) | ~1s | Re-establish 50211 port-forward |
| kubectl port-forward (RPC) | ~1s | Re-establish 7546 port-forward |
| Connection verification | ~1s | Confirm ports are responding |
| **TOTAL** | **~3s** | |

### Shutdown Time: 129 seconds (2m 9s)

*Two commands required for full shutdown.*

| Step | Duration | Description |
|------|----------|-------------|
| solo one-shot single destroy | 125s | Remove all Hedera components |
| ├─ Explorer destroy | 1s | Uninstall explorer chart |
| ├─ Relay destroy | 1s | Uninstall JSON-RPC relay chart |
| ├─ Mirror node destroy | 4s | Uninstall mirror node, delete PVCs |
| ├─ Consensus network destroy | 74s | Delete secrets, network components |
| ├─ Cluster config reset | 0.4s | Uninstall MinIO operator |
| └─ Cleanup | 45s | Final cleanup and config removal |
| kind delete cluster | 4s | Remove kind Kubernetes cluster |
| **TOTAL** | **129s** | |

> **Note**: The `kind delete cluster` command is NOT part of Solo CLI. This is a separate command required for full cleanup.

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

### Warm Start vs Redeployment
**Warm Start (Supported)**: Reconnecting to a running Solo network by re-establishing port-forwards. Takes ~3 seconds.

**Redeployment on Same Cluster (NOT Supported)**: Solo's architecture creates cluster-scoped Kubernetes resources (ClusterRoles, ClusterRoleBindings) that are tied to specific namespace names. When attempting to redeploy after destroying a deployment:
- A new namespace is created with a new hash
- Old cluster resources conflict with new deployment
- Helm cannot import resources from different namespaces

**Error encountered when redeploying**:
```
ClusterRole "mirror-ingress-controller" in namespace "" exists and cannot be
imported into the current release: invalid ownership metadata; annotation
validation error: key "meta.helm.sh/release-namespace" must equal "solo-{new}"
current value is "solo-{old}"
```

**Workaround**: To redeploy, destroy the entire kind cluster first (`kind delete cluster`) and do a full cold start.

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
# Clean environment (simulate fresh machine)
brew untap hiero-ledger/tools 2>/dev/null || true
brew uninstall solo 2>/dev/null || true
docker system prune -af --volumes
kind delete clusters --all

# INSTALL TIME - measure tap + update + install (~61s)
START=$(date +%s)
brew tap hiero-ledger/tools
brew update
brew install solo
END=$(date +%s)
echo "Install Time: $((END-START)) seconds"

# COLD START TIME - measure network startup only (~530s)
# (Solo is already installed from above)
docker system prune -af --volumes
kind delete clusters --all

START=$(date +%s)
solo one-shot single deploy --quiet-mode
END=$(date +%s)
echo "Cold Start Time: $((END-START)) seconds"

# WARM START TIME - reconnect to running network (~3s)
# First, kill port-forwards (simulates closing terminal)
pkill -f "kubectl.*port-forward"
sleep 2

# Now reconnect
NAMESPACE=$(kubectl get ns | grep solo- | grep -v setup | awk '{print $1}')
START=$(date +%s)
kubectl port-forward -n $NAMESPACE svc/network-node1-svc 50211:50211 &
kubectl port-forward -n $NAMESPACE svc/relay-hedera-json-rpc-relay 7546:7546 &
sleep 2
END=$(date +%s)
echo "Warm Start Time: $((END-START)) seconds"

# Run EVM test
cd examples/hardhat/contract-smoke
npx hardhat test test/EVMBenchmark.test.ts --network solo

# Run HAPI test
npx hardhat test test/HAPIBenchmark.test.ts --network solo

# SHUTDOWN TIME - measure destroy + cluster deletion (~129s)
START=$(date +%s)
solo one-shot single destroy --quiet-mode
kind delete cluster --name solo-cluster  # Required - Solo CLI doesn't delete the cluster
END=$(date +%s)
echo "Shutdown Time: $((END-START)) seconds"
```

**Note**:
- Install Time (61s) = `brew tap` + `brew update` + `brew install solo`
- Cold Start Time (530s) = `solo one-shot single deploy` (assumes Solo already installed)
- Warm Start Time (~3s) = Re-establish kubectl port-forwards to running network (requires `kubectl` command, not Solo CLI)
- Shutdown Time (129s) = `solo one-shot single destroy` + `kind delete cluster` (kind command required for full cleanup)

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
