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
| **Shutdown Time** | 125 seconds (2m 5s) | PASS |
| **EVM Test Run** | 40 seconds | PASS |
| **HAPI Test Run** | 6 seconds | PASS |
| **EVM Sub-Test** | 41 seconds | PASS |
| **HAPI Sub-Test** | 5 seconds | PASS |

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
**Definition**: Time from running state to all Hedera network components removed.

**Solo Method**:
```bash
solo one-shot single destroy --quiet-mode
```

**What was measured**: The complete Solo CLI shutdown process:
1. Destroy explorer and ingress controller
2. Destroy JSON-RPC relay
3. Destroy mirror node (postgres, importer, REST, gRPC, web3) and delete PVCs
4. Destroy consensus network and delete secrets
5. Reset cluster configuration and uninstall operators
6. Remove deployment from local config

**Total Shutdown Time**: **125 seconds**

> **Note**: `solo one-shot single destroy` removes all Hedera components but leaves the kind cluster intact. The cluster can be reused for a subsequent `solo one-shot single deploy`, though ClusterRole conflicts may require manual cleanup (see Known Limitations).

### HAPI Test Run
**Definition**: Create 3 accounts, Create FT Token, Mint Token, Transfer token. All tests run sequentially after confirmation in mirror node.

**Solo Method**: `npx hardhat test test/HAPIBenchmark.test.ts --network solo`

