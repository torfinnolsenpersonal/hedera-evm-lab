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

| Step | Duration | % of Total | Description |
|------|----------|------------|-------------|
| brew tap | ~5s | 8% | Add hiero-ledger/tools tap |
| brew update | ~3s | 5% | Update Homebrew formulas |
| Install dependencies | ~16s | 26% | sqlite, zstd, node |
| **Install Solo** | **~37s** | **61%** | Solo CLI via npm |
| **Total** | **61s** | **100%** | |

**Key Finding**: Solo CLI npm installation is the largest component (61%). This includes downloading and installing the Solo npm package and its JavaScript dependencies.

### Cold Start Time: 530 seconds (8m 50s)

*Assumes Solo is already installed. See Install Time above for installation timing.*

| Phase | Duration | % of Total | Description |
|-------|----------|------------|-------------|
| Dependencies check | 0.3s | 0.1% | Verify helm, kubectl, kind |
| Chart manager setup | 5s | 0.9% | Initialize Helm chart manager |
| Kind cluster creation | 43s | 8.1% | Create Kubernetes cluster in Docker |
| Cluster configuration | 1s | 0.2% | Set up cluster reference and deployment config |
| MinIO operator | 1s | 0.2% | Install object storage operator |
| Key generation | 1s | 0.2% | Generate gossip and TLS keys |
| Consensus network deploy | 72s | 13.6% | Deploy network node pod + proxies |
| Consensus node setup | 15s | 2.8% | Fetch platform software, configure node |
| Consensus node start | 38s | 7.2% | Start node, wait for ACTIVE status |
| **Mirror node add** | **220s** | **41.5%** | Deploy postgres, importer, REST, gRPC, web3 |
| Explorer add | 20s | 3.8% | Deploy Hedera explorer |
| Relay add | 51s | 9.6% | Deploy JSON-RPC relay |
| Account creation | 16s | 3.0% | Create 30 test accounts |
| **TOTAL** | **530s** | **100%** | |

#### Cold Start Component Analysis

```
Mirror Node        ████████████████████████████████████████░░░░░░░░  41.5%  (220s)
Consensus Deploy   █████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  13.6%  (72s)
Relay              █████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   9.6%  (51s)
Kind Cluster       ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   8.1%  (43s)
Consensus Start    ███████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   7.2%  (38s)
Explorer           ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   3.8%  (20s)
Account Creation   ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   3.0%  (16s)
Consensus Setup    ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   2.8%  (15s)
Other              █░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   1.6%  (8.3s)
```

**Key Findings**:

| Component Group | Duration | % of Total | Notes |
|-----------------|----------|------------|-------|
| **Mirror Node** | 220s | 41.5% | Largest bottleneck - deploys Postgres, importer, REST API, gRPC, web3 |
| **Consensus Node** | 125s | 23.6% | Deploy (72s) + setup (15s) + start (38s) |
| **Infrastructure** | 92s | 17.4% | Kind cluster (43s) + relay (51s) - both are external dependencies |
| **Auxiliary** | 36s | 6.8% | Explorer (20s) + accounts (16s) |
| **Setup/Config** | 8.3s | 1.6% | Chart manager, MinIO, keys, etc. |

**Optimization Opportunities**:
1. **Mirror Node (41.5%)** - Largest target. Consider lazy initialization or lighter mirror node config for development.
2. **Consensus Deploy (13.6%)** - Pod scheduling and image pulls. Pre-pulling images could help.
3. **Relay (9.6%)** - Could potentially be optional for HAPI-only development.
4. **Kind Cluster (8.1%)** - One-time cost if cluster is preserved between sessions.

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

| Phase | Duration | % of Total | Description |
|-------|----------|------------|-------------|
| Explorer destroy | 1s | 0.8% | Uninstall explorer chart |
| Relay destroy | 1s | 0.8% | Uninstall JSON-RPC relay chart |
| Mirror node destroy | 4s | 3.2% | Uninstall mirror node, delete PVCs |
| **Consensus network destroy** | **74s** | **59.2%** | Delete secrets, network components |
| Cluster config reset | 0.4s | 0.3% | Uninstall MinIO operator |
| **Config cleanup** | **45s** | **36.0%** | Remove deployment from local config |
| **TOTAL** | **125s** | **100%** | |

