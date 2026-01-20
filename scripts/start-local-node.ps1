# Start Hiero Local Node (PowerShell)
# Based on: repos/hiero-local-node/README.md
# Usage: .\start-local-node.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LabDir = Split-Path -Parent $ScriptDir

Write-Host "=== Starting Hiero Local Node ===" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
try {
    $null = Get-Command docker -ErrorAction Stop
} catch {
    Write-Host "Error: Docker is not installed" -ForegroundColor Red
    exit 1
}

try {
    docker info 2>$null | Out-Null
} catch {
    Write-Host "Error: Docker is not running" -ForegroundColor Red
    exit 1
}

# Check if hedera CLI is available
try {
    $null = Get-Command hedera -ErrorAction Stop
    Write-Host "Using hedera CLI..."
    Write-Host ""

    hedera start --limits=false
} catch {
    # Fallback to using the cloned repo
    $LocalNodeDir = Join-Path $LabDir "repos\hiero-local-node"

    if (-not (Test-Path $LocalNodeDir)) {
        Write-Host "Error: hiero-local-node repo not found at $LocalNodeDir" -ForegroundColor Red
        Write-Host "Please run: .\scripts\clone-repos.ps1"
        exit 1
    }

    Write-Host "Using cloned repo at $LocalNodeDir..."
    Write-Host ""

    Push-Location $LocalNodeDir

    if (-not (Test-Path "node_modules")) {
        Write-Host "Installing dependencies..."
        npm install
    }

    npm run start -- --limits=false

    Pop-Location
}

Write-Host ""
Write-Host "=== Network Configuration ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "JSON-RPC Relay URL:      http://127.0.0.1:7546"
Write-Host "JSON-RPC WebSocket:      ws://127.0.0.1:8546"
Write-Host "Chain ID:                298 (0x12a)"
Write-Host ""
Write-Host "Mirror Node REST API:    http://127.0.0.1:5551"
Write-Host "Mirror Node gRPC:        127.0.0.1:5600"
Write-Host "Mirror Node Explorer:    http://127.0.0.1:8090"
Write-Host ""
Write-Host "Consensus Node:          127.0.0.1:50211"
Write-Host "Node Account ID:         0.0.3"
Write-Host ""
Write-Host "=== Default Test Accounts (Alias ECDSA - MetaMask compatible) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Account 0.0.1012:"
Write-Host "  Address: 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69"
Write-Host "  Private Key: 0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524"
Write-Host ""
Write-Host "Account 0.0.1013:"
Write-Host "  Address: 0x05FbA803Be258049A27B820088bab1cAD2058871"
Write-Host "  Private Key: 0x2e1d968b041d84dd120a5860cee60cd83f9374ef527ca86996317ada3d0d03e7"
Write-Host ""
Write-Host "READY - Network is ready for transactions" -ForegroundColor Green
