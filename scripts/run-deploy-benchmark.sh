#!/usr/bin/env bash
# Run the Deploy Benchmark across one or more networks
# Usage: ./scripts/run-deploy-benchmark.sh [--clean|--warm|--warm-cluster] [anvil|localnode|solo|hedera_testnet|local|all]
#
# Flags:
#   --clean         (default) Full developer journey: clean node_modules/artifacts, npm install, compile, then benchmark
#   --warm          Skip install/compile steps; only run network startup + contract benchmark
#   --warm-cluster  Like --warm, but also preserves the kind cluster between runs (Solo only)
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
WARM_CLUSTER=false
MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN_MODE=true
            WARM_CLUSTER=false
            shift
            ;;
        --warm)
            CLEAN_MODE=false
            WARM_CLUSTER=false
            shift
            ;;
        --warm-cluster)
            CLEAN_MODE=false
            WARM_CLUSTER=true
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

# Timing data directory (persisted alongside the report)
TIMING_DATA_DIR="${REPORTS_DIR}/${TIMESTAMP}_timing-data"
mkdir -p "$TIMING_DATA_DIR"

# Track per-network results: pass/fail/skip (bash 3.x compatible key-value store)
# Keys are sanitized labels: solo_1st, anvil, hedera_testnet_2nd, etc.
kv_set() { eval "${1}_${2}=\${3}"; }
kv_get() { eval "echo \"\${${1}_${2}:-${3:-}}\""; }

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Deploy Benchmark — Developer Journey${NC}"
echo -e "${CYAN}============================================${NC}"
echo "Mode: ${MODE}"
if $WARM_CLUSTER; then
    echo "Run type: WARM CLUSTER (cluster persists, deploy + contract ops only)"
elif $CLEAN_MODE; then
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
        echo "Usage: $0 [--clean|--warm|--warm-cluster] [anvil|localnode|solo|hedera_testnet|local|all]"
        exit 1
        ;;
esac

echo "Networks: ${NETWORKS[*]}"
echo ""

# Resolve actual network name from a run label
# e.g., "solo_1st" → "solo", "anvil_1st" → "anvil", "anvil" → "anvil"
net_name() {
    case "$1" in
        *_1st) echo "${1%_1st}" ;;
        *_2nd) echo "${1%_2nd}" ;;
        *) echo "$1" ;;
    esac
}

# Display-friendly label for reports
# e.g., "solo_1st" → "solo (1st start)", "anvil" → "anvil"
display_name() {
    case "$1" in
        *_1st) echo "${1%_1st} (1st start)" ;;
        *_2nd) echo "${1%_2nd} (2nd start)" ;;
        *) echo "$1" ;;
    esac
}

# Build run list — expand each network into two runs for --warm-cluster
RUN_LIST=()
for net in "${NETWORKS[@]}"; do
    if $WARM_CLUSTER; then
        RUN_LIST+=("${net}_1st" "${net}_2nd")
    else
        RUN_LIST+=("$net")
    fi
