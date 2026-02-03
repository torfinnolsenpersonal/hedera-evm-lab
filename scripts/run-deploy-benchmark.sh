#!/usr/bin/env bash
# Run the Deploy Benchmark across one or more networks
# Usage: ./scripts/run-deploy-benchmark.sh [--clean|--warm] [anvil|localnode|solo|hedera_testnet|local|all]
#
# Flags:
#   --clean  (default) Full developer journey: clean node_modules/artifacts, npm install, compile, then benchmark
#   --warm   Skip install/compile steps; only run network startup + contract benchmark
#
# Modes:
#   anvil          - Benchmark against Anvil (local Ethereum)
#   localnode      - Benchmark against Hiero Local Node
#   solo           - Benchmark against Solo
#   hedera_testnet - Benchmark against Hedera Testnet (requires HEDERA_TESTNET_PRIVATE_KEY)
#   local          - Run anvil + localnode + solo
#   all            - Run all four networks
#
# Results are saved to reports/YYYY-MM-DD_HH-MM-SS_deploy-benchmark.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HARDHAT_DIR="${PROJECT_ROOT}/examples/hardhat/contract-smoke"
REPORTS_DIR="${PROJECT_ROOT}/reports"

# Source timing library
source "${SCRIPT_DIR}/lib/timing.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse flags
CLEAN_MODE=true
MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN_MODE=true
            shift
            ;;
        --warm)
            CLEAN_MODE=false
            shift
            ;;
        *)
            MODE="$1"
            shift
            ;;
    esac
done

MODE="${MODE:-anvil}"

# Create temp directory for outputs
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

mkdir -p "$REPORTS_DIR"

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Deploy Benchmark — Developer Journey${NC}"
echo -e "${CYAN}============================================${NC}"
echo "Mode: ${MODE}"
if $CLEAN_MODE; then
    echo "Run type: CLEAN (full developer journey)"
else
    echo "Run type: WARM (skip install/compile)"
fi
echo ""

# Determine which networks to run
NETWORKS=()
case "$MODE" in
    anvil|localnode|solo|hedera_testnet)
        NETWORKS=("$MODE")
        ;;
    local)
        NETWORKS=(anvil localnode solo)
        ;;
    all)
        NETWORKS=(anvil localnode solo hedera_testnet)
        ;;
    *)
        echo -e "${RED}Unknown mode: ${MODE}${NC}"
        echo "Usage: $0 [--clean|--warm] [anvil|localnode|solo|hedera_testnet|local|all]"
        exit 1
        ;;
esac

echo "Networks: ${NETWORKS[*]}"
echo ""

# In warm mode, ensure hardhat project is ready once up front
if ! $CLEAN_MODE; then
    cd "$HARDHAT_DIR"
    if [ ! -d "node_modules" ]; then
        echo "Installing dependencies (warm mode, node_modules missing)..."
        npm install
        echo ""
    fi
    echo "Compiling contracts..."
    npx hardhat compile --quiet 2>/dev/null || npx hardhat compile
    echo ""
fi

# ============================================================================
# Network lifecycle helpers
# ============================================================================

start_network() {
    local net="$1"
    case "$net" in
        anvil)
            echo -e "${CYAN}Starting Anvil...${NC}"
            "${SCRIPT_DIR}/start-anvil.sh"
            ;;
        localnode)
            echo -e "${CYAN}Starting Local Node...${NC}"
            "${SCRIPT_DIR}/start-local-node.sh"
            sleep 10  # Stabilization wait
            ;;
        solo)
            echo -e "${CYAN}Starting Solo...${NC}"
            "${SCRIPT_DIR}/start-solo.sh"
            sleep 30  # Stabilization wait
            ;;
        hedera_testnet)
            # Remote network -- just validate connectivity
            if [ -z "${HEDERA_TESTNET_PRIVATE_KEY:-}" ]; then
                echo -e "${RED}Error: HEDERA_TESTNET_PRIVATE_KEY is required for hedera_testnet${NC}"
                echo "Export it before running:"
                echo "  export HEDERA_TESTNET_PRIVATE_KEY=0x..."
                return 1
            fi
            local rpc_url="${HEDERA_TESTNET_RPC_URL:-https://testnet.hashio.io/api}"
            echo "Validating Hedera Testnet connectivity at ${rpc_url}..."
            if curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x128"; then
                echo -e "${GREEN}Hedera Testnet reachable (Chain ID: 296)${NC}"
            else
                echo -e "${RED}Error: Cannot reach Hedera Testnet at ${rpc_url}${NC}"
                return 1
            fi
            ;;
    esac
}

