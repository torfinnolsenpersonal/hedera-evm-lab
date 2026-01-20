# Stop Hiero Local Node (PowerShell)
# Based on: repos/hiero-local-node/README.md
# Usage: .\stop-local-node.ps1

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LabDir = Split-Path -Parent $ScriptDir

Write-Host "=== Stopping Hiero Local Node ===" -ForegroundColor Cyan
Write-Host ""

# Check if hedera CLI is available
try {
    $null = Get-Command hedera -ErrorAction Stop
    Write-Host "Using hedera CLI..."
    hedera stop
} catch {
    # Fallback to using the cloned repo
    $LocalNodeDir = Join-Path $LabDir "repos\hiero-local-node"

    if (Test-Path $LocalNodeDir) {
        Write-Host "Using cloned repo at $LocalNodeDir..."
        Push-Location $LocalNodeDir

        if (Test-Path "node_modules") {
            npm run stop
        } else {
            docker compose down -v 2>$null
        }

        Pop-Location
    } else {
        Write-Host "Attempting direct Docker cleanup..."
        docker compose down -v 2>$null
    }
}

Write-Host ""
Write-Host "Checking for leftover containers..."

# Clean up any remaining hedera containers
$containers = docker ps -a --filter "name=hedera" --filter "name=network-node" --filter "name=mirror" -q 2>$null
if ($containers) {
    Write-Host "Removing leftover containers..."
    $containers | ForEach-Object { docker rm -f $_ 2>$null }
}

# Check for hedera networks
$networks = docker network ls --filter "name=hedera" -q 2>$null
if ($networks) {
    Write-Host "Removing leftover networks..."
    $networks | ForEach-Object { docker network rm $_ 2>$null }
}

# Verify cleanup
$remaining = docker ps --filter "name=hedera" --filter "name=network-node" --filter "name=mirror" -q 2>$null
if (-not $remaining) {
    Write-Host ""
    Write-Host "=== CLEAN ===" -ForegroundColor Green
    Write-Host "All Local Node containers and networks removed."
} else {
    Write-Host ""
    Write-Host "Warning: Some containers may still be running:" -ForegroundColor Yellow
    docker ps --filter "name=hedera" --filter "name=network-node" --filter "name=mirror" --format "table {{.Names}}\t{{.Status}}"
}
