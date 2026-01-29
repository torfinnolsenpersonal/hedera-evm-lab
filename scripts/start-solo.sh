#!/usr/bin/env bash
# Start Solo Network (One-Shot Single Node)
# Based on: repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md
# Usage: ./start-solo.sh
# Environment: RPC_PORT (default: 7546)
#              TIMING_ENABLED (default: false) - enable timing instrumentation
#              TIMING_OUTPUT_DIR - directory for timing output files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="${SCRIPT_DIR}/.."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configurable port
RPC_PORT="${RPC_PORT:-7546}"
export RPC_PORT

# Timing instrumentation
TIMING_ENABLED="${TIMING_ENABLED:-false}"
if [ "$TIMING_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/lib/timing.sh" ]; then
    source "${SCRIPT_DIR}/lib/timing.sh"
    timing_init "solo"
    timing_start "solo_total"
fi

echo -e "${CYAN}=== Starting Solo Network ===${NC}"
echo "RPC_PORT=${RPC_PORT}"
echo ""

# Preflight cleanup - ensure no port conflicts
if [ "$TIMING_ENABLED" = "true" ]; then timing_start "solo_preflight"; fi

echo "Running preflight cleanup..."
if [ -f "${SCRIPT_DIR}/cleanup.sh" ]; then
    "${SCRIPT_DIR}/cleanup.sh" --verify-only
    CLEANUP_EXIT=$?
    if [ $CLEANUP_EXIT -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}Ports are in use. Running full cleanup...${NC}"
        "${SCRIPT_DIR}/cleanup.sh"
        echo ""
    fi
fi

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker is not running${NC}"
    exit 1
fi

if ! command -v kind &> /dev/null; then
    echo -e "${RED}Error: kind is not installed${NC}"
    echo "Install with: brew install kind (macOS) or see https://kind.sigs.k8s.io/"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Install with: brew install kubernetes-cli (macOS)"
    exit 1
fi

if ! command -v solo &> /dev/null; then
    echo -e "${RED}Error: solo is not installed${NC}"
    echo "Install with Homebrew (recommended):"
    echo "  brew tap hiero-ledger/tools"
    echo "  brew install solo"
    echo ""
    echo "Or pin a specific version:"
    echo "  brew install hiero-ledger/tools/solo@<version>"
    echo ""
    echo "Alternative (npm): npm install -g @hashgraph/solo"
    exit 1
fi

if [ "$TIMING_ENABLED" = "true" ]; then timing_end "solo_preflight"; fi

# Environment variables for Solo
export SOLO_CLUSTER_NAME="${SOLO_CLUSTER_NAME:-solo}"
export SOLO_NAMESPACE="${SOLO_NAMESPACE:-solo}"
export SOLO_CLUSTER_SETUP_NAMESPACE="${SOLO_CLUSTER_SETUP_NAMESPACE:-solo-cluster}"
export SOLO_DEPLOYMENT="${SOLO_DEPLOYMENT:-solo-deployment}"

echo "Configuration:"
echo "  Cluster Name: ${SOLO_CLUSTER_NAME}"
echo "  Namespace:    ${SOLO_NAMESPACE}"
echo "  Deployment:   ${SOLO_DEPLOYMENT}"
echo ""

# Create/check kind cluster
if [ "$TIMING_ENABLED" = "true" ]; then timing_start "solo_kind_cluster"; fi

if kind get clusters 2>/dev/null | grep -q "^${SOLO_CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Kind cluster '${SOLO_CLUSTER_NAME}' already exists${NC}"
    echo "Checking if Solo network is running..."

    if kubectl get pods -n "${SOLO_NAMESPACE}" 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}Solo network appears to be running already${NC}"
        echo ""
        echo "To restart, first run: ./stop-solo.sh"
        echo "Then run this script again."
        exit 0
    fi
else
    echo "Creating kind cluster '${SOLO_CLUSTER_NAME}'..."
    kind create cluster -n "${SOLO_CLUSTER_NAME}"
fi

if [ "$TIMING_ENABLED" = "true" ]; then timing_end "solo_kind_cluster"; fi