stop_network() {
    local net="$1"
    case "$net" in
        anvil)
            "${SCRIPT_DIR}/stop-anvil.sh" || true
            ;;
        localnode)
            "${SCRIPT_DIR}/stop-local-node.sh" || true
            ;;
        solo)
            "${SCRIPT_DIR}/stop-solo.sh" || true
            ;;
        hedera_testnet)
            # Nothing to stop for a remote network
            ;;
    esac
}

# ============================================================================
# Run benchmark for a single network
# ============================================================================

run_benchmark() {
    local net="$1"
    local output_file="${TEMP_DIR}/benchmark_${net}.txt"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Benchmarking: ${net}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    timing_init "$net"

    # Stage 1: npm install (clean mode only)
    if $CLEAN_MODE; then
        echo -e "${YELLOW}Stage 1: npm install (clean)${NC}"
        rm -rf "$HARDHAT_DIR/node_modules"
        timing_start "${net}_npm_install"
        cd "$HARDHAT_DIR" && npm install
        timing_end "${net}_npm_install"
        echo ""
    fi

    # Stage 2: Tooling check (anvil only)
    if [ "$net" = "anvil" ]; then
        echo -e "${YELLOW}Stage 2: Tooling check (anvil)${NC}"
        timing_start "${net}_tooling_check"
        if command -v anvil &>/dev/null; then
            echo -e "${GREEN}anvil found: $(command -v anvil)${NC}"
        else
            echo -e "${RED}anvil not found — install with: curl -L https://foundry.paradigm.xyz | bash && foundryup${NC}"
        fi
        timing_end "${net}_tooling_check"
        echo ""
    fi

    # Stage 3: Compile contracts (clean mode only)
    if $CLEAN_MODE; then
        echo -e "${YELLOW}Stage 3: Compile contracts (clean)${NC}"
        rm -rf "$HARDHAT_DIR/artifacts" "$HARDHAT_DIR/cache"
        timing_start "${net}_compile"
        cd "$HARDHAT_DIR" && npx hardhat compile
        timing_end "${net}_compile"
        echo ""
    fi

    # Stage 4: Network startup
    echo -e "${YELLOW}Stage 4: Network startup${NC}"
    timing_start "${net}_startup"
    if ! start_network "$net"; then
        echo -e "${RED}Failed to start ${net}, skipping${NC}"
        timing_end "${net}_startup"
        return 1
    fi
    timing_end "${net}_startup"

    # Stage 5: Contract benchmark
    timing_start "${net}_benchmark"
    echo ""
    echo -e "${YELLOW}Stage 5: Contract benchmark${NC}"
    echo -e "${CYAN}Running benchmark tests against ${net}...${NC}"
    echo ""

    cd "$HARDHAT_DIR"
    if npx hardhat test test/DeployBenchmark.test.ts --network "$net" 2>&1 | tee "$output_file"; then
        echo ""
        echo -e "${GREEN}Benchmark PASSED for ${net}${NC}"
    else
        echo ""
        echo -e "${RED}Benchmark FAILED for ${net}${NC}"
    fi
    timing_end "${net}_benchmark"

    # Stage 6: Network shutdown
    if [ "$net" != "hedera_testnet" ]; then
        echo -e "${YELLOW}Stage 6: Network shutdown${NC}"
        timing_start "${net}_shutdown"
        stop_network "$net"
        timing_end "${net}_shutdown"
    fi

    echo ""
    timing_summary
}

# ============================================================================
# Parse timing from benchmark output
# ============================================================================

parse_benchmark_output() {
    local file="$1"
    local step="$2"

    if [ -f "$file" ]; then
        # Match lines like "║  Deploy contract          1234ms ║"
        grep -oE "${step}[[:space:]]+[0-9]+ms" "$file" 2>/dev/null | grep -oE '[0-9]+ms' | head -1 || echo "N/A"
    else
        echo "N/A"
    fi
}

# ============================================================================
# Generate report
# ============================================================================

