# Solo vs Hiero Local Node: Gap Analysis for EVM Smart Contract Execution

This document provides a gap analysis focused on **EVM smart contract execution** between Solo and Hiero Local Node for developers building Hedera-compatible smart contracts.

## Executive Summary

| Aspect | Local Node | Solo | Recommendation |
|--------|------------|------|----------------|
| **Setup Complexity** | Simple (Docker Compose) | Moderate (Kubernetes) | Either works well |
| **Resource Usage** | Lower (8GB RAM min) | Higher (12GB RAM min) | Local Node for constrained systems |
| **EVM Feature Parity** | Full | Full | Both fully support EVM |
| **CI/CD Suitability** | Good | Good | Both work well in CI/CD |
| **Production Similarity** | Good | Excellent | Solo for production-like testing |

## EVM Smart Contract Execution: Gap Analysis

Both Solo and Local Node provide **identical EVM execution environments** through the Hedera JSON-RPC Relay. There are no functional gaps for standard EVM smart contract development.

### EVM Feature Parity

| EVM Feature | Local Node | Solo | Notes |
|-------------|------------|------|-------|
| **Contract Deployment** | Full support | Full support | CREATE, CREATE2 |
| **State Management** | Full support | Full support | SLOAD, SSTORE |
| **Events/Logs** | Full support | Full support | LOG0-LOG4 |
| **Value Transfers** | Full support | Full support | CALL with value |
| **Precompiles (0x01-0x09)** | Full support | Full support | ecrecover, sha256, etc. |
| **Hedera Precompiles** | Full support | Full support | HTS, PRNG, Exchange Rate |
| **ERC-20/721/1155** | Full support | Full support | Standard token contracts |
| **Gas Estimation** | Full support | Full support | eth_estimateGas |
| **Transaction Receipts** | Full support | Full support | eth_getTransactionReceipt |

### Hedera-Specific EVM Features

| Feature | Local Node | Solo | Notes |
|---------|------------|------|-------|
| **HTS Precompile (0x167)** | Yes | Yes | Token operations |
| **Exchange Rate (0x168)** | Yes | Yes | HBAR/USD conversion |
| **PRNG (0x169)** | Yes | Yes | Pseudorandom generation |
| **Chain ID 298** | Yes | Yes | Hedera local networks |
| **3-5 second finality** | Yes | Yes | Faster than Ethereum |

### When to Use Each for EVM Development

| Scenario | Recommendation |
|----------|----------------|
| Rapid contract iteration | Either |
| Hardhat/Foundry tests | Either |
| ERC-20/721 development | Either |
| Hedera precompile testing | Either |
| Production CI pipeline | Solo (more widely utilized) |
| Multi-signer scenarios | Solo |

## Feature Matrix

| Capability | Local Node | Solo | Notes | Evidence |
|------------|------------|------|-------|----------|
| **Consensus Node** | Single node | Single or multi-node | Solo supports `--num-consensus-nodes` | `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md:386` |
| **Mirror Node** | Yes | Yes | Both include full mirror node | `repos/hiero-local-node/README.md:569-581` |
| **JSON-RPC Relay** | Yes (port 7546) | Yes (port 7546) | Same port, same relay software | `repos/hiero-local-node/.env:64` |
| **Block Explorer** | Yes (port 8090) | Yes (port 8080) | Different ports | `repos/hiero-local-node/README.md:578` |
| **WebSocket Support** | Yes (port 8546) | Yes | Via JSON-RPC relay | `repos/hiero-local-node/README.md:577` |
| **Block Node** | Optional | Optional | Experimental in both | `repos/hiero-local-node/package.json:9` |
| **Grafana/Prometheus** | Yes | Yes | Both include monitoring | `repos/hiero-local-node/README.md:583-596` |
| **Multi-Node Consensus** | Yes (`--multinode`) | Yes | Solo has more flexibility | `repos/hiero-local-node/package.json:10` |
| **Account Generation** | Automatic (30 accounts) | Manual (`solo ledger account create`) | Local Node auto-creates test accounts | `repos/hiero-local-node/README.md:174-221` |
| **Pre-funded Accounts** | Yes (10,000 HBAR each) | Yes (via operator) | Local Node more convenient | `repos/hiero-local-node/README.md:179-189` |

## Network Endpoints Comparison

