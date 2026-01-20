#!/usr/bin/env bash
# Stop Solo Network
# Based on: repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md
# Usage: ./stop-solo.sh
# Environment: RPC_PORT (default: 7546)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configurable port
RPC_PORT="${RPC_PORT:-7546}"
export RPC_PORT

echo -e "${CYAN}=== Stopping Solo Network ===${NC}"
echo "RPC_PORT=${RPC_PORT}"
echo ""

# Environment variables for Solo
export SOLO_CLUSTER_NAME="${SOLO_CLUSTER_NAME:-solo}"
export SOLO_NAMESPACE="${SOLO_NAMESPACE:-solo}"
export SOLO_DEPLOYMENT="${SOLO_DEPLOYMENT:-solo-deployment}"

# Check if solo is installed
if ! command -v solo &> /dev/null; then
    echo -e "${YELLOW}Warning: solo CLI not found, falling back to direct kind cleanup${NC}"
else
    # Check if cluster exists
    if kind get clusters 2>/dev/null | grep -q "^${SOLO_CLUSTER_NAME}$"; then
        echo "Destroying Solo network..."
        solo one-shot single destroy 2>/dev/null || true
    fi
fi

# Delete the kind cluster
if command -v kind &> /dev/null; then
    echo ""
    echo "Deleting kind cluster '${SOLO_CLUSTER_NAME}'..."
    if kind get clusters 2>/dev/null | grep -q "^${SOLO_CLUSTER_NAME}$"; then
        kind delete cluster -n "${SOLO_CLUSTER_NAME}"
        echo "Kind cluster deleted."
    else
        echo "Kind cluster '${SOLO_CLUSTER_NAME}' not found."
    fi
fi

# Clean up Solo home directory (optional, preserves logs)
# Uncomment to fully clean:
# rm -rf ~/.solo

echo ""
echo "Checking for leftover kind clusters..."
REMAINING_CLUSTERS=$(kind get clusters 2>/dev/null || echo "")

if [ -z "$REMAINING_CLUSTERS" ]; then
    echo "No kind clusters remaining."
else
    echo -e "${YELLOW}Remaining kind clusters:${NC}"
    echo "$REMAINING_CLUSTERS"
fi

# Check for leftover containers
echo ""
echo "Checking for leftover Docker resources..."

SOLO_CONTAINERS=$(docker ps -a --filter "name=solo" --filter "name=kind" -q 2>/dev/null || true)
if [ -n "$SOLO_CONTAINERS" ]; then
    echo "Cleaning up Solo-related containers..."
    echo "$SOLO_CONTAINERS" | xargs docker rm -f 2>/dev/null || true
fi

# Verify cleanup
REMAINING=$(docker ps --filter "name=solo" --filter "name=kind-${SOLO_CLUSTER_NAME}" -q 2>/dev/null || true)

if [ -z "$REMAINING" ]; then
    echo ""
    echo -e "${GREEN}=== CLEAN ===${NC}"
    echo "Solo network stopped and resources cleaned up."
    echo ""
    echo "Note: ~/.solo directory preserved (logs, cache)."
    echo "To fully clean: rm -rf ~/.solo"
else
    echo ""
    echo -e "${YELLOW}Warning: Some containers may still be running${NC}"
    docker ps --filter "name=solo" --filter "name=kind" --format "table {{.Names}}\t{{.Status}}"
fi

# Post-stop verification
echo ""
echo "Running post-stop verification..."
if [ -f "${SCRIPT_DIR}/cleanup.sh" ]; then
    "${SCRIPT_DIR}/cleanup.sh" --verify-only
fi
