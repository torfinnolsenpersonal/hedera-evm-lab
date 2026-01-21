# Troubleshooting Guide

Common issues and solutions for the Hedera EVM Lab.

## Critical: Shared Proxy Port Conflict

**Both Local Node and Solo use port 7546 for the JSON-RPC relay by default.**

### Symptoms
- Connection refused errors
- Wrong chain ID returned
- Transactions going to wrong network
- Unpredictable test failures

### Diagnosis
```bash
# Check what's using port 7546
lsof -i :7546

# Or on Windows
netstat -ano | findstr :7546
```

### Solution
**Never run Local Node and Solo simultaneously.**

```bash
# Stop Local Node
./scripts/stop-local-node.sh

# Stop Solo
./scripts/stop-solo.sh

# Verify port is free
lsof -i :7546  # Should return nothing
```

---

## Docker Issues

### Docker Not Running

**Symptoms:**
```
Cannot connect to the Docker daemon
```

**Diagnosis:**
```bash
docker info
```

**Fix:**
```bash
# macOS
open -a Docker

# Linux
sudo systemctl start docker

# Windows
# Start Docker Desktop from Start menu
```

### Insufficient Docker Resources

**Symptoms:**
- Containers crash on startup
- OOM (Out of Memory) errors
- Pods stuck in `Pending` or `CrashLoopBackOff`

**Diagnosis:**
```bash
docker info | grep -E "Total Memory|CPUs"
docker stats --no-stream
```

**Fix:**
1. Open Docker Desktop > Settings > Resources
2. Set Memory >= 12 GB (for Solo) or >= 8 GB (for Local Node)
3. Set CPUs >= 6
4. Restart Docker

### Port Already in Use

**Symptoms:**
```
Error: Port 7546 is already in use
Error: bind: address already in use
```

**Diagnosis:**
```bash
# Find process using port
lsof -i :7546
lsof -i :5551
lsof -i :5600

# Or
netstat -tulpn | grep -E "7546|5551|5600"
```

**Fix:**
```bash
# Kill specific process
kill -9 <PID>

# Or kill all hedera-related containers
docker rm -f $(docker ps -aq --filter name=hedera)
docker rm -f $(docker ps -aq --filter name=network-node)
docker rm -f $(docker ps -aq --filter name=mirror)
```

### Leftover Docker Volumes

**Symptoms:**
- Network starts but has stale data
- Accounts missing or wrong balances

**Diagnosis:**
```bash
docker volume ls | grep hedera
```

**Fix:**
```bash
# Full cleanup
docker compose down -v
docker volume prune -f
```

---

## Local Node Issues

### hedera Command Not Found

**Symptoms:**
```
hedera: command not found
```

**Fix:**
```bash
npm install -g @hashgraph/hedera-local

# Verify
which hedera
hedera --version
```

### Network Won't Start

**Symptoms:**
- `hedera start` hangs
- Containers keep restarting

**Diagnosis:**
```bash
docker ps -a | grep hedera
docker logs network-node
```

**Fix:**
```bash
# Full cleanup and restart
hedera stop
docker compose down -v 2>/dev/null || true
docker rm -f $(docker ps -aq --filter name=hedera) 2>/dev/null || true
hedera start
```

### Mirror Node Not Syncing

**Symptoms:**
- REST API returns empty results
- Transactions not appearing in explorer

**Diagnosis:**
```bash
curl http://127.0.0.1:5551/api/v1/transactions?limit=1
docker logs mirror-node-importer
```

**Fix:**
Wait longer (mirror node sync can take time) or restart:
```bash
hedera restart
```

### Windows Line Ending Issues

**Symptoms (Windows/WSL):**
```
/bin/bash: bad interpreter
```

**Fix:**
```bash
dos2unix compose-network/mirror-node/init.sh
# Or
git config --global core.autocrlf input
# Then re-clone the repo
```

---

## Solo Issues

### solo Command Not Found

**Symptoms:**
```
solo: command not found
```

**Fix (Homebrew - Recommended):**
```bash
brew tap hiero-ledger/tools
brew install solo

# Verify
which solo
solo --version
```

**Alternative Fix (npm):**
```bash
npm install -g @hashgraph/solo

# Verify
which solo
solo --version
```

### kind Cluster Won't Start

**Symptoms:**
```
ERROR: failed to create cluster
```

**Diagnosis:**
```bash
kind get clusters
docker ps | grep kind
```

