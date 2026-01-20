# Setup and Prerequisites

This document covers the system requirements and installation steps for the Hedera EVM Lab.

## Repository Commit SHAs

These are the versions of the repositories cloned in this workspace:

| Repository | Commit SHA |
|------------|------------|
| solo | 8e0f0075a53dfd9a0a3d191add9f136f573ee3e4 |
| hiero-local-node | b92cdb897403f358e1bad34c368a13fd7215f586 |
| hardhat | b1156c90176e69fc3fab61f7adea30e256e36ec5 |
| foundry | f613d83e3057040643a97ec1aad0e0c909163cf5 |

## System Requirements

### Minimum Requirements (Local Node Only)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| Memory | 8 GB | 16 GB |
| CPU Cores | 4 | 6+ |
| Disk Space | 20 GB | 40 GB |
| OS | macOS 12+, Linux (Ubuntu 22.04+), Windows 10+ (WSL2) | Same |

### Minimum Requirements (Solo)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| Memory | 12 GB | 16 GB+ |
| CPU Cores | 6 | 8+ |
| Disk Space | 20 GB | 40 GB |
| OS | macOS 12+, Linux (Ubuntu 22.04+), Windows 10+ (WSL2) | Same |

## Software Prerequisites

### Core Requirements (Both Tools)

| Software | Local Node Version | Solo Version | Installation |
|----------|-------------------|--------------|--------------|
| **Node.js** | >= 20.11.0 | >= 22.0.0 | See below |
| **NPM** | >= 10.2.4 | >= 9.8.1 | Bundled with Node.js |
| **Docker** | >= 27.3.1 | Latest | See below |
| **Docker Compose** | >= 2.29.7 | (via Docker) | Bundled with Docker Desktop |
| **Git** | Any recent | Any recent | See below |

### Solo-Specific Requirements

| Software | Version | Required | Installation |
|----------|---------|----------|--------------|
| **kubectl** | >= 1.27.3 | Yes | See below |
| **kind** | >= 0.26.0 | Yes | See below |
| **helm** | >= 3.14.2 | Recommended | See below |

## Installation Commands

### macOS (Homebrew)

```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Core tools
brew install git node@22 docker

# Solo-specific tools
brew install kubectl kind helm

# Hedera CLIs (after prerequisites)
npm install -g @hashgraph/hedera-local

# Solo CLI (Homebrew - recommended)
brew tap hiero-ledger/tools
brew install solo
# Or pin a specific version: brew install hiero-ledger/tools/solo@<version>
```

### Ubuntu/Debian (apt)

```bash
# Update package index
sudo apt update

# Install Git
sudo apt install -y git curl

# Install Node.js 22 (via NodeSource)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.26.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Hedera CLIs
npm install -g @hashgraph/hedera-local

# Solo CLI (npm - alternative to Homebrew for Linux)
# On macOS, prefer: brew tap hiero-ledger/tools && brew install solo
npm install -g @hashgraph/solo
```

### Fedora/RHEL (dnf)

```bash
# Install Git and curl
sudo dnf install -y git curl

# Install Node.js 22
sudo dnf module install nodejs:22

# Install Docker
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# kubectl, kind, helm - same as Ubuntu commands above
```

### Windows (WSL2)

**Important**: Run all commands inside WSL2 Ubuntu terminal.

1. Enable WSL2:
   ```powershell
   # In PowerShell (Admin)
   wsl --install
   # Restart computer, then:
   wsl --install Ubuntu
   ```

2. Install Docker Desktop for Windows with WSL2 backend enabled.

3. Follow Ubuntu instructions above inside WSL2 terminal.

Alternatively, use native Windows with:
```powershell
# Using Chocolatey
choco install git nodejs docker-desktop kubernetes-cli kind kubernetes-helm
npm install -g @hashgraph/hedera-local
# Solo CLI (npm is the primary option on Windows)
npm install -g @hashgraph/solo
```

### Using nvm (Recommended for Node.js version management)

```bash
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Restart shell, then:
nvm install 22
nvm use 22
nvm alias default 22

# Verify
node -v  # Should show v22.x.x
```

## Docker Configuration

### Docker Desktop Settings (macOS/Windows)

1. Open Docker Desktop > Settings > Resources
2. Configure:
   - **CPUs**: 6 (minimum)
   - **Memory**: 12 GB for Solo, 8 GB for Local Node
   - **Swap**: 1 GB
   - **Disk image size**: 64 GB

3. Enable VirtioFS file sharing (Settings > General)

4. On macOS/Windows, add the workspace directory to File Sharing if needed.

### Linux Docker Configuration

```bash
# Check Docker daemon memory
docker info | grep -i memory

# If needed, edit /etc/docker/daemon.json:
{
  "storage-driver": "overlay2",
  "default-address-pools": [
    {"base": "172.17.0.0/16", "size": 24}
  ]
}

# Restart Docker
sudo systemctl restart docker
```

## Verification

Run the doctor script to verify your setup:

```bash
# macOS/Linux
./scripts/doctor.sh

# Windows PowerShell
.\scripts\doctor.ps1
```

Expected output for a complete setup:
```
=== Core Requirements ===
[OK] Git found (version: 2.x.x)
[OK] Node.js 22.x.x (Solo requires 22+, Local Node requires 20+)
[OK] NPM found (version: 10.x.x)
[OK] Docker found (version: 27.x.x)
[OK] Docker Compose v2 found (version: 2.x.x)

=== Docker Resources ===
[OK] Docker memory: 12GiB (recommended: 12GB+)
[OK] Docker CPUs: 8 (recommended: 6+)

=== Solo-Specific Requirements ===
[OK] kubectl found (version: v1.x.x)
[OK] kind found (version: v0.26.x)
[OK] Helm found (version: v3.x.x)

=== Installed Hedera Tools ===
[OK] hedera-local CLI found
[OK] Solo CLI found (version: 0.53.x)

=== Summary ===
All required prerequisites are met!
```

## Evidence Files Referenced

- `repos/solo/README.md` - Solo prerequisites (lines 18-40)
- `repos/solo/package.json` - Node.js version requirement (line 130)
- `repos/hiero-local-node/README.md` - Local Node requirements (lines 26-56)
- `repos/hiero-local-node/package.json` - Dependencies and Node version
- `repos/solo/docs/site/content/en/templates/step-by-step-guide.template.md` - Full setup guide