done

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
            if $WARM_CLUSTER; then
                "${SCRIPT_DIR}/stop-solo.sh" --keep-cluster || true
            else
                "${SCRIPT_DIR}/stop-solo.sh" || true
            fi
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
    local label="$1"
    local net
    net=$(net_name "$label")
    local output_file="${TEMP_DIR}/benchmark_${label}.txt"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Benchmarking: $(display_name "$label")${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    timing_init "$label"

    # Stage 1: npm install (clean mode only)
    if $CLEAN_MODE; then
        echo -e "${YELLOW}Stage 1: npm install (clean)${NC}"
        rm -rf "$HARDHAT_DIR/node_modules"
        timing_start "${label}_npm_install"
        cd "$HARDHAT_DIR" && npm install
        timing_end "${label}_npm_install"
        echo ""
    fi

    # Stage 2: Tooling check (anvil only)
    if [ "$net" = "anvil" ]; then
        echo -e "${YELLOW}Stage 2: Tooling check (anvil)${NC}"
        timing_start "${label}_tooling_check"
        if command -v anvil &>/dev/null; then
            echo -e "${GREEN}anvil found: $(command -v anvil)${NC}"
        else
            echo -e "${RED}anvil not found — install with: curl -L https://foundry.paradigm.xyz | bash && foundryup${NC}"
        fi
        timing_end "${label}_tooling_check"
        echo ""
    fi

    # Stage 3: Compile contracts (clean mode only)
    if $CLEAN_MODE; then
        echo -e "${YELLOW}Stage 3: Compile contracts (clean)${NC}"
        rm -rf "$HARDHAT_DIR/artifacts" "$HARDHAT_DIR/cache"
        timing_start "${label}_compile"
        cd "$HARDHAT_DIR" && npx hardhat compile
        timing_end "${label}_compile"
        echo ""
    fi

    # Stage 4: Network startup
    echo -e "${YELLOW}Stage 4: Network startup${NC}"
    timing_start "${label}_startup"
    if ! start_network "$net"; then
        echo -e "${RED}Failed to start ${net}, skipping${NC}"
        timing_end "${label}_startup"
        return 1
    fi
    timing_end "${label}_startup"

    # Stage 5: Contract benchmark
    timing_start "${label}_benchmark"
    echo ""
    echo -e "${YELLOW}Stage 5: Contract benchmark${NC}"
    echo -e "${CYAN}Running benchmark tests against ${net}...${NC}"
    echo ""

    cd "$HARDHAT_DIR"
    if npx hardhat test test/DeployBenchmark.test.ts --network "$net" 2>&1 | tee "$output_file"; then
        echo ""
        echo -e "${GREEN}Benchmark PASSED for $(display_name "$label")${NC}"
    else
        echo ""
        echo -e "${RED}Benchmark FAILED for $(display_name "$label")${NC}"
    fi
    timing_end "${label}_benchmark"

    # Parse pass/fail from test output
    local passing failing total
    passing=$(grep -oE '[0-9]+ passing' "$output_file" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "0")
    failing=$(grep -oE '[0-9]+ failing' "$output_file" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "0")
    total=$((passing + failing))
    kv_set NET_PASSED "$label" "$passing"
    kv_set NET_FAILED "$label" "$failing"
    kv_set NET_TOTAL "$label" "$total"
    if [ "$failing" -eq 0 ] && [ "$passing" -gt 0 ]; then
        kv_set NET_STATUS "$label" "PASS"
    elif [ "$passing" -gt 0 ]; then
        kv_set NET_STATUS "$label" "PARTIAL"
    else
        kv_set NET_STATUS "$label" "FAIL"
    fi

    # Stage 6: Network shutdown
    if [ "$net" != "hedera_testnet" ]; then
        echo -e "${YELLOW}Stage 6: Network shutdown${NC}"
        timing_start "${label}_shutdown"
        stop_network "$net"
        timing_end "${label}_shutdown"
    fi

    echo ""
    timing_summary

    # Export timing JSON for this run
    timing_export_json "${TIMING_DATA_DIR}/${label}-timing.json"

    # Copy raw timing data
    if [ -f "$TIMING_DATA_FILE" ]; then
        cp "$TIMING_DATA_FILE" "${TIMING_DATA_DIR}/${label}-timing-data.txt"
    fi

    # Copy benchmark output
    if [ -f "$output_file" ]; then
        cp "$output_file" "${TIMING_DATA_DIR}/${label}-benchmark-output.txt"
    fi
}

# ============================================================================
# Parse timing from benchmark output
# ============================================================================

