#!/usr/bin/env bash
# Run all smoke tests against Local Node and/or Solo
# Usage: ./run-all.sh [localnode|solo|both]
#
# IMPORTANT: Local Node and Solo share port 7546 (JSON-RPC relay).
# They cannot run simultaneously. This script handles the sequencing.
#
# Reports are automatically generated in the reports/ directory.

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

# Create temp directory for test outputs
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Output files
HARDHAT_LN_OUTPUT="${TEMP_DIR}/hardhat_localnode.txt"
FOUNDRY_LN_OUTPUT="${TEMP_DIR}/foundry_localnode.txt"
HARDHAT_SOLO_OUTPUT="${TEMP_DIR}/hardhat_solo.txt"
FOUNDRY_SOLO_OUTPUT="${TEMP_DIR}/foundry_solo.txt"

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

    # Start Solo
    echo "Starting Solo..."
    "$SCRIPT_DIR/start-solo.sh"
    echo ""

    # Wait for Solo to be fully ready
    echo "Waiting for Solo network to stabilize..."
    sleep 30

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

# Generate comprehensive report
echo -e "${CYAN}=== Generating Test Report ===${NC}"
REPORT_FILE="${REPORTS_DIR}/${TIMESTAMP}_${MODE}-test-report.md"
mkdir -p "$REPORTS_DIR"

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
