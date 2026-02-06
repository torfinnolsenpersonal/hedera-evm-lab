# Benchmark Error Tracking and Proposed Fixes

**Created**: 2026-02-06
**Last Run**: 2026-02-06_11-06-55

---

## Summary

This document tracks errors encountered during Solo lifecycle benchmarks and proposes fixes for each issue.

---

## Error Categories

| Category | Count | Severity | Status |
|----------|-------|----------|--------|
| Docker Stops Mid-Run | 3 runs | **BLOCKER** | Open |
| Mirror Node 503 | 2 runs | High | Open |
| GRPC Port Not Exposed | All HAPI runs | High | Open |
| RPC Connection Refused | When Docker stops | Derived | Derived from Docker issue |

---

## Error 1: Docker Desktop Stops Mid-Run

### Symptoms
```
Error: Docker is not running
```
```
Caused by: Error: connect ECONNREFUSED 127.0.0.1:7546
```

### When It Occurs
- During `solo one-shot single deploy` phase
- After ~60s of the cold start
- Intermittently and unpredictably

### Impact
- **Cold start fails**: Solo cannot deploy the Hedera network
- **All subsequent tests fail**: No network to connect to
- **Timing data is invalid**: Startup time includes failure, not success

### Root Cause Analysis
Docker Desktop on macOS has automatic resource management that can pause/stop the Docker engine when:
1. System goes to sleep (even briefly)
2. Resource limits are exceeded
3. Background activity timeout triggers

### Proposed Fixes

**Fix 1: Disable Docker Desktop Resource Saver** (Recommended)
```
Docker Desktop → Settings → Resources → Resource Saver → OFF
```

**Fix 2: Keep Mac Awake During Benchmark**
```bash
caffeinate -dims ./scripts/run-deploy-benchmark.sh --full-lifecycle solo
```

**Fix 3: Add Docker Health Check to Benchmark Script**
```bash
# Add to run-deploy-benchmark.sh before any Docker operation
ensure_docker_running() {
    if ! docker info >/dev/null 2>&1; then
        echo "Docker not running, attempting to start..."
        open -a Docker
        sleep 30
        if ! docker info >/dev/null 2>&1; then
            echo "ERROR: Docker failed to start"
            return 1
        fi
    fi
}
```

**Fix 4: Use Docker Keep-Alive Container**
```bash
# Run a lightweight container that keeps Docker active
docker run -d --name docker-keepalive --restart=always alpine sleep infinity
```

---

## Error 2: Mirror Node 503 Service Unavailable

### Symptoms
```
ProviderError: [Request ID: xxx] Mirror node upstream failure: statusCode=503, message=Service unavailable
```

### When It Occurs
- Immediately after Solo reports "network ready"
- During contract deployment (first RPC call)
- More common on cold starts than warm starts

### Impact
- **Contract deployment fails**: Cannot deploy Counter or ERC20
- **All contract operations fail**: Dependent on successful deploy
- **EVM benchmark fails completely**

### Root Cause Analysis
The Solo start script considers the network "ready" when:
1. RPC relay responds to `eth_chainId`
2. Port 7546 is accessible

But the mirror node (which the RPC relay queries for state) may not be fully synced yet. The relay is up, but the mirror node returns 503.

### Proposed Fixes

**Fix 1: Increase Stabilization Wait** (Quick fix)
```bash
# In scripts/run-deploy-benchmark.sh, change:
sleep 60  # Current
# To:
sleep 120  # More time for mirror node
```

**Fix 2: Add Mirror Node Health Check** (Better fix)
```bash
# Add to scripts/start-solo.sh
wait_for_mirror_node() {
    local max_attempts=60
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "http://127.0.0.1:8081/api/v1/network/nodes" | grep -q "nodes"; then
            echo "Mirror node is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        echo "Waiting for mirror node... ($attempt/$max_attempts)"
        sleep 5
    done
    echo "Mirror node did not become ready"
    return 1
}
```

