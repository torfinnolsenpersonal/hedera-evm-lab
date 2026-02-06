#!/usr/bin/env bash
# Run the Deploy Benchmark across one or more networks
# Usage: ./scripts/run-deploy-benchmark.sh [--clean|--warm|--warm-cluster|--full-lifecycle] [anvil|localnode|solo|hedera_testnet|local|all]
#
# Flags:
#   --clean           (default) Full developer journey: clean node_modules/artifacts, npm install, compile, then benchmark
#   --warm            Skip install/compile steps; only run network startup + contract benchmark
#   --warm-cluster    Like --warm, but also preserves the kind cluster between runs (Solo only)
#   --full-lifecycle  Benchmark the complete developer journey: install → cold start → warm restart → hot restart
#                     Solo: install, cold, warm, hot  |  Local Node: cold, restart, docker_warm
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

# Source evidence library
source "${SCRIPT_DIR}/lib/evidence.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Docker Health Monitoring
# ============================================================================
# Ensures Docker stays running during long benchmarks (macOS Docker Desktop
# has a "Resource Saver" feature that can pause the engine)

DOCKER_MONITOR_PID=""
DOCKER_MONITOR_LOG=""

# Start a Docker keep-alive container to prevent Resource Saver from pausing Docker
DOCKER_KEEPALIVE_CONTAINER="benchmark-keepalive"

start_docker_keepalive() {
    # Remove any existing keepalive container
    docker rm -f "$DOCKER_KEEPALIVE_CONTAINER" 2>/dev/null || true

    # Start a lightweight alpine container that runs indefinitely
    # This prevents Docker Desktop Resource Saver from pausing the engine
    docker run -d --name "$DOCKER_KEEPALIVE_CONTAINER" \
        --restart=unless-stopped \
        alpine:latest \
        sh -c "while true; do sleep 10; done" >/dev/null 2>&1

    if docker ps -q -f "name=$DOCKER_KEEPALIVE_CONTAINER" | grep -q .; then
        echo "[Docker Keepalive] Container started - Docker will stay active"
    else
        echo "[Docker Keepalive] Warning: Failed to start keepalive container"
    fi
}

stop_docker_keepalive() {
    docker rm -f "$DOCKER_KEEPALIVE_CONTAINER" 2>/dev/null || true
    echo "[Docker Keepalive] Container stopped"
}

# Start a background process that monitors Docker and restarts it if needed
start_docker_monitor() {
    DOCKER_MONITOR_LOG="${TIMING_DATA_DIR:-/tmp}/docker-monitor.log"

    (
        while true; do
            if ! docker info >/dev/null 2>&1; then
                echo "[$(date '+%H:%M:%S')] Docker stopped! Attempting restart..." >> "$DOCKER_MONITOR_LOG"

                # Try to restart Docker Desktop on macOS
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    open -a Docker 2>/dev/null || true
                    echo "[$(date '+%H:%M:%S')] Sent open command to Docker.app" >> "$DOCKER_MONITOR_LOG"

                    # Wait for Docker to come back
                    for i in {1..60}; do
                        if docker info >/dev/null 2>&1; then
                            echo "[$(date '+%H:%M:%S')] Docker recovered after ${i}s" >> "$DOCKER_MONITOR_LOG"
                            # Restart keepalive container
                            start_docker_keepalive 2>/dev/null || true
                            break
                        fi
                        sleep 1
                    done
                fi
            fi
            sleep 5
        done
    ) &
    DOCKER_MONITOR_PID=$!
    echo "[Docker Monitor] Started with PID $DOCKER_MONITOR_PID"
}

# Stop the Docker monitor
stop_docker_monitor() {
    if [ -n "$DOCKER_MONITOR_PID" ] && kill -0 "$DOCKER_MONITOR_PID" 2>/dev/null; then
        kill "$DOCKER_MONITOR_PID" 2>/dev/null || true
        echo "[Docker Monitor] Stopped"
    fi
}

# ============================================================================
# Mac Sleep Prevention (caffeinate)
# ============================================================================
# Prevents macOS from sleeping during long benchmarks

CAFFEINATE_PID=""

start_caffeinate() {
    if [[ "$OSTYPE" == "darwin"* ]] && command -v caffeinate &>/dev/null; then
        # -d: prevent display sleep
        # -i: prevent idle sleep
        # -m: prevent disk sleep
        # -s: prevent system sleep (on AC power)
        caffeinate -dims &
        CAFFEINATE_PID=$!
        echo "[Caffeinate] Started - Mac will stay awake (PID: $CAFFEINATE_PID)"
    fi
}

stop_caffeinate() {
    if [ -n "$CAFFEINATE_PID" ] && kill -0 "$CAFFEINATE_PID" 2>/dev/null; then
        kill "$CAFFEINATE_PID" 2>/dev/null || true
        echo "[Caffeinate] Stopped"
    fi
}

# Ensure Docker is running before we start
ensure_docker_running() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker is not running. Attempting to start...${NC}"

        if [[ "$OSTYPE" == "darwin"* ]]; then
            open -a Docker
            echo "Waiting for Docker to start..."
            for i in {1..60}; do
                if docker info >/dev/null 2>&1; then
                    echo -e "${GREEN}Docker is now running${NC}"
                    return 0
                fi
                sleep 2
            done
            echo -e "${RED}Docker failed to start within 2 minutes${NC}"
            return 1
        else
            echo -e "${RED}Please start Docker manually${NC}"
            return 1
        fi
    fi
    return 0
}

# Parse flags
CLEAN_MODE=true
WARM_CLUSTER=false
FULL_LIFECYCLE=false
CLEAN_IMAGES=false
MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN_MODE=true
            WARM_CLUSTER=false
            FULL_LIFECYCLE=false
            shift
            ;;
        --warm)
            CLEAN_MODE=false
            WARM_CLUSTER=false
            FULL_LIFECYCLE=false
            shift
            ;;
        --warm-cluster)
            CLEAN_MODE=false
            WARM_CLUSTER=true
            FULL_LIFECYCLE=false
            shift
            ;;
        --full-lifecycle)
            CLEAN_MODE=false
            WARM_CLUSTER=false
            FULL_LIFECYCLE=true
            shift
            ;;
        --clean-images)
            CLEAN_IMAGES=true
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

# Cleanup trap - remove temp dir, stop monitors and keepalive container
cleanup_on_exit() {
    stop_docker_monitor
    stop_docker_keepalive
    stop_caffeinate
    rm -rf "$TEMP_DIR"
}
trap cleanup_on_exit EXIT

mkdir -p "$REPORTS_DIR"

# Timing data directory (persisted alongside the report)
TIMING_DATA_DIR="${REPORTS_DIR}/${TIMESTAMP}_timing-data"
mkdir -p "$TIMING_DATA_DIR"

# Initialize evidence collection
evidence_init "$TIMESTAMP" "$TIMING_DATA_DIR"

# Evidence directory for contract artifacts (exported to hardhat test)
export BENCHMARK_EVIDENCE_DIR="${TIMING_DATA_DIR}"