generate_report() {
    local report_file="${REPORTS_DIR}/${TIMESTAMP}_deploy-benchmark.md"

    echo -e "${CYAN}Generating benchmark report...${NC}"

    {
        echo "# Deploy Benchmark Report — Developer Journey"
        echo ""
        echo "**Date:** ${TIMESTAMP}"
        echo ""
        echo "**Networks tested:** ${NETWORKS[*]}"
        echo ""
        if $CLEAN_MODE; then
            echo "**Run type:** Clean (full developer journey — npm install, compile, startup, benchmark)"
        else
            echo "**Run type:** Warm (network startup + benchmark only)"
        fi
        echo ""
        echo "## Results"
        echo ""

        # Build header
        local header="| Stage |"
        local separator="|-------|"
        for net in "${NETWORKS[@]}"; do
            header="${header} ${net} |"
            separator="${separator}------|"
        done
        echo "$header"
        echo "$separator"

        # Infrastructure stages (clean mode only)
        if $CLEAN_MODE; then
            # npm install row
            local row="| npm install |"
            for net in "${NETWORKS[@]}"; do
                local value
                value=$(timing_get_duration_formatted "${net}_npm_install" 2>/dev/null || echo "N/A")
                row="${row} ${value} |"
            done
            echo "$row"

            # Tooling check row (only shows for anvil)
            local has_tooling=false
            for net in "${NETWORKS[@]}"; do
                if [ "$net" = "anvil" ]; then
                    has_tooling=true
                    break
                fi
            done
            if $has_tooling; then
                row="| Tooling check |"
                for net in "${NETWORKS[@]}"; do
                    if [ "$net" = "anvil" ]; then
                        local value
                        value=$(timing_get_duration_formatted "${net}_tooling_check" 2>/dev/null || echo "N/A")
                        row="${row} ${value} |"
                    else
                        row="${row} — |"
                    fi
                done
                echo "$row"
            fi

            # Compile row
            row="| Compile contracts |"
            for net in "${NETWORKS[@]}"; do
                local value
                value=$(timing_get_duration_formatted "${net}_compile" 2>/dev/null || echo "N/A")
                row="${row} ${value} |"
            done
            echo "$row"
        fi

        # Network startup row
        local row="| Network startup |"
        for net in "${NETWORKS[@]}"; do
            local value
            if [ "$net" = "hedera_testnet" ]; then
                value="N/A (remote)"
            else
                value=$(timing_get_duration_formatted "${net}_startup" 2>/dev/null || echo "N/A")
            fi
            row="${row} ${value} |"
        done
        echo "$row"

        # Contract benchmark steps (parsed from test output)
        local steps=("Deploy contract" "Write (increment)" "Read (count)" "Event verification" "Write (setCount)" "Final read")
        for step in "${steps[@]}"; do
            local row="| ${step} |"
            for net in "${NETWORKS[@]}"; do
                local output_file="${TEMP_DIR}/benchmark_${net}.txt"
                local value
                value=$(parse_benchmark_output "$output_file" "$step")
                row="${row} ${value} |"
            done
            echo "$row"
        done

        # TOTAL row from benchmark output
        row="| **Contract ops total** |"
        for net in "${NETWORKS[@]}"; do
            local output_file="${TEMP_DIR}/benchmark_${net}.txt"
            local value
            value=$(parse_benchmark_output "$output_file" "TOTAL")
            row="${row} **${value}** |"
        done
        echo "$row"

        # Network shutdown row
        row="| Network shutdown |"
        for net in "${NETWORKS[@]}"; do
            if [ "$net" = "hedera_testnet" ]; then
                row="${row} — |"
            else
                local value
                value=$(timing_get_duration_formatted "${net}_shutdown" 2>/dev/null || echo "N/A")
                row="${row} ${value} |"
            fi
        done
        echo "$row"

        echo ""
        echo "---"
        echo "*Generated by run-deploy-benchmark.sh*"
    } > "$report_file"

    echo -e "${GREEN}Report saved to: ${report_file}${NC}"
}

# ============================================================================
# Main
# ============================================================================

OVERALL_START=$(date +%s)

for net in "${NETWORKS[@]}"; do
    run_benchmark "$net" || true
    echo ""
done

generate_report

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${GREEN}   Deploy Benchmark Complete${NC}"
echo -e "${CYAN}============================================${NC}"
echo "Total wall time: ${OVERALL_DURATION}s"
echo "Report: ${REPORTS_DIR}/${TIMESTAMP}_deploy-benchmark.md"
echo ""
