#!/bin/bash
#
# Generate comprehensive test report with timing data
# Usage: ./scripts/generate-report.sh [hardhat_output] [foundry_output] [network]
#
# Can also be called with environment variables:
#   HARDHAT_OUTPUT_FILE - path to hardhat test output
#   FOUNDRY_OUTPUT_FILE - path to foundry test output
#   NETWORK - "localnode" or "solo"
#   REPORT_NAME - optional custom report name
#   TIMING_OUTPUT_DIR - directory containing timing JSON files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="${PROJECT_ROOT}/reports"

# Parse arguments or use environment variables
HARDHAT_OUTPUT="${1:-$HARDHAT_OUTPUT_FILE}"
FOUNDRY_OUTPUT="${2:-$FOUNDRY_OUTPUT_FILE}"
NETWORK="${3:-$NETWORK}"
REPORT_NAME="${REPORT_NAME:-}"
TIMING_OUTPUT_DIR="${TIMING_OUTPUT_DIR:-}"

# Generate timestamp
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DATE_HUMAN=$(date +"%Y-%m-%d %H:%M:%S %Z")

# Generate report filename
if [ -n "$REPORT_NAME" ]; then
    REPORT_FILE="${REPORTS_DIR}/${TIMESTAMP}_${REPORT_NAME}.md"
else
    REPORT_FILE="${REPORTS_DIR}/${TIMESTAMP}_test-report.md"
fi

# Ensure reports directory exists
mkdir -p "$REPORTS_DIR"

# Function to extract test counts from Hardhat output
extract_hardhat_stats() {
    local output_file="$1"
    if [ -f "$output_file" ]; then
        local passing=$(grep -oE '[0-9]+ passing' "$output_file" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "0")
        local failing=$(grep -oE '[0-9]+ failing' "$output_file" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "0")
        local pending=$(grep -oE '[0-9]+ pending' "$output_file" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "0")
        local duration=$(grep -oE '[0-9]+m|[0-9]+s' "$output_file" 2>/dev/null | tail -1 || echo "N/A")
        echo "$passing|$failing|$pending|$duration"
    else
        echo "0|0|0|N/A"
    fi
}