# Track per-network results: pass/fail/skip (bash 3.x compatible key-value store)
# Keys are sanitized labels: solo_1st, anvil, hedera_testnet_2nd, etc.
kv_set() { eval "${1}_${2}=\${3}"; }
kv_get() { eval "echo \"\${${1}_${2}:-${3:-}}\""; }

# Ensure Docker is running before we start (for Docker-based networks)
if ! ensure_docker_running; then
    echo -e "${RED}Cannot proceed without Docker${NC}"
    exit 1
fi

# Start Docker keepalive container to prevent Resource Saver from pausing Docker
start_docker_keepalive

# Start Docker health monitor to detect and recover from Docker stops
start_docker_monitor

# Keep Mac awake during benchmark (prevents sleep-induced Docker stops)
start_caffeinate

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Deploy Benchmark — Developer Journey${NC}"
echo -e "${CYAN}============================================${NC}"
echo "Mode: ${MODE}"
if $FULL_LIFECYCLE; then
    echo "Run type: FULL LIFECYCLE (install → cold → warm → hot)"
elif $WARM_CLUSTER; then
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
# e.g., "solo_1st" → "solo", "solo_cold" → "solo", "localnode_restart" → "localnode"
net_name() {
    case "$1" in
        *_1st) echo "${1%_1st}" ;;
        *_2nd) echo "${1%_2nd}" ;;
        *_install) echo "${1%_install}" ;;
        *_cold) echo "${1%_cold}" ;;
        *_warm) echo "${1%_warm}" ;;
        *_hot) echo "${1%_hot}" ;;
        *_evm) echo "${1%_evm}" ;;
        *_hapi) echo "${1%_hapi}" ;;
        *_restart) echo "${1%_restart}" ;;
        *_docker_warm) echo "${1%_docker_warm}" ;;
        *) echo "$1" ;;
    esac
}

# Display-friendly label for reports
# e.g., "solo_1st" → "solo (1st start)", "solo_cold" → "solo (cold start)"
display_name() {
    case "$1" in
        *_1st) echo "${1%_1st} (1st start)" ;;
        *_2nd) echo "${1%_2nd} (2nd start)" ;;
        *_install) echo "${1%_install} (install)" ;;
        *_cold) echo "${1%_cold} (cold start)" ;;
        *_warm) echo "${1%_warm} (warm restart)" ;;
        *_hot) echo "${1%_hot} (hot restart)" ;;
        *_evm) echo "${1%_evm} (EVM test)" ;;
        *_hapi) echo "${1%_hapi} (HAPI test)" ;;
        *_restart) echo "${1%_restart} (CLI restart)" ;;
        *_docker_warm) echo "${1%_docker_warm} (docker warm)" ;;
        *) echo "$1" ;;
    esac
}

# Build run list — expand each network into two runs for --warm-cluster
# In --full-lifecycle mode, RUN_LIST is built dynamically by lifecycle orchestrators
RUN_LIST=()
if ! $FULL_LIFECYCLE; then
    for net in "${NETWORKS[@]}"; do
        if $WARM_CLUSTER; then
            RUN_LIST+=("${net}_1st" "${net}_2nd")
        else
            RUN_LIST+=("$net")
        fi
    done
fi

# In warm/lifecycle mode, ensure hardhat project is ready once up front
if ! $CLEAN_MODE || $FULL_LIFECYCLE; then
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
            sleep 60  # Stabilization wait (mirror node needs extra time)
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
    local mode="${2:-auto}"  # auto | keep-cluster | docker-stop | full | none
    if [ "$mode" = "none" ]; then
        echo -e "${YELLOW}Skipping shutdown (stop_mode=none)${NC}"
        return 0
    fi
    case "$net" in
        anvil)
            "${SCRIPT_DIR}/stop-anvil.sh" || true
            ;;
        localnode)
            if [ "$mode" = "docker-stop" ]; then
                "${SCRIPT_DIR}/stop-local-node.sh" --docker-stop || true
            else
                "${SCRIPT_DIR}/stop-local-node.sh" || true
            fi
            ;;
        solo)
            if [ "$mode" = "keep-cluster" ] || { [ "$mode" = "auto" ] && $WARM_CLUSTER; }; then
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

# Ensure a clean environment before starting a network.
# Force-stops the network, runs cleanup.sh to kill stragglers, then verifies.
ensure_network_clean() {
    local net="$1"
    echo -e "${YELLOW}Ensuring clean slate for ${net}...${NC}"

    # 1. Force-stop the network (full mode — destroy everything)
    stop_network "$net" "full" 2>/dev/null || true

    # 2. Run cleanup.sh to kill stragglers (port-forwards, orphan containers)
    "${SCRIPT_DIR}/cleanup.sh" 2>/dev/null || true

    # 3. Verify clean state
    if ! "${SCRIPT_DIR}/cleanup.sh" --verify-only >/dev/null 2>&1; then
        echo -e "${YELLOW}Environment not fully clean, retrying cleanup...${NC}"
        sleep 2
        "${SCRIPT_DIR}/cleanup.sh" 2>/dev/null || true
    fi

    echo -e "${GREEN}Clean slate confirmed for ${net}${NC}"
}

# Clean Docker images and volumes to simulate first-run on a fresh machine.
# This is called when --clean-images flag is set to measure true cold start times.
clean_docker_artifacts() {
    echo -e "${YELLOW}Cleaning Docker images and volumes (simulating fresh machine)...${NC}"

    # Stop all containers first
    if docker ps -q 2>/dev/null | grep -q .; then
        echo "Stopping running containers..."
        docker stop $(docker ps -q) 2>/dev/null || true
    fi

    # Remove all containers
    if docker ps -aq 2>/dev/null | grep -q .; then
        echo "Removing containers..."
        docker rm -f $(docker ps -aq) 2>/dev/null || true
    fi

    # Remove all volumes
    echo "Removing Docker volumes..."
    docker volume prune -f 2>/dev/null || true

    # Remove all images (this will force re-pull on next start)
    echo "Removing Docker images..."
    docker image prune -af 2>/dev/null || true

    # Remove specific network images to ensure fresh pull
    # Solo images
    docker rmi $(docker images -q "gcr.io/hedera-registry/*" 2>/dev/null) 2>/dev/null || true
    docker rmi $(docker images -q "hashgraph/*" 2>/dev/null) 2>/dev/null || true
    # Local Node images
    docker rmi $(docker images -q "hashgraph/hedera*" 2>/dev/null) 2>/dev/null || true

    echo -e "${GREEN}Docker artifacts cleaned${NC}"
}

# Verify RPC endpoint is healthy (used for hot restart where network is already running)
# Arguments:
#   $1 - RPC URL (default: http://127.0.0.1:7546)
#   $2 - Max attempts (default: 30)
#   $3 - Sleep interval in seconds (default: 2)
# Returns: 0 on success, 1 on timeout
verify_rpc_health() {
    local rpc_url="${1:-http://127.0.0.1:7546}"
    local max_attempts="${2:-30}"
    local interval="${3:-2}"
    local attempt=0

    echo "Verifying RPC health at ${rpc_url}..."
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q '"result"'; then
            echo -e "${GREEN}RPC endpoint is healthy${NC}"
            return 0
        fi
        attempt=$((attempt + 1))
        echo "Waiting for RPC... (attempt ${attempt}/${max_attempts})"
        sleep "$interval"
    done
    echo -e "${RED}RPC health check timed out after ${max_attempts} attempts${NC}"
    return 1
}