parse_benchmark_output() {
    local file="$1"
    local step="$2"

    if [ -f "$file" ]; then
        # Escape regex special chars in step names (e.g., parentheses in "Write (increment)")
        local escaped_step
        escaped_step=$(printf '%s' "$step" | sed 's/[()]/\\&/g')
        # Match lines like "║  Deploy contract          1234ms ║"
        grep -oE "${escaped_step}[[:space:]]+[0-9]+ms" "$file" 2>/dev/null | grep -oE '[0-9]+ms' | head -1 || echo "N/A"
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

    # Helper to read timing for a specific run label
    timing_for() {
        local lbl="$1"
        local phase="$2"
        TIMING_DATA_FILE="${TIMING_OUTPUT_DIR}/${lbl}-timing-data.txt"
        timing_get_duration_formatted "${lbl}_${phase}" 2>/dev/null || echo "N/A"
    }

    {
        # ── Header (matches existing report format) ──
        echo "# Hedera EVM Lab - Deploy Benchmark Report"
        echo ""
        echo "**Generated**: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "**Report ID**: ${TIMESTAMP}"
        echo "**Test Mode**: deploy-benchmark"
        echo "**Networks**: ${NETWORKS[*]}"
        if $WARM_CLUSTER; then
            echo "**Run Type**: Warm Cluster (dependencies pre-installed, cluster persists between runs)"
        elif $CLEAN_MODE; then
            echo "**Run Type**: Clean (full developer journey — npm install, compile, startup, benchmark)"
        else
            echo "**Run Type**: Warm (network startup + benchmark only)"
        fi
        echo ""
        echo "---"
        echo ""

        # ── Executive Summary ──
        echo "## Executive Summary"
        echo ""
        echo "| Network | Passed | Failed | Total | Pass Rate | Status |"
        echo "|---------|--------|--------|-------|-----------|--------|"
        for label in "${RUN_LIST[@]}"; do
            local passed failed total status rate
            passed=$(kv_get NET_PASSED "$label" "0")
            failed=$(kv_get NET_FAILED "$label" "0")
            total=$(kv_get NET_TOTAL "$label" "0")
            status=$(kv_get NET_STATUS "$label" "SKIP")
            rate="N/A"
            if [ "$total" -gt 0 ]; then
                rate="$(echo "scale=1; $passed * 100 / $total" | bc)%"
            fi
            echo "| $(display_name "$label") | ${passed} | ${failed} | ${total} | ${rate} | ${status} |"
        done
        echo ""
        echo "---"
        echo ""

        # ── Timing Results Table ──
        echo "## Timing Results"
        echo ""

        # Build header
        local header="| Stage |"
        local separator="|-------|"
        for label in "${RUN_LIST[@]}"; do
            header="${header} $(display_name "$label") |"
            separator="${separator}------|"
        done
        echo "$header"
        echo "$separator"

        # Infrastructure stages (clean mode only)
        if $CLEAN_MODE; then
            # npm install row
            local row="| npm install |"
            for label in "${RUN_LIST[@]}"; do
                local value
                value=$(timing_for "$label" "npm_install")
                row="${row} ${value} |"
            done
            echo "$row"

            # Tooling check row (only if anvil is in the run list)
            local has_tooling=false
            for label in "${RUN_LIST[@]}"; do
                if [ "$(net_name "$label")" = "anvil" ]; then has_tooling=true; break; fi
            done
            if $has_tooling; then
                row="| Tooling check |"
                for label in "${RUN_LIST[@]}"; do
                    if [ "$(net_name "$label")" = "anvil" ]; then
                        local value
                        value=$(timing_for "$label" "tooling_check")
                        row="${row} ${value} |"
                    else
                        row="${row} — |"
                    fi
                done
                echo "$row"
            fi

            # Compile row
            row="| Compile contracts |"
            for label in "${RUN_LIST[@]}"; do
                local value
                value=$(timing_for "$label" "compile")
                row="${row} ${value} |"
            done
            echo "$row"
        fi

        # Network startup row
        local row="| Network startup |"
        for label in "${RUN_LIST[@]}"; do
            local value
            local real_net
            real_net=$(net_name "$label")
            if [ "$real_net" = "hedera_testnet" ]; then
                value="N/A (remote)"
            else
                value=$(timing_for "$label" "startup")
            fi
            row="${row} ${value} |"
        done
        echo "$row"

        # Contract benchmark steps (parsed from test output)
        local steps=("Deploy contract" "Write (increment)" "Read (count)" "Event verification" "Write (setCount)" "Final read")
        for step in "${steps[@]}"; do
            local row="| ${step} |"
            for label in "${RUN_LIST[@]}"; do
                local output_file="${TEMP_DIR}/benchmark_${label}.txt"
                local value
                value=$(parse_benchmark_output "$output_file" "$step")
                row="${row} ${value} |"
            done
            echo "$row"
        done

        # Contract ops total row
        row="| **Contract ops total** |"
        for label in "${RUN_LIST[@]}"; do
            local output_file="${TEMP_DIR}/benchmark_${label}.txt"
            local value
            value=$(parse_benchmark_output "$output_file" "TOTAL")
            row="${row} **${value}** |"
        done
        echo "$row"

        # Network shutdown row
        row="| Network shutdown |"
        for label in "${RUN_LIST[@]}"; do
            local real_net
            real_net=$(net_name "$label")
            if [ "$real_net" = "hedera_testnet" ]; then
                row="${row} — |"
            else
                local value
                value=$(timing_for "$label" "shutdown")
                row="${row} ${value} |"
            fi
        done
        echo "$row"

        echo ""
        echo "---"
        echo ""

        # ── Per-Network Details ──
        for label in "${RUN_LIST[@]}"; do
            local real_net
            real_net=$(net_name "$label")
            echo "## $(display_name "$label")"
            echo ""
            local output_file="${TIMING_DATA_DIR}/${label}-benchmark-output.txt"
            local passed failed status
            passed=$(kv_get NET_PASSED "$label" "0")
            failed=$(kv_get NET_FAILED "$label" "0")
            status=$(kv_get NET_STATUS "$label" "SKIP")
            echo "**Status**: ${status} (${passed} passed, ${failed} failed)"
            echo ""

            # Show per-step timings from this network
            echo "### Contract Operations"
            echo ""
            echo "| Step | Duration |"
            echo "|------|----------|"
            for step in "${steps[@]}"; do
                local value
                value=$(parse_benchmark_output "$output_file" "$step")
                echo "| ${step} | ${value} |"
            done
            local total_val
            total_val=$(parse_benchmark_output "$output_file" "TOTAL")
            echo "| **TOTAL** | **${total_val}** |"
            echo ""

            # Show orchestrator timing phases
            echo "### Orchestrator Timing"
            echo ""
            echo "| Phase | Duration |"
            echo "|-------|----------|"
            if $CLEAN_MODE; then
                local npm_val compile_val
                npm_val=$(timing_for "$label" "npm_install")
                compile_val=$(timing_for "$label" "compile")
                echo "| npm install | ${npm_val} |"
                if [ "$real_net" = "anvil" ]; then
                    local tool_val
                    tool_val=$(timing_for "$label" "tooling_check")
                    echo "| Tooling check | ${tool_val} |"
                fi
                echo "| Compile | ${compile_val} |"
            fi
            local startup_val benchmark_val shutdown_val
            if [ "$real_net" = "hedera_testnet" ]; then
                startup_val="N/A (remote)"
            else
                startup_val=$(timing_for "$label" "startup")
            fi
            benchmark_val=$(timing_for "$label" "benchmark")
            echo "| Network startup | ${startup_val} |"
            echo "| Benchmark run | ${benchmark_val} |"
            if [ "$real_net" != "hedera_testnet" ]; then
                shutdown_val=$(timing_for "$label" "shutdown")
                echo "| Shutdown | ${shutdown_val} |"
            fi
            echo ""

            # Show failed tests if any
            if [ "$failed" -gt 0 ] && [ -f "$output_file" ]; then
                echo "### Failed Tests"
                echo ""
                echo '```'
                grep -E "^\s+[0-9]+\)" "$output_file" 2>/dev/null || true
                echo '```'
                echo ""
            fi

            echo "---"
            echo ""
        done

        # ── Environment ──
        echo "## Environment"
        echo ""
        echo "- **OS**: $(uname -s) $(uname -r)"
        echo "- **Architecture**: $(uname -m)"
        echo "- **Node.js**: $(node --version 2>/dev/null || echo 'N/A')"
        echo "- **Docker**: $(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'N/A')"
        if command -v solo &>/dev/null; then
            echo "- **Solo**: $(solo --version 2>/dev/null | grep -oE 'Version[[:space:]]*:[[:space:]]*[0-9.]+' | head -1 || echo 'installed')"
        fi
        if command -v anvil &>/dev/null; then
            echo "- **Anvil**: $(anvil --version 2>/dev/null | head -1 || echo 'installed')"
        fi
        echo ""
        echo "---"
        echo ""
        echo "*Report generated by run-deploy-benchmark.sh*"
        echo ""
        echo "Timing data: \`${TIMESTAMP}_timing-data/\`"
    } > "$report_file"

    echo -e "${GREEN}Report saved to: ${report_file}${NC}"
    echo -e "${GREEN}Timing data saved to: ${TIMING_DATA_DIR}/${NC}"
}

# ============================================================================
# Main
# ============================================================================

OVERALL_START=$(date +%s)

for label in "${RUN_LIST[@]}"; do
    run_benchmark "$label" || true
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
