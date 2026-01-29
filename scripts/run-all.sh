#!/usr/bin/env bash
# Run all smoke tests against Local Node and/or Solo
# Usage: ./run-all.sh [localnode|solo|both]
#
# IMPORTANT: Local Node and Solo share port 7546 (JSON-RPC relay).
# They cannot run simultaneously. This script handles the sequencing.
#
# Reports are automatically generated in the reports/ directory.
# Timing instrumentation is enabled by default.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="${PROJECT_ROOT}/reports"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MODE="${1:-localnode}"

# Create temp directory for test outputs and timing data
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Timing configuration
export TIMING_ENABLED="true"
export TIMING_OUTPUT_DIR="${TEMP_DIR}/timing"
mkdir -p "$TIMING_OUTPUT_DIR"

# Source timing library for first-tx and mirror-sync measurements
if [ -f "${SCRIPT_DIR}/lib/timing.sh" ]; then
    source "${SCRIPT_DIR}/lib/timing.sh"
fi

# Output files
HARDHAT_LN_OUTPUT="${TEMP_DIR}/hardhat_localnode.txt"
FOUNDRY_LN_OUTPUT="${TEMP_DIR}/foundry_localnode.txt"
HARDHAT_SOLO_OUTPUT="${TEMP_DIR}/hardhat_solo.txt"
FOUNDRY_SOLO_OUTPUT="${TEMP_DIR}/foundry_solo.txt"