# Start Local Node containers using raw docker compose start (for docker_warm scenario)
# Discovers the compose directory and runs docker compose start + health check
# Returns: 0 on success, 1 on failure
start_localnode_docker_only() {
    local rpc_port="${RPC_PORT:-7546}"

    echo -e "${CYAN}Starting Local Node via docker compose start...${NC}"

    # Discover the docker-compose working directory
    local compose_dir=""
    local hedera_workdir="$HOME/Library/Application Support/hedera-local"
    if [ -f "${hedera_workdir}/docker-compose.yml" ] || [ -f "${hedera_workdir}/compose.yaml" ]; then
        compose_dir="$hedera_workdir"
    elif [ -d "${PROJECT_ROOT}/repos/hiero-local-node" ]; then
        compose_dir="${PROJECT_ROOT}/repos/hiero-local-node"
    fi

    if [ -z "$compose_dir" ]; then
        echo -e "${RED}Error: Could not find Local Node docker-compose directory${NC}"
        return 1
    fi

    echo "Using compose dir: ${compose_dir}"
    cd "$compose_dir"
    docker compose start 2>/dev/null || {
        echo -e "${RED}docker compose start failed${NC}"
        return 1
    }

    # Wait for health
    sleep 5
    if verify_rpc_health "http://127.0.0.1:${rpc_port}" 30 2; then
        echo -e "${GREEN}Local Node containers restarted successfully${NC}"
        return 0
    else
        echo -e "${RED}Local Node did not become healthy after docker compose start${NC}"
        return 1
    fi
}

# ============================================================================
# Run benchmark for a single network
# ============================================================================