# Function to extract test counts from Foundry output
extract_foundry_stats() {
    local output_file="$1"
    if [ -f "$output_file" ]; then
        local summary=$(grep -E '[0-9]+ tests passed' "$output_file" 2>/dev/null | tail -1)
        local passing=$(echo "$summary" | grep -oE '[0-9]+ tests passed' | grep -oE '^[0-9]+' || echo "0")
        local failing=$(echo "$summary" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo "0")
        local skipped=$(echo "$summary" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' || echo "0")
        local total=$(grep -oE '[0-9]+ total tests' "$output_file" 2>/dev/null | tail -1 | grep -oE '[0-9]+' || echo "0")
        echo "$passing|$failing|$skipped|$total"
    else
        echo "0|0|0|0"
    fi
}

# Function to extract failed test names from Hardhat
extract_hardhat_failures() {
    local output_file="$1"
    if [ -f "$output_file" ]; then
        grep -E '^\s+[0-9]+\)' "$output_file" 2>/dev/null | sed 's/^[[:space:]]*//' || echo "None"
    else
        echo "No output file"
    fi
}

# Function to extract failed test names from Foundry
extract_foundry_failures() {
    local output_file="$1"
    if [ -f "$output_file" ]; then
        grep -E '^\[FAIL' "$output_file" 2>/dev/null | head -20 || echo "None"
    else
        echo "No output file"
    fi
}

# Function to calculate pass rate
calc_pass_rate() {
    local passed=$1
    local failed=$2
    local total=$((passed + failed))
    if [ $total -gt 0 ]; then
        echo "scale=1; $passed * 100 / $total" | bc
    else
        echo "0"
    fi
}

# Get system info
get_system_info() {
    echo "- **OS**: $(uname -s) $(uname -r)"
    echo "- **Architecture**: $(uname -m)"
    echo "- **Node.js**: $(node -v 2>/dev/null || echo 'Not found')"
    echo "- **Docker**: $(docker -v 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'Not found')"
    if command -v forge &> /dev/null; then
        echo "- **Foundry**: $(forge --version 2>/dev/null | head -1 || echo 'Not found')"
    fi
    if command -v solo &> /dev/null; then
        echo "- **Solo**: $(solo --version 2>/dev/null || echo 'Not found')"
    fi
    if command -v hedera &> /dev/null; then
        echo "- **Hedera Local**: $(hedera --version 2>/dev/null || echo 'Not found')"
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

# Add timing section to the report
add_timing_section() {
    local timing_dir="$1"

    if [ -z "$timing_dir" ] || [ ! -d "$timing_dir" ]; then
        return
    fi

    echo ""
    echo "---"
    echo ""
    echo "## Startup Timing"
    echo ""

    # Look for timing files
    local ln_timing="${timing_dir}/localnode-timing.json"
    local solo_timing="${timing_dir}/solo-timing.json"
    local ln_first_tx="${timing_dir}/localnode-first-tx.json"
    local solo_first_tx="${timing_dir}/solo-first-tx.json"
    local solo_mirror="${timing_dir}/solo-mirror-sync.json"
    local solo_components="${timing_dir}/solo-components.json"

    # Extract timing values
    local ln_total="N/A"
    local ln_first="N/A"
    local solo_total="N/A"
    local solo_first="N/A"
    local solo_mir="N/A"

    if [ -f "$ln_timing" ]; then
        ln_total=$(parse_timing_json "$ln_timing" "localnode_total")
    fi

    if [ -f "$ln_first_tx" ]; then
        ln_first=$(parse_timing_json "$ln_first_tx" "localnode_first_tx")
    fi

    if [ -f "$solo_timing" ]; then
        solo_total=$(parse_timing_json "$solo_timing" "solo_total")
    fi

    if [ -f "$solo_first_tx" ]; then
        solo_first=$(parse_timing_json "$solo_first_tx" "solo_first_tx")
    fi

    if [ -f "$solo_mirror" ]; then
        solo_mir=$(parse_timing_json "$solo_mirror" "solo_mirror_sync")
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

    echo "### Startup Timing Summary"
    echo ""
    echo "| Metric | Local Node | Solo | Ratio |"
    echo "|--------|------------|------|-------|"
    echo "| Total Startup | ${ln_total} | ${solo_total} | ${ratio} |"
    echo "| Time to First TX | ${ln_first} | ${solo_first} | - |"
    echo "| Mirror Node Sync | N/A | ${solo_mir} | - |"
    echo ""

    # Add Local Node breakdown if available
    if [ -f "$ln_timing" ]; then
        echo "### Local Node Breakdown"
        echo ""
        echo "| Phase | Duration | % of Total |"
        echo "|-------|----------|------------|"

        local total_ms=$(grep -A3 '"localnode_total":' "$ln_timing" 2>/dev/null | grep "duration_ms" | grep -oE '[0-9]+' | head -1)
        [ -z "$total_ms" ] && total_ms=1

        for phase in localnode_preflight localnode_docker_check localnode_start localnode_health_wait; do
            local duration_ms=$(grep -A3 "\"$phase\":" "$ln_timing" 2>/dev/null | grep "duration_ms" | grep -oE '[0-9]+' | head -1)
            if [ -n "$duration_ms" ]; then
                local duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc)
                local pct=$(echo "scale=1; $duration_ms * 100 / $total_ms" | bc)
                local phase_name=$(echo "$phase" | sed 's/localnode_//' | sed 's/_/ /g')
                echo "| ${phase_name^} | ${duration_sec}s | ${pct}% |"
            fi
        done
        echo ""
    fi

    # Add Solo breakdown if available
    if [ -f "$solo_timing" ]; then
        echo "### Solo Breakdown"
        echo ""
        echo "| Phase | Duration | % of Total |"
        echo "|-------|----------|------------|"

        local total_ms=$(grep -A3 '"solo_total":' "$solo_timing" 2>/dev/null | grep "duration_ms" | grep -oE '[0-9]+' | head -1)
        [ -z "$total_ms" ] && total_ms=1

        for phase in solo_preflight solo_kind_cluster solo_deploy solo_health_wait; do
            local duration_ms=$(grep -A3 "\"$phase\":" "$solo_timing" 2>/dev/null | grep "duration_ms" | grep -oE '[0-9]+' | head -1)
            if [ -n "$duration_ms" ]; then
                local duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc)
                local pct=$(echo "scale=1; $duration_ms * 100 / $total_ms" | bc)
                local phase_name=$(echo "$phase" | sed 's/solo_//' | sed 's/_/ /g')
                echo "| ${phase_name^} | ${duration_sec}s | ${pct}% |"
            fi
        done
        echo ""
    fi

    # Add Solo component breakdown if available
    if [ -f "$solo_components" ]; then
        echo "### Solo Component Breakdown (from deploy output)"
        echo ""
        echo "| Component | Duration | % of Total |"
        echo "|-----------|----------|------------|"

        local total_ms=$(grep '"total_parsed_ms":' "$solo_components" 2>/dev/null | grep -oE '[0-9]+' | head -1)
        [ -z "$total_ms" ] && total_ms=1

        local in_tasks=false
        local current_name=""

        while IFS= read -r line; do
            if echo "$line" | grep -q '"tasks":'; then
                in_tasks=true
                continue
            fi

            if [ "$in_tasks" = true ]; then
                if echo "$line" | grep -q '"name":'; then
                    current_name=$(echo "$line" | grep -oE '"name": "[^"]+"' | cut -d'"' -f4)
                fi

                if echo "$line" | grep -q '"duration_ms":'; then
                    local duration_ms=$(echo "$line" | grep -oE '[0-9]+')
                    if [ -n "$current_name" ] && [ -n "$duration_ms" ]; then
                        local duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc)
                        local pct=$(echo "scale=1; $duration_ms * 100 / $total_ms" | bc)
                        echo "| ${current_name} | ${duration_sec}s | ${pct}% |"
                    fi
                    current_name=""
                fi

                if echo "$line" | grep -q '^  },'; then
                    in_tasks=false
                fi
            fi
        done < "$solo_components"
        echo ""
    fi
}

