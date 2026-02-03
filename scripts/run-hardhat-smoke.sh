#!/usr/bin/env bash
# Run Hardhat smoke tests against the running Hedera network
# Usage: ./run-hardhat-smoke.sh [localnode|solo|anvil|hedera_testnet]

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

# Network-specific connectivity checks
case "$NETWORK" in
    anvil)
        # Anvil on port 8545, Chain ID 31337 (0x7a69)
        if ! curl -s "http://127.0.0.1:8545" -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x7a69"; then
            echo -e "${RED}Error: No Anvil network detected on port 8545${NC}"
            echo ""
            echo "Start Anvil first:"
            echo "  ./scripts/start-anvil.sh"
            exit 1
        fi
        echo "Anvil detected on port 8545 (Chain ID: 31337)"
        ;;
    hedera_testnet)
        # Remote Hedera Testnet, Chain ID 296 (0x128)
        if [ -z "${HEDERA_TESTNET_PRIVATE_KEY:-}" ]; then
            echo -e "${RED}Error: HEDERA_TESTNET_PRIVATE_KEY is required${NC}"
            echo "Export it before running:"
            echo "  export HEDERA_TESTNET_PRIVATE_KEY=0x..."
            exit 1
        fi
        RPC_URL="${HEDERA_TESTNET_RPC_URL:-https://testnet.hashio.io/api}"
        if ! curl -s "$RPC_URL" -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x128"; then
            echo -e "${RED}Error: Cannot reach Hedera Testnet at ${RPC_URL}${NC}"
            exit 1
        fi
        echo "Hedera Testnet reachable (Chain ID: 296)"
        ;;
    localnode|solo|*)
        # Hedera networks on port 7546, Chain ID 298 (0x12a)
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
        ;;
esac
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
