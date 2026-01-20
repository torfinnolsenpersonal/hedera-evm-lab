#!/usr/bin/env bash
# Run Hardhat smoke tests against the running Hedera network
# Usage: ./run-hardhat-smoke.sh [localnode|solo]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="${SCRIPT_DIR}/.."
HARDHAT_DIR="${LAB_DIR}/examples/hardhat/contract-smoke"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

NETWORK="${1:-localnode}"

echo -e "${CYAN}=== Hardhat Smoke Test ===${NC}"
echo "Network: ${NETWORK}"
echo ""

# Check if network is running
if ! curl -s "http://127.0.0.1:7546" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x12a"; then
    echo -e "${RED}Error: No Hedera network detected on port 7546${NC}"
    echo ""
    echo "Start a network first:"
    echo "  ./scripts/start-local-node.sh   # For Local Node"
    echo "  ./scripts/start-solo.sh         # For Solo"
    exit 1
fi

echo "Network detected on port 7546 (Chain ID: 298)"
echo ""

cd "$HARDHAT_DIR"

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
    echo ""
fi

# Compile contracts
echo "Compiling contracts..."
npx hardhat compile
echo ""

# Run tests
echo -e "${CYAN}Running tests against ${NETWORK}...${NC}"
echo ""

if npx hardhat test --network "$NETWORK"; then
    echo ""
    echo -e "${GREEN}=== Hardhat Smoke Test PASSED ===${NC}"
else
    echo ""
    echo -e "${RED}=== Hardhat Smoke Test FAILED ===${NC}"
    exit 1
fi