# Timing JSON files
LOCALNODE_TIMING_JSON="${TIMING_OUTPUT_DIR}/localnode-timing.json"
SOLO_TIMING_JSON="${TIMING_OUTPUT_DIR}/solo-timing.json"
SOLO_COMPONENTS_JSON="${TIMING_OUTPUT_DIR}/solo-components.json"
COMBINED_TIMING_JSON="${TIMING_OUTPUT_DIR}/combined-timing.json"

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Hedera EVM Lab - Full Test Suite${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "Timing output directory: $TIMING_OUTPUT_DIR"
echo ""

# Measure first transaction time
# Arguments:
#   $1 - network name (localnode, solo)
#   $2 - RPC URL (default: http://127.0.0.1:7546)
measure_first_transaction() {
    local network="$1"
    local rpc_url="${2:-http://127.0.0.1:7546}"

    echo -e "${CYAN}Measuring first transaction time for ${network}...${NC}"

    # Initialize timing for this measurement
    timing_init "$network"

    if timing_measure_first_tx "$rpc_url"; then
        local duration=$(timing_get_duration_formatted "${network}_first_tx")
        echo -e "${GREEN}First TX completed in ${duration}${NC}"
    else
        echo -e "${YELLOW}First TX measurement failed${NC}"
    fi

    # Append to the network's timing JSON
    local timing_file="${TIMING_OUTPUT_DIR}/${network}-first-tx.json"
    timing_export_json "$timing_file"
}

# Measure mirror node sync time (Solo only)
# Arguments:
#   $1 - mirror node REST URL
#   $2 - max wait time in seconds
measure_mirror_sync() {
    local mirror_url="${1:-http://localhost:8081/api/v1}"
    local max_wait="${2:-300}"

    echo -e "${CYAN}Measuring mirror node sync time...${NC}"

    timing_init "solo"

    if timing_measure_mirror_sync "$mirror_url" "$max_wait"; then
        local duration=$(timing_get_duration_formatted "solo_mirror_sync")
        echo -e "${GREEN}Mirror sync completed in ${duration}${NC}"
    else
        echo -e "${YELLOW}Mirror sync timed out${NC}"
    fi

    # Export mirror sync timing
    local timing_file="${TIMING_OUTPUT_DIR}/solo-mirror-sync.json"
    timing_export_json "$timing_file"
}

run_tests_against_localnode() {
    echo -e "${CYAN}=== Testing with Hiero Local Node ===${NC}"
    echo ""

    # Start Local Node (with timing enabled via environment)
    echo "Starting Local Node..."
    export TIMING_FILE="${LOCALNODE_TIMING_JSON}"
    "$SCRIPT_DIR/start-local-node.sh"
    echo ""

    # Wait a bit for full initialization
    echo "Waiting for network to stabilize..."
    sleep 10

    # Measure first transaction time
    measure_first_transaction "localnode" "http://127.0.0.1:7546"

    # Run Hardhat tests (capture output)
    echo ""
    "$SCRIPT_DIR/run-hardhat-smoke.sh" localnode 2>&1 | tee "$HARDHAT_LN_OUTPUT" || HARDHAT_FAILED=1

    # Run Foundry tests (capture output)
    echo ""
    "$SCRIPT_DIR/run-foundry-smoke.sh" --fork 2>&1 | tee "$FOUNDRY_LN_OUTPUT" || FOUNDRY_FAILED=1

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
        echo "Install with: brew tap hiero-ledger/tools && brew install solo"
        return 1
    fi

    # Start Solo (with timing enabled via environment)
    echo "Starting Solo..."
    export TIMING_FILE="${SOLO_TIMING_JSON}"
    "$SCRIPT_DIR/start-solo.sh"
    echo ""

    # Wait for Solo to be fully ready
    echo "Waiting for Solo network to stabilize..."
    sleep 30

    # Measure first transaction time
    measure_first_transaction "solo" "http://127.0.0.1:7546"

    # Measure mirror node sync time (Solo-specific)
    measure_mirror_sync "http://localhost:8081/api/v1" 300

    # Run Hardhat tests (capture output)
    echo ""
    "$SCRIPT_DIR/run-hardhat-smoke.sh" solo 2>&1 | tee "$HARDHAT_SOLO_OUTPUT" || HARDHAT_FAILED=1

    # Run Foundry tests (capture output)
    echo ""
    "$SCRIPT_DIR/run-foundry-smoke.sh" --fork 2>&1 | tee "$FOUNDRY_SOLO_OUTPUT" || FOUNDRY_FAILED=1

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

# Combine all timing data into a single JSON file
combine_timing_data() {
    echo -e "${CYAN}Combining timing data...${NC}"

    local output="$COMBINED_TIMING_JSON"

    {
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"report_id\": \"$TIMESTAMP\","
        echo "  \"mode\": \"$MODE\","

        # Local Node timing
        if [ -f "$LOCALNODE_TIMING_JSON" ]; then
            echo "  \"localnode\": $(cat "$LOCALNODE_TIMING_JSON"),"
        fi

        # Local Node first TX timing
        if [ -f "${TIMING_OUTPUT_DIR}/localnode-first-tx.json" ]; then
            echo "  \"localnode_first_tx\": $(cat "${TIMING_OUTPUT_DIR}/localnode-first-tx.json"),"
        fi

        # Solo timing
        if [ -f "$SOLO_TIMING_JSON" ]; then
            echo "  \"solo\": $(cat "$SOLO_TIMING_JSON"),"
        fi

        # Solo components timing
        if [ -f "$SOLO_COMPONENTS_JSON" ]; then
            echo "  \"solo_components\": $(cat "$SOLO_COMPONENTS_JSON"),"
        fi

        # Solo first TX timing
        if [ -f "${TIMING_OUTPUT_DIR}/solo-first-tx.json" ]; then
            echo "  \"solo_first_tx\": $(cat "${TIMING_OUTPUT_DIR}/solo-first-tx.json"),"
        fi

        # Solo mirror sync timing
        if [ -f "${TIMING_OUTPUT_DIR}/solo-mirror-sync.json" ]; then
            echo "  \"solo_mirror_sync\": $(cat "${TIMING_OUTPUT_DIR}/solo-mirror-sync.json"),"
        fi

        echo "  \"_end\": true"
        echo "}"
    } > "$output"

    echo "Combined timing data saved to: $output"
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

# Combine timing data before report generation
combine_timing_data

# Generate comprehensive report
echo -e "${CYAN}=== Generating Test Report ===${NC}"
REPORT_FILE="${REPORTS_DIR}/${TIMESTAMP}_${MODE}-test-report.md"
mkdir -p "$REPORTS_DIR"

# Export timing files to reports directory for debugging
cp -r "$TIMING_OUTPUT_DIR" "${REPORTS_DIR}/${TIMESTAMP}_timing-data" 2>/dev/null || true

generate_report() {
    local report_file="$1"
    local date_human=$(date +"%Y-%m-%d %H:%M:%S %Z")

    cat > "$report_file" << EOF
# Hedera EVM Lab - Test Report

**Generated**: ${date_human}
**Report ID**: ${TIMESTAMP}
**Test Mode**: ${MODE}

---

## Executive Summary

| Framework | Network | Passed | Failed | Total | Pass Rate |
|-----------|---------|--------|--------|-------|-----------|
EOF

    # Extract stats from Local Node outputs
    if [ -f "$HARDHAT_LN_OUTPUT" ]; then
        local h_pass=$(grep -oE '[0-9]+ passing' "$HARDHAT_LN_OUTPUT" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "0")
        local h_fail=$(grep -oE '[0-9]+ failing' "$HARDHAT_LN_OUTPUT" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "0")
        local h_total=$((h_pass + h_fail))
        local h_rate=0
        [ $h_total -gt 0 ] && h_rate=$(echo "scale=1; $h_pass * 100 / $h_total" | bc)
        echo "| Hardhat | Local Node | ${h_pass} | ${h_fail} | ${h_total} | ${h_rate}% |" >> "$report_file"
    fi

    if [ -f "$FOUNDRY_LN_OUTPUT" ]; then
        local f_summary=$(grep -E '[0-9]+ tests passed' "$FOUNDRY_LN_OUTPUT" 2>/dev/null | tail -1)
        local f_pass=$(echo "$f_summary" | grep -oE '[0-9]+ tests passed' | grep -oE '^[0-9]+' || echo "0")
        local f_fail=$(echo "$f_summary" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo "0")
        local f_total=$((f_pass + f_fail))
        local f_rate=0
        [ $f_total -gt 0 ] && f_rate=$(echo "scale=1; $f_pass * 100 / $f_total" | bc)
        echo "| Foundry | Local Node | ${f_pass} | ${f_fail} | ${f_total} | ${f_rate}% |" >> "$report_file"
    fi

    # Extract stats from Solo outputs
    if [ -f "$HARDHAT_SOLO_OUTPUT" ]; then
        local h_pass=$(grep -oE '[0-9]+ passing' "$HARDHAT_SOLO_OUTPUT" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "0")
        local h_fail=$(grep -oE '[0-9]+ failing' "$HARDHAT_SOLO_OUTPUT" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "0")
        local h_total=$((h_pass + h_fail))
        local h_rate=0
        [ $h_total -gt 0 ] && h_rate=$(echo "scale=1; $h_pass * 100 / $h_total" | bc)
        echo "| Hardhat | Solo | ${h_pass} | ${h_fail} | ${h_total} | ${h_rate}% |" >> "$report_file"
    fi

    if [ -f "$FOUNDRY_SOLO_OUTPUT" ]; then
        local f_summary=$(grep -E '[0-9]+ tests passed' "$FOUNDRY_SOLO_OUTPUT" 2>/dev/null | tail -1)
        local f_pass=$(echo "$f_summary" | grep -oE '[0-9]+ tests passed' | grep -oE '^[0-9]+' || echo "0")
        local f_fail=$(echo "$f_summary" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo "0")
        local f_total=$((f_pass + f_fail))
        local f_rate=0
        [ $f_total -gt 0 ] && f_rate=$(echo "scale=1; $f_pass * 100 / $f_total" | bc)
        echo "| Foundry | Solo | ${f_pass} | ${f_fail} | ${f_total} | ${f_rate}% |" >> "$report_file"
    fi

    # Add timing section
    add_timing_section "$report_file"

    cat >> "$report_file" << EOF

---

## Environment

- **OS**: $(uname -s) $(uname -r)
- **Architecture**: $(uname -m)
- **Node.js**: $(node -v 2>/dev/null || echo 'Not found')
- **Docker**: $(docker -v 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'Not found')
- **Foundry**: $(forge --version 2>/dev/null | head -1 || echo 'Not found')
- **Solo**: $(solo --version 2>/dev/null || echo 'Not found')

---

EOF

    # Add Hardhat Local Node details
    if [ -f "$HARDHAT_LN_OUTPUT" ]; then
        cat >> "$report_file" << EOF
## Hardhat - Local Node

### Failed Tests

\`\`\`
$(grep -E '^\s+[0-9]+\)' "$HARDHAT_LN_OUTPUT" 2>/dev/null | head -30 || echo "None")
\`\`\`

---

EOF
    fi

    # Add Foundry Local Node details
    if [ -f "$FOUNDRY_LN_OUTPUT" ]; then
        cat >> "$report_file" << EOF
## Foundry - Local Node

### Failed Tests

\`\`\`
$(grep -E '^\[FAIL' "$FOUNDRY_LN_OUTPUT" 2>/dev/null | head -20 || echo "None")
\`\`\`

---

EOF
    fi

    # Add Hardhat Solo details
    if [ -f "$HARDHAT_SOLO_OUTPUT" ]; then
        cat >> "$report_file" << EOF
## Hardhat - Solo

### Failed Tests

\`\`\`
$(grep -E '^\s+[0-9]+\)' "$HARDHAT_SOLO_OUTPUT" 2>/dev/null | head -30 || echo "None")
\`\`\`

---

EOF
    fi

    # Add Foundry Solo details
    if [ -f "$FOUNDRY_SOLO_OUTPUT" ]; then
        cat >> "$report_file" << EOF
## Foundry - Solo

### Failed Tests

\`\`\`
$(grep -E '^\[FAIL' "$FOUNDRY_SOLO_OUTPUT" 2>/dev/null | head -20 || echo "None")
\`\`\`

---

EOF
    fi

    cat >> "$report_file" << EOF
*Report generated by hedera-evm-lab test framework*
EOF
}

# Add timing section to the report
add_timing_section() {
    local report_file="$1"

    cat >> "$report_file" << EOF

---

## Startup Timing

EOF

    # Extract timing values from JSON files
    local ln_total="N/A"
    local ln_first_tx="N/A"
    local solo_total="N/A"
    local solo_first_tx="N/A"
    local solo_mirror="N/A"

    # Parse Local Node timing
    if [ -f "$LOCALNODE_TIMING_JSON" ]; then
        ln_total=$(parse_timing_json "$LOCALNODE_TIMING_JSON" "localnode_total")
    fi

    if [ -f "${TIMING_OUTPUT_DIR}/localnode-first-tx.json" ]; then
        ln_first_tx=$(parse_timing_json "${TIMING_OUTPUT_DIR}/localnode-first-tx.json" "localnode_first_tx")
    fi

    # Parse Solo timing
    if [ -f "$SOLO_TIMING_JSON" ]; then
        solo_total=$(parse_timing_json "$SOLO_TIMING_JSON" "solo_total")
    fi

    if [ -f "${TIMING_OUTPUT_DIR}/solo-first-tx.json" ]; then
        solo_first_tx=$(parse_timing_json "${TIMING_OUTPUT_DIR}/solo-first-tx.json" "solo_first_tx")
    fi

    if [ -f "${TIMING_OUTPUT_DIR}/solo-mirror-sync.json" ]; then
        solo_mirror=$(parse_timing_json "${TIMING_OUTPUT_DIR}/solo-mirror-sync.json" "solo_mirror_sync")
    fi

    # Calculate ratio if both values are available
    local ratio="N/A"
    if [ "$ln_total" != "N/A" ] && [ "$solo_total" != "N/A" ]; then
        local ln_ms=$(echo "$ln_total" | sed 's/s$//' | awk '{print $1 * 1000}')
        local solo_ms=$(echo "$solo_total" | sed 's/s$//' | awk '{print $1 * 1000}')
        if [ "$ln_ms" != "0" ]; then
            ratio=$(echo "scale=1; $solo_ms / $ln_ms" | bc 2>/dev/null || echo "N/A")
            [ "$ratio" != "N/A" ] && ratio="${ratio}x"
        fi
    fi

    cat >> "$report_file" << EOF
### Startup Timing Summary

| Metric | Local Node | Solo | Ratio |
|--------|------------|------|-------|
| Total Startup | ${ln_total} | ${solo_total} | ${ratio} |
| Time to First TX | ${ln_first_tx} | ${solo_first_tx} | - |
| Mirror Node Sync | N/A | ${solo_mirror} | - |

EOF

    # Add Local Node breakdown if available
    if [ -f "$LOCALNODE_TIMING_JSON" ]; then
        add_localnode_breakdown "$report_file"
    fi

    # Add Solo breakdown if available
    if [ -f "$SOLO_TIMING_JSON" ]; then
        add_solo_breakdown "$report_file"
    fi

    # Add Solo component breakdown if available
    if [ -f "$SOLO_COMPONENTS_JSON" ]; then
        add_solo_components_breakdown "$report_file"
    fi
}

# Parse a timing value from JSON (simplified parsing without jq)
parse_timing_json() {
    local json_file="$1"
    local phase="$2"

    if [ ! -f "$json_file" ]; then
        echo "N/A"
        return
    fi

    # Extract duration_ms for the given phase
    local duration_ms=$(grep -A3 "\"$phase\":" "$json_file" 2>/dev/null | grep "duration_ms" | grep -oE '[0-9]+' | head -1)

    if [ -n "$duration_ms" ]; then
        local duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc)
        echo "${duration_sec}s"
    else
        echo "N/A"
    fi
}

# Add Local Node phase breakdown
add_localnode_breakdown() {
    local report_file="$1"

    cat >> "$report_file" << EOF
### Local Node Breakdown

| Phase | Duration | % of Total |
|-------|----------|------------|
EOF

    local total_ms=$(grep -A3 '"localnode_total":' "$LOCALNODE_TIMING_JSON" 2>/dev/null | grep "duration_ms" | grep -oE '[0-9]+' | head -1)
    [ -z "$total_ms" ] && total_ms=1  # Avoid division by zero

    for phase in localnode_preflight localnode_docker_check localnode_start localnode_health_wait; do
        local duration_ms=$(grep -A3 "\"$phase\":" "$LOCALNODE_TIMING_JSON" 2>/dev/null | grep "duration_ms" | grep -oE '[0-9]+' | head -1)
        if [ -n "$duration_ms" ]; then
            local duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc)
            local pct=$(echo "scale=1; $duration_ms * 100 / $total_ms" | bc)
            local phase_name=$(echo "$phase" | sed 's/localnode_//' | sed 's/_/ /g')
            local phase_cap=$(echo "$phase_name" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
            echo "| ${phase_cap} | ${duration_sec}s | ${pct}% |" >> "$report_file"
        fi
    done

    echo "" >> "$report_file"
}

# Add Solo phase breakdown
add_solo_breakdown() {
    local report_file="$1"

    cat >> "$report_file" << EOF
### Solo Breakdown

| Phase | Duration | % of Total |
|-------|----------|------------|
EOF

    local total_ms=$(grep -A3 '"solo_total":' "$SOLO_TIMING_JSON" 2>/dev/null | grep "duration_ms" | grep -oE '[0-9]+' | head -1)
    [ -z "$total_ms" ] && total_ms=1  # Avoid division by zero

    for phase in solo_preflight solo_kind_cluster solo_deploy solo_health_wait; do
        local duration_ms=$(grep -A3 "\"$phase\":" "$SOLO_TIMING_JSON" 2>/dev/null | grep "duration_ms" | grep -oE '[0-9]+' | head -1)
        if [ -n "$duration_ms" ]; then
            local duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc)
            local pct=$(echo "scale=1; $duration_ms * 100 / $total_ms" | bc)
            local phase_name=$(echo "$phase" | sed 's/solo_//' | sed 's/_/ /g')
            local phase_cap=$(echo "$phase_name" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
            echo "| ${phase_cap} | ${duration_sec}s | ${pct}% |" >> "$report_file"
        fi
    done

    echo "" >> "$report_file"
}

# Add Solo component breakdown from parsed Listr2 output
add_solo_components_breakdown() {
    local report_file="$1"

    if [ ! -f "$SOLO_COMPONENTS_JSON" ]; then
        return
    fi

    cat >> "$report_file" << EOF
### Solo Component Breakdown (from deploy output)

| Component | Duration | % of Total |
|-----------|----------|------------|
EOF

    # Get total from the JSON
    local total_ms=$(grep '"total_parsed_ms":' "$SOLO_COMPONENTS_JSON" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    [ -z "$total_ms" ] && total_ms=1

    # Extract each task's timing
    # Look for lines with duration_ms in the tasks section
    local in_tasks=false
    local current_name=""

    while IFS= read -r line; do
        if echo "$line" | grep -q '"tasks":'; then
            in_tasks=true
            continue
        fi

        if [ "$in_tasks" = true ]; then
            # Check for task name
            if echo "$line" | grep -q '"name":'; then
                current_name=$(echo "$line" | grep -oE '"name": "[^"]+"' | cut -d'"' -f4)
            fi

            # Check for duration_ms
            if echo "$line" | grep -q '"duration_ms":'; then
                local duration_ms=$(echo "$line" | grep -oE '[0-9]+')
                if [ -n "$current_name" ] && [ -n "$duration_ms" ]; then
                    local duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc)
                    local pct=$(echo "scale=1; $duration_ms * 100 / $total_ms" | bc)
                    echo "| ${current_name} | ${duration_sec}s | ${pct}% |" >> "$report_file"
                fi
                current_name=""
            fi

            # End of tasks section
            if echo "$line" | grep -q '^  },'; then
                in_tasks=false
            fi
        fi
    done < "$SOLO_COMPONENTS_JSON"

    echo "" >> "$report_file"
}

generate_report "$REPORT_FILE"
echo -e "${GREEN}Report saved to: ${REPORT_FILE}${NC}"
echo ""

if [ "$LOCALNODE_RESULT" = "0" ] && [ "$SOLO_RESULT" = "0" ]; then
    echo -e "${GREEN}=== ALL TESTS PASSED ===${NC}"
    exit 0
else
    echo -e "${RED}=== SOME TESTS FAILED ===${NC}"
    exit 1
fi