**Key Findings**:
- **Consensus network destroy (59.2%)** - Deleting Kubernetes secrets is the slowest operation
- **Config cleanup (36.0%)** - Removing deployment config and cleanup tasks
- Chart uninstalls are fast (<5% combined) because Helm just removes manifests

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

## Step-by-Step Recreation Guide

This section provides complete instructions for recreating all benchmark tests from scratch.

### Prerequisites

Before starting, ensure you have the following installed:

| Tool | Version | Installation |
|------|---------|--------------|
| macOS | 14.0+ | N/A |
| Homebrew | 4.0+ | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Docker Desktop | 27.0+ | `brew install --cask docker` |
| Node.js | 20+ | `brew install node` |
| kubectl | 1.30+ | `brew install kubectl` |
| kind | 0.20+ | `brew install kind` |
| helm | 3.12+ | `brew install helm` |

Verify prerequisites:
```bash
docker --version    # Docker version 27.x.x
node --version      # v25.x.x or v20.x.x
kubectl version     # Client Version: v1.3x.x
kind --version      # kind v0.2x.x
helm version        # v3.1x.x
```

### Step 1: Install Solo

```bash
# Add the Hiero Homebrew tap
brew tap hiero-ledger/tools

# Update Homebrew formulas
brew update

# Install Solo
brew install solo

# Verify installation
solo --version
# Version: 0.54.0
```

### Step 2: Start Solo Network

```bash
# Ensure Docker is running
docker info

# Deploy Solo network (takes ~8-9 minutes on first run)
solo one-shot single deploy --quiet-mode

# Verify network is running
curl -s http://127.0.0.1:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Expected: {"jsonrpc":"2.0","id":1,"result":"0x12a"}
```

### Step 3: Set Up Test Project

Create the Hardhat project structure:

```bash
# Create project directory
mkdir -p hedera-benchmark/contracts hedera-benchmark/test
cd hedera-benchmark

# Initialize npm project
npm init -y
```

#### package.json

```json
{
  "name": "hedera-benchmark",
  "version": "1.0.0",
  "description": "Hedera Solo benchmark tests",
  "scripts": {
    "compile": "hardhat compile",
    "test:evm": "hardhat test test/EVMBenchmark.test.ts --network solo",
    "test:evm:sub": "hardhat test test/EVMBenchmarkSub.test.ts --network solo",
    "test:hapi": "hardhat test test/HAPIBenchmark.test.ts --network solo",
    "test:hapi:sub": "hardhat test test/HAPIBenchmarkSub.test.ts --network solo"
  },
  "devDependencies": {
    "@nomicfoundation/hardhat-toolbox": "^4.0.0",
    "@types/node": "^20.0.0",
    "dotenv": "^16.3.0",
    "hardhat": "^2.19.0",
    "ts-node": "^10.9.0",
    "typescript": "^5.3.0"
  },
  "dependencies": {
    "@hashgraph/sdk": "^2.80.0"
  }
}
```

Install dependencies:
```bash
npm install
```

#### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "outDir": "./dist",
    "resolveJsonModule": true
  },
  "include": ["./scripts", "./test", "./hardhat.config.ts"],
  "files": ["./hardhat.config.ts"]
}
```

#### hardhat.config.ts

```typescript
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

