#!/usr/bin/env bash
# Clone all repositories for the Hedera EVM Lab
# Usage: ./clone-repos.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/../repos"

echo "=== Hedera EVM Lab - Repository Cloner ==="
echo "Target directory: ${REPO_DIR}"
echo ""

mkdir -p "${REPO_DIR}"

declare -A REPOS=(
    ["solo"]="https://github.com/hiero-ledger/solo.git"
    ["hiero-local-node"]="https://github.com/hiero-ledger/hiero-local-node.git"
    ["hardhat"]="https://github.com/NomicFoundation/hardhat.git"
    ["foundry"]="https://github.com/foundry-rs/foundry.git"
)

echo "Cloning repositories..."
echo ""

for repo_name in "${!REPOS[@]}"; do
    repo_url="${REPOS[$repo_name]}"
    repo_path="${REPO_DIR}/${repo_name}"

    if [ -d "${repo_path}/.git" ]; then
        echo "[SKIP] ${repo_name} already exists at ${repo_path}"
        echo "       Current SHA: $(git -C "${repo_path}" rev-parse HEAD)"
    else
        echo "[CLONE] ${repo_name} from ${repo_url}"
        git clone --depth 1 "${repo_url}" "${repo_path}"
        echo "       Cloned SHA: $(git -C "${repo_path}" rev-parse HEAD)"
    fi
    echo ""
done

echo "=== Repository SHAs ==="
for repo_name in "${!REPOS[@]}"; do
    repo_path="${REPO_DIR}/${repo_name}"
    if [ -d "${repo_path}/.git" ]; then
        sha=$(git -C "${repo_path}" rev-parse HEAD)
        echo "${repo_name}: ${sha}"
    fi
done

echo ""
echo "=== Clone Complete ==="
