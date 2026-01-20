# Start Solo Network (One-Shot Single Node) - PowerShell
# Based on: repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md
# Usage: .\start-solo.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LabDir = Split-Path -Parent $ScriptDir

Write-Host "=== Starting Solo Network ===" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
$prereqs = @("docker", "kind", "kubectl", "solo")
foreach ($cmd in $prereqs) {
    try {
        $null = Get-Command $cmd -ErrorAction Stop
    } catch {
        Write-Host "Error: $cmd is not installed" -ForegroundColor Red
        switch ($cmd) {
            "docker" { Write-Host "Install Docker Desktop from https://www.docker.com/products/docker-desktop" }
            "kind" { Write-Host "Install with: choco install kind (Windows) or see https://kind.sigs.k8s.io/" }
            "kubectl" { Write-Host "Install with: choco install kubernetes-cli (Windows)" }
            "solo" { Write-Host "Install with: npm install -g @hashgraph/solo" }
        }
        exit 1
    }
}

# Environment variables for Solo
$env:SOLO_CLUSTER_NAME = if ($env:SOLO_CLUSTER_NAME) { $env:SOLO_CLUSTER_NAME } else { "solo" }
$env:SOLO_NAMESPACE = if ($env:SOLO_NAMESPACE) { $env:SOLO_NAMESPACE } else { "solo" }
$env:SOLO_CLUSTER_SETUP_NAMESPACE = if ($env:SOLO_CLUSTER_SETUP_NAMESPACE) { $env:SOLO_CLUSTER_SETUP_NAMESPACE } else { "solo-cluster" }
$env:SOLO_DEPLOYMENT = if ($env:SOLO_DEPLOYMENT) { $env:SOLO_DEPLOYMENT } else { "solo-deployment" }

Write-Host "Configuration:"
Write-Host "  Cluster Name: $($env:SOLO_CLUSTER_NAME)"
Write-Host "  Namespace:    $($env:SOLO_NAMESPACE)"
Write-Host "  Deployment:   $($env:SOLO_DEPLOYMENT)"
Write-Host ""

# Check if cluster already exists
$clusters = kind get clusters 2>$null
if ($clusters -contains $env:SOLO_CLUSTER_NAME) {
    Write-Host "Kind cluster '$($env:SOLO_CLUSTER_NAME)' already exists" -ForegroundColor Yellow
    Write-Host "Checking if Solo network is running..."

    $pods = kubectl get pods -n $env:SOLO_NAMESPACE 2>$null
    if ($pods -match "Running") {
        Write-Host "Solo network appears to be running already" -ForegroundColor Green
        Write-Host ""
        Write-Host "To restart, first run: .\stop-solo.ps1"
        Write-Host "Then run this script again."
        exit 0
    }
} else {
    Write-Host "Creating kind cluster '$($env:SOLO_CLUSTER_NAME)'..."
    kind create cluster -n $env:SOLO_CLUSTER_NAME
}

Write-Host ""
Write-Host "Deploying Solo network using one-shot command..."
Write-Host "This will deploy: consensus node, mirror node, explorer, and JSON-RPC relay"
Write-Host ""

# Use the one-shot single deploy command
solo one-shot single deploy

Write-Host ""
Write-Host "=== Solo Network Started Successfully ===" -ForegroundColor Green
Write-Host ""
Write-Host "=== Network Configuration ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "JSON-RPC Relay URL:      http://127.0.0.1:7546"
Write-Host "Chain ID:                298 (0x12a)"
Write-Host ""
Write-Host "Mirror Node REST API:    http://localhost:8081/api/v1"
Write-Host "Mirror Node gRPC:        localhost:5600"
Write-Host "Explorer:                http://localhost:8080"
Write-Host ""
Write-Host "Consensus Node:          localhost:50211"
Write-Host "Operator Account ID:     0.0.2"
Write-Host ""
Write-Host "=== READY ===" -ForegroundColor Green
