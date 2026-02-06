#!/usr/bin/env bash
# Hedera EVM Lab - Cleanup Script
# Ensures clean state by killing all port-forwards, proxies, and network processes
# Usage: ./cleanup.sh [--verify-only]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default ports used by Hedera networks
RPC_PORT="${RPC_PORT:-7546}"
WS_PORT="${WS_PORT:-8546}"
MIRROR_REST_PORT="${MIRROR_REST_PORT:-5551}"
MIRROR_GRPC_PORT="${MIRROR_GRPC_PORT:-5600}"
EXPLORER_PORT="${EXPLORER_PORT:-8080}"
EXPLORER_PORT_ALT="${EXPLORER_PORT_ALT:-8090}"
CONSENSUS_PORT="${CONSENSUS_PORT:-50211}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"

ALL_PORTS=("$RPC_PORT" "$WS_PORT" "$MIRROR_REST_PORT" "$MIRROR_GRPC_PORT" "$EXPLORER_PORT" "$EXPLORER_PORT_ALT" "$CONSENSUS_PORT" "$GRAFANA_PORT" "$PROMETHEUS_PORT")

VERIFY_ONLY=false
ISSUES_FOUND=0

if [[ "${1:-}" == "--verify-only" ]]; then
    VERIFY_ONLY=true
fi

echo -e "${CYAN}=== Hedera EVM Lab - Cleanup ===${NC}"
echo "RPC_PORT=${RPC_PORT} (override with RPC_PORT env var)"
echo ""

# Function to check if a port is in use
check_port() {
    local port="$1"
    local pid=""
    local process=""

    if command -v lsof &> /dev/null; then
        pid=$(lsof -ti ":$port" 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            process=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            echo "$pid:$process"
            return 0
        fi
    elif command -v netstat &> /dev/null; then
        # Fallback for systems without lsof
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo "unknown:unknown"
            return 0
        fi
    fi
    return 1
}

# Function to kill process on port
kill_port() {
    local port="$1"
    local result

    if result=$(check_port "$port"); then
        local pid="${result%%:*}"
        local process="${result##*:}"

        if [ "$pid" != "unknown" ] && [ -n "$pid" ]; then
            echo -e "${YELLOW}Killing process on port $port: PID=$pid ($process)${NC}"
            kill -9 "$pid" 2>/dev/null || true
            sleep 0.5
            return 0
        fi
    fi
    return 1
}

# Kill kubectl port-forward processes
kill_kubectl_port_forwards() {
    echo "Checking for kubectl port-forward processes..."

    local pids
    pids=$(pgrep -f "kubectl port-forward" 2>/dev/null || true)

    if [ -n "$pids" ]; then
        echo -e "${YELLOW}Killing kubectl port-forward processes: $pids${NC}"
        echo "$pids" | xargs kill -9 2>/dev/null || true
        sleep 1
    else
        echo -e "${GREEN}No kubectl port-forward processes found${NC}"
    fi
}

# Stop Local Node containers
stop_local_node() {
    echo ""
    echo "Checking for Local Node containers..."

    local containers
    containers=$(docker ps -aq --filter "name=hedera" --filter "name=network-node" --filter "name=mirror" 2>/dev/null || true)

    if [ -n "$containers" ]; then
        echo -e "${YELLOW}Stopping and removing Local Node containers...${NC}"
        docker stop $containers 2>/dev/null || true
        docker rm -f $containers 2>/dev/null || true
    else
        echo -e "${GREEN}No Local Node containers running${NC}"
    fi

    # Clean up networks
    local networks
    networks=$(docker network ls --filter "name=hedera" -q 2>/dev/null || true)
    if [ -n "$networks" ]; then
        echo -e "${YELLOW}Removing hedera networks...${NC}"
        echo "$networks" | xargs docker network rm 2>/dev/null || true
    fi
}

# Stop Solo related processes
stop_solo() {
    echo ""
    echo "Checking for Solo/Kind processes..."

    # Check for kind clusters
    if command -v kind &> /dev/null; then
        local clusters
        clusters=$(kind get clusters 2>/dev/null || true)
        if [ -n "$clusters" ]; then
            echo -e "${YELLOW}Found kind clusters: $clusters${NC}"
            if [ "$VERIFY_ONLY" = false ]; then
                echo "Note: Use ./scripts/stop-solo.sh to properly destroy Solo clusters"
            fi
        else
            echo -e "${GREEN}No kind clusters found${NC}"
        fi
    fi

    # Kill any solo-related background processes
    # Exclude: benchmark script, docker monitor, caffeinate, and this script's own processes
    local solo_pids
    solo_pids=$(pgrep -f "solo" 2>/dev/null | \
        grep -v "^$$" | \
        grep -v "run-deploy-benchmark" | \
        grep -v "docker info" | \
        grep -v "caffeinate" | \
        grep -v "cleanup.sh" || true)
    if [ -n "$solo_pids" ]; then
        echo -e "${YELLOW}Found solo-related processes: $solo_pids${NC}"
        if [ "$VERIFY_ONLY" = false ]; then
            echo "$solo_pids" | xargs kill -9 2>/dev/null || true
        fi
    fi
}

# Verify ports are clean
verify_ports() {
    echo ""
    echo -e "${CYAN}=== Port Status ===${NC}"

    local all_clean=true

    for port in "${ALL_PORTS[@]}"; do
        local result
        if result=$(check_port "$port"); then
            local pid="${result%%:*}"
            local process="${result##*:}"
            echo -e "${RED}[IN USE]${NC} Port $port - PID: $pid ($process)"
            all_clean=false
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        else
            echo -e "${GREEN}[FREE]${NC} Port $port"
        fi
    done

    if [ "$all_clean" = true ]; then
        return 0
    fi
    return 1
}

# Main cleanup logic
if [ "$VERIFY_ONLY" = true ]; then
    echo "Running in VERIFY-ONLY mode (no changes will be made)"
    echo ""
    verify_ports
else
    # Step 1: Kill port forwards
    kill_kubectl_port_forwards

    # Step 2: Kill processes on known ports
    echo ""
    echo "Cleaning up processes on known ports..."
    for port in "${ALL_PORTS[@]}"; do
        kill_port "$port" || true
    done

    # Step 3: Stop Local Node
    stop_local_node

    # Step 4: Check Solo (but don't destroy clusters automatically)
    stop_solo

    # Step 5: Final verification
    echo ""
    sleep 1
    verify_ports
fi

echo ""
if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}=== CLEAN ===${NC}"
    echo "All ports are free. Ready to start a network."
    exit 0
else
    echo -e "${RED}=== NOT CLEAN ===${NC}"
    echo "Found $ISSUES_FOUND port(s) still in use."
    echo ""
    echo "Manual cleanup options:"
    echo "  1. Kill specific process: kill -9 <PID>"
    echo "  2. Stop Solo completely: ./scripts/stop-solo.sh"
    echo "  3. Nuclear option: docker rm -f \$(docker ps -aq); kind delete clusters --all"
    exit 1
fi
