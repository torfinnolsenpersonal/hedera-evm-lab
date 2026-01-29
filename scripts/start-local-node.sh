#!/usr/bin/env bash
# Start Hiero Local Node
# Based on: repos/hiero-local-node/README.md
# Usage: ./start-local-node.sh
# Environment: RPC_PORT (default: 7546)
#              TIMING_ENABLED (default: false) - enable timing instrumentation
#              TIMING_OUTPUT_DIR - directory for timing output files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="${SCRIPT_DIR}/.."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configurable port
RPC_PORT="${RPC_PORT:-7546}"
export RPC_PORT

# Timing instrumentation
TIMING_ENABLED="${TIMING_ENABLED:-false}"
if [ "$TIMING_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/lib/timing.sh" ]; then
    source "${SCRIPT_DIR}/lib/timing.sh"
    timing_init "localnode"
    timing_start "localnode_total"
fi

echo -e "${CYAN}=== Starting Hiero Local Node ===${NC}"
echo "RPC_PORT=${RPC_PORT}"
echo ""

# Preflight cleanup - ensure no port conflicts
if [ "$TIMING_ENABLED" = "true" ]; then timing_start "localnode_preflight"; fi

echo "Running preflight cleanup..."
if [ -f "${SCRIPT_DIR}/cleanup.sh" ]; then
    "${SCRIPT_DIR}/cleanup.sh" --verify-only
    CLEANUP_EXIT=$?
    if [ $CLEANUP_EXIT -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}Ports are in use. Running full cleanup...${NC}"
        "${SCRIPT_DIR}/cleanup.sh"
        echo ""
    fi
fi

if [ "$TIMING_ENABLED" = "true" ]; then timing_end "localnode_preflight"; fi

# Check prerequisites
if [ "$TIMING_ENABLED" = "true" ]; then timing_start "localnode_docker_check"; fi

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker is not running${NC}"
    exit 1
fi

if [ "$TIMING_ENABLED" = "true" ]; then timing_end "localnode_docker_check"; fi

# Start the local node
if [ "$TIMING_ENABLED" = "true" ]; then timing_start "localnode_start"; fi

# Check if hedera CLI is available
if command -v hedera &> /dev/null; then
    echo "Using hedera CLI..."
    echo ""

    # Start the local node with rate limits disabled (better for dev)
    hedera start --limits=false

    echo ""
    echo -e "${GREEN}=== Local Node Started Successfully ===${NC}"
else
    # Fallback to using the cloned repo
    LOCAL_NODE_DIR="${LAB_DIR}/repos/hiero-local-node"

    if [ ! -d "$LOCAL_NODE_DIR" ]; then
        echo -e "${RED}Error: hiero-local-node repo not found at ${LOCAL_NODE_DIR}${NC}"
        echo "Please run: ./scripts/clone-repos.sh"
        exit 1
    fi

    echo "Using cloned repo at ${LOCAL_NODE_DIR}..."
    echo ""

    cd "$LOCAL_NODE_DIR"

    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
        echo "Installing dependencies..."
        npm install
    fi

    # Start the local node
    npm run start -- --limits=false

    echo ""
    echo -e "${GREEN}=== Local Node Started Successfully ===${NC}"
fi

if [ "$TIMING_ENABLED" = "true" ]; then timing_end "localnode_start"; fi

echo ""
echo -e "${CYAN}=== Network Configuration ===${NC}"
echo ""
echo "JSON-RPC Relay URL:      http://127.0.0.1:${RPC_PORT}"
echo "JSON-RPC WebSocket:      ws://127.0.0.1:8546"
echo "Chain ID:                298 (0x12a)"
echo ""
echo "Mirror Node REST API:    http://127.0.0.1:5551"
echo "Mirror Node gRPC:        127.0.0.1:5600"
echo "Mirror Node Explorer:    http://127.0.0.1:8090"
echo ""
echo "Consensus Node:          127.0.0.1:50211"
echo "Node Account ID:         0.0.3"
echo ""
echo "Grafana Dashboard:       http://127.0.0.1:3000 (admin/admin)"
echo "Prometheus:              http://127.0.0.1:9090"
echo ""
echo -e "${CYAN}=== Default Test Accounts (Alias ECDSA - MetaMask compatible) ===${NC}"
echo ""
echo "Account 0.0.1012:"
echo "  Address: 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69"
echo "  Private Key: 0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524"
echo ""
echo "Account 0.0.1013:"
echo "  Address: 0x05FbA803Be258049A27B820088bab1cAD2058871"
echo "  Private Key: 0x2e1d968b041d84dd120a5860cee60cd83f9374ef527ca86996317ada3d0d03e7"
echo ""
echo "(See full account list in startup output above)"
echo ""
echo -e "${GREEN}READY${NC} - Network is ready for transactions"
echo ""

# Verify network is healthy
if [ "$TIMING_ENABLED" = "true" ]; then timing_start "localnode_health_wait"; fi

echo "Verifying network health..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s "http://127.0.0.1:${RPC_PORT}" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x12a"; then
        echo -e "${GREEN}JSON-RPC Relay is responding correctly (Chain ID: 298)${NC}"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "Waiting for JSON-RPC Relay... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}Warning: JSON-RPC Relay may not be fully ready yet${NC}"
fi

if [ "$TIMING_ENABLED" = "true" ]; then timing_end "localnode_health_wait"; fi

echo ""
echo -e "${GREEN}=== READY ===${NC}"

# Export timing data if enabled
if [ "$TIMING_ENABLED" = "true" ]; then
    timing_end "localnode_total"
    timing_summary
    timing_export_json
fi