**Fix:**
```bash
# Delete stuck cluster
kind delete cluster -n solo

# Clean up Docker
docker rm -f $(docker ps -aq --filter name=kind)

# Retry
kind create cluster -n solo
```

### kubectl Not Configured

**Symptoms:**
```
The connection to the server localhost:8080 was refused
```

**Fix:**
```bash
# After kind cluster creation
kubectl config get-contexts
kubectl config use-context kind-solo

# Or
kind export kubeconfig -n solo
```

### Pods Not Starting

**Symptoms:**
```
kubectl get pods -n solo
# Shows Pending, CrashLoopBackOff, or Error
```

**Diagnosis:**
```bash
kubectl describe pod -n solo <pod-name>
kubectl logs -n solo <pod-name>
```

**Common fixes:**
1. Increase Docker resources (Memory >= 12 GB)
2. Delete and recreate cluster
3. Check disk space

### Solo Artifacts Causing Issues

**Symptoms:**
- Solo commands behave unexpectedly
- "Already exists" errors

**Fix:**
```bash
# Nuclear option - full Solo cleanup
rm -rf ~/.solo
kind delete cluster -n solo
solo one-shot single deploy
```

### Port Forwarding Not Working

**Symptoms:**
- Cannot access services on localhost
- Connection refused to specific ports

**Diagnosis:**
```bash
kubectl get svc -n solo
kubectl port-forward -n solo svc/haproxy-node1-svc 50211:50211 &
```

**Fix:**
```bash
# Kill existing port forwards
pkill -f "kubectl port-forward"

# Restart port forwards
kubectl port-forward -n solo svc/relay-node1-hedera-json-rpc-relay 7546:7546 &
```

---

## Hardhat Issues

### Connection Refused

**Symptoms:**
```
Error: connect ECONNREFUSED 127.0.0.1:7546
```

**Diagnosis:**
```bash
curl http://127.0.0.1:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

**Fix:**
Start the network first:
```bash
./scripts/start-local-node.sh
# or
./scripts/start-solo.sh
```

### Transaction Timeout

**Symptoms:**
```
Error: Timeout exceeded during request
```

**Fix:**
Increase timeout in `hardhat.config.ts`:
```typescript
networks: {
  localnode: {
    timeout: 120000, // 2 minutes
  },
},
```

### Wrong Chain ID

**Symptoms:**
```
Error: chainId mismatch
```

**Fix:**
Ensure chainId is 298:
```typescript
networks: {
  localnode: {
    chainId: 298,
  },
},
```

---

## Foundry Issues

### forge Not Found

**Symptoms:**
```
forge: command not found
```

**Fix:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Tests Pass Locally but Fail on Fork

**Symptoms:**
- `forge test` passes
- `forge test --fork-url http://127.0.0.1:7546` fails

**Diagnosis:**
Check for Hedera-specific EVM differences (gas, opcodes).

**Fix:**
Some EVM features may behave differently on Hedera. Test against Hedera network early.

---

## Network Verification Commands

### Verify JSON-RPC Relay

```bash
# Check chain ID
curl -s http://127.0.0.1:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Expected: {"jsonrpc":"2.0","id":1,"result":"0x12a"}

# Check block number
curl -s http://127.0.0.1:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Verify Mirror Node

```bash
# REST API
curl -s http://127.0.0.1:5551/api/v1/transactions?limit=1 | jq .

# gRPC (requires grpcurl)
grpcurl -plaintext 127.0.0.1:5600 list
```

### Verify Consensus Node

```bash
# For Local Node
docker logs network-node 2>&1 | tail -20

# For Solo
kubectl logs -n solo network-node1-0 --tail=20
```

---

## Quick Recovery Commands

### Local Node Full Reset

```bash
./scripts/stop-local-node.sh
docker rm -f $(docker ps -aq --filter name=hedera) 2>/dev/null
docker volume prune -f
./scripts/start-local-node.sh
```

### Solo Full Reset

```bash
./scripts/stop-solo.sh
rm -rf ~/.solo
kind delete clusters --all
./scripts/start-solo.sh
```

### Kill All Port Forwards

```bash
pkill -f "kubectl port-forward"
```

### Check All Hedera-Related Processes

```bash
# Docker containers
docker ps -a | grep -E "hedera|network-node|mirror|solo|kind"

# Ports in use
lsof -i :7546 -i :5551 -i :5600 -i :8080 -i :8090

# Kind clusters
kind get clusters

# Kubernetes pods (if Solo)
kubectl get pods -A | grep solo
```