run_benchmark() {
    local label="$1"
    local stop_mode="${2:-auto}"  # auto | keep-cluster | docker-stop | full | none
    local net
    net=$(net_name "$label")
    local output_file="${TEMP_DIR}/benchmark_${label}.txt"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Benchmarking: $(display_name "$label")${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Ensure no stale infrastructure from a previous session
    if [ "$net" != "hedera_testnet" ]; then
        ensure_network_clean "$net"
    fi

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
    export BENCHMARK_LABEL="$label"
    set +e
    BENCHMARK_LABEL="$label" npx hardhat test test/DeployBenchmark.test.ts --network "$net" 2>&1 | tee "$output_file"
    local bench_exit=${PIPESTATUS[0]}
    set -e
    if [ "$bench_exit" -eq 0 ]; then
        echo ""
        echo -e "${GREEN}Benchmark PASSED for $(display_name "$label")${NC}"
    else
        echo ""
        echo -e "${RED}Benchmark FAILED for $(display_name "$label")${NC}"
    fi
    timing_end "${label}_benchmark"

    # Evidence: record benchmark step
    evidence_record_step "${label}_benchmark" "hardhat test --network $net" "$bench_exit" "$output_file"

    # Evidence: record contract if artifact exists
    local contract_artifact="${BENCHMARK_EVIDENCE_DIR}/${label}-contract-evidence.json"
    if [ -f "$contract_artifact" ]; then
        evidence_record_contract "$contract_artifact"
    fi

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
    if [ "$net" != "hedera_testnet" ] && [ "$stop_mode" != "none" ]; then
        echo -e "${YELLOW}Stage 6: Network shutdown${NC}"
        timing_start "${label}_shutdown"
        stop_network "$net" "$stop_mode"
        timing_end "${label}_shutdown"
    elif [ "$stop_mode" = "none" ]; then
        echo -e "${YELLOW}Stage 6: Skipping shutdown (managed by lifecycle orchestrator)${NC}"
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
# Full Lifecycle: benchmark variant with custom startup/shutdown
# ============================================================================

# Run a benchmark scenario with a custom startup function and stop mode.
# Unlike run_benchmark(), startup is handled by the caller (lifecycle orchestrator).
# Arguments:
#   $1 - label (e.g., "solo_cold")
#   $2 - startup_fn: function name to call for startup (or "none" to skip)
#   $3 - stop_mode: how to shut down after benchmark (auto|keep-cluster|docker-stop|full|none)
run_benchmark_lifecycle() {
    local label="$1"
    local startup_fn="${2:-none}"
    local stop_mode="${3:-none}"
    local net
    net=$(net_name "$label")
    local output_file="${TEMP_DIR}/benchmark_${label}.txt"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Benchmarking: $(display_name "$label")${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    timing_init "$label"

    # Startup (managed by lifecycle orchestrator)
    if [ "$startup_fn" != "none" ]; then
        echo -e "${YELLOW}Startup: ${startup_fn}${NC}"
        timing_start "${label}_startup"
        if ! eval "$startup_fn"; then
            echo -e "${RED}Startup failed for ${label}${NC}"
            timing_end "${label}_startup"
            kv_set NET_STATUS "$label" "FAIL"
            kv_set NET_PASSED "$label" "0"
            kv_set NET_FAILED "$label" "0"
            kv_set NET_TOTAL "$label" "0"
            return 1
        fi
        timing_end "${label}_startup"
    fi

    # Contract benchmark
    timing_start "${label}_benchmark"
    echo ""
    echo -e "${YELLOW}Contract benchmark${NC}"
    echo -e "${CYAN}Running benchmark tests against ${net}...${NC}"
    echo ""

    cd "$HARDHAT_DIR"
    export BENCHMARK_LABEL="$label"
    set +e
    BENCHMARK_LABEL="$label" npx hardhat test test/DeployBenchmark.test.ts --network "$net" 2>&1 | tee "$output_file"
    local bench_exit=${PIPESTATUS[0]}
    set -e
    if [ "$bench_exit" -eq 0 ]; then
        echo ""
        echo -e "${GREEN}Benchmark PASSED for $(display_name "$label")${NC}"
    else
        echo ""
        echo -e "${RED}Benchmark FAILED for $(display_name "$label")${NC}"
    fi
    timing_end "${label}_benchmark"

    # Evidence: record benchmark step and contract
    evidence_record_step "${label}_benchmark" "hardhat test --network $net" "$bench_exit" "$output_file"
    local contract_artifact="${BENCHMARK_EVIDENCE_DIR}/${label}-contract-evidence.json"
    if [ -f "$contract_artifact" ]; then
        evidence_record_contract "$contract_artifact"
    fi

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

    # Shutdown (managed by lifecycle orchestrator)
    if [ "$stop_mode" != "none" ]; then
        echo -e "${YELLOW}Shutdown: stop_mode=${stop_mode}${NC}"
        timing_start "${label}_shutdown"
        stop_network "$net" "$stop_mode"
        timing_end "${label}_shutdown"
    else
        echo -e "${YELLOW}Skipping shutdown (managed by lifecycle orchestrator)${NC}"
    fi

    echo ""
    timing_summary

    # Export timing data
    timing_export_json "${TIMING_DATA_DIR}/${label}-timing.json"
    if [ -f "$TIMING_DATA_FILE" ]; then
        cp "$TIMING_DATA_FILE" "${TIMING_DATA_DIR}/${label}-timing-data.txt"
    fi
    if [ -f "$output_file" ]; then
        cp "$output_file" "${TIMING_DATA_DIR}/${label}-benchmark-output.txt"
    fi
}

# ============================================================================
# Full Lifecycle: Anvil (2 scenarios — cold + hot)
# ============================================================================

run_anvil_lifecycle() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Anvil Full Lifecycle (cold → hot)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Ensure no stale anvil process from a previous session
    ensure_network_clean anvil

    # Clean Docker artifacts if --clean-images flag is set (Anvil doesn't use Docker, but keep consistent)
    if [ "$CLEAN_IMAGES" = "true" ]; then
        clean_docker_artifacts
    fi

    # ── Step 1: anvil_cold — start anvil, run benchmark, keep running ──
    echo -e "${CYAN}[1/2] anvil_cold: start + benchmark${NC}"
    local cold_label="anvil_cold"
    RUN_LIST+=("$cold_label")
    run_benchmark_lifecycle "$cold_label" "start_network anvil" "none" || true
    echo ""

    # ── Step 2: anvil_hot — network already running, health check + benchmark, then stop ──
    echo -e "${CYAN}[2/2] anvil_hot: health check + benchmark${NC}"
    local hot_label="anvil_hot"
    RUN_LIST+=("$hot_label")
    _anvil_hot_startup() {
        echo -e "${CYAN}Verifying Anvil is still running...${NC}"
        verify_rpc_health "http://127.0.0.1:${RPC_PORT:-8545}" 10 1
    }
    run_benchmark_lifecycle "$hot_label" "_anvil_hot_startup" "auto" || true
    echo ""
}

# ============================================================================
# Full Lifecycle: Hedera Testnet (2 scenarios — cold + warm)
# ============================================================================

run_testnet_lifecycle() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Hedera Testnet Full Lifecycle (cold → warm)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # ── Step 1: hedera_testnet_cold — first connection ──
    echo -e "${CYAN}[1/2] hedera_testnet_cold: first connection + benchmark${NC}"
    local cold_label="hedera_testnet_cold"
    RUN_LIST+=("$cold_label")
    run_benchmark_lifecycle "$cold_label" "start_network hedera_testnet" "none" || true
    echo ""

    # ── Step 2: hedera_testnet_warm — cached connection ──
    echo -e "${CYAN}[2/2] hedera_testnet_warm: cached connection + benchmark${NC}"
    local warm_label="hedera_testnet_warm"
    RUN_LIST+=("$warm_label")
    _testnet_warm_startup() {
        echo -e "${CYAN}Re-validating Hedera Testnet connectivity (cached)...${NC}"
        local rpc_url="${HEDERA_TESTNET_RPC_URL:-https://testnet.hashio.io/api}"
        if curl -s "$rpc_url" -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x128"; then
            echo -e "${GREEN}Hedera Testnet reachable${NC}"
            return 0
        else
            echo -e "${RED}Cannot reach Hedera Testnet${NC}"
            return 1
        fi
    }
    run_benchmark_lifecycle "$warm_label" "_testnet_warm_startup" "none" || true
    echo ""
}

# ============================================================================
# Run EVM Benchmark (ERC20 + 3 accounts)
# ============================================================================

run_evm_benchmark() {
    local label="${1:-solo}"
    local net
    net=$(net_name "$label")
    local output_file="${TEMP_DIR}/evm_benchmark_${label}.txt"

    echo -e "${CYAN}Running EVM Benchmark (ERC20 + 3 accounts)...${NC}"

    timing_start "${label}_evm_benchmark"

    cd "$HARDHAT_DIR"
    export BENCHMARK_LABEL="${label}_evm"
    set +e
    BENCHMARK_LABEL="${label}_evm" npx hardhat test test/EVMBenchmark.test.ts --network "$net" 2>&1 | tee "$output_file"
    local evm_exit=${PIPESTATUS[0]}
    set -e

    timing_end "${label}_evm_benchmark"

    if [ "$evm_exit" -eq 0 ]; then
        echo -e "${GREEN}EVM Benchmark PASSED${NC}"
    else
        echo -e "${RED}EVM Benchmark FAILED${NC}"
    fi

    # Copy output for report
    if [ -f "$output_file" ]; then
        cp "$output_file" "${TIMING_DATA_DIR}/${label}-evm-benchmark-output.txt"
    fi

    # Parse EVM timing from output
    local evm_total
    evm_total=$(grep -oE '\[TIMING\] evm_total=[0-9]+' "$output_file" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "0")
    kv_set EVM_TOTAL "$label" "$evm_total"

    return $evm_exit
}

# ============================================================================
# Run HAPI Benchmark (SDK token operations + 3 accounts)
# ============================================================================

run_hapi_benchmark() {
    local label="${1:-solo}"
    local output_file="${TEMP_DIR}/hapi_benchmark_${label}.txt"

    echo -e "${CYAN}Running HAPI Benchmark (SDK token ops + 3 accounts)...${NC}"

    timing_start "${label}_hapi_benchmark"

    cd "$HARDHAT_DIR"
    export BENCHMARK_LABEL="${label}_hapi"
    set +e
    # HAPI benchmark uses the Hedera SDK, run with hardhat test for mocha
    BENCHMARK_LABEL="${label}_hapi" npx hardhat test test/HAPIBenchmark.test.ts --network solo 2>&1 | tee "$output_file"
    local hapi_exit=${PIPESTATUS[0]}
    set -e

    timing_end "${label}_hapi_benchmark"

    if [ "$hapi_exit" -eq 0 ]; then
        echo -e "${GREEN}HAPI Benchmark PASSED${NC}"
    else
        echo -e "${RED}HAPI Benchmark FAILED${NC}"
    fi

    # Copy output for report
    if [ -f "$output_file" ]; then
        cp "$output_file" "${TIMING_DATA_DIR}/${label}-hapi-benchmark-output.txt"
    fi

    # Parse HAPI timing from output
    local hapi_total
    hapi_total=$(grep -oE '\[TIMING\] hapi_total=[0-9]+' "$output_file" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "0")
    kv_set HAPI_TOTAL "$label" "$hapi_total"

    return $hapi_exit
}

# ============================================================================
# Full Lifecycle: Solo (4 scenarios)
# ============================================================================

run_solo_lifecycle() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Solo Full Lifecycle (install → cold → warm → hot)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Ensure no stale kind cluster or port-forwards from a previous session
    ensure_network_clean solo

    # ── Step 1: solo_install — brew reinstall solo timing ──
    echo -e "${CYAN}[1/4] solo_install: brew reinstall solo${NC}"
    local install_label="solo_install"
    RUN_LIST+=("$install_label")
    timing_init "$install_label"
    timing_start "${install_label}_startup"

    if command -v brew &>/dev/null; then
        # Run brew reinstall (use gtimeout if available, else run without timeout)
        local timeout_cmd=""
        if command -v gtimeout &>/dev/null; then
            timeout_cmd="gtimeout 600"
        elif command -v timeout &>/dev/null; then
            timeout_cmd="timeout 600"
        fi
        if $timeout_cmd brew reinstall solo 2>&1; then
            echo -e "${GREEN}solo reinstalled successfully${NC}"
            kv_set NET_STATUS "$install_label" "PASS"
        else
            echo -e "${RED}brew reinstall solo failed or timed out${NC}"
            kv_set NET_STATUS "$install_label" "FAIL"
        fi
    else
        echo -e "${YELLOW}brew not found, skipping install timing${NC}"
        kv_set NET_STATUS "$install_label" "SKIP"
    fi

    timing_end "${install_label}_startup"
    kv_set NET_PASSED "$install_label" "0"
    kv_set NET_FAILED "$install_label" "0"
    kv_set NET_TOTAL "$install_label" "0"

    timing_summary
    timing_export_json "${TIMING_DATA_DIR}/${install_label}-timing.json"
    if [ -f "$TIMING_DATA_FILE" ]; then
        cp "$TIMING_DATA_FILE" "${TIMING_DATA_DIR}/${install_label}-timing-data.txt"
    fi
    echo ""

    # ── Step 2: solo_cold — full cold start (kind create + solo deploy + benchmark) ──
    # Ensure clean slate before cold start (install may have started Solo)
    ensure_network_clean solo

    # Clean Docker artifacts if --clean-images flag is set (simulates fresh machine)
    if [ "$CLEAN_IMAGES" = "true" ]; then
        clean_docker_artifacts
    fi

    echo -e "${CYAN}[2/4] solo_cold: full cold start${NC}"
    local cold_label="solo_cold"
    RUN_LIST+=("$cold_label")
    run_benchmark_lifecycle "$cold_label" "start_network solo" "keep-cluster" || true
    echo ""

    # ── Step 3: solo_warm — redeploy on existing cluster ──
    echo -e "${CYAN}[3/6] solo_warm: redeploy on existing cluster${NC}"
    local warm_label="solo_warm"
    RUN_LIST+=("$warm_label")
    run_benchmark_lifecycle "$warm_label" "start_network solo" "none" || true
    echo ""

    # ── Step 4: EVM Benchmark (network still running from warm) ──
    echo -e "${CYAN}[4/6] solo_evm: EVM benchmark (ERC20 + 3 accounts)${NC}"
    local evm_label="solo_evm"
    RUN_LIST+=("$evm_label")
    timing_init "$evm_label"
    run_evm_benchmark "solo" || true
    kv_set NET_STATUS "$evm_label" "$([ $? -eq 0 ] && echo 'PASS' || echo 'FAIL')"
    kv_set NET_PASSED "$evm_label" "0"
    kv_set NET_FAILED "$evm_label" "0"
    kv_set NET_TOTAL "$evm_label" "0"
    timing_export_json "${TIMING_DATA_DIR}/${evm_label}-timing.json"
    echo ""

    # ── Step 5: HAPI Benchmark (network still running) ──
    echo -e "${CYAN}[5/6] solo_hapi: HAPI benchmark (SDK token ops + 3 accounts)${NC}"
    local hapi_label="solo_hapi"
    RUN_LIST+=("$hapi_label")
    timing_init "$hapi_label"
    run_hapi_benchmark "solo" || true
    kv_set NET_STATUS "$hapi_label" "$([ $? -eq 0 ] && echo 'PASS' || echo 'FAIL')"
    kv_set NET_PASSED "$hapi_label" "0"
    kv_set NET_FAILED "$hapi_label" "0"
    kv_set NET_TOTAL "$hapi_label" "0"
    timing_export_json "${TIMING_DATA_DIR}/${hapi_label}-timing.json"
    echo ""

    # ── Step 6: solo_hot — network already running, health check only ──
    echo -e "${CYAN}[6/6] solo_hot: network already running (health check + benchmark)${NC}"
    local hot_label="solo_hot"
    RUN_LIST+=("$hot_label")
    # For hot restart, just verify health — network is already running from warm step
    _solo_hot_startup() {
        echo -e "${CYAN}Verifying Solo network is still running...${NC}"
        verify_rpc_health "http://127.0.0.1:${RPC_PORT:-7546}" 30 5
    }
    run_benchmark_lifecycle "$hot_label" "_solo_hot_startup" "full" || true
    echo ""
}