**Fix 3: Retry Logic in Test** (Application-level)
```typescript
// In test setup, retry on 503
async function deployWithRetry(factory: ContractFactory, maxRetries = 5) {
    for (let i = 0; i < maxRetries; i++) {
        try {
            const contract = await factory.deploy();
            await contract.waitForDeployment();
            return contract;
        } catch (e) {
            if (e.message.includes('503') && i < maxRetries - 1) {
                console.log(`Deploy failed with 503, retrying in 10s... (${i + 1}/${maxRetries})`);
                await new Promise(r => setTimeout(r, 10000));
            } else {
                throw e;
            }
        }
    }
}
```

---

## Error 3: GRPC Port 50211 Not Exposed

### Symptoms
```
Error: timeout exceeded
  at AccountCreateTransaction.execute
```

### When It Occurs
- All HAPI benchmark tests
- First SDK transaction attempt
- After 2 minutes (SDK default timeout)

### Impact
- **HAPI benchmark fails completely**: Cannot execute any SDK transaction
- **Cannot test token operations**: FT create/mint/transfer all fail
- **Cannot verify SDK-based cold start**: Criteria requires SDK transaction

### Root Cause Analysis
Solo runs inside a kind (Kubernetes in Docker) cluster. The RPC relay port (7546) is exposed via `kubectl port-forward`, but the consensus node's GRPC port (50211) is not.

The HAPI test tries to connect to `127.0.0.1:50211`, but that port is not forwarded from the kind cluster.

### Proposed Fixes

**Fix 1: Add GRPC Port-Forward to start-solo.sh**
```bash
# Add after existing port-forward setup
echo "Setting up GRPC port-forward..."
kubectl port-forward svc/network-node1-svc 50211:50211 -n solo-${NAMESPACE} &
GRPC_PF_PID=$!
echo "GRPC port-forward PID: $GRPC_PF_PID"
```

**Fix 2: Use Solo's Built-in Port-Forward** (If available)
```bash
# Check if Solo exposes GRPC
solo network info --show-ports
```

**Fix 3: Modify HAPI Test to Use In-Cluster Address**
```typescript
// If running inside the cluster, use service DNS
const SOLO_CONFIG = {
    grpcEndpoint: process.env.SOLO_GRPC_ENDPOINT || "network-node1-svc.solo:50211",
    // ...
};
```

**Fix 4: Use JSON-RPC for Account Creation Instead**
The EVM test already works via JSON-RPC. Could potentially use ethers.js to create accounts instead of SDK, though this wouldn't test HAPI specifically.

---

## Error 4: RPC Connection Refused

### Symptoms
```
HardhatError: HH108: Cannot connect to the network solo.
Caused by: Error: connect ECONNREFUSED 127.0.0.1:7546
```

### When It Occurs
- When Docker stops mid-run
- When port-forward dies
- When Solo fails to start

### Impact
- **All EVM tests fail**: No RPC endpoint
- **Derived from Error 1**: Usually caused by Docker stopping

### Root Cause Analysis
This is a symptom of Docker stopping or the port-forward failing. Not a primary error.

### Proposed Fixes
See Error 1 fixes for Docker issues.

---

## Recommended Fix Priority

| Priority | Fix | Effort | Impact |
|----------|-----|--------|--------|
| 1 | Disable Docker Resource Saver | 1 min | Fixes Docker stops |
| 2 | Add mirror node health check | 30 min | Fixes 503 errors |
| 3 | Add GRPC port-forward | 15 min | Enables HAPI tests |
| 4 | Use caffeinate for benchmarks | 1 min | Backup for Docker |

---

## Successful Run Reference

From the Feb 4th successful run (2026-02-04_08-52-42):

| Metric | Cold Start | Warm Start |
|--------|------------|------------|
| Network startup | 884.6s | 30.6s |
| Deploy contract | 14.9s | 8.8s |
| Contract ops total | 38.1s | 26.8s |
| All tests | **6/6 PASS** | **6/6 PASS** |

This proves the tests work when Docker stays running and the mirror node is ready.

---

## Next Steps

1. [ ] Configure Docker Desktop to not stop automatically
2. [ ] Run benchmark with `caffeinate -dims`
3. [ ] Add mirror node health check to start-solo.sh
4. [ ] Add GRPC port-forward for HAPI tests
5. [ ] Re-run benchmark and verify all tests pass
