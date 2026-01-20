#!/usr/bin/env bash
# Run Foundry smoke tests against the running Hedera network
# Usage: ./run-foundry-smoke.sh [--fork]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="${SCRIPT_DIR}/.."
FOUNDRY_DIR="${LAB_DIR}/examples/foundry/contract-smoke"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

USE_FORK="${1:-}"
RPC_URL="http://127.0.0.1:7546"

echo -e "${CYAN}=== Foundry Smoke Test ===${NC}"
echo ""

# Check if forge is installed
if ! command -v forge &> /dev/null; then
    echo -e "${RED}Error: Foundry (forge) is not installed${NC}"
    echo "Install with: curl -L https://foundry.paradigm.xyz | bash && foundryup"
    exit 1
fi

cd "$FOUNDRY_DIR"

# Install forge-std if needed
if [ ! -d "lib/forge-std" ]; then
    echo "Installing forge-std..."
    forge install foundry-rs/forge-std --no-git
    echo ""
fi

if [ "$USE_FORK" = "--fork" ]; then
    # Check if network is running for fork mode
    if ! curl -s "$RPC_URL" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x12a"; then
        echo -e "${RED}Error: No Hedera network detected on port 7546${NC}"
        echo ""
        echo "Start a network first:"
        echo "  ./scripts/start-local-node.sh   # For Local Node"
        echo "  ./scripts/start-solo.sh         # For Solo"
        exit 1
    fi
    echo "Network detected on port 7546 (Chain ID: 298)"
    echo "Running tests in FORK mode against Hedera network..."
    echo ""

    if forge test --fork-url "$RPC_URL" -vvv; then
        echo ""
        echo -e "${GREEN}=== Foundry Smoke Test (Fork) PASSED ===${NC}"
    else
        echo ""
        echo -e "${RED}=== Foundry Smoke Test (Fork) FAILED ===${NC}"
        exit 1
    fi
else
    echo "Running tests locally (no fork)..."
    echo "(Use --fork to run against Hedera network)"
    echo ""

    if forge test -vvv; then
        echo ""
        echo -e "${GREEN}=== Foundry Smoke Test PASSED ===${NC}"
    else
        echo ""
        echo -e "${RED}=== Foundry Smoke Test FAILED ===${NC}"
        exit 1
    fi
fi