### Local Node Default Endpoints
```
Consensus Node:           127.0.0.1:50211
Mirror Node gRPC:         127.0.0.1:5600
Mirror Node REST API:     127.0.0.1:5551
JSON-RPC Relay:           127.0.0.1:7546
JSON-RPC WebSocket:       127.0.0.1:8546
Block Explorer:           127.0.0.1:8090
Grafana:                  127.0.0.1:3000
Prometheus:               127.0.0.1:9090
```
Evidence: `repos/hiero-local-node/README.md:569-581`

### Solo Default Endpoints
```
Consensus Node:           localhost:50211
Mirror Node gRPC:         localhost:5600
Mirror Node REST API:     localhost:8081 (via ingress) or localhost:5551 (port-forward)
JSON-RPC Relay:           localhost:7546
Explorer:                 localhost:8080
```
Evidence: `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md:599-627`

### Chain ID
Both use **Chain ID 298 (0x12a)** by default.

## Testing Workflow Fit

### Unit Tests (Contract Logic)

| Aspect | Local Node | Solo |
|--------|------------|------|
| Startup Time | ~2-3 minutes | ~5-10 minutes |
| Teardown Time | ~30 seconds | ~1-2 minutes |
| Best For | Rapid iteration | Production-like behavior |
| Recommendation | **Local Node** | If multi-node needed |

### Integration Tests (Contract + Backend)

| Aspect | Local Node | Solo |
|--------|------------|------|
| Stability | Good | Excellent |
| Reset Semantics | Clean (no state persistence) | Clean |
| Account Setup | Automatic | Manual or scripted |
| Recommendation | **Local Node** for simplicity | Solo for complex scenarios |

### End-to-End Tests (Full Stack)

| Aspect | Local Node | Solo |
|--------|------------|------|
| Mirror Node Accuracy | Good | Excellent |
| Block Explorer | Basic | Full featured |
| Multi-node Testing | Limited | Full support |
| Recommendation | Local Node for speed | **Solo** for completeness |

### Performance/Load Tests

| Aspect | Local Node | Solo |
|--------|------------|------|
| Scalability | Limited | Better (k8s resources) |
| Resource Isolation | Docker | Kubernetes pods |
| Monitoring | Basic | Full Prometheus stack |
| Recommendation | Simple load tests | **Solo** for serious perf testing |

## Operational Comparison

### Installation Path

**Local Node:**
```bash
npm install -g @hashgraph/hedera-local
hedera start
# Ready in ~2-3 minutes
```

**Solo (Homebrew - Recommended):**
```bash
brew tap hiero-ledger/tools
brew install solo
kind create cluster -n solo
solo one-shot single deploy
# Ready in ~5-10 minutes
```

### Startup Commands

**Local Node:**
```bash
hedera start                        # Basic start
hedera start --limits=false         # Disable rate limits
hedera start --multinode            # Multi-node mode
hedera start --dev                  # Developer mode
hedera start --enable-block-node    # With block node
```
Evidence: `repos/hiero-local-node/README.md:113-148`

**Solo:**
```bash
solo one-shot single deploy         # Single node
solo one-shot multi deploy          # Multi-node
solo one-shot falcon deploy         # Custom config
```
Evidence: `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md:242-334`

### Teardown Commands

**Local Node:**
```bash
hedera stop
# Or for complete cleanup:
docker compose down -v; git clean -xfd; git reset --hard
```
Evidence: `repos/hiero-local-node/README.md:280-288`

**Solo:**
```bash
solo one-shot single destroy
kind delete cluster -n solo
rm -rf ~/.solo  # Optional: full cleanup
```
Evidence: `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md:256-258`

### Failure Modes and Recovery

**Local Node:**
- Docker container crashes: `hedera restart`
- Port conflicts: Check `lsof -i :7546` and kill conflicting processes
- Corrupted state: `hedera stop && hedera start`
- Full reset: `docker compose down -v`

**Solo:**
- Pod crashes: `kubectl get pods -n solo` → delete stuck pod
- Cluster issues: `kind delete cluster -n solo && kind create cluster`
- Full reset: `rm -rf ~/.solo && kind delete cluster`
- Network not ready: Check `kubectl logs -n solo <pod-name>`

### Resource Usage (Qualitative)

| Resource | Local Node | Solo | Notes |
|----------|------------|------|-------|
| Memory at Idle | ~4-6 GB | ~8-10 GB | Solo has more components |
| Memory Under Load | ~6-8 GB | ~10-14 GB | Depends on TPS |
| CPU at Idle | Low | Low | Similar |
| CPU Under Load | Moderate | Moderate-High | Solo has k8s overhead |
| Disk Usage | ~5-10 GB | ~10-15 GB | Solo stores in ~/.solo |

### Logs and Observability