echo ""
echo "Deploying Solo network using one-shot command..."
echo "This will deploy: consensus node, mirror node, explorer, and JSON-RPC relay"
echo ""

# Deploy Solo with timing
if [ "$TIMING_ENABLED" = "true" ]; then timing_start "solo_deploy"; fi

# Use the one-shot single deploy command
# Capture output for parsing component timings if timing is enabled
if [ "$TIMING_ENABLED" = "true" ] && [ -n "${TIMING_OUTPUT_DIR:-}" ]; then
    SOLO_OUTPUT_LOG="${TIMING_OUTPUT_DIR}/solo-output.log"
    echo "[TIMING] Capturing Solo output to: $SOLO_OUTPUT_LOG"
    solo one-shot single deploy 2>&1 | tee "$SOLO_OUTPUT_LOG"
    SOLO_EXIT_CODE=${PIPESTATUS[0]}

    # Parse the Solo output for component timings
    if [ -f "${SCRIPT_DIR}/lib/parse-solo-output.sh" ] && [ -f "$SOLO_OUTPUT_LOG" ]; then
        echo ""
        echo "[TIMING] Parsing Solo component timings..."
        SOLO_COMPONENTS_JSON="${TIMING_OUTPUT_DIR}/solo-components.json"
        "${SCRIPT_DIR}/lib/parse-solo-output.sh" "$SOLO_OUTPUT_LOG" "$SOLO_COMPONENTS_JSON" || true
    fi

    if [ $SOLO_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}Solo deploy failed with exit code: $SOLO_EXIT_CODE${NC}"
        exit $SOLO_EXIT_CODE
    fi
else
    solo one-shot single deploy
fi

if [ "$TIMING_ENABLED" = "true" ]; then timing_end "solo_deploy"; fi

echo ""
echo -e "${GREEN}=== Solo Network Started Successfully ===${NC}"
echo ""
echo -e "${CYAN}=== Network Configuration ===${NC}"
echo ""
echo "JSON-RPC Relay URL:      http://127.0.0.1:${RPC_PORT}"
echo "Chain ID:                298 (0x12a)"
echo ""
echo "Mirror Node REST API:    http://localhost:8081/api/v1"
echo "Mirror Node gRPC:        localhost:5600"
echo "Explorer:                http://localhost:8080"
echo ""
echo "Consensus Node:          localhost:50211"
echo "Operator Account ID:     0.0.2"
echo "Operator Private Key:    302e020100300506032b65700422042091132178e72057a1d7528025956fe39b0b847f200ab59b2fdd367017f3087137"
echo ""
echo -e "${CYAN}=== Useful Commands ===${NC}"
echo ""
echo "Check pods:     kubectl get pods -n ${SOLO_NAMESPACE}"
echo "View logs:      kubectl logs -n ${SOLO_NAMESPACE} <pod-name>"
echo "Port forward:   kubectl port-forward -n ${SOLO_NAMESPACE} svc/<service> <port>:<port>"
echo ""
echo "Create account: solo ledger account create --deployment ${SOLO_DEPLOYMENT} --hbar-amount 100"
echo ""

# Verify network is healthy
if [ "$TIMING_ENABLED" = "true" ]; then timing_start "solo_health_wait"; fi

echo "Verifying network health..."
MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s "http://127.0.0.1:${RPC_PORT}" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | grep -q "0x12a"; then
        echo -e "${GREEN}JSON-RPC Relay is responding correctly (Chain ID: 298)${NC}"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "Waiting for JSON-RPC Relay... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}Warning: JSON-RPC Relay may not be fully ready yet${NC}"
    echo "Check pod status with: kubectl get pods -n ${SOLO_NAMESPACE}"
fi

if [ "$TIMING_ENABLED" = "true" ]; then timing_end "solo_health_wait"; fi

echo ""
echo -e "${GREEN}=== READY ===${NC}"

# Export timing data if enabled
if [ "$TIMING_ENABLED" = "true" ]; then
    timing_end "solo_total"
    timing_summary
    timing_export_json
fi
