#!/usr/bin/env bash
# Hedera EVM Lab - Transaction Test Harness
# Runs identical tests on both Local Node and Solo, captures outputs for comparison
# Usage: ./run-transaction-tests.sh [localnode|solo|both] [--compare]
# Environment: RPC_PORT (default: 7546)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="${SCRIPT_DIR}/.."
OUTPUT_DIR="${LAB_DIR}/test-results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configurable port
RPC_PORT="${RPC_PORT:-7546}"
export RPC_PORT

# Parse arguments
TARGET="${1:-localnode}"
COMPARE_MODE="${2:-}"

# Timestamp for output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

print_header() {
    echo ""
    echo -e "${CYAN}=== $1 ===${NC}"
}

ensure_output_dir() {
    mkdir -p "$OUTPUT_DIR"
}

check_network() {
    local rpc_url="http://127.0.0.1:${RPC_PORT}"
    if curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x12a"; then
        return 0
    fi
    return 1
}

run_rpc_tests() {
    local network="$1"
    local output_file="$2"
    local rpc_url="http://127.0.0.1:${RPC_PORT}"

    echo "Running RPC tests against ${network}..." | tee -a "$output_file"
    echo "RPC URL: ${rpc_url}" | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    # Test 1: eth_chainId
    echo "Test 1: eth_chainId" | tee -a "$output_file"
    local chain_id
    chain_id=$(curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null)
    echo "Response: $chain_id" | tee -a "$output_file"
    if echo "$chain_id" | grep -q "0x12a"; then
        echo -e "${GREEN}PASS${NC}" | tee -a "$output_file"
    else
        echo -e "${RED}FAIL${NC}" | tee -a "$output_file"
    fi
    echo "" | tee -a "$output_file"

    # Test 2: eth_blockNumber
    echo "Test 2: eth_blockNumber" | tee -a "$output_file"
    local block_num
    block_num=$(curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null)
    echo "Response: $block_num" | tee -a "$output_file"
    if echo "$block_num" | grep -q "result"; then
        echo -e "${GREEN}PASS${NC}" | tee -a "$output_file"
    else
        echo -e "${RED}FAIL${NC}" | tee -a "$output_file"
    fi
    echo "" | tee -a "$output_file"

    # Test 3: eth_gasPrice
    echo "Test 3: eth_gasPrice" | tee -a "$output_file"
    local gas_price
    gas_price=$(curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}' 2>/dev/null)
    echo "Response: $gas_price" | tee -a "$output_file"
    if echo "$gas_price" | grep -q "result"; then
        echo -e "${GREEN}PASS${NC}" | tee -a "$output_file"
    else
        echo -e "${RED}FAIL${NC}" | tee -a "$output_file"
    fi
    echo "" | tee -a "$output_file"

    # Test 4: eth_getBalance (default test account)
    echo "Test 4: eth_getBalance" | tee -a "$output_file"
    local balance
    balance=$(curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69","latest"],"id":1}' 2>/dev/null)
    echo "Response: $balance" | tee -a "$output_file"
    if echo "$balance" | grep -q "result"; then
        echo -e "${GREEN}PASS${NC}" | tee -a "$output_file"
    else
        echo -e "${RED}FAIL${NC}" | tee -a "$output_file"
    fi
    echo "" | tee -a "$output_file"

    # Test 5: web3_clientVersion
    echo "Test 5: web3_clientVersion" | tee -a "$output_file"
    local client_version
    client_version=$(curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' 2>/dev/null)
    echo "Response: $client_version" | tee -a "$output_file"
    if echo "$client_version" | grep -q "result"; then
        echo -e "${GREEN}PASS${NC}" | tee -a "$output_file"
    else
        echo -e "${RED}FAIL${NC}" | tee -a "$output_file"
    fi
    echo "" | tee -a "$output_file"

    # Test 6: net_version
    echo "Test 6: net_version" | tee -a "$output_file"
    local net_version
    net_version=$(curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' 2>/dev/null)
    echo "Response: $net_version" | tee -a "$output_file"
    if echo "$net_version" | grep -q "result"; then
        echo -e "${GREEN}PASS${NC}" | tee -a "$output_file"
    else
        echo -e "${RED}FAIL${NC}" | tee -a "$output_file"
    fi
    echo "" | tee -a "$output_file"
}

run_hardhat_tests() {
    local network="$1"
    local output_file="$2"

    echo "Running Hardhat tests against ${network}..." | tee -a "$output_file"

    local hardhat_dir="${LAB_DIR}/examples/hardhat/contract-smoke"
    if [ ! -d "$hardhat_dir" ]; then
        echo -e "${YELLOW}Hardhat project not found at ${hardhat_dir}${NC}" | tee -a "$output_file"
        return 1
    fi

    cd "$hardhat_dir"

    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
        echo "Installing dependencies..." | tee -a "$output_file"
        npm install >> "$output_file" 2>&1
    fi

    # Compile and run tests
    echo "Compiling contracts..." | tee -a "$output_file"
    npx hardhat compile >> "$output_file" 2>&1

    echo "Running tests..." | tee -a "$output_file"
    if npx hardhat test --network "$network" >> "$output_file" 2>&1; then
        echo -e "${GREEN}Hardhat tests PASSED${NC}" | tee -a "$output_file"
        return 0
    else
        echo -e "${RED}Hardhat tests FAILED${NC}" | tee -a "$output_file"
        return 1
    fi
}

run_foundry_tests() {
    local network="$1"
    local output_file="$2"

    echo "Running Foundry tests against ${network}..." | tee -a "$output_file"

    if ! command -v forge &> /dev/null; then
        echo -e "${YELLOW}Foundry not installed, skipping${NC}" | tee -a "$output_file"
        return 1
    fi

    local foundry_dir="${LAB_DIR}/examples/foundry/contract-smoke"
    if [ ! -d "$foundry_dir" ]; then
        echo -e "${YELLOW}Foundry project not found at ${foundry_dir}${NC}" | tee -a "$output_file"
        return 1
    fi

    cd "$foundry_dir"

    # Install forge-std if needed
    if [ ! -d "lib/forge-std" ]; then
        echo "Installing forge-std..." | tee -a "$output_file"
        forge install foundry-rs/forge-std --no-commit >> "$output_file" 2>&1
    fi

    local rpc_url="http://127.0.0.1:${RPC_PORT}"

    echo "Running fork tests against ${rpc_url}..." | tee -a "$output_file"
    if forge test --fork-url "$rpc_url" -vvv >> "$output_file" 2>&1; then
        echo -e "${GREEN}Foundry tests PASSED${NC}" | tee -a "$output_file"
        return 0
    else
        echo -e "${RED}Foundry tests FAILED${NC}" | tee -a "$output_file"
        return 1
    fi
}

run_full_suite() {
    local network="$1"
    local output_file="${OUTPUT_DIR}/${network}_${TIMESTAMP}.log"

    print_header "Testing ${network} Network"
    echo "Output file: ${output_file}"
    echo ""

    echo "=== Transaction Test Results for ${network} ===" > "$output_file"
    echo "Timestamp: $(date)" >> "$output_file"
    echo "RPC_PORT: ${RPC_PORT}" >> "$output_file"
    echo "" >> "$output_file"

    # RPC tests
    echo "=== RPC Tests ===" >> "$output_file"
    run_rpc_tests "$network" "$output_file"

    # Hardhat tests
    echo "" >> "$output_file"
    echo "=== Hardhat Tests ===" >> "$output_file"
    run_hardhat_tests "$network" "$output_file" || true

    # Foundry tests
    echo "" >> "$output_file"
    echo "=== Foundry Tests ===" >> "$output_file"
    run_foundry_tests "$network" "$output_file" || true

    echo ""
    echo -e "${GREEN}Results saved to: ${output_file}${NC}"
}

compare_results() {
    local localnode_file
    local solo_file

    # Find most recent result files
    localnode_file=$(ls -t "${OUTPUT_DIR}"/localnode_*.log 2>/dev/null | head -1)
    solo_file=$(ls -t "${OUTPUT_DIR}"/solo_*.log 2>/dev/null | head -1)

    if [ -z "$localnode_file" ] || [ -z "$solo_file" ]; then
        echo -e "${RED}Cannot compare: Need results from both localnode and solo${NC}"
        echo "Run tests on both networks first:"
        echo "  ./run-transaction-tests.sh localnode"
        echo "  ./run-transaction-tests.sh solo"
        exit 1
    fi

    print_header "Comparing Test Results"
    echo "Local Node: ${localnode_file}"
    echo "Solo:       ${solo_file}"
    echo ""

    local compare_file="${OUTPUT_DIR}/comparison_${TIMESTAMP}.txt"

    echo "=== Test Result Comparison ===" > "$compare_file"
    echo "Generated: $(date)" >> "$compare_file"
    echo "" >> "$compare_file"
    echo "Local Node file: ${localnode_file}" >> "$compare_file"
    echo "Solo file:       ${solo_file}" >> "$compare_file"
    echo "" >> "$compare_file"

    echo "=== Differences ===" >> "$compare_file"
    diff -u "$localnode_file" "$solo_file" >> "$compare_file" 2>&1 || true

    echo "Comparison saved to: ${compare_file}"
    echo ""

    # Show summary
    local ln_pass
    local solo_pass
    ln_pass=$(grep -c "PASS" "$localnode_file" 2>/dev/null || echo "0")
    solo_pass=$(grep -c "PASS" "$solo_file" 2>/dev/null || echo "0")

    echo "Summary:"
    echo "  Local Node: ${ln_pass} tests passed"
    echo "  Solo:       ${solo_pass} tests passed"
}

# Main logic
print_header "Hedera EVM Lab - Transaction Test Harness"
echo "Target: ${TARGET}"
echo "RPC_PORT: ${RPC_PORT}"
echo ""

ensure_output_dir

case "$TARGET" in
    localnode)
        if ! check_network; then
            echo -e "${RED}No network detected on port ${RPC_PORT}${NC}"
            echo "Start Local Node first: ./scripts/start-local-node.sh"
            exit 1
        fi
        run_full_suite "localnode"
        ;;
    solo)
        if ! check_network; then
            echo -e "${RED}No network detected on port ${RPC_PORT}${NC}"
            echo "Start Solo first: ./scripts/start-solo.sh"
            exit 1
        fi
        run_full_suite "solo"
        ;;
    both)
        echo -e "${YELLOW}Note: Running 'both' requires manual network switching${NC}"
        echo "This mode will guide you through testing both networks."
        echo ""

        # Test Local Node
        echo "Step 1: Ensure Local Node is running"
        echo "  Start with: ./scripts/start-local-node.sh"
        read -p "Press Enter when Local Node is ready (or Ctrl+C to abort)..."

        if check_network; then
            run_full_suite "localnode"
        else
            echo -e "${RED}Local Node not detected, skipping${NC}"
        fi

        # Stop Local Node, start Solo
        echo ""
        echo "Step 2: Stop Local Node and start Solo"
        echo "  Stop:  ./scripts/stop-local-node.sh"
        echo "  Start: ./scripts/start-solo.sh"
        read -p "Press Enter when Solo is ready (or Ctrl+C to skip)..."

        if check_network; then
            run_full_suite "solo"
        else
            echo -e "${RED}Solo not detected, skipping${NC}"
        fi

        # Compare results
        compare_results
        ;;
    compare)
        compare_results
        ;;
    *)
        echo "Usage: $0 [localnode|solo|both|compare]"
        echo ""
        echo "Options:"
        echo "  localnode  Run tests against Local Node (default)"
        echo "  solo       Run tests against Solo"
        echo "  both       Run tests against both (interactive)"
        echo "  compare    Compare most recent results from both networks"
        echo ""
        echo "Environment variables:"
        echo "  RPC_PORT   JSON-RPC port (default: 7546)"
        exit 1
        ;;
esac

print_header "Complete"
echo "Test results stored in: ${OUTPUT_DIR}"