**Local Node:**
```bash
# Logs in ./network-logs/
ls -la network-logs/node/

# Docker logs
docker logs <container-name>

# Grafana dashboards at http://localhost:3000
```
Evidence: `repos/hiero-local-node/README.md:537-540`

**Solo:**
```bash
# Pod logs
kubectl logs -n solo <pod-name>

# Diagnostic dump
solo consensus diagnostics all --deployment solo-deployment

# Logs in ~/.solo/logs/
ls ~/.solo/logs/
```
Evidence: `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md:656-668`

## CI/CD Suitability

Both Solo and Local Node work well in CI/CD pipelines. Solo is more widely utilized in production CI environments due to its closer alignment with mainnet behavior.

### GitHub Actions / CI Pipeline

**Local Node:**
```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm install -g @hashgraph/hedera-local
      - run: hedera start --limits=false &
      - run: sleep 180  # Wait for startup
      - run: npm test
      - run: hedera stop
```

**Solo:**
```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
      - uses: helm/kind-action@v1
      - run: |
          brew tap hiero-ledger/tools
          brew install solo
      - run: solo one-shot single deploy
      - run: sleep 300  # Wait for startup
      - run: npm test
      - run: solo one-shot single destroy
```

**Note:** Solo is the more widely utilized option in production CI pipelines due to its production-like environment and multi-node testing capabilities.

## Known Pain Points and Mitigations

### Local Node Pain Points

1. **State not preserved across restarts**
   - Mitigation: Script account/contract setup in test fixtures
   - Evidence: `repos/hiero-local-node/README.md:616-618`

2. **Port 7546 conflicts with other services**
   - Mitigation: Use `--host` flag or modify `.env`
   - Evidence: `repos/hiero-local-node/README.md:127`

3. **Windows line ending issues**
   - Mitigation: Run `dos2unix compose-network/mirror-node/init.sh`
   - Evidence: `repos/hiero-local-node/README.md:495-499`

4. **hedera- prefix networks may conflict**
   - Mitigation: Manual cleanup with `docker network ls --filter name=hedera`
   - Evidence: `repos/hiero-local-node/README.md:111`

### Solo Pain Points

1. **Requires Kubernetes knowledge**
   - Mitigation: Use one-shot commands, avoid manual kubectl
   - Evidence: `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md:242-280`

2. **~/.solo artifacts from old installs cause issues**
   - Mitigation: Clean before fresh install: `rm -rf ~/.solo`
   - Evidence: `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md:156-176`

3. **High memory requirements**
   - Mitigation: Use single node, increase Docker resources
   - Evidence: `repos/solo/README.md:38-39`

4. **Pod startup timeouts**
   - Mitigation: Retry, check resource limits, increase timeout env vars
   - Evidence: `repos/solo/docs/site/content/en/docs/env.md:36-51`

5. **Port forwarding complexity**
   - Mitigation: Use `--enable-ingress` flag for mirror node
   - Evidence: `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md:534`

## Decision Tree

```
Need a local Hedera network?
│
├── Just need quick EVM contract testing?
│   └── Either works - choose based on your environment
│
├── Need multi-node consensus testing?
│   └── Use SOLO
│
├── Running in CI/CD?
│   └── Use SOLO (more widely utilized in production CI)
│
├── Testing production-like behavior?
│   └── Use SOLO
│
├── Limited resources (<12GB RAM)?
│   └── Use LOCAL NODE
│
└── EVM smart contract development
    └── Either works - both have full EVM support
```

## Recommendations Summary

1. **Both options support full EVM smart contract execution** - choose based on your workflow
2. **Solo is recommended for:**
   - CI/CD pipelines (more widely utilized)
   - Production-like testing
   - Multi-node consensus testing
   - Kubernetes-native deployments

3. **Local Node is recommended for:**
   - Quick development iteration
   - Resource-constrained systems (<12GB RAM)
   - Simple Docker-based workflows

4. **EVM feature parity:** Both provide identical EVM smart contract execution capabilities

## Evidence Files Referenced

| File | Purpose |
|------|---------|
| `repos/hiero-local-node/README.md` | Local Node documentation |
| `repos/hiero-local-node/.env` | Default environment configuration |
| `repos/hiero-local-node/package.json` | CLI commands and dependencies |
| `repos/solo/README.md` | Solo overview and requirements |
| `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md` | Complete Solo setup guide |
| `repos/solo/docs/site/content/en/docs/env.md` | Solo environment variables |
| `repos/solo/package.json` | Solo version and dependencies |
