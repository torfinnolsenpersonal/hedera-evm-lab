#!/usr/bin/env bash
# Run all smoke tests against Local Node and/or Solo
# Usage: ./run-all.sh [localnode|solo|both]
#
# IMPORTANT: Local Node and Solo share port 7546 (JSON-RPC relay).
# They cannot run simultaneously. This script handles the sequencing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MODE="${1:-localnode}"

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Hedera EVM Lab - Full Test Suite${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

run_tests_against_localnode() {
    echo -e "${CYAN}=== Testing with Hiero Local Node ===${NC}"
    echo ""

    # Start Local Node
    echo "Starting Local Node..."
    "$SCRIPT_DIR/start-local-node.sh"
    echo ""

    # Wait a bit for full initialization
    echo "Waiting for network to stabilize..."
    sleep 10

    # Run Hardhat tests
    echo ""
    "$SCRIPT_DIR/run-hardhat-smoke.sh" localnode || HARDHAT_FAILED=1

    # Run Foundry tests
    echo ""
    "$SCRIPT_DIR/run-foundry-smoke.sh" --fork || FOUNDRY_FAILED=1

    # Stop Local Node
    echo ""
    echo "Stopping Local Node..."
    "$SCRIPT_DIR/stop-local-node.sh"

    if [ "${HARDHAT_FAILED:-0}" = "1" ] || [ "${FOUNDRY_FAILED:-0}" = "1" ]; then
        echo -e "${RED}Some Local Node tests failed${NC}"
        return 1
    fi

    echo -e "${GREEN}All Local Node tests passed${NC}"
    return 0
}

run_tests_against_solo() {
    echo -e "${CYAN}=== Testing with Solo ===${NC}"
    echo ""

    # Check prerequisites
    if ! command -v kind &> /dev/null; then
        echo -e "${RED}Error: kind is not installed (required for Solo)${NC}"
        return 1
    fi

    if ! command -v solo &> /dev/null; then
        echo -e "${RED}Error: solo is not installed${NC}"
        echo "Install with: npm install -g @hashgraph/solo"
        return 1
    fi

    # Start Solo
    echo "Starting Solo..."
    "$SCRIPT_DIR/start-solo.sh"
    echo ""

    # Wait for Solo to be fully ready
    echo "Waiting for Solo network to stabilize..."
    sleep 30

    # Run Hardhat tests
    echo ""
    "$SCRIPT_DIR/run-hardhat-smoke.sh" solo || HARDHAT_FAILED=1

    # Run Foundry tests
    echo ""
    "$SCRIPT_DIR/run-foundry-smoke.sh" --fork || FOUNDRY_FAILED=1

    # Stop Solo
    echo ""
    echo "Stopping Solo..."
    "$SCRIPT_DIR/stop-solo.sh"

    if [ "${HARDHAT_FAILED:-0}" = "1" ] || [ "${FOUNDRY_FAILED:-0}" = "1" ]; then
        echo -e "${RED}Some Solo tests failed${NC}"
        return 1
    fi

    echo -e "${GREEN}All Solo tests passed${NC}"
    return 0
}

LOCALNODE_RESULT=0
SOLO_RESULT=0

case "$MODE" in
    localnode)
        run_tests_against_localnode || LOCALNODE_RESULT=1
        ;;
    solo)
        run_tests_against_solo || SOLO_RESULT=1
        ;;
    both)
        echo -e "${YELLOW}Running tests against BOTH networks sequentially${NC}"
        echo -e "${YELLOW}(They share port 7546 and cannot run simultaneously)${NC}"
        echo ""

        run_tests_against_localnode || LOCALNODE_RESULT=1

        echo ""
        echo "Waiting before starting Solo..."
        sleep 5

        run_tests_against_solo || SOLO_RESULT=1
        ;;
    *)
        echo "Usage: $0 [localnode|solo|both]"
        echo ""
        echo "  localnode  - Test against Hiero Local Node only (default)"
        echo "  solo       - Test against Solo only"
        echo "  both       - Test against both (sequentially)"
        exit 1
        ;;
esac

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Test Summary${NC}"
echo -e "${CYAN}============================================${NC}"

if [ "$MODE" = "localnode" ] || [ "$MODE" = "both" ]; then
    if [ "$LOCALNODE_RESULT" = "0" ]; then
        echo -e "Local Node: ${GREEN}PASSED${NC}"
    else
        echo -e "Local Node: ${RED}FAILED${NC}"
    fi
fi

if [ "$MODE" = "solo" ] || [ "$MODE" = "both" ]; then
    if [ "$SOLO_RESULT" = "0" ]; then
        echo -e "Solo:       ${GREEN}PASSED${NC}"
    else
        echo -e "Solo:       ${RED}FAILED${NC}"
    fi
fi

echo ""

if [ "$LOCALNODE_RESULT" = "0" ] && [ "$SOLO_RESULT" = "0" ]; then
    echo -e "${GREEN}=== ALL TESTS PASSED ===${NC}"
    exit 0
else
    echo -e "${RED}=== SOME TESTS FAILED ===${NC}"
    exit 1
fi
