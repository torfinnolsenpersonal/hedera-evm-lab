# Stop Solo Network - PowerShell
# Based on: repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md
# Usage: .\stop-solo.ps1

$ErrorActionPreference = "Continue"

Write-Host "=== Stopping Solo Network ===" -ForegroundColor Cyan
Write-Host ""

# Environment variables for Solo
$env:SOLO_CLUSTER_NAME = if ($env:SOLO_CLUSTER_NAME) { $env:SOLO_CLUSTER_NAME } else { "solo" }

# Check if solo is installed
try {
    $null = Get-Command solo -ErrorAction Stop

    $clusters = kind get clusters 2>$null
    if ($clusters -contains $env:SOLO_CLUSTER_NAME) {
        Write-Host "Destroying Solo network..."
        solo one-shot single destroy 2>$null
    }
} catch {
    Write-Host "Warning: solo CLI not found, falling back to direct kind cleanup" -ForegroundColor Yellow
}

# Delete the kind cluster
try {
    $null = Get-Command kind -ErrorAction Stop
    Write-Host ""
    Write-Host "Deleting kind cluster '$($env:SOLO_CLUSTER_NAME)'..."

    $clusters = kind get clusters 2>$null
    if ($clusters -contains $env:SOLO_CLUSTER_NAME) {
        kind delete cluster -n $env:SOLO_CLUSTER_NAME
        Write-Host "Kind cluster deleted."
    } else {
        Write-Host "Kind cluster '$($env:SOLO_CLUSTER_NAME)' not found."
    }
} catch {}

Write-Host ""
Write-Host "=== CLEAN ===" -ForegroundColor Green
Write-Host "Solo network stopped and resources cleaned up."
