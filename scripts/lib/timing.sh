#!/usr/bin/env bash
# Timing instrumentation library for Hedera EVM Lab
# Provides millisecond-precision timing for environment startup measurements
# Compatible with bash 3.x (macOS default)
#
# Usage:
#   source scripts/lib/timing.sh
#   timing_init "localnode"
#   timing_start "preflight"
#   # ... do work ...
#   timing_end "preflight"
#   timing_export_json "/path/to/output.json"

# Ensure we don't source this multiple times
if [ -n "${_TIMING_LIB_LOADED:-}" ]; then
    return 0
fi
_TIMING_LIB_LOADED=1

# Global variables
TIMING_NETWORK=""
TIMING_RUN_START=""
TIMING_FILE="${TIMING_FILE:-}"
TIMING_OUTPUT_DIR="${TIMING_OUTPUT_DIR:-}"
TIMING_DATA_FILE=""

# Get current time in milliseconds (macOS compatible)
timing_now_ms() {
    if command -v perl &> /dev/null; then
        perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'
    elif command -v python3 &> /dev/null; then
        python3 -c 'import time; print(int(time.time() * 1000))'
    elif command -v gdate &> /dev/null; then
        echo $(($(gdate +%s%N)/1000000))
    else
        # Fallback to seconds precision
        echo $(($(date +%s) * 1000))
    fi
}

# Initialize timing for a run
# Arguments:
#   $1 - network name (localnode, solo)
timing_init() {
    local network="${1:-unknown}"
    TIMING_NETWORK="$network"
    TIMING_RUN_START=$(timing_now_ms)

    # Set default output directory if not set
    if [ -z "$TIMING_OUTPUT_DIR" ]; then
        TIMING_OUTPUT_DIR="${TMPDIR:-/tmp}/hedera-timing-$$"
        mkdir -p "$TIMING_OUTPUT_DIR"
    fi

    # Create data file for storing timing entries
    TIMING_DATA_FILE="${TIMING_OUTPUT_DIR}/${network}-timing-data.txt"
    : > "$TIMING_DATA_FILE"  # Clear/create the file

    # Set timing file path
    if [ -z "$TIMING_FILE" ]; then
        TIMING_FILE="${TIMING_OUTPUT_DIR}/${network}-timing.json"
    fi

    echo "Timing initialized for network: $network"
    echo "  Output directory: $TIMING_OUTPUT_DIR"
}

# Record the start of a phase
# Arguments:
#   $1 - phase name
timing_start() {
    local phase="$1"
    local now=$(timing_now_ms)
    echo "START|${phase}|${now}" >> "$TIMING_DATA_FILE"
    echo "[TIMING] Started: $phase at $(date '+%H:%M:%S')"
}

# Record the end of a phase and calculate duration
# Arguments:
#   $1 - phase name
timing_end() {
    local phase="$1"
    local now=$(timing_now_ms)

    # Find the start time for this phase
    local start_line=$(grep "^START|${phase}|" "$TIMING_DATA_FILE" 2>/dev/null | tail -1)
    if [ -n "$start_line" ]; then
        local start=$(echo "$start_line" | cut -d'|' -f3)
        local duration=$((now - start))
        echo "END|${phase}|${now}|${start}|${duration}" >> "$TIMING_DATA_FILE"
        local duration_sec=$(echo "scale=2; $duration / 1000" | bc)
        echo "[TIMING] Completed: $phase in ${duration_sec}s"
    else
        echo "[TIMING] Warning: No start time found for phase: $phase"
        echo "END|${phase}|${now}|0|0" >> "$TIMING_DATA_FILE"
    fi
}

# Get duration of a phase in milliseconds
# Arguments:
#   $1 - phase name
# Returns: duration in ms or empty if not available
timing_get_duration_ms() {
    local phase="$1"
    local end_line=$(grep "^END|${phase}|" "$TIMING_DATA_FILE" 2>/dev/null | tail -1)
    if [ -n "$end_line" ]; then
        echo "$end_line" | cut -d'|' -f5
    fi
}

# Get duration of a phase formatted as seconds
# Arguments:
#   $1 - phase name
# Returns: duration as formatted string (e.g., "45.2s")
timing_get_duration_formatted() {
    local phase="$1"
    local ms=$(timing_get_duration_ms "$phase")
    if [ -n "$ms" ] && [ "$ms" != "0" ]; then
        echo "$(echo "scale=1; $ms / 1000" | bc)s"
    else
        echo "N/A"
    fi
}