# ============================================================================
# Full Lifecycle: Local Node (3 scenarios)
# ============================================================================

run_localnode_lifecycle() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Local Node Full Lifecycle (install → cold → restart → docker_warm)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Ensure no stale containers or networks from a previous session
    ensure_network_clean localnode

    # ── Step 1: localnode_install — npm install -g @hashgraph/hedera-local ──
    echo -e "${CYAN}[1/4] localnode_install: npm install -g @hashgraph/hedera-local${NC}"
    local install_label="localnode_install"
    RUN_LIST+=("$install_label")
    timing_init "$install_label"
    timing_start "${install_label}_startup"

    if npm install -g @hashgraph/hedera-local 2>&1; then
        echo -e "${GREEN}hedera-local installed successfully${NC}"
        kv_set NET_STATUS "$install_label" "PASS"
    else
        echo -e "${RED}npm install -g @hashgraph/hedera-local failed${NC}"
        kv_set NET_STATUS "$install_label" "FAIL"
    fi

    timing_end "${install_label}_startup"
    kv_set NET_PASSED "$install_label" "0"
    kv_set NET_FAILED "$install_label" "0"
    kv_set NET_TOTAL "$install_label" "0"

    timing_summary
    timing_export_json "${TIMING_DATA_DIR}/${install_label}-timing.json"
    if [ -f "$TIMING_DATA_FILE" ]; then
        cp "$TIMING_DATA_FILE" "${TIMING_DATA_DIR}/${install_label}-timing-data.txt"
    fi
    echo ""

    # ── Step 2: localnode_cold — full cold start ──
    # Ensure clean slate before cold start
    ensure_network_clean localnode

    # Clean Docker artifacts if --clean-images flag is set (simulates fresh machine)
    if [ "$CLEAN_IMAGES" = "true" ]; then
        clean_docker_artifacts
    fi

    echo -e "${CYAN}[2/4] localnode_cold: full cold start${NC}"
    local cold_label="localnode_cold"
    RUN_LIST+=("$cold_label")
    run_benchmark_lifecycle "$cold_label" "start_network localnode" "full" || true
    echo ""

    # ── Step 3: localnode_restart — CLI restart (hedera start after full stop) ──
    echo -e "${CYAN}[3/4] localnode_restart: CLI restart${NC}"
    local restart_label="localnode_restart"
    RUN_LIST+=("$restart_label")
    run_benchmark_lifecycle "$restart_label" "start_network localnode" "docker-stop" || true
    echo ""

    # ── Step 4: localnode_docker_warm — docker compose start (containers stopped, volumes preserved) ──
    echo -e "${CYAN}[4/4] localnode_docker_warm: docker compose start (experimental)${NC}"
    local docker_warm_label="localnode_docker_warm"
    RUN_LIST+=("$docker_warm_label")
    run_benchmark_lifecycle "$docker_warm_label" "start_localnode_docker_only" "full" || true
    echo ""
}

