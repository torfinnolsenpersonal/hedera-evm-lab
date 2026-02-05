#!/usr/bin/env bash
# Evidence collection library for Hedera EVM Lab benchmarks
# Produces a verifiable evidence manifest (JSON) for each benchmark run.
# Compatible with bash 3.x (macOS default). No jq dependency.
#
# Usage:
#   source scripts/lib/evidence.sh
#   evidence_init "$TIMESTAMP" "$TIMING_DATA_DIR"
#   evidence_record_step "solo_cold_startup" "start-solo.sh" 0 "/path/to/output.log"
#   evidence_record_contract "/path/to/contract-evidence.json"
#   evidence_finalize

# Ensure we don't source this multiple times
if [ -n "${_EVIDENCE_LIB_LOADED:-}" ]; then
    return 0
fi
_EVIDENCE_LIB_LOADED=1

# Global state
_EVIDENCE_RUN_ID=""
_EVIDENCE_OUTPUT_DIR=""
_EVIDENCE_STEPS_FILE=""
_EVIDENCE_CONTRACTS_FILE=""
_EVIDENCE_GIT_COMMIT=""
_EVIDENCE_GIT_BRANCH=""
_EVIDENCE_GIT_DIRTY=""
_EVIDENCE_DOCTOR_JSON=""

# Initialize evidence collection for a benchmark run.
# Arguments:
#   $1 - run timestamp / ID (e.g. "2026-02-05_10-30-00")
#   $2 - timing data directory (evidence JSON is written here)
evidence_init() {
    local run_id="$1"
    local output_dir="$2"
    _EVIDENCE_RUN_ID="$run_id"
    _EVIDENCE_OUTPUT_DIR="$output_dir"

    # Temp files for accumulating steps and contracts (pipe-delimited)
    _EVIDENCE_STEPS_FILE=$(mktemp "${TMPDIR:-/tmp}/evidence-steps.XXXXXX")
    _EVIDENCE_CONTRACTS_FILE=$(mktemp "${TMPDIR:-/tmp}/evidence-contracts.XXXXXX")
    : > "$_EVIDENCE_STEPS_FILE"
    : > "$_EVIDENCE_CONTRACTS_FILE"

    # Capture git state
    _EVIDENCE_GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    _EVIDENCE_GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    if git diff --quiet HEAD 2>/dev/null; then
        _EVIDENCE_GIT_DIRTY="false"
    else
        _EVIDENCE_GIT_DIRTY="true"
    fi

    # Capture doctor.sh --json output if available
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -x "${script_dir}/doctor.sh" ]; then
        _EVIDENCE_DOCTOR_JSON=$("${script_dir}/doctor.sh" --json 2>/dev/null || echo '{}')
    else
        _EVIDENCE_DOCTOR_JSON='{}'
    fi

    echo "[EVIDENCE] Initialized for run ${run_id} (git: ${_EVIDENCE_GIT_COMMIT}, branch: ${_EVIDENCE_GIT_BRANCH}, dirty: ${_EVIDENCE_GIT_DIRTY})"
}

# Record a benchmark step with its output hash.
# Arguments:
#   $1 - step name (e.g. "solo_cold_startup")
#   $2 - command that was run (e.g. "start-solo.sh")
#   $3 - exit code
#   $4 - output file path (SHA256 is computed; empty string if no file)
evidence_record_step() {
    local step_name="$1"
    local command="$2"
    local exit_code="$3"
    local output_file="${4:-}"

    local output_sha=""
    if [ -n "$output_file" ] && [ -f "$output_file" ]; then
        output_sha=$(shasum -a 256 "$output_file" 2>/dev/null | cut -d' ' -f1 || echo "")
    fi

    printf '%s|%s|%s|%s\n' "$step_name" "$command" "$exit_code" "$output_sha" >> "$_EVIDENCE_STEPS_FILE"
}