# Export all timing data to JSON
# Arguments:
#   $1 - output file path (optional, uses TIMING_FILE if not provided)
timing_export_json() {
    local output_file="${1:-$TIMING_FILE}"
    local total_duration=""

    # Calculate total duration if we have a run start time
    if [ -n "$TIMING_RUN_START" ]; then
        local now=$(timing_now_ms)
        total_duration=$((now - TIMING_RUN_START))
    fi

    # Build JSON
    {
        echo "{"
        echo "  \"network\": \"$TIMING_NETWORK\","
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        if [ -n "$total_duration" ]; then
            echo "  \"total_duration_ms\": $total_duration,"
        fi
        echo "  \"phases\": {"

        local first=true
        # Read all END lines and output as JSON
        while IFS='|' read -r type phase end_ms start_ms duration_ms; do
            if [ "$type" = "END" ]; then
                if [ "$first" = true ]; then
                    first=false
                else
                    echo ","
                fi
                printf "    \"%s\": {\n" "$phase"
                printf "      \"duration_ms\": %s,\n" "${duration_ms:-0}"
                printf "      \"start_ms\": %s,\n" "${start_ms:-0}"
                printf "      \"end_ms\": %s\n" "${end_ms:-0}"
                printf "    }"
            fi
        done < "$TIMING_DATA_FILE"

        echo ""
        echo "  }"
        echo "}"
    } > "$output_file"

    echo "[TIMING] Exported timing data to: $output_file"
}

# Add a timing entry directly (useful for parsed timings from external sources)
# Arguments:
#   $1 - phase name
#   $2 - duration in milliseconds
timing_add_entry() {
    local phase="$1"
    local duration_ms="$2"
    local now=$(timing_now_ms)
    local start=$((now - duration_ms))
    echo "END|${phase}|${now}|${start}|${duration_ms}" >> "$TIMING_DATA_FILE"
}

# Print a summary of all timings to stdout
timing_summary() {
    echo ""
    echo "=== Timing Summary for $TIMING_NETWORK ==="
    echo ""
    printf "%-30s %12s\n" "Phase" "Duration"
    printf "%-30s %12s\n" "------------------------------" "------------"

    # Read all END lines and print
    while IFS='|' read -r type phase end_ms start_ms duration_ms; do
        if [ "$type" = "END" ]; then
            local duration_sec=$(echo "scale=2; ${duration_ms:-0} / 1000" | bc)
            printf "%-30s %10.2fs\n" "$phase" "$duration_sec"
        fi
    done < "$TIMING_DATA_FILE"

    # Print total if available
    if [ -n "$TIMING_RUN_START" ]; then
        local now=$(timing_now_ms)
        local total=$((now - TIMING_RUN_START))
        local total_sec=$(echo "scale=2; $total / 1000" | bc)
        echo ""
        printf "%-30s %10.2fs\n" "TOTAL" "$total_sec"
    fi
    echo ""
}

# Measure the time for a first transaction (eth_blockNumber call)
# Arguments:
#   $1 - RPC URL (default: http://127.0.0.1:7546)
# Returns: 0 on success, 1 on failure
timing_measure_first_tx() {
    local rpc_url="${1:-http://127.0.0.1:7546}"
    local phase="${TIMING_NETWORK}_first_tx"

    timing_start "$phase"

    local response
    response=$(curl -s -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null)

    timing_end "$phase"

    if echo "$response" | grep -q '"result"'; then
        local block=$(echo "$response" | grep -oE '"result":"0x[0-9a-fA-F]+"' | cut -d'"' -f4)
        echo "[TIMING] First TX response - Block: $block"
        return 0
    else
        echo "[TIMING] First TX failed or no response"
        return 1
    fi
}

# Measure mirror node sync time (Solo only)
# Waits until mirror node REST API returns valid data
# Arguments:
#   $1 - Mirror node REST URL (default: http://localhost:8081/api/v1)
#   $2 - Max wait time in seconds (default: 300)
# Returns: 0 on success, 1 on timeout
timing_measure_mirror_sync() {
    local mirror_url="${1:-http://localhost:8081/api/v1}"
    local max_wait="${2:-300}"
    local phase="${TIMING_NETWORK}_mirror_sync"

    timing_start "$phase"

    local elapsed=0
    local interval=5

    while [ $elapsed -lt $max_wait ]; do
        # Try to get blocks from mirror node
        local response
        response=$(curl -s "${mirror_url}/blocks?limit=1" 2>/dev/null)

        if echo "$response" | grep -q '"blocks"'; then
            timing_end "$phase"
            echo "[TIMING] Mirror node is synced"
            return 0
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
        echo "[TIMING] Waiting for mirror node sync... (${elapsed}s / ${max_wait}s)"
    done

    timing_end "$phase"
    echo "[TIMING] Mirror node sync timed out after ${max_wait}s"
    return 1
}