**Test Context**:
- **Framework**: Mocha test runner (via Hardhat) with @hashgraph/sdk
- **Connection**: gRPC directly to consensus node on port 50211
- **Operator Account**: 0.0.2 (Solo's default operator with ED25519 key)
- **Mirror Node**: REST API on port 8081 for balance confirmation
- **Test File**: `examples/hardhat/contract-smoke/test/HAPIBenchmark.test.ts`

**What was measured**: Using the Hedera SDK (@hashgraph/sdk) directly via gRPC:

| Step | Description | Hedera Transaction |
|------|-------------|-------------------|
| 1. Create 3 accounts | Create new accounts with ED25519 keys, 100 HBAR each | `AccountCreateTransaction` x3 |
| 2. Create FT token | Create "Benchmark Token" (BENCH) with 2 decimals, infinite supply | `TokenCreateTransaction` |
| 3. Associate token | Associate BENCH token with accounts 1 and 2 | `TokenAssociateTransaction` x2 |
| 4. Mint tokens | Mint 10,000 units (100.00 BENCH) to treasury (account[0]) | `TokenMintTransaction` |
| 5. Transfer tokens | Transfer 1,000 units to account[1] and 1,000 to account[2] | `TransferTransaction` |
| 6. Mirror node confirm | Wait 3s for sync, query balances via REST API | HTTP GET to mirror node |
| 7. SDK query confirm | Query balances via SDK | `AccountBalanceQuery` x3 |

**Expected Final Balances** (2 decimal places):
- account[0]: 80.00 BENCH (100.00 - 10.00 - 10.00)
- account[1]: 10.00 BENCH
- account[2]: 10.00 BENCH

**Key Differences from EVM Test**:
- Creates new accounts (EVM uses pre-funded accounts from Solo startup)
- Uses native Hedera token (HTS) instead of ERC-20 contract
- Requires token association before receiving tokens (Hedera-specific)
- Direct gRPC to consensus node (EVM goes through JSON-RPC relay)
- Two confirmation methods: Mirror Node REST API + SDK query

### EVM Test Run
**Definition**: Deploy ERC20 contract, Mint Token, Transfer Token between 3 accounts. All tests run sequentially after confirmation from eth_call.

**Solo Method**: `npx hardhat test test/EVMBenchmark.test.ts --network solo`

**Test Context**:
- **Framework**: Hardhat with ethers.js
- **Connection**: JSON-RPC relay on port 7546
- **Accounts**: 3 pre-funded ECDSA accounts created during Solo cold start (each has 10,000 HBAR)
- **Contract**: `TestToken.sol` - A basic ERC-20 implementation with mint/transfer/burn functions
- **Test File**: `examples/hardhat/contract-smoke/test/EVMBenchmark.test.ts`

**What was measured**: Using ethers.js via JSON-RPC relay (port 7546):

| Step | Description | Hedera Operation |
|------|-------------|------------------|
| 1. Get 3 signers | Retrieve pre-funded ECDSA accounts from Hardhat | N/A (local) |
| 2. Deploy TestToken | Deploy ERC-20 contract ("Benchmark Token", "BENCH") | `ContractCreateTransaction` via relay |
| 3. Mint tokens | Mint 10,000 BENCH (18 decimals) to account[0] | `ContractCallTransaction` via relay |
| 4. Transfer to account[1] | Transfer 1,000 BENCH from account[0] to account[1] | `ContractCallTransaction` via relay |
| 5. Transfer to account[2] | Transfer 1,000 BENCH from account[0] to account[2] | `ContractCallTransaction` via relay |
| 6. Verify balances | Call `balanceOf()` for all 3 accounts | `eth_call` (read-only) |

**Expected Final Balances**:
- account[0]: 8,000 BENCH (10,000 - 1,000 - 1,000)
- account[1]: 1,000 BENCH
- account[2]: 1,000 BENCH

**Network Configuration**:
- Default wait after transaction: 2,500ms (allows mirror node sync)
- Test timeout: 120,000ms (2 minutes)

### HAPI Sub-Test
**Definition**: Create 3 accounts, Create FT Token, Mint Token, Transfer token. All tests run sequentially after confirmation in mirror node.

**Solo Method**: `npx hardhat test test/HAPIBenchmarkSub.test.ts --network solo`

**Test Context**:
- **Framework**: Mocha test runner (via Hardhat) with @hashgraph/sdk
- **Connection**: gRPC directly to consensus node on port 50211
- **Confirmation**: All balances confirmed via Mirror Node REST API only (no SDK query step)
- **Test File**: `examples/hardhat/contract-smoke/test/HAPIBenchmarkSub.test.ts`

**What was measured**: Using the Hedera SDK (@hashgraph/sdk) directly via gRPC:

| Step | Description | Hedera Transaction |
|------|-------------|-------------------|
| 1. Create 3 accounts | Create new accounts with ED25519 keys, 100 HBAR each | `AccountCreateTransaction` x3 |
| 2. Create FT token | Create "Benchmark Token" (BENCH) with 2 decimals, infinite supply | `TokenCreateTransaction` |
| 3. Associate token | Associate BENCH token with accounts 1 and 2 | `TokenAssociateTransaction` x2 |
| 4. Mint tokens | Mint 10,000 units (100.00 BENCH) to treasury (account[0]) | `TokenMintTransaction` |
| 5. Transfer tokens | Transfer 1,000 units to account[1] and 1,000 to account[2] | `TransferTransaction` |
| 6. Mirror node confirm | Wait for mirror node, confirm all 3 balances via REST API | HTTP GET to mirror node |

**Timing Results**:
| Step | Duration |
|------|----------|
| Create 3 accounts | 0.8s |
| Create FT token | 0.3s |
| Associate token | 0.5s |
| Mint tokens | 0.5s |
| Transfer tokens | 0.3s |
| Mirror node confirm | 2.1s |
| **TOTAL** | **4.6s** |

### EVM Sub-Test
**Definition**: Create 3 accounts, Deploy ERC20 contract, Mint Token, Transfer Token. All tests run sequentially after confirmation from eth_call.

**Solo Method**: `npx hardhat test test/EVMBenchmarkSub.test.ts --network solo`

**Test Context**:
- **Framework**: Hardhat with ethers.js + @hashgraph/sdk (for account creation)
- **Connection**: gRPC (port 50211) for account creation, JSON-RPC relay (port 7546) for EVM operations
- **Accounts**: 3 NEW ECDSA accounts created via Hedera SDK (not pre-funded accounts)
- **Contract**: `TestToken.sol` - A basic ERC-20 implementation
- **Test File**: `examples/hardhat/contract-smoke/test/EVMBenchmarkSub.test.ts`

**What was measured**: Account creation via HAPI, then EVM operations via JSON-RPC:

| Step | Description | Operation |
|------|-------------|-----------|
| 1. Create 3 accounts | Create ECDSA accounts via Hedera SDK, fund with 1000 HBAR each | `AccountCreateTransaction` x3 |
| 2. Deploy ERC20 | Deploy TestToken contract using new account[0] | `ContractCreateTransaction` via relay |
| 3. Mint tokens | Mint 10,000 BENCH (18 decimals) to account[0] | `ContractCallTransaction` via relay |
| 4. Transfer to account[1] | Transfer 1,000 BENCH from account[0] to account[1] | `ContractCallTransaction` via relay |
| 5. Transfer to account[2] | Transfer 1,000 BENCH from account[0] to account[2] | `ContractCallTransaction` via relay |
| 6. Verify balances | Call `balanceOf()` for all 3 accounts | `eth_call` (read-only) |

**Timing Results**:
| Step | Duration |
|------|----------|
| Create 3 accounts | 5.9s |
| Deploy ERC20 | 14.0s |
| Mint tokens | 7.1s |
| Transfer to acc[1] | 6.8s |
| Transfer to acc[2] | 7.0s |
| Confirm balances | 0.3s |
| **TOTAL** | **41.1s** |

**Key Difference from EVM Test Run**:
- Creates new accounts via HAPI first (adds ~6s overhead)
- Uses freshly created ECDSA accounts instead of pre-funded accounts from Solo startup

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

### Shutdown Time: 125 seconds (2m 5s)

*Using `solo one-shot single destroy --quiet-mode`*

| Phase | Duration | Description |
|-------|----------|-------------|
| Explorer destroy | 1s | Uninstall explorer chart |
| Relay destroy | 1s | Uninstall JSON-RPC relay chart |
| Mirror node destroy | 4s | Uninstall mirror node, delete PVCs |
| Consensus network destroy | 74s | Delete secrets, network components |
| Cluster config reset | 0.4s | Uninstall MinIO operator |
| Config cleanup | 45s | Remove deployment from local config |
| **TOTAL** | **125s** | |

> **Note**: The kind cluster remains after destroy. A subsequent `solo one-shot single deploy` can reuse the cluster, though ClusterRole conflicts may occur (see Known Limitations).

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

# SHUTDOWN TIME - measure destroy (~125s)
START=$(date +%s)
solo one-shot single destroy --quiet-mode
END=$(date +%s)
echo "Shutdown Time: $((END-START)) seconds"
```

**Note**:
- Install Time (61s) = `brew tap` + `brew update` + `brew install solo`
- Cold Start Time (530s) = `solo one-shot single deploy` (assumes Solo already installed)
- Warm Start Time (~3s) = Re-establish kubectl port-forwards to running network (requires `kubectl` command, not Solo CLI)
- Shutdown Time (125s) = `solo one-shot single destroy` (kind cluster remains for potential reuse)

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