# Start generating report
cat > "$REPORT_FILE" << 'HEADER'
# Hedera EVM Lab - Test Report

HEADER

echo "**Generated**: ${DATE_HUMAN}" >> "$REPORT_FILE"
echo "**Report ID**: ${TIMESTAMP}" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Add network info if provided
if [ -n "$NETWORK" ]; then
    echo "**Network**: ${NETWORK}" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Executive Summary
echo "## Executive Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# If we have output files, parse them
if [ -f "$HARDHAT_OUTPUT" ] || [ -f "$FOUNDRY_OUTPUT" ]; then
    echo "| Framework | Network | Passed | Failed | Total | Pass Rate |" >> "$REPORT_FILE"
    echo "|-----------|---------|--------|--------|-------|-----------|" >> "$REPORT_FILE"

    if [ -f "$HARDHAT_OUTPUT" ]; then
        IFS='|' read -r h_pass h_fail h_pend h_dur <<< "$(extract_hardhat_stats "$HARDHAT_OUTPUT")"
        h_total=$((h_pass + h_fail))
        h_rate=$(calc_pass_rate $h_pass $h_fail)
        echo "| Hardhat | ${NETWORK:-unknown} | ${h_pass} | ${h_fail} | ${h_total} | ${h_rate}% |" >> "$REPORT_FILE"
    fi

    if [ -f "$FOUNDRY_OUTPUT" ]; then
        IFS='|' read -r f_pass f_fail f_skip f_total <<< "$(extract_foundry_stats "$FOUNDRY_OUTPUT")"
        f_rate=$(calc_pass_rate $f_pass $f_fail)
        echo "| Foundry | ${NETWORK:-unknown} | ${f_pass} | ${f_fail} | ${f_total} | ${f_rate}% |" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
fi

# Add timing section if timing data is available
if [ -n "$TIMING_OUTPUT_DIR" ] && [ -d "$TIMING_OUTPUT_DIR" ]; then
    add_timing_section "$TIMING_OUTPUT_DIR" >> "$REPORT_FILE"
fi

# System Information
echo "## Environment" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
get_system_info >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Detailed Results - Hardhat
if [ -f "$HARDHAT_OUTPUT" ]; then
    echo "## Hardhat Test Results" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    IFS='|' read -r h_pass h_fail h_pend h_dur <<< "$(extract_hardhat_stats "$HARDHAT_OUTPUT")"

    echo "### Summary" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "- **Passing**: ${h_pass}" >> "$REPORT_FILE"
    echo "- **Failing**: ${h_fail}" >> "$REPORT_FILE"
    echo "- **Duration**: ${h_dur}" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    if [ "$h_fail" -gt 0 ]; then
        echo "### Failed Tests" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        extract_hardhat_failures "$HARDHAT_OUTPUT" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
fi

# Detailed Results - Foundry
if [ -f "$FOUNDRY_OUTPUT" ]; then
    echo "## Foundry Test Results" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    IFS='|' read -r f_pass f_fail f_skip f_total <<< "$(extract_foundry_stats "$FOUNDRY_OUTPUT")"

    echo "### Summary" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "- **Passing**: ${f_pass}" >> "$REPORT_FILE"
    echo "- **Failing**: ${f_fail}" >> "$REPORT_FILE"
    echo "- **Skipped**: ${f_skip}" >> "$REPORT_FILE"
    echo "- **Total**: ${f_total}" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    if [ "$f_fail" -gt 0 ]; then
        echo "### Failed Tests" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        extract_foundry_failures "$FOUNDRY_OUTPUT" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
fi

echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "*Report generated by hedera-evm-lab test framework*" >> "$REPORT_FILE"

echo "Report generated: $REPORT_FILE"
