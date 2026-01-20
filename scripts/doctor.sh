#!/usr/bin/env bash
# Hedera EVM Lab - Environment Doctor
# Checks all prerequisites for Local Node and Solo
# Usage: ./doctor.sh

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ISSUES_FOUND=0

# Configurable port (same default as the networks use)
RPC_PORT="${RPC_PORT:-7546}"

print_header() {
    echo ""
    echo -e "${CYAN}=== $1 ===${NC}"
}

check_command() {
    local cmd="$1"
    local name="$2"
    local required="$3"
    local version_cmd="${4:-}"

    if command -v "$cmd" &> /dev/null; then
        local version=""
        if [ -n "$version_cmd" ]; then
            version=$(eval "$version_cmd" 2>/dev/null || echo "unknown")
        fi
        echo -e "${GREEN}[OK]${NC} $name found${version:+ (version: $version)}"
        return 0
    else
        if [ "$required" = "required" ]; then
            echo -e "${RED}[MISSING]${NC} $name - REQUIRED"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        else
            echo -e "${YELLOW}[MISSING]${NC} $name - optional"
        fi
        return 1
    fi
}

check_docker_resources() {
    if command -v docker &> /dev/null; then
        local docker_info
        if docker_info=$(docker info 2>/dev/null); then
            local memory
            memory=$(echo "$docker_info" | grep "Total Memory" | awk '{print $3}' | sed 's/GiB//')
            if [ -n "$memory" ]; then
                local mem_int=${memory%.*}
                if [ "$mem_int" -ge 12 ]; then
                    echo -e "${GREEN}[OK]${NC} Docker memory: ${memory}GiB (recommended: 12GB+)"
                elif [ "$mem_int" -ge 8 ]; then
                    echo -e "${YELLOW}[WARN]${NC} Docker memory: ${memory}GiB (Solo needs 12GB+, Local Node needs 8GB+)"
                else
                    echo -e "${RED}[LOW]${NC} Docker memory: ${memory}GiB (minimum 8GB required)"
                    ISSUES_FOUND=$((ISSUES_FOUND + 1))
                fi
            fi

            local cpus
            cpus=$(echo "$docker_info" | grep "CPUs" | head -1 | awk '{print $2}')
            if [ -n "$cpus" ]; then
                if [ "$cpus" -ge 6 ]; then
                    echo -e "${GREEN}[OK]${NC} Docker CPUs: $cpus (recommended: 6+)"
                else
                    echo -e "${YELLOW}[WARN]${NC} Docker CPUs: $cpus (recommended: 6+)"
                fi
            fi
        else
            echo -e "${RED}[ERROR]${NC} Cannot query Docker info - is Docker running?"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi
}

check_docker_compose() {
    if docker compose version &> /dev/null; then
        local version
        version=$(docker compose version --short 2>/dev/null || echo "unknown")
        echo -e "${GREEN}[OK]${NC} Docker Compose v2 found (version: $version)"
        return 0
    elif command -v docker-compose &> /dev/null; then
        local version
        version=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        echo -e "${YELLOW}[WARN]${NC} Docker Compose v1 found ($version) - v2 recommended"
        return 0
    else
        echo -e "${RED}[MISSING]${NC} Docker Compose - REQUIRED for Local Node"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    fi
}

check_node_version() {
    if command -v node &> /dev/null; then
        local version
        version=$(node -v 2>/dev/null | sed 's/v//')
        local major
        major=$(echo "$version" | cut -d. -f1)

        if [ "$major" -ge 22 ]; then
            echo -e "${GREEN}[OK]${NC} Node.js $version (Solo requires 22+, Local Node requires 20+)"
        elif [ "$major" -ge 20 ]; then
            echo -e "${YELLOW}[WARN]${NC} Node.js $version (Local Node OK, but Solo requires 22+)"
        else
            echo -e "${RED}[OLD]${NC} Node.js $version (requires 20+ for Local Node, 22+ for Solo)"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    else
        echo -e "${RED}[MISSING]${NC} Node.js - REQUIRED"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
}

check_brew_tap() {
    if command -v brew &> /dev/null; then
        if brew tap 2>/dev/null | grep -q "hiero-ledger/tools"; then
            echo -e "${GREEN}[OK]${NC} Homebrew tap hiero-ledger/tools is configured"
            return 0
        else
            echo -e "${YELLOW}[MISSING]${NC} Homebrew tap hiero-ledger/tools"
            echo "       Install with: brew tap hiero-ledger/tools"
            return 1
        fi
    fi
    return 1
}

