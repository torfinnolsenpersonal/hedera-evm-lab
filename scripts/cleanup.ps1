# Hedera EVM Lab - Cleanup Script (PowerShell)
# Ensures clean state by killing all port-forwards, proxies, and network processes
# Usage: .\cleanup.ps1 [-VerifyOnly]

param(
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Continue"

# Default ports
$RpcPort = if ($env:RPC_PORT) { $env:RPC_PORT } else { 7546 }
$WsPort = if ($env:WS_PORT) { $env:WS_PORT } else { 8546 }
$MirrorRestPort = 5551
$MirrorGrpcPort = 5600
$ExplorerPort = 8080
$ExplorerPortAlt = 8090
$ConsensusPort = 50211
$GrafanaPort = 3000
$PrometheusPort = 9090

$AllPorts = @($RpcPort, $WsPort, $MirrorRestPort, $MirrorGrpcPort, $ExplorerPort, $ExplorerPortAlt, $ConsensusPort, $GrafanaPort, $PrometheusPort)

$IssuesFound = 0

Write-Host "=== Hedera EVM Lab - Cleanup ===" -ForegroundColor Cyan
Write-Host "RPC_PORT=$RpcPort (override with RPC_PORT env var)"
Write-Host ""

function Get-PortProcess {
    param([int]$Port)

    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($connections) {
            $proc = Get-Process -Id $connections[0].OwningProcess -ErrorAction SilentlyContinue
            return @{
                PID = $connections[0].OwningProcess
                Name = $proc.ProcessName
            }
        }
    } catch {}
    return $null
}

function Stop-PortProcess {
    param([int]$Port)

    $info = Get-PortProcess -Port $Port
    if ($info) {
        Write-Host "Killing process on port ${Port}: PID=$($info.PID) ($($info.Name))" -ForegroundColor Yellow
        Stop-Process -Id $info.PID -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        return $true
    }
    return $false
}

function Stop-KubectlPortForwards {
    Write-Host "Checking for kubectl port-forward processes..."

    $procs = Get-Process | Where-Object { $_.ProcessName -like "*kubectl*" } -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Killing kubectl processes..." -ForegroundColor Yellow
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    } else {
        Write-Host "No kubectl port-forward processes found" -ForegroundColor Green
    }
}

function Stop-LocalNodeContainers {
    Write-Host ""
    Write-Host "Checking for Local Node containers..."

    $containers = docker ps -aq --filter "name=hedera" --filter "name=network-node" --filter "name=mirror" 2>$null
    if ($containers) {
        Write-Host "Stopping and removing Local Node containers..." -ForegroundColor Yellow
        $containers | ForEach-Object { docker stop $_ 2>$null; docker rm -f $_ 2>$null }
    } else {
        Write-Host "No Local Node containers running" -ForegroundColor Green
    }

    $networks = docker network ls --filter "name=hedera" -q 2>$null
    if ($networks) {
        Write-Host "Removing hedera networks..." -ForegroundColor Yellow
        $networks | ForEach-Object { docker network rm $_ 2>$null }
    }
}

function Test-PortsClean {
    Write-Host ""
    Write-Host "=== Port Status ===" -ForegroundColor Cyan

    $allClean = $true

    foreach ($port in $AllPorts) {
        $info = Get-PortProcess -Port $port
        if ($info) {
            Write-Host "[IN USE] Port $port - PID: $($info.PID) ($($info.Name))" -ForegroundColor Red
            $allClean = $false
            $script:IssuesFound++
        } else {
            Write-Host "[FREE] Port $port" -ForegroundColor Green
        }
    }

    return $allClean
}

if ($VerifyOnly) {
    Write-Host "Running in VERIFY-ONLY mode (no changes will be made)"
    Write-Host ""
    $null = Test-PortsClean
} else {
    Stop-KubectlPortForwards

    Write-Host ""
    Write-Host "Cleaning up processes on known ports..."
    foreach ($port in $AllPorts) {
        $null = Stop-PortProcess -Port $port
    }

    Stop-LocalNodeContainers

    Write-Host ""
    Start-Sleep -Seconds 1
    $null = Test-PortsClean
}

Write-Host ""
if ($IssuesFound -eq 0) {
    Write-Host "=== CLEAN ===" -ForegroundColor Green
    Write-Host "All ports are free. Ready to start a network."
    exit 0
} else {
    Write-Host "=== NOT CLEAN ===" -ForegroundColor Red
    Write-Host "Found $IssuesFound port(s) still in use."
    exit 1
}
