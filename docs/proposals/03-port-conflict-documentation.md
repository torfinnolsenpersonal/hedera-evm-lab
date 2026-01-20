# Proposal: Port Conflict Documentation and Cleanup Scripts

**Date:** 2026-01-20
**Status:** Implemented in hedera-evm-lab (LOCAL ONLY)

## Problem Statement

Both Hiero Local Node and Solo use the same default port (7546) for JSON-RPC relay. Users frequently encounter port conflicts when:

1. Switching between Local Node and Solo
2. Previous network didn't shut down cleanly
3. Other applications use common ports (3000, 5551, 8080, etc.)

## Solution Implemented

### 1. Cleanup Script (`scripts/cleanup.sh`)

A comprehensive cleanup script that:
- Kills kubectl port-forward processes
- Stops and removes Local Node containers
- Terminates Solo-related processes
- Verifies all ports are free
- Supports `--verify-only` mode for diagnostics

### 2. RPC_PORT Environment Variable

All scripts now support `RPC_PORT` override:
```bash
RPC_PORT=8545 ./scripts/start-local-node.sh
```

### 3. Preflight/Post-Stop Integration

Start scripts run cleanup verification before starting:
```bash
# start-local-node.sh now includes:
"${SCRIPT_DIR}/cleanup.sh" --verify-only
```

Stop scripts verify clean state after stopping:
```bash
# stop-local-node.sh now includes:
"${SCRIPT_DIR}/cleanup.sh" --verify-only
```

## Ports Managed

| Port | Service | Notes |
|------|---------|-------|
| 7546 | JSON-RPC Relay | Primary EVM endpoint |
| 8546 | WebSocket | WS subscriptions |
| 5551 | Mirror Node REST | Account/transaction queries |
| 5600 | Mirror Node gRPC | Streaming data |
| 8080 | Explorer | HashScan-like UI |
| 8090 | Explorer (alt) | Alternative explorer port |
| 50211 | Consensus Node | HAPI endpoint |
| 3000 | Grafana | Metrics dashboard |
| 9090 | Prometheus | Metrics collection |

## Usage Examples

### Check Port Status
```bash
./scripts/cleanup.sh --verify-only
```

### Force Cleanup
```bash
./scripts/cleanup.sh
```

### Start with Custom Port
```bash
RPC_PORT=8545 ./scripts/start-local-node.sh
```

## Documentation Updates Needed

### For Solo Documentation

Add to troubleshooting section:
```markdown
### Port Conflicts

If you see "address already in use" errors:

1. **Check what's using the port:**
   ```bash
   lsof -i :7546
   ```

2. **Kill the process:**
   ```bash
   kill -9 <PID>
   ```

3. **Or use a different port:**
   ```bash
   # Set before running solo commands
   export RPC_PORT=8545
   ```

### Clean Shutdown

Always use the proper stop command:
```bash
solo one-shot single destroy
```

If that fails, manually clean up:
```bash
kind delete clusters --all
rm -rf ~/.solo
```
```

### For Local Node Documentation

Add to README:
```markdown
### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| RPC_PORT | 7546 | JSON-RPC relay port |

### Cleanup

If you encounter port conflicts:
```bash
# View what's running
docker ps --filter name=hedera

# Force stop all containers
docker rm -f $(docker ps -aq --filter name=hedera)

# Remove networks
docker network prune -f
```
```

## Files Created/Modified

### New Files
- `scripts/cleanup.sh` - Main cleanup script
- `scripts/cleanup.ps1` - PowerShell version
- `scripts/run-transaction-tests.sh` - Test harness

### Modified Files
- `scripts/start-local-node.sh` - Added preflight cleanup, RPC_PORT support
- `scripts/stop-local-node.sh` - Added post-stop verification
- `scripts/start-solo.sh` - Added preflight cleanup, RPC_PORT support
- `scripts/stop-solo.sh` - Added post-stop verification
- `scripts/doctor.sh` - Added port availability checks

## Recommendation for Upstream

Consider adding to both Solo and Local Node:

1. **Standard cleanup command:**
   ```bash
   hedera cleanup  # for Local Node
   solo cleanup    # for Solo
   ```

2. **Port conflict detection in start commands:**
   - Check if port is in use before starting
   - Offer to kill conflicting process or use different port

3. **Environment variable standardization:**
   - Both tools should respect `RPC_PORT`, `WS_PORT`, etc.
   - Document standard environment variables