# Record contract deployment evidence from a JSON artifact produced by the hardhat test.
# Arguments:
#   $1 - path to contract evidence JSON file (produced by DeployBenchmark.test.ts)
evidence_record_contract() {
    local json_path="$1"
    if [ ! -f "$json_path" ]; then
        echo "[EVIDENCE] Warning: contract evidence file not found: $json_path"
        return 1
    fi

    # Read fields from the JSON using grep/sed (no jq dependency)
    local label address bytecode_sha deploy_tx
    label=$(grep -o '"label"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_path" 2>/dev/null | head -1 | sed 's/.*"label"[[:space:]]*:[[:space:]]*"//;s/"$//')
    address=$(grep -o '"address"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_path" 2>/dev/null | head -1 | sed 's/.*"address"[[:space:]]*:[[:space:]]*"//;s/"$//')
    bytecode_sha=$(grep -o '"bytecode_sha256"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_path" 2>/dev/null | head -1 | sed 's/.*"bytecode_sha256"[[:space:]]*:[[:space:]]*"//;s/"$//')
    deploy_tx=$(grep -o '"deploy_tx"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_path" 2>/dev/null | head -1 | sed 's/.*"deploy_tx"[[:space:]]*:[[:space:]]*"//;s/"$//')

    printf '%s|%s|%s|%s\n' "${label:-unknown}" "${address:-}" "${bytecode_sha:-}" "${deploy_tx:-}" >> "$_EVIDENCE_CONTRACTS_FILE"
    echo "[EVIDENCE] Recorded contract: label=${label:-unknown}, address=${address:-N/A}"
}

# Finalize evidence and write the manifest JSON to the output directory.
# Returns: path to evidence file on stdout
evidence_finalize() {
    local evidence_file="${_EVIDENCE_OUTPUT_DIR}/${_EVIDENCE_RUN_ID}_evidence.json"

    {
        printf '{\n'
        printf '  "run_id": "%s",\n' "$_EVIDENCE_RUN_ID"
        printf '  "git": {\n'
        printf '    "commit": "%s",\n' "$_EVIDENCE_GIT_COMMIT"
        printf '    "branch": "%s",\n' "$_EVIDENCE_GIT_BRANCH"
        printf '    "dirty": %s\n' "$_EVIDENCE_GIT_DIRTY"
        printf '  },\n'

        # Environment (inline doctor.sh output)
        printf '  "environment": %s,\n' "$_EVIDENCE_DOCTOR_JSON"

        # Steps array
        printf '  "steps": [\n'
        local first=true
        while IFS='|' read -r step_name command exit_code output_sha; do
            [ -z "$step_name" ] && continue
            if [ "$first" = true ]; then
                first=false
            else
                printf ',\n'
            fi
            printf '    {"name": "%s", "command": "%s", "exit_code": %s' "$step_name" "$command" "${exit_code:-0}"
            if [ -n "$output_sha" ]; then
                printf ', "output_sha256": "%s"' "$output_sha"
            fi
            printf '}'
        done < "$_EVIDENCE_STEPS_FILE"
        printf '\n  ],\n'

        # Contracts array
        printf '  "contracts": [\n'
        first=true
        while IFS='|' read -r label address bytecode_sha deploy_tx; do
            [ -z "$label" ] && continue
            if [ "$first" = true ]; then
                first=false
            else
                printf ',\n'
            fi
            printf '    {"label": "%s"' "$label"
            [ -n "$address" ] && printf ', "address": "%s"' "$address"
            [ -n "$bytecode_sha" ] && printf ', "bytecode_sha256": "%s"' "$bytecode_sha"
            [ -n "$deploy_tx" ] && printf ', "deploy_tx": "%s"' "$deploy_tx"
            printf '}'
        done < "$_EVIDENCE_CONTRACTS_FILE"
        printf '\n  ]\n'

        printf '}\n'
    } > "$evidence_file"

    # Cleanup temp files
    rm -f "$_EVIDENCE_STEPS_FILE" "$_EVIDENCE_CONTRACTS_FILE"

    echo "[EVIDENCE] Finalized: $evidence_file"
    echo "$evidence_file"
}