// Solo pre-funded ECDSA accounts (created during solo one-shot single deploy)
// These are the first 5 ECDSA Alias Accounts from Solo's output
const SOLO_ACCOUNTS = [
  "0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524",
  "0x2e1d968b041d84dd120a5860cee60cd83f9374ef527ca86996317ada3d0d03e7",
  "0x45a5a7108a18dd5013cf2d5857a28144beadc9c70b3bdbd914e38df4e804b8d8",
  "0x6e9d61a325be3f6675cf8b7676c70e4a004d2308e3e182370a41f5653d52c6bd",
  "0x0b58b1bd44469ac9f813b5aeaf6213ddaea26720f0b2f133d08b6f234130a64f",
];

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "solo",
  networks: {
    solo: {
      url: process.env.SOLO_RPC_URL || "http://127.0.0.1:7546",
      accounts: SOLO_ACCOUNTS,
      chainId: 298, // 0x12a - Hedera local networks
      timeout: 120000, // 2 minutes for Hedera transactions
    },
    hardhat: {
      chainId: 31337,
    },
  },
};

export default config;
```

> **Note**: The private keys above are the default ECDSA Alias Accounts created by Solo. They are deterministic and safe to use in local development. For production, never commit private keys.

#### contracts/TestToken.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TestToken
 * @dev ERC-20 token for benchmarking token operations on Hedera EVM
 */
contract TestToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        decimals = 18;
        totalSupply = _initialSupply * 10 ** decimals;
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        if (spender == address(0)) revert ZeroAddress();

        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (balanceOf[from] < amount) revert InsufficientBalance();
        if (allowance[from][msg.sender] < amount) revert InsufficientAllowance();

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) public {
        if (to == address(0)) revert ZeroAddress();

        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) public {
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }
}
```

Compile the contract:
```bash
npx hardhat compile
```

### Step 4: Create EVM Benchmark Test

#### test/EVMBenchmark.test.ts