check_port_available() {
    local port="$1"
    if command -v lsof &> /dev/null; then
        if lsof -i ":$port" &> /dev/null; then
            local proc
            proc=$(lsof -ti ":$port" 2>/dev/null | head -1)
            local name="unknown"
            if [ -n "$proc" ]; then
                name=$(ps -p "$proc" -o comm= 2>/dev/null || echo "unknown")
            fi
            echo -e "${YELLOW}[IN USE]${NC} Port $port is in use (PID: $proc, $name)"
            return 1
        else
            echo -e "${GREEN}[FREE]${NC} Port $port is available"
            return 0
        fi
    else
        echo -e "${YELLOW}[SKIP]${NC} Cannot check port $port (lsof not available)"
        return 0
    fi
}

print_header "Hedera EVM Lab - Environment Doctor"
echo "Checking prerequisites for Hiero Local Node and Solo..."
echo "RPC_PORT=${RPC_PORT} (override with RPC_PORT env var)"

print_header "Core Requirements"
check_command "git" "Git" "required" "git --version | head -1"
check_node_version
check_command "npm" "NPM" "required" "npm -v"
check_command "docker" "Docker" "required" "docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1"
check_docker_compose

print_header "Docker Resources"
check_docker_resources

print_header "Solo-Specific Requirements (Kubernetes)"
check_command "kubectl" "kubectl" "optional" "kubectl version --client -o json 2>/dev/null | grep -oE '\"gitVersion\"[^,]+' | head -1 | cut -d'\"' -f4"
check_command "kind" "kind" "optional" "kind version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+'"
check_command "helm" "Helm" "optional" "helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+'"

print_header "Optional Tools"
check_command "curl" "curl" "optional" "curl --version | head -1"
check_command "jq" "jq" "optional" "jq --version"
check_command "brew" "Homebrew" "optional" "brew --version | head -1"

print_header "Homebrew Tap (for Solo via brew)"
if command -v brew &> /dev/null; then
    check_brew_tap
else
    echo -e "${YELLOW}[SKIP]${NC} Homebrew not installed (Solo can still be installed via npm)"
fi

print_header "Installed Hedera Tools"
if command -v hedera &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} hedera-local CLI found"
else
    echo -e "${YELLOW}[NOT INSTALLED]${NC} hedera-local CLI"
    echo "       Install: npm install -g @hashgraph/hedera-local"
fi

if command -v solo &> /dev/null; then
    local solo_version
    solo_version=$(solo --version 2>/dev/null | head -1 || echo "unknown")
    # Check if installed via brew
    local solo_path
    solo_path=$(which solo 2>/dev/null || echo "")
    if [[ "$solo_path" == *"Cellar"* ]] || [[ "$solo_path" == *"homebrew"* ]]; then
        echo -e "${GREEN}[OK]${NC} Solo CLI found via Homebrew (version: $solo_version)"
    else
        echo -e "${GREEN}[OK]${NC} Solo CLI found (version: $solo_version)"
    fi
else
    echo -e "${YELLOW}[NOT INSTALLED]${NC} Solo CLI"
    echo "       Install (recommended): brew tap hiero-ledger/tools && brew install solo"
    echo "       Install (alternative): npm install -g @hashgraph/solo"
fi

print_header "Port Availability"
check_port_available "$RPC_PORT"
check_port_available "5551"
check_port_available "5600"

print_header "Summary"

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}All required prerequisites are met!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Install hedera-local: npm install -g @hashgraph/hedera-local"
    echo "  2. Install Solo (brew):  brew tap hiero-ledger/tools && brew install solo"
    echo "     Or pin version:       brew install hiero-ledger/tools/solo@<version>"
    echo "  3. Start Local Node:     ./scripts/start-local-node.sh"
    echo "  4. Or start Solo:        ./scripts/start-solo.sh"
else
    echo -e "${RED}Found $ISSUES_FOUND issue(s) that need attention.${NC}"
    echo ""
    echo "Please install missing requirements before proceeding."
fi

echo ""
exit $ISSUES_FOUND
