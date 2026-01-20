# Run Hardhat smoke tests against the running Hedera network
# Usage: .\run-hardhat-smoke.ps1 [localnode|solo]

param(
    [string]$Network = "localnode"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LabDir = Split-Path -Parent $ScriptDir
$HardhatDir = Join-Path $LabDir "examples\hardhat\contract-smoke"

Write-Host "=== Hardhat Smoke Test ===" -ForegroundColor Cyan
Write-Host "Network: $Network"
Write-Host ""

# Check if network is running
try {
    $response = Invoke-RestMethod -Uri "http://127.0.0.1:7546" -Method Post `
        -ContentType "application/json" `
        -Body '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

    if ($response.result -ne "0x12a") {
        throw "Wrong chain ID"
    }
    Write-Host "Network detected on port 7546 (Chain ID: 298)"
} catch {
    Write-Host "Error: No Hedera network detected on port 7546" -ForegroundColor Red
    Write-Host ""
    Write-Host "Start a network first:"
    Write-Host "  .\scripts\start-local-node.ps1   # For Local Node"
    Write-Host "  .\scripts\start-solo.ps1         # For Solo"
    exit 1
}

Write-Host ""
Push-Location $HardhatDir

if (-not (Test-Path "node_modules")) {
    Write-Host "Installing dependencies..."
    npm install
    Write-Host ""
}

Write-Host "Compiling contracts..."
npx hardhat compile
Write-Host ""

Write-Host "Running tests against $Network..." -ForegroundColor Cyan
npx hardhat test --network $Network

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== Hardhat Smoke Test PASSED ===" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "=== Hardhat Smoke Test FAILED ===" -ForegroundColor Red
}

Pop-Location
exit $LASTEXITCODE