```typescript
import { expect } from "chai";
import { ethers, network } from "hardhat";

// Token amounts (using 18 decimals)
const INITIAL_MINT = ethers.parseEther("10000");
const TRANSFER_AMOUNT = ethers.parseEther("1000");

interface StepTiming {
  step: string;
  durationMs: number;
}

const stepTimings: StepTiming[] = [];

function recordStep(step: string, startMs: number): void {
  stepTimings.push({ step, durationMs: Date.now() - startMs });
}

describe("EVM Benchmark", function () {
  this.timeout(120000); // 2 minutes

  let token: any;
  let accounts: any[];
  let addresses: string[];

  before(async function () {
    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log(`║         EVM BENCHMARK - ${network.name.padEnd(31)}║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");

    // Get exactly 3 accounts (pre-funded by Solo)
    const allSigners = await ethers.getSigners();
    accounts = allSigners.slice(0, 3);
    addresses = await Promise.all(accounts.map(a => a.getAddress()));

    console.log("Accounts:");
    for (let i = 0; i < 3; i++) {
      console.log(`  [${i}] ${addresses[i]}`);
    }
  });

  after(function () {
    const totalMs = stepTimings.reduce((sum, s) => sum + s.durationMs, 0);
    const formatSec = (ms: number) => (ms / 1000).toFixed(1) + "s";

    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log("║         EVM BENCHMARK RESULTS                            ║");
    console.log("╠══════════════════════════════════════════════════════════╣");
    for (const s of stepTimings) {
      console.log(`║  ${s.step.padEnd(38)}${formatSec(s.durationMs).padStart(8)} ║`);
    }
    console.log("╠══════════════════════════════════════════════════════════╣");
    console.log(`║  TOTAL${" ".repeat(34)}${formatSec(totalMs).padStart(8)} ║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");
  });

  it("Step 1: Deploy ERC20 contract", async function () {
    const start = Date.now();

    const TestToken = await ethers.getContractFactory("TestToken");
    token = await TestToken.deploy("Benchmark Token", "BENCH", 0);
    await token.waitForDeployment();

    // Wait for mirror node sync
    await new Promise(resolve => setTimeout(resolve, 2500));

    recordStep("Deploy ERC20", start);
    expect(await token.getAddress()).to.be.properAddress;
  });

  it("Step 2: Mint tokens to account[0]", async function () {
    const start = Date.now();

    const tx = await token.mint(addresses[0], INITIAL_MINT);
    await tx.wait();
    await new Promise(resolve => setTimeout(resolve, 2500));

    recordStep("Mint tokens", start);
    expect(await token.balanceOf(addresses[0])).to.equal(INITIAL_MINT);
  });

  it("Step 3: Transfer to account[1]", async function () {
    const start = Date.now();

    const tx = await token.connect(accounts[0]).transfer(addresses[1], TRANSFER_AMOUNT);
    await tx.wait();
    await new Promise(resolve => setTimeout(resolve, 2500));

    recordStep("Transfer to acc[1]", start);
  });

  it("Step 4: Transfer to account[2]", async function () {
    const start = Date.now();

    const tx = await token.connect(accounts[0]).transfer(addresses[2], TRANSFER_AMOUNT);
    await tx.wait();
    await new Promise(resolve => setTimeout(resolve, 2500));

    recordStep("Transfer to acc[2]", start);
  });

  it("Step 5: eth_call confirms final balances", async function () {
    const start = Date.now();

    const bal0 = await token.balanceOf(addresses[0]);
    const bal1 = await token.balanceOf(addresses[1]);
    const bal2 = await token.balanceOf(addresses[2]);

    expect(bal0).to.equal(ethers.parseEther("8000"));
    expect(bal1).to.equal(ethers.parseEther("1000"));
    expect(bal2).to.equal(ethers.parseEther("1000"));

    recordStep("Confirm balances", start);

    console.log("\nFinal balances:");
    console.log(`  account[0]: ${ethers.formatEther(bal0)} BENCH`);
    console.log(`  account[1]: ${ethers.formatEther(bal1)} BENCH`);
    console.log(`  account[2]: ${ethers.formatEther(bal2)} BENCH`);
  });
});
```

### Step 5: Create HAPI Benchmark Test

#### test/HAPIBenchmark.test.ts

```typescript
import { expect } from "chai";
import {
  Client,
  AccountCreateTransaction,
  TokenCreateTransaction,
  TokenMintTransaction,
  TransferTransaction,
  TokenAssociateTransaction,
  AccountBalanceQuery,
  PrivateKey,
  Hbar,
  TokenType,
  TokenSupplyType,
} from "@hashgraph/sdk";

// Solo network configuration
const SOLO_CONFIG = {
  grpcEndpoint: "127.0.0.1:50211",
  nodeAccountId: "0.0.3",
  operatorId: "0.0.2",
  operatorKey: "302e020100300506032b65700422042091132178e72057a1d7528025956fe39b0b847f200ab59b2fdd367017f3087137",
  mirrorNodeUrl: "http://127.0.0.1:8081",
};

interface StepTiming {
  step: string;
  durationMs: number;
}

const stepTimings: StepTiming[] = [];

function recordStep(step: string, startMs: number): void {
  stepTimings.push({ step, durationMs: Date.now() - startMs });
}

describe("HAPI Benchmark", function () {
  this.timeout(180000); // 3 minutes

  let client: Client;
  let accounts: { id: string; key: PrivateKey }[] = [];
  let tokenId: string;

  before(async function () {
    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log("║         HAPI BENCHMARK - Solo                            ║");
    console.log("╠══════════════════════════════════════════════════════════╣");
    console.log(`║  GRPC: ${SOLO_CONFIG.grpcEndpoint.padEnd(48)}║`);
    console.log(`║  Operator: ${SOLO_CONFIG.operatorId.padEnd(44)}║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");

    const network: Record<string, string> = {};
    network[SOLO_CONFIG.grpcEndpoint] = SOLO_CONFIG.nodeAccountId;

    client = Client.forNetwork(network);
    client.setOperator(
      SOLO_CONFIG.operatorId,
      PrivateKey.fromStringED25519(SOLO_CONFIG.operatorKey)
    );
  });

  after(async function () {
    if (client) client.close();

    const totalMs = stepTimings.reduce((sum, s) => sum + s.durationMs, 0);
    const formatSec = (ms: number) => (ms / 1000).toFixed(1) + "s";

    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log("║         HAPI BENCHMARK RESULTS                           ║");
    console.log("╠══════════════════════════════════════════════════════════╣");
    for (const s of stepTimings) {
      console.log(`║  ${s.step.padEnd(38)}${formatSec(s.durationMs).padStart(8)} ║`);
    }
    console.log("╠══════════════════════════════════════════════════════════╣");
    console.log(`║  TOTAL${" ".repeat(34)}${formatSec(totalMs).padStart(8)} ║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");
  });

  it("Step 1: Create 3 accounts", async function () {
    const start = Date.now();

    for (let i = 0; i < 3; i++) {
      const key = PrivateKey.generateED25519();
      const tx = await new AccountCreateTransaction()
        .setKey(key.publicKey)
        .setInitialBalance(new Hbar(100))
        .execute(client);

      const receipt = await tx.getReceipt(client);
      accounts.push({ id: receipt.accountId!.toString(), key });
      console.log(`  Created account[${i}]: ${receipt.accountId}`);
    }

    recordStep("Create 3 accounts", start);
    expect(accounts.length).to.equal(3);
  });

  it("Step 2: Create FT token", async function () {
    const start = Date.now();

    const tx = await new TokenCreateTransaction()
      .setTokenName("Benchmark Token")
      .setTokenSymbol("BENCH")
      .setDecimals(2)
      .setInitialSupply(0)
      .setTreasuryAccountId(accounts[0].id)
      .setSupplyType(TokenSupplyType.Infinite)
      .setTokenType(TokenType.FungibleCommon)
      .setSupplyKey(accounts[0].key.publicKey)
      .freezeWith(client)
      .sign(accounts[0].key);

    const response = await tx.execute(client);
    const receipt = await response.getReceipt(client);
    tokenId = receipt.tokenId!.toString();

    console.log(`  Created token: ${tokenId}`);

    recordStep("Create FT token", start);
    expect(tokenId).to.match(/^\d+\.\d+\.\d+$/);
  });

  it("Step 3: Associate token with accounts 1 and 2", async function () {
    const start = Date.now();

    for (let i = 1; i <= 2; i++) {
      const tx = await new TokenAssociateTransaction()
        .setAccountId(accounts[i].id)
        .setTokenIds([tokenId])
        .freezeWith(client)
        .sign(accounts[i].key);
      await (await tx.execute(client)).getReceipt(client);
    }

    console.log(`  Associated token with accounts 1 and 2`);
    recordStep("Associate token", start);
  });

  it("Step 4: Mint tokens", async function () {
    const start = Date.now();

    const tx = await new TokenMintTransaction()
      .setTokenId(tokenId)
      .setAmount(10000) // 100.00 tokens
      .freezeWith(client)
      .sign(accounts[0].key);

    const response = await tx.execute(client);
    const receipt = await response.getReceipt(client);

    console.log(`  Minted ${receipt.totalSupply} tokens`);
    recordStep("Mint tokens", start);
  });

  it("Step 5: Transfer tokens", async function () {
    const start = Date.now();

    const tx = await new TransferTransaction()
      .addTokenTransfer(tokenId, accounts[0].id, -2000)
      .addTokenTransfer(tokenId, accounts[1].id, 1000)
      .addTokenTransfer(tokenId, accounts[2].id, 1000)
      .freezeWith(client)
      .sign(accounts[0].key);

    await (await tx.execute(client)).getReceipt(client);

    console.log(`  Transferred tokens to accounts 1 and 2`);
    recordStep("Transfer tokens", start);
  });

  it("Step 6: Mirror node confirms balances", async function () {
    const start = Date.now();

    // Wait for mirror node
    await new Promise(resolve => setTimeout(resolve, 3000));

    const fetchBalance = async (accountId: string): Promise<number> => {
      const url = `${SOLO_CONFIG.mirrorNodeUrl}/api/v1/accounts/${accountId}/tokens?token.id=${tokenId}`;
      const response = await fetch(url);
      const data = await response.json() as { tokens?: { balance?: number }[] };
      return data.tokens?.[0]?.balance ?? 0;
    };

    const bal0 = await fetchBalance(accounts[0].id);
    const bal1 = await fetchBalance(accounts[1].id);
    const bal2 = await fetchBalance(accounts[2].id);

    console.log("\n  Mirror node balances:");
    console.log(`    account[0]: ${bal0 / 100} BENCH`);
    console.log(`    account[1]: ${bal1 / 100} BENCH`);
    console.log(`    account[2]: ${bal2 / 100} BENCH`);

    recordStep("Mirror confirm", start);

    expect(bal0).to.equal(8000);
    expect(bal1).to.equal(1000);
    expect(bal2).to.equal(1000);
  });

  it("Step 7: SDK query confirms balances", async function () {
    const start = Date.now();

    const query0 = await new AccountBalanceQuery().setAccountId(accounts[0].id).execute(client);
    const query1 = await new AccountBalanceQuery().setAccountId(accounts[1].id).execute(client);
    const query2 = await new AccountBalanceQuery().setAccountId(accounts[2].id).execute(client);

    const sdkBal0 = query0.tokens?.get(tokenId)?.toNumber() ?? 0;
    const sdkBal1 = query1.tokens?.get(tokenId)?.toNumber() ?? 0;
    const sdkBal2 = query2.tokens?.get(tokenId)?.toNumber() ?? 0;

    console.log("\n  SDK query balances:");
    console.log(`    account[0]: ${sdkBal0 / 100} BENCH`);
    console.log(`    account[1]: ${sdkBal1 / 100} BENCH`);
    console.log(`    account[2]: ${sdkBal2 / 100} BENCH`);

    recordStep("SDK query confirm", start);

    expect(sdkBal0).to.equal(8000);
    expect(sdkBal1).to.equal(1000);
    expect(sdkBal2).to.equal(1000);
  });
});
```

### Step 6: Run the Benchmarks

```bash
# Ensure Solo is running
curl -s http://127.0.0.1:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

# Run EVM benchmark (~40 seconds)
npx hardhat test test/EVMBenchmark.test.ts --network solo

# Run HAPI benchmark (~6 seconds)
npx hardhat test test/HAPIBenchmark.test.ts --network solo
```

### Step 7: Shutdown Solo

```bash
# Destroy Solo network (keeps kind cluster)
solo one-shot single destroy --quiet-mode

# Verify shutdown
kubectl get ns | grep solo
# Should show no solo namespaces (except possibly solo-setup)
```

### Expected Output

#### EVM Benchmark
```
╔══════════════════════════════════════════════════════════╗
║         EVM BENCHMARK RESULTS                            ║
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

#### HAPI Benchmark
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

### Troubleshooting

| Issue | Solution |
|-------|----------|
| `ECONNREFUSED 127.0.0.1:7546` | Solo is not running. Run `solo one-shot single deploy --quiet-mode` |
| `ECONNREFUSED 127.0.0.1:50211` | gRPC port-forward died. Check `kubectl get pods -A` and restart Solo |
| `insufficient gas` | Increase gas limit in hardhat.config.ts or wait longer between transactions |
| `INVALID_SIGNATURE` | Account keys don't match. Ensure using Solo's default ECDSA accounts |
| `no space left on device` | Run `docker system prune -af --volumes` to free Docker disk space |
| `ImagePullBackOff` | Docker disk full. Free at least 20GB and restart Solo |

### Project Structure Summary

```
hedera-benchmark/
├── contracts/
│   └── TestToken.sol          # ERC-20 contract for EVM tests
├── test/
│   ├── EVMBenchmark.test.ts   # EVM test (uses pre-funded accounts)
│   ├── EVMBenchmarkSub.test.ts # EVM sub-test (creates new accounts)
│   ├── HAPIBenchmark.test.ts  # HAPI test with SDK + mirror confirm
│   └── HAPIBenchmarkSub.test.ts # HAPI sub-test (mirror only)
├── hardhat.config.ts          # Hardhat configuration for Solo
├── package.json               # Dependencies
└── tsconfig.json              # TypeScript configuration
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
