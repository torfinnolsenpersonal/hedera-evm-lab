#!/usr/bin/env bash
# Start Anvil (Foundry's local Ethereum node) for benchmarking
# Usage: ./scripts/start-anvil.sh [port]
#
# Anvil ships with 10 deterministic accounts, each funded with 10,000 ETH.
# Account #0 private key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# These are the same default accounts used by Hardhat Network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/timing.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

PORT="${1:-8545}"
PID_DIR="${TMPDIR:-/tmp}"
PID_FILE="${PID_DIR}/anvil.pid"

echo -e "${CYAN}=== Starting Anvil ===${NC}"

# Check if anvil is installed
if ! command -v anvil &> /dev/null; then
    echo -e "${RED}Error: anvil not found. Install Foundry: https://book.getfoundry.sh/getting-started/installation${NC}"
    exit 1
fi

# Check if port is already in use
if lsof -i ":${PORT}" -sTCP:LISTEN &> /dev/null; then
    echo -e "${RED}Error: Port ${PORT} is already in use${NC}"
    echo "Check what's running: lsof -i :${PORT}"
    echo "Or stop Anvil first: ./scripts/stop-anvil.sh"
    exit 1
fi

timing_init "anvil"
timing_start "anvil_startup"

# Start Anvil in background
anvil --port "$PORT" --chain-id 31337 --silent &
ANVIL_PID=$!
echo "$ANVIL_PID" > "$PID_FILE"

# Wait for RPC readiness (up to 10 seconds)
MAX_WAIT=10
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if curl -s "http://127.0.0.1:${PORT}" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x7a69"; then
        break
    fi
    sleep 0.5
    ELAPSED=$((ELAPSED + 1))
done

timing_end "anvil_startup"

# Verify readiness
if curl -s "http://127.0.0.1:${PORT}" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x7a69"; then
    echo -e "${GREEN}Anvil is running${NC}"
    echo ""
    echo "  RPC URL:    http://127.0.0.1:${PORT}"
    echo "  Chain ID:   31337 (0x7a69)"
    echo "  PID:        ${ANVIL_PID}"
    echo "  PID file:   ${PID_FILE}"
    echo ""
    echo "  Account #0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    echo "  Key #0:     0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    echo ""
    echo -e "${GREEN}=== Anvil Ready ===${NC}"
else
    echo -e "${RED}Error: Anvil failed to start within ${MAX_WAIT}s${NC}"
    kill "$ANVIL_PID" 2>/dev/null || true
    rm -f "$PID_FILE"
    exit 1
fi