# ============================================================================
# Full Lifecycle: top-level dispatcher
# ============================================================================

run_full_lifecycle() {
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}   Full Lifecycle Benchmark${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    local has_solo=false
    local has_localnode=false
    local has_anvil=false
    local has_testnet=false

    for net in "${NETWORKS[@]}"; do
        case "$net" in
            solo) has_solo=true ;;
            localnode) has_localnode=true ;;
            anvil) has_anvil=true ;;
            hedera_testnet) has_testnet=true ;;
        esac
    done

    # Anvil lifecycle (cold + hot)
    if $has_anvil; then
        run_anvil_lifecycle
    fi

    # Solo lifecycle (install + cold + warm + hot)
    if $has_solo; then
        run_solo_lifecycle
    fi

    # Local Node lifecycle (install + cold + restart + docker_warm)
    if $has_localnode; then
        run_localnode_lifecycle
    fi

    # Hedera Testnet lifecycle (cold + warm)
    if $has_testnet; then
        run_testnet_lifecycle
    fi

    # Finalize evidence before report generation
    evidence_finalize

    # Generate the unified lifecycle report
    generate_lifecycle_report
}

# ============================================================================
# Generate lifecycle comparison report
# ============================================================================

generate_lifecycle_report() {
    local report_file="${REPORTS_DIR}/${TIMESTAMP}_deploy-benchmark.md"

    echo -e "${CYAN}Generating full lifecycle benchmark report...${NC}"

    # Helper to read timing for a specific run label
    timing_for() {
        local lbl="$1"
        local phase="$2"
        TIMING_DATA_FILE="${TIMING_OUTPUT_DIR}/${lbl}-timing-data.txt"
        timing_get_duration_formatted "${lbl}_${phase}" 2>/dev/null || echo "N/A"
    }

    # Helper to read timing in ms for a specific run label
    timing_for_ms() {
        local lbl="$1"
        local phase="$2"
        TIMING_DATA_FILE="${TIMING_OUTPUT_DIR}/${lbl}-timing-data.txt"
        timing_get_duration_ms "${lbl}_${phase}" 2>/dev/null || echo ""
    }

    {
        # ── Header ──
        echo "# Hedera EVM Lab - Full Lifecycle Benchmark Report"
        echo ""
        echo "**Generated**: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "**Report ID**: ${TIMESTAMP}"
        echo "**Test Mode**: full-lifecycle"
        echo "**Networks**: ${NETWORKS[*]}"
        echo "**Run Type**: Full Lifecycle (install → cold start → warm restart → hot restart)"
        echo ""
        echo "---"
        echo ""

        # ── Evidence & Verification ──
        echo "## Evidence & Verification"
        echo ""
        echo "| Field | Value |"
        echo "|-------|-------|"
        echo "| Git commit | \`$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')\` |"
        echo "| Git branch | \`$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')\` |"
        local dirty_status="clean"
        if ! git diff --quiet HEAD 2>/dev/null; then dirty_status="dirty"; fi
        echo "| Working tree | ${dirty_status} |"
        echo "| Run ID | ${TIMESTAMP} |"
        echo "| Evidence file | \`${TIMESTAMP}_timing-data/${TIMESTAMP}_evidence.json\` |"
        echo ""
        echo "---"
        echo ""

        # ── Test Matrix ──
        echo "## Test Matrix"
        echo ""

        # Anvil section
        local has_anvil_labels=false
        for label in "${RUN_LIST[@]}"; do
            if [ "$(net_name "$label")" = "anvil" ]; then has_anvil_labels=true; break; fi
        done
        if $has_anvil_labels; then
            echo "### Anvil (local Ethereum — baseline)"
            echo ""
            echo "| Run | What It Tests | Result |"
            echo "|-----|---------------|--------|"
            for label in "${RUN_LIST[@]}"; do
                local net
                net=$(net_name "$label")
                if [ "$net" = "anvil" ]; then
                    local status
                    status=$(kv_get NET_STATUS "$label" "SKIP")
                    local desc=""
                    case "$label" in
                        anvil) desc="Single run (start + benchmark + stop)" ;;
                        anvil_cold) desc="Cold start (start anvil + benchmark)" ;;
                        anvil_hot) desc="Hot restart (already running, health check only)" ;;
                    esac
                    echo "| $(display_name "$label") | ${desc} | ${status} |"
                fi
            done
            echo ""
        fi

        # Solo section
        local has_solo_labels=false
        for label in "${RUN_LIST[@]}"; do
            if [ "$(net_name "$label")" = "solo" ]; then has_solo_labels=true; break; fi
        done
        if $has_solo_labels; then
            echo "### Solo (Kubernetes/kind — 3-layer architecture)"
            echo ""
            echo "| Run | What It Tests | Result |"
            echo "|-----|---------------|--------|"
            for label in "${RUN_LIST[@]}"; do
                local net
                net=$(net_name "$label")
                if [ "$net" = "solo" ]; then
                    local status
                    status=$(kv_get NET_STATUS "$label" "SKIP")
                    local desc=""
                    case "$label" in
                        solo_install) desc="CLI install timing (brew reinstall)" ;;
                        solo_cold) desc="Full cold start (kind create + deploy)" ;;
                        solo_warm) desc="Warm restart (redeploy on existing cluster)" ;;
                        solo_hot) desc="Hot restart (health check only)" ;;
                    esac
                    echo "| $(display_name "$label") | ${desc} | ${status} |"
                fi
            done
            echo ""
        fi

        # Local Node section
        local has_localnode_labels=false
        for label in "${RUN_LIST[@]}"; do
            if [ "$(net_name "$label")" = "localnode" ]; then has_localnode_labels=true; break; fi
        done
        if $has_localnode_labels; then
            echo "### Local Node (Docker Compose — 2-layer architecture)"
            echo ""
            echo "| Run | What It Tests | Result |"
            echo "|-----|---------------|--------|"
            for label in "${RUN_LIST[@]}"; do
                local net
                net=$(net_name "$label")
                if [ "$net" = "localnode" ]; then
                    local status
                    status=$(kv_get NET_STATUS "$label" "SKIP")
                    local desc=""
                    case "$label" in
                        localnode_install) desc="CLI install timing (npm install -g)" ;;
                        localnode_cold) desc="Full cold start (hedera start)" ;;
                        localnode_restart) desc="CLI restart (hedera start after full stop)" ;;
                        localnode_docker_warm) desc="Docker warm (docker compose start, experimental)" ;;
                    esac
                    echo "| $(display_name "$label") | ${desc} | ${status} |"
                fi
            done
            echo ""
        fi

        # Hedera Testnet section
        local has_testnet_labels=false
        for label in "${RUN_LIST[@]}"; do
            if [ "$(net_name "$label")" = "hedera_testnet" ]; then has_testnet_labels=true; break; fi
        done
        if $has_testnet_labels; then
            echo "### Hedera Testnet (remote network)"
            echo ""
            echo "| Run | What It Tests | Result |"
            echo "|-----|---------------|--------|"
            for label in "${RUN_LIST[@]}"; do
                local net
                net=$(net_name "$label")
                if [ "$net" = "hedera_testnet" ]; then
                    local status
                    status=$(kv_get NET_STATUS "$label" "SKIP")
                    local desc=""
                    case "$label" in
                        hedera_testnet_cold) desc="First connection + benchmark" ;;
                        hedera_testnet_warm) desc="Cached connection + benchmark" ;;
                    esac
                    echo "| $(display_name "$label") | ${desc} | ${status} |"
                fi
            done
            echo ""
        fi

        echo "---"
        echo ""

        # ── Executive Summary ──
        echo "## Executive Summary"
        echo ""
        echo "| Scenario | Startup | Passed | Failed | Status |"
        echo "|----------|---------|--------|--------|--------|"
        for label in "${RUN_LIST[@]}"; do
            local passed failed status startup_val
            passed=$(kv_get NET_PASSED "$label" "0")
            failed=$(kv_get NET_FAILED "$label" "0")
            status=$(kv_get NET_STATUS "$label" "SKIP")
            startup_val=$(timing_for "$label" "startup")
            echo "| $(display_name "$label") | ${startup_val} | ${passed} | ${failed} | ${status} |"
        done
        echo ""
        echo "---"
        echo ""

        # ── Startup Time Comparison ──
        echo "## Startup Time Comparison"
        echo ""

        # Collect Solo labels and Local Node labels
        local solo_labels=()
        local localnode_labels=()
        local anvil_labels=()
        for label in "${RUN_LIST[@]}"; do
            local net
            net=$(net_name "$label")
            case "$net" in
                solo) solo_labels+=("$label") ;;
                localnode) localnode_labels+=("$label") ;;
                anvil) anvil_labels+=("$label") ;;
            esac
        done

        # Build side-by-side table
        local header="| Scenario |"
        local separator="|----------|"
        for label in "${RUN_LIST[@]}"; do
            header="${header} $(display_name "$label") |"
            separator="${separator}------|"
        done
        echo "$header"
        echo "$separator"

        # Startup row
        local row="| Network startup |"
        for label in "${RUN_LIST[@]}"; do
            local value
            value=$(timing_for "$label" "startup")
            row="${row} ${value} |"
        done
        echo "$row"

        # Benchmark row
        row="| Benchmark run |"
        for label in "${RUN_LIST[@]}"; do
            local value
            value=$(timing_for "$label" "benchmark")
            row="${row} ${value} |"
        done
        echo "$row"

        # Shutdown row
        row="| Shutdown |"
        for label in "${RUN_LIST[@]}"; do
            local value
            value=$(timing_for "$label" "shutdown")
            if [ "$value" = "N/A" ]; then
                row="${row} — |"
            else
                row="${row} ${value} |"
            fi
        done
        echo "$row"

        echo ""
        echo "---"
        echo ""

        # ── Contract Operations Comparison ──
        echo "## Contract Operations Comparison"
        echo ""

        local header="| Step |"
        local separator="|------|"
        for label in "${RUN_LIST[@]}"; do
            # Skip install-only labels (no contract ops)
            case "$label" in *_install) continue ;; esac
            header="${header} $(display_name "$label") |"
            separator="${separator}------|"
        done
        echo "$header"
        echo "$separator"

        local steps=("Deploy contract" "Write (increment)" "Read (count)" "Event verification" "Write (setCount)" "Final read")
        for step in "${steps[@]}"; do
            local row="| ${step} |"
            for label in "${RUN_LIST[@]}"; do
                case "$label" in *_install) continue ;; esac
                local output_file="${TEMP_DIR}/benchmark_${label}.txt"
                local value
                value=$(parse_benchmark_output "$output_file" "$step")
                row="${row} ${value} |"
            done
            echo "$row"
        done

        # Total row
        local row="| **TOTAL** |"
        for label in "${RUN_LIST[@]}"; do
            case "$label" in *_install) continue ;; esac
            local output_file="${TEMP_DIR}/benchmark_${label}.txt"
            local value
            value=$(parse_benchmark_output "$output_file" "TOTAL")
            row="${row} **${value}** |"
        done
        echo "$row"

        echo ""
        echo "---"
        echo ""

        # ── Per-Scenario Details ──
        echo "## Per-Scenario Details"
        echo ""

        for label in "${RUN_LIST[@]}"; do
            local net
            net=$(net_name "$label")
            echo "### $(display_name "$label")"
            echo ""
            local passed failed status
            passed=$(kv_get NET_PASSED "$label" "0")
            failed=$(kv_get NET_FAILED "$label" "0")
            status=$(kv_get NET_STATUS "$label" "SKIP")
            echo "**Status**: ${status}"

            # Install-only scenario
            case "$label" in
                *_install)
                    local startup_val
                    startup_val=$(timing_for "$label" "startup")
                    echo "**Install time**: ${startup_val}"
                    echo ""
                    echo "---"
                    echo ""
                    continue
                    ;;
            esac

            echo "**Tests**: ${passed} passed, ${failed} failed"
            echo ""

            # Orchestrator timing
            echo "| Phase | Duration |"
            echo "|-------|----------|"
            local startup_val benchmark_val shutdown_val
            startup_val=$(timing_for "$label" "startup")
            benchmark_val=$(timing_for "$label" "benchmark")
            shutdown_val=$(timing_for "$label" "shutdown")
            echo "| Startup | ${startup_val} |"
            echo "| Benchmark | ${benchmark_val} |"
            if [ "$shutdown_val" != "N/A" ]; then
                echo "| Shutdown | ${shutdown_val} |"
            fi
            echo ""

            # Contract operations
            local output_file="${TIMING_DATA_DIR}/${label}-benchmark-output.txt"
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

            # Show failed tests if any
            if [ "$failed" -gt 0 ] && [ -f "$output_file" ]; then
                echo "**Failed Tests**:"
                echo '```'
                grep -E "^\s+[0-9]+\)" "$output_file" 2>/dev/null || true
                echo '```'
                echo ""
            fi

            echo "---"
            echo ""
        done

        # ── Setup Requirements ──
        echo "## Setup Requirements"
        echo ""
        echo "| Network | Prerequisites | Install Command | Measured Install Time |"
        echo "|---------|--------------|-----------------|----------------------|"
        # Anvil
        local anvil_install_time="N/A"
        echo "| Anvil | Foundry | \`curl -L https://foundry.paradigm.xyz \\| bash && foundryup\` | ${anvil_install_time} |"
        # Solo
        local solo_install_time
        solo_install_time=$(timing_for "solo_install" "startup")
        echo "| Solo | Homebrew, Docker, kubectl, kind, helm | \`brew tap hiero-ledger/tools && brew install solo\` | ${solo_install_time} |"
        # Local Node
        local localnode_install_time
        localnode_install_time=$(timing_for "localnode_install" "startup")
        echo "| Local Node | Docker, Docker Compose, Node.js 20+ | \`npm install -g @hashgraph/hedera-local\` | ${localnode_install_time} |"
        # Testnet
        echo "| Hedera Testnet | HEDERA_TESTNET_PRIVATE_KEY | N/A (remote) | N/A |"
        echo ""
        echo "---"
        echo ""

        # ── Developer Loop Comparison ──
        echo "## Developer Loop Comparison"
        echo ""
        echo "Fastest retest path for each network (after initial setup):"
        echo ""
        echo "| Network | Fastest Retest | Startup Time | Contract Ops |"
        echo "|---------|---------------|-------------|-------------|"
        # Find fastest scenario per network
        for net_type in anvil solo localnode hedera_testnet; do
            local best_label="" best_startup_ms=999999999
            for label in "${RUN_LIST[@]}"; do
                local net
                net=$(net_name "$label")
                # Skip install-only labels
                case "$label" in *_install) continue ;; esac
                if [ "$net" = "$net_type" ]; then
                    local ms
                    ms=$(timing_for_ms "$label" "startup")
                    if [ -n "$ms" ] && [ "$ms" -lt "$best_startup_ms" ] 2>/dev/null; then
                        best_startup_ms=$ms
                        best_label=$label
                    fi
                fi
            done
            if [ -n "$best_label" ]; then
                local startup_val benchmark_val
                startup_val=$(timing_for "$best_label" "startup")
                local output_file="${TEMP_DIR}/benchmark_${best_label}.txt"
                benchmark_val=$(parse_benchmark_output "$output_file" "TOTAL")
                echo "| ${net_type} | $(display_name "$best_label") | ${startup_val} | ${benchmark_val} |"
            fi
        done
        echo ""
        echo "---"
        echo ""

        # ── CI Recommendations ──
        echo "## CI Recommendations"
        echo ""
        echo "| CI Use Case | Recommended Network | Why |"
        echo "|------------|-------------------|-----|"
        echo "| Unit tests / fast feedback | Anvil | Near-instant startup, full EVM compatibility |"
        echo "| Hedera-specific behavior | Solo (warm) or Local Node | Hedera EVM with mirror node; Solo warm avoids cluster creation overhead |"
        echo "| Pre-merge PR checks | Local Node (cold) | Deterministic from-scratch environment, moderate startup |"
        echo "| Nightly / full regression | Solo (cold) | Full Kubernetes deployment, closest to production topology |"
        echo "| Testnet integration | Hedera Testnet | Real network validation before mainnet deploy |"
        echo ""
        echo "---"
        echo ""

        # ── Architecture Analysis ──
        echo "## Architecture Analysis"
        echo ""
        echo "### Anvil (local Ethereum — baseline)"
        echo ""
        echo "Anvil is a local Ethereum node from the Foundry toolkit. It starts in under a second"
        echo "and provides full EVM compatibility. It serves as the performance baseline — any Hedera-specific"
        echo "overhead shows up as the delta between Anvil and the Hedera networks."
        echo ""
        echo "### Solo (Kubernetes / kind — 3-layer architecture)"
        echo ""
        echo "Solo's architecture has three layers: **CLI install → Kubernetes cluster → Hedera network**."
        echo "This creates distinct restart strategies:"
        echo ""
        echo "- **Cold start**: Creates kind cluster + deploys all Hedera components. Slowest path."
        echo "- **Warm restart**: Reuses existing cluster, only redeploys Hedera network. Cluster creation is skipped."
        echo "- **Hot restart**: Network is already running. Only a health check is needed. Fastest path."
        echo ""
        echo "The 3-layer architecture means Solo can preserve infrastructure (cluster) while redeploying"
        echo "application (network), giving developers a fast inner loop once the cluster is up."
        echo ""
        echo "### Local Node (Docker Compose — 2-layer architecture)"
        echo ""
        echo "Local Node's architecture has two layers: **CLI install → Docker containers**."
        echo "The \`hedera\` CLI always runs \`docker compose down -v\` on stop, which destroys volumes."
        echo ""
        echo "- **Cold start**: Full \`hedera start\` from scratch."
        echo "- **CLI restart**: \`hedera start\` after \`hedera stop\` — always a cold start because volumes are destroyed."
        echo "- **Docker warm** (experimental): Bypasses CLI with raw \`docker compose stop/start\` to preserve volumes."
        echo "  This tests whether Docker's volume persistence gives any startup benefit."
        echo ""
        echo "The 2-layer architecture is simpler but offers fewer restart strategies."
        echo "\`hedera stop\` is all-or-nothing — there's no equivalent to Solo's \`--keep-cluster\`."
        echo ""
        echo "### Hedera Testnet (remote network)"
        echo ""
        echo "Hedera Testnet is a remote network — no local infrastructure to manage."
        echo "Startup time is just connection validation. Contract operations reflect real network latency"
        echo "and gas pricing. Useful for integration testing before mainnet deployment."
        echo ""

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
        if command -v hedera &>/dev/null; then
            echo "- **Hedera CLI**: $(hedera --version 2>/dev/null | head -1 || echo 'installed')"
        fi
        echo ""
        echo "---"
        echo ""
        echo "*Report generated by run-deploy-benchmark.sh --full-lifecycle*"
        echo ""
        echo "Timing data: \`${TIMESTAMP}_timing-data/\`"
    } > "$report_file"

    echo -e "${GREEN}Report saved to: ${report_file}${NC}"
    echo -e "${GREEN}Timing data saved to: ${TIMING_DATA_DIR}/${NC}"
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

        # ── Evidence & Verification ──
        echo "## Evidence & Verification"
        echo ""
        echo "| Field | Value |"
        echo "|-------|-------|"
        echo "| Git commit | \`$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')\` |"
        echo "| Git branch | \`$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')\` |"
        local dirty_status="clean"
        if ! git diff --quiet HEAD 2>/dev/null; then dirty_status="dirty"; fi
        echo "| Working tree | ${dirty_status} |"
        echo "| Run ID | ${TIMESTAMP} |"
        echo "| Evidence file | \`${TIMESTAMP}_timing-data/${TIMESTAMP}_evidence.json\` |"
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

if $FULL_LIFECYCLE; then
    # Full lifecycle mode: lifecycle orchestrators manage RUN_LIST and shutdown
    run_full_lifecycle
else
    # Standard mode: run each network independently
    for label in "${RUN_LIST[@]}"; do
        run_benchmark "$label" || true
        echo ""
    done

    # Finalize evidence before report generation
    evidence_finalize

    generate_report
fi

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${GREEN}   Deploy Benchmark Complete${NC}"
echo -e "${CYAN}============================================${NC}"
echo "Total wall time: ${OVERALL_DURATION}s"
echo "Report: ${REPORTS_DIR}/${TIMESTAMP}_deploy-benchmark.md"
echo ""
