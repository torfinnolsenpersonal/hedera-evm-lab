#!/usr/bin/env bash
# Stop Hiero Local Node
# Based on: repos/hiero-local-node/README.md
# Usage: ./stop-local-node.sh [--docker-stop]
# Flags:
#   --docker-stop  Run `docker compose stop` (preserve volumes) instead of full teardown
# Environment: RPC_PORT (default: 7546)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="${SCRIPT_DIR}/.."

# Parse flags
DOCKER_STOP_ONLY=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker-stop) DOCKER_STOP_ONLY=true; shift ;;
        *) shift ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configurable port
RPC_PORT="${RPC_PORT:-7546}"
export RPC_PORT

echo -e "${CYAN}=== Stopping Hiero Local Node ===${NC}"
echo "RPC_PORT=${RPC_PORT}"
if $DOCKER_STOP_ONLY; then
    echo "Mode: docker compose stop (preserve volumes)"
fi
echo ""

# Discover the docker-compose working directory for hedera local node
find_localnode_compose_dir() {
    # 1. hedera CLI default workdir (macOS)
    local hedera_workdir="$HOME/Library/Application Support/hedera-local"
    if [ -f "${hedera_workdir}/docker-compose.yml" ] || [ -f "${hedera_workdir}/compose.yaml" ]; then
        echo "$hedera_workdir"
        return 0
    fi
    # 2. Cloned repo fallback
    local repo_dir="${LAB_DIR}/repos/hiero-local-node"
    if [ -d "$repo_dir" ]; then
        echo "$repo_dir"
        return 0
    fi
    return 1
}

if $DOCKER_STOP_ONLY; then
    # --docker-stop: use raw docker compose stop (no -v, preserves volumes)
    echo "Running docker compose stop (preserving volumes)..."
    COMPOSE_DIR=$(find_localnode_compose_dir) || true
    if [ -n "${COMPOSE_DIR:-}" ]; then
        echo "Using compose dir: ${COMPOSE_DIR}"
        cd "$COMPOSE_DIR"
        docker compose stop 2>/dev/null || true
    else
        echo -e "${YELLOW}Warning: Could not find docker-compose directory${NC}"
        echo "Attempting docker compose stop in current directory..."
        docker compose stop 2>/dev/null || true
    fi
    echo ""
    echo -e "${GREEN}=== Containers stopped (volumes preserved) ===${NC}"
    exit 0
fi

# Full stop (default behavior)
# Check if hedera CLI is available
if command -v hedera &> /dev/null; then
    echo "Using hedera CLI..."
    hedera stop
else
    # Fallback to using the cloned repo
    LOCAL_NODE_DIR="${LAB_DIR}/repos/hiero-local-node"

    if [ -d "$LOCAL_NODE_DIR" ]; then
        echo "Using cloned repo at ${LOCAL_NODE_DIR}..."
        cd "$LOCAL_NODE_DIR"

        if [ -d "node_modules" ]; then
            npm run stop
        else
            # Direct docker compose approach
            docker compose down -v 2>/dev/null || true
        fi
    else
        # Try direct docker approach
        echo "Attempting direct Docker cleanup..."
        docker compose down -v 2>/dev/null || true
    fi
fi

echo ""
echo "Checking for leftover containers..."

# Clean up any remaining hedera containers
HEDERA_CONTAINERS=$(docker ps -a --filter "name=hedera" --filter "name=network-node" --filter "name=mirror" -q 2>/dev/null || true)

if [ -n "$HEDERA_CONTAINERS" ]; then
    echo "Removing leftover containers..."
    echo "$HEDERA_CONTAINERS" | xargs docker rm -f 2>/dev/null || true
fi

# Check for hedera networks
HEDERA_NETWORKS=$(docker network ls --filter "name=hedera" -q 2>/dev/null || true)

if [ -n "$HEDERA_NETWORKS" ]; then
    echo "Removing leftover networks..."
    echo "$HEDERA_NETWORKS" | xargs docker network rm 2>/dev/null || true
fi

# Verify cleanup
REMAINING=$(docker ps --filter "name=hedera" --filter "name=network-node" --filter "name=mirror" -q 2>/dev/null || true)

if [ -z "$REMAINING" ]; then
    echo ""
    echo -e "${GREEN}=== CLEAN ===${NC}"
    echo "All Local Node containers and networks removed."
else
    echo ""
    echo -e "${YELLOW}Warning: Some containers may still be running:${NC}"
    docker ps --filter "name=hedera" --filter "name=network-node" --filter "name=mirror" --format "table {{.Names}}\t{{.Status}}"
    echo ""
    echo "Run 'docker rm -f \$(docker ps -aq --filter name=hedera)' to force remove"
fi

# Post-stop verification
echo ""
echo "Running post-stop verification..."
if [ -f "${SCRIPT_DIR}/cleanup.sh" ]; then
    "${SCRIPT_DIR}/cleanup.sh" --verify-only
fi
