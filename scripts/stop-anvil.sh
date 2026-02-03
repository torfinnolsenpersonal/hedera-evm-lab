#!/usr/bin/env bash
# Stop Anvil by PID file or port lookup
# Usage: ./scripts/stop-anvil.sh [port]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

PORT="${1:-8545}"
PID_DIR="${TMPDIR:-/tmp}"
PID_FILE="${PID_DIR}/anvil.pid"

echo -e "${CYAN}=== Stopping Anvil ===${NC}"

KILLED=false

# Try PID file first
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Killing Anvil process (PID: ${PID}) from PID file"
        kill "$PID" 2>/dev/null || true
        KILLED=true
    fi
    rm -f "$PID_FILE"
fi

# Fallback: kill by port
if ! $KILLED; then
    PIDS=$(lsof -t -i ":${PORT}" -sTCP:LISTEN 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        echo "Killing process(es) on port ${PORT}: ${PIDS}"
        echo "$PIDS" | xargs kill 2>/dev/null || true
        KILLED=true
    fi
fi

if $KILLED; then
    # Wait briefly and verify port is free
    sleep 0.5
    if lsof -i ":${PORT}" -sTCP:LISTEN &> /dev/null; then
        echo -e "${RED}Warning: Port ${PORT} is still in use${NC}"
    else
        echo -e "${GREEN}Port ${PORT} is free${NC}"
    fi
    echo -e "${GREEN}=== Anvil Stopped ===${NC}"
else
    echo "No Anvil process found (PID file or port ${PORT})"
    echo -e "${GREEN}=== Nothing to stop ===${NC}"
fi
