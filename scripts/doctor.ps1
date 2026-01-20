# Hedera EVM Lab - Environment Doctor (PowerShell)
# Checks all prerequisites for Local Node and Solo
# Usage: .\doctor.ps1

$IssuesFound = 0

function Write-Status {
    param(
        [string]$Status,
        [string]$Message
    )
    switch ($Status) {
        "OK" { Write-Host "[OK] $Message" -ForegroundColor Green }
        "WARN" { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        "MISSING" { Write-Host "[MISSING] $Message" -ForegroundColor Red; $script:IssuesFound++ }
        "ERROR" { Write-Host "[ERROR] $Message" -ForegroundColor Red; $script:IssuesFound++ }
    }
}

function Test-Command {
    param(
        [string]$Command,
        [string]$Name,
        [bool]$Required = $true
    )

    try {
        $null = Get-Command $Command -ErrorAction Stop
        $version = ""
        try {
            switch ($Command) {
                "git" { $version = (git --version) -replace "git version ", "" }
                "node" { $version = (node -v) -replace "v", "" }
                "npm" { $version = npm -v }
                "docker" { $version = (docker --version) -replace "Docker version ", "" -replace ",.*", "" }
                "kubectl" { $version = (kubectl version --client -o json 2>$null | ConvertFrom-Json).clientVersion.gitVersion }
                "kind" { $version = (kind version) -replace "kind ", "" }
                "helm" { $version = (helm version --short) -replace "v", "" }
            }
        } catch {}

        if ($version) {
            Write-Status "OK" "$Name found (version: $version)"
        } else {
            Write-Status "OK" "$Name found"
        }
        return $true
    } catch {
        if ($Required) {
            Write-Status "MISSING" "$Name - REQUIRED"
        } else {
            Write-Host "[MISSING] $Name - optional" -ForegroundColor Yellow
        }
        return $false
    }
}

function Test-DockerCompose {
    try {
        $version = docker compose version --short 2>$null
        if ($version) {
            Write-Status "OK" "Docker Compose v2 found (version: $version)"
            return $true
        }
    } catch {}

    try {
        $version = (docker-compose --version) -match '\d+\.\d+\.\d+'
        if ($version) {
            Write-Host "[WARN] Docker Compose v1 found - v2 recommended" -ForegroundColor Yellow
            return $true
        }
    } catch {}

    Write-Status "MISSING" "Docker Compose - REQUIRED for Local Node"
    return $false
}

function Test-NodeVersion {
    try {
        $version = (node -v) -replace "v", ""
        $major = [int]($version.Split('.')[0])

        if ($major -ge 22) {
            Write-Status "OK" "Node.js $version (Solo requires 22+, Local Node requires 20+)"
        } elseif ($major -ge 20) {
            Write-Host "[WARN] Node.js $version (Local Node OK, but Solo requires 22+)" -ForegroundColor Yellow
        } else {
            Write-Status "ERROR" "Node.js $version (requires 20+ for Local Node, 22+ for Solo)"
        }
    } catch {
        Write-Status "MISSING" "Node.js - REQUIRED"
    }
}

Write-Host ""
Write-Host "=== Hedera EVM Lab - Environment Doctor ===" -ForegroundColor Cyan
Write-Host "Checking prerequisites for Hiero Local Node and Solo..."
Write-Host ""

Write-Host "=== Core Requirements ===" -ForegroundColor Cyan
Test-Command "git" "Git" $true | Out-Null
Test-NodeVersion
Test-Command "npm" "NPM" $true | Out-Null
Test-Command "docker" "Docker" $true | Out-Null
Test-DockerCompose | Out-Null

Write-Host ""
Write-Host "=== Docker Resources ===" -ForegroundColor Cyan
try {
    $dockerInfo = docker info 2>$null
    if ($dockerInfo) {
        $memLine = $dockerInfo | Select-String "Total Memory"
        if ($memLine) {
            $mem = $memLine -replace ".*: ", "" -replace " GiB", ""
            Write-Host "Docker memory: ${mem}GiB" -ForegroundColor $(if ([double]$mem -ge 12) { "Green" } elseif ([double]$mem -ge 8) { "Yellow" } else { "Red" })
        }
    }
} catch {
    Write-Status "ERROR" "Cannot query Docker info - is Docker running?"
}

Write-Host ""
Write-Host "=== Solo-Specific Requirements (Kubernetes) ===" -ForegroundColor Cyan
Test-Command "kubectl" "kubectl" $false | Out-Null
Test-Command "kind" "kind" $false | Out-Null
Test-Command "helm" "Helm" $false | Out-Null

Write-Host ""
Write-Host "=== Optional Tools ===" -ForegroundColor Cyan
Test-Command "curl" "curl" $false | Out-Null

Write-Host ""
Write-Host "=== Installed Hedera Tools ===" -ForegroundColor Cyan
try {
    $null = Get-Command hedera -ErrorAction Stop
    Write-Status "OK" "hedera-local CLI found"
} catch {
    Write-Host "[NOT INSTALLED] hedera-local CLI (install: npm install -g @hashgraph/hedera-local)" -ForegroundColor Yellow
}

try {
    $null = Get-Command solo -ErrorAction Stop
    $soloVersion = solo --version 2>$null
    Write-Status "OK" "Solo CLI found (version: $soloVersion)"
} catch {
    Write-Host "[NOT INSTALLED] Solo CLI" -ForegroundColor Yellow
    Write-Host "       Install (recommended on macOS): brew tap hiero-ledger/tools && brew install solo" -ForegroundColor Yellow
    Write-Host "       Or pin version: brew install hiero-ledger/tools/solo@<version>" -ForegroundColor Yellow
    Write-Host "       Install (Windows/npm): npm install -g @hashgraph/solo" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan

if ($IssuesFound -eq 0) {
    Write-Host "All required prerequisites are met!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Install hedera-local: npm install -g @hashgraph/hedera-local"
    Write-Host "  2. Install Solo (macOS): brew tap hiero-ledger/tools && brew install solo"
    Write-Host "     Or pin version:       brew install hiero-ledger/tools/solo@<version>"
    Write-Host "     On Windows/npm:       npm install -g @hashgraph/solo"
    Write-Host "  3. Start Local Node:     .\scripts\start-local-node.ps1"
    Write-Host "  4. Or start Solo:        .\scripts\start-solo.ps1"
} else {
    Write-Host "Found $IssuesFound issue(s) that need attention." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install missing requirements before proceeding."
}

Write-Host ""
exit $IssuesFound
