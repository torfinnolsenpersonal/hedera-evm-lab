# Run Foundry smoke tests
# Usage: .\run-foundry-smoke.ps1 [-Fork]

param(
    [switch]$Fork
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LabDir = Split-Path -Parent $ScriptDir
$FoundryDir = Join-Path $LabDir "examples\foundry\contract-smoke"

Write-Host "=== Foundry Smoke Test ===" -ForegroundColor Cyan
Write-Host ""

try {
    $null = Get-Command forge -ErrorAction Stop
} catch {
    Write-Host "Error: Foundry (forge) is not installed" -ForegroundColor Red
    Write-Host "Install with: curl -L https://foundry.paradigm.xyz | bash && foundryup"
    exit 1
}

Push-Location $FoundryDir

if (-not (Test-Path "lib\forge-std")) {
    Write-Host "Installing forge-std..."
    forge install foundry-rs/forge-std --no-commit
    Write-Host ""
}

if ($Fork) {
    $RpcUrl = "http://127.0.0.1:7546"

    try {
        $response = Invoke-RestMethod -Uri $RpcUrl -Method Post `
            -ContentType "application/json" `
            -Body '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

        if ($response.result -ne "0x12a") {
            throw "Wrong chain ID"
        }
    } catch {
        Write-Host "Error: No Hedera network detected on port 7546" -ForegroundColor Red
        Pop-Location
        exit 1
    }

    Write-Host "Running tests in FORK mode against Hedera network..."
    forge test --fork-url $RpcUrl -vvv
} else {
    Write-Host "Running tests locally (no fork)..."
    Write-Host "(Use -Fork to run against Hedera network)"
    forge test -vvv
}

$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "=== Foundry Smoke Test PASSED ===" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "=== Foundry Smoke Test FAILED ===" -ForegroundColor Red
}

Pop-Location
exit $exitCode
