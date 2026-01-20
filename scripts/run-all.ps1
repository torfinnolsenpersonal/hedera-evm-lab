# Run all smoke tests against Local Node and/or Solo
# Usage: .\run-all.ps1 [localnode|solo|both]
#
# IMPORTANT: Local Node and Solo share port 7546 (JSON-RPC relay).
# They cannot run simultaneously.

param(
    [ValidateSet("localnode", "solo", "both")]
    [string]$Mode = "localnode"
)

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Hedera EVM Lab - Full Test Suite" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$LocalNodeResult = 0
$SoloResult = 0

function Test-LocalNode {
    Write-Host "=== Testing with Hiero Local Node ===" -ForegroundColor Cyan
    Write-Host ""

    & "$ScriptDir\start-local-node.ps1"
    Write-Host ""
    Write-Host "Waiting for network to stabilize..."
    Start-Sleep -Seconds 10

    & "$ScriptDir\run-hardhat-smoke.ps1" -Network localnode
    $hardhatResult = $LASTEXITCODE

    & "$ScriptDir\run-foundry-smoke.ps1" -Fork
    $foundryResult = $LASTEXITCODE

    & "$ScriptDir\stop-local-node.ps1"

    if ($hardhatResult -ne 0 -or $foundryResult -ne 0) {
        return 1
    }
    return 0
}

function Test-Solo {
    Write-Host "=== Testing with Solo ===" -ForegroundColor Cyan
    Write-Host ""

    & "$ScriptDir\start-solo.ps1"
    Write-Host ""
    Write-Host "Waiting for Solo network to stabilize..."
    Start-Sleep -Seconds 30

    & "$ScriptDir\run-hardhat-smoke.ps1" -Network solo
    $hardhatResult = $LASTEXITCODE

    & "$ScriptDir\run-foundry-smoke.ps1" -Fork
    $foundryResult = $LASTEXITCODE

    & "$ScriptDir\stop-solo.ps1"

    if ($hardhatResult -ne 0 -or $foundryResult -ne 0) {
        return 1
    }
    return 0
}

switch ($Mode) {
    "localnode" {
        $LocalNodeResult = Test-LocalNode
    }
    "solo" {
        $SoloResult = Test-Solo
    }
    "both" {
        Write-Host "Running tests against BOTH networks sequentially" -ForegroundColor Yellow
        Write-Host "(They share port 7546 and cannot run simultaneously)" -ForegroundColor Yellow
        Write-Host ""

        $LocalNodeResult = Test-LocalNode
        Start-Sleep -Seconds 5
        $SoloResult = Test-Solo
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Test Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($Mode -eq "localnode" -or $Mode -eq "both") {
    if ($LocalNodeResult -eq 0) {
        Write-Host "Local Node: PASSED" -ForegroundColor Green
    } else {
        Write-Host "Local Node: FAILED" -ForegroundColor Red
    }
}

if ($Mode -eq "solo" -or $Mode -eq "both") {
    if ($SoloResult -eq 0) {
        Write-Host "Solo:       PASSED" -ForegroundColor Green
    } else {
        Write-Host "Solo:       FAILED" -ForegroundColor Red
    }
}

Write-Host ""

if ($LocalNodeResult -eq 0 -and $SoloResult -eq 0) {
    Write-Host "=== ALL TESTS PASSED ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== SOME TESTS FAILED ===" -ForegroundColor Red
    exit 1
}
