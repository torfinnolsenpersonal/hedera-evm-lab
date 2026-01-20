# Clone all repositories for the Hedera EVM Lab
# Usage: .\clone-repos.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Join-Path $ScriptDir "..\repos"

Write-Host "=== Hedera EVM Lab - Repository Cloner ===" -ForegroundColor Cyan
Write-Host "Target directory: $RepoDir"
Write-Host ""

if (-not (Test-Path $RepoDir)) {
    New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null
}

$Repos = @{
    "solo" = "https://github.com/hiero-ledger/solo.git"
    "hiero-local-node" = "https://github.com/hiero-ledger/hiero-local-node.git"
    "hardhat" = "https://github.com/NomicFoundation/hardhat.git"
    "foundry" = "https://github.com/foundry-rs/foundry.git"
}

Write-Host "Cloning repositories..."
Write-Host ""

foreach ($repo in $Repos.GetEnumerator()) {
    $repoName = $repo.Key
    $repoUrl = $repo.Value
    $repoPath = Join-Path $RepoDir $repoName

    if (Test-Path (Join-Path $repoPath ".git")) {
        Write-Host "[SKIP] $repoName already exists at $repoPath" -ForegroundColor Yellow
        $sha = git -C $repoPath rev-parse HEAD
        Write-Host "       Current SHA: $sha"
    } else {
        Write-Host "[CLONE] $repoName from $repoUrl" -ForegroundColor Green
        git clone --depth 1 $repoUrl $repoPath
        $sha = git -C $repoPath rev-parse HEAD
        Write-Host "       Cloned SHA: $sha"
    }
    Write-Host ""
}

Write-Host "=== Repository SHAs ===" -ForegroundColor Cyan
foreach ($repo in $Repos.GetEnumerator()) {
    $repoName = $repo.Key
    $repoPath = Join-Path $RepoDir $repoName
    if (Test-Path (Join-Path $repoPath ".git")) {
        $sha = git -C $repoPath rev-parse HEAD
        Write-Host "$repoName`: $sha"
    }
}

Write-Host ""
Write-Host "=== Clone Complete ===" -ForegroundColor Cyan
