#!/usr/bin/env bash
# Parser for Solo's Listr2 task output
# Extracts component timings from Solo deploy output
# Compatible with bash 3.x (macOS default)
#
# Usage:
#   ./parse-solo-output.sh <solo-output.log> [output.json]
#
# Solo output format (Listr2):
#   ✔ Initialize [3.2s]
#   ✔ Generate keys [5.1s]
#   ✔ Setup consensus node (node1) [45.6s]
#
# This script parses these lines and extracts timing data.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Input file
INPUT_FILE="${1:-}"
OUTPUT_FILE="${2:-}"

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <solo-output.log> [output.json]"
    echo ""
    echo "Parses Solo Listr2 output and extracts timing data."
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

# Temp file for parsed data
PARSED_DATA_FILE=$(mktemp)
trap "rm -f $PARSED_DATA_FILE" EXIT

# Parse duration string to milliseconds
# Supports formats: 3.2s, 45s, 1m30s, 2m, 10.5s
parse_duration_to_ms() {
    local duration="$1"
    local total_ms=0

    # Extract minutes if present
    local minutes=$(echo "$duration" | grep -oE '[0-9]+m' | grep -oE '[0-9]+' || echo "")
    if [ -n "$minutes" ]; then
        total_ms=$((total_ms + minutes * 60 * 1000))
    fi

    # Extract seconds (with optional decimal)
    local seconds=$(echo "$duration" | grep -oE '[0-9]+\.?[0-9]*s' | sed 's/s$//' || echo "")
    if [ -n "$seconds" ]; then
        # Use bc for floating point
        local sec_ms=$(echo "$seconds * 1000" | bc | cut -d'.' -f1)
        total_ms=$((total_ms + sec_ms))
    fi

    echo "$total_ms"
}

# Normalize task name to a consistent key format
# e.g., "Setup consensus node (node1)" -> "setup_consensus_node"
normalize_task_name() {
    local name="$1"
    # Remove parenthetical parts
    name=$(echo "$name" | sed 's/([^)]*)//g')
    # Convert to lowercase
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    # Replace spaces and special chars with underscores
    name=$(echo "$name" | sed 's/[^a-z0-9]/_/g')
    # Remove multiple underscores
    name=$(echo "$name" | sed 's/__*/_/g')
    # Remove leading/trailing underscores
    name=$(echo "$name" | sed 's/^_//; s/_$//')
    echo "$name"
}

# Parse the Solo output file
parse_solo_output() {
    local input="$1"

    # Read file and look for completed tasks with timings
    # Match pattern: ✔ <task name> [<duration>]
    while IFS= read -r line; do
        # Remove ANSI escape codes
        local clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g')

        # Try to match completed task pattern
        # Look for checkmark followed by task name and duration in brackets
        if echo "$clean_line" | grep -qE '✔|✓|\[✔\]'; then
            # Extract the part after checkmark and before the duration
            local task_part=$(echo "$clean_line" | sed -E 's/.*[✔✓][ ]*//' | sed -E 's/\[✔\][ ]*//')

            # Check if there's a duration at the end
            if echo "$task_part" | grep -qE '\[[0-9]+\.?[0-9]*[ms]+\]$'; then
                # Extract duration (in brackets at end)
                local duration=$(echo "$task_part" | grep -oE '\[[0-9]+\.?[0-9]*[ms]+\]$' | tr -d '[]')
                # Extract task name (everything before the duration)
                local task_name=$(echo "$task_part" | sed -E 's/\[[0-9]+\.?[0-9]*[ms]+\]$//' | xargs)

                if [ -n "$task_name" ] && [ -n "$duration" ]; then
                    local key=$(normalize_task_name "$task_name")
                    local duration_ms=$(parse_duration_to_ms "$duration")
                    echo "${key}|${task_name}|${duration_ms}" >> "$PARSED_DATA_FILE"
                fi
            fi
        fi
    done < "$input"
}

# Export parsed data to JSON
export_to_json() {
    local output="$1"

    local total_ms=0
    # Calculate total
    while IFS='|' read -r key name duration_ms; do
        total_ms=$((total_ms + duration_ms))
    done < "$PARSED_DATA_FILE"

    {
        echo "{"
        echo "  \"source\": \"solo-listr2-output\","
        echo "  \"parsed_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"tasks\": {"

        local first=true
        while IFS='|' read -r key name duration_ms; do
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi

            local duration_sec=$(echo "scale=2; $duration_ms / 1000" | bc)

            printf "    \"%s\": {\n" "$key"
            printf "      \"name\": \"%s\",\n" "$name"
            printf "      \"duration_ms\": %s,\n" "$duration_ms"
            printf "      \"duration_formatted\": \"%ss\"\n" "$duration_sec"
            printf "    }"
        done < "$PARSED_DATA_FILE"

        echo ""
        echo "  },"
        echo "  \"total_parsed_ms\": $total_ms"
        echo "}"
    } > "$output"
}

# Print summary to stdout
print_summary() {
    echo ""
    echo "=== Solo Component Timings ==="
    echo ""
    printf "%-40s %12s\n" "Component" "Duration"
    printf "%-40s %12s\n" "----------------------------------------" "------------"

    local total_ms=0

    while IFS='|' read -r key name duration_ms; do
        total_ms=$((total_ms + duration_ms))
        local duration_sec=$(echo "scale=2; $duration_ms / 1000" | bc)
        printf "%-40s %10.2fs\n" "$name" "$duration_sec"
    done < "$PARSED_DATA_FILE"

    local total_sec=$(echo "scale=2; $total_ms / 1000" | bc)
    echo ""
    printf "%-40s %10.2fs\n" "TOTAL (parsed tasks)" "$total_sec"
    echo ""
}

# Main execution
parse_solo_output "$INPUT_FILE"

# Count parsed entries
parsed_count=$(wc -l < "$PARSED_DATA_FILE" | tr -d ' ')

if [ "$parsed_count" -eq 0 ]; then
    echo "Warning: No timing data found in $INPUT_FILE"
    echo "Expected format: ✔ Task Name [duration]"
    exit 0
fi

echo "Parsed ${parsed_count} timing entries from Solo output"

# Export to JSON if output file specified
if [ -n "$OUTPUT_FILE" ]; then
    export_to_json "$OUTPUT_FILE"
    echo "Exported to: $OUTPUT_FILE"
fi

# Print summary
print_summary
