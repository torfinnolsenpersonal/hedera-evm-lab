# Hedera EVM Lab - Documentation Proposals Summary

**Generated:** 2026-01-20
**Status:** LOCAL ONLY - These are proposals, not PRs

## Overview

This directory contains documentation proposals and patch files generated from the hedera-evm-lab workspace. All content is local and intended for review before any external submission.

## Proposals Included

### 01 - Solo Brew-First Installation

**Files:**
- `01-solo-brew-first-docs-proposal.md` - Full proposal document
- `01-solo-brew-first.patch` - Patch file for README.md changes

**Summary:**
Updates Solo documentation to recommend Homebrew as the primary installation method for macOS users, with npm as an alternative. Includes:
- README.md installation section rewrite
- Version pinning guidance for CI/CD
- Upgrade instructions

### 02 - Streamlined Solo README

**Files:**
- `02-solo-streamlined-readme-proposal.md` - Proposal with rationale

**Summary:**
Proposes a restructured README that:
- Leads with quick start (one-shot command)
- Reduces badge clutter
- Moves version matrix to documentation site
- Prioritizes action over explanation

### 03 - Port Conflict Documentation

**Files:**
- `03-port-conflict-documentation.md` - Implementation notes and upstream recommendations

**Summary:**
Documents the port conflict management implemented in hedera-evm-lab:
- Cleanup scripts for both bash and PowerShell
- RPC_PORT environment variable support
- Preflight/post-stop verification
- Recommendations for upstream Solo/Local Node

## Implementation Status in hedera-evm-lab

| Feature | Status | Files |
|---------|--------|-------|
| Brew-first Solo in local docs | Implemented | README.md, docs/01-setup-and-prereqs.md |
| Cleanup scripts | Implemented | scripts/cleanup.sh, scripts/cleanup.ps1 |
| Start/stop integration | Implemented | scripts/start-*.sh, scripts/stop-*.sh |
| RPC_PORT support | Implemented | All start/stop scripts |
| Transaction test harness | Implemented | scripts/run-transaction-tests.sh |
| Port checks in doctor | Implemented | scripts/doctor.sh |

## How to Use These Proposals

1. **Review locally:**
   ```bash
   cd ~/hedera-evm-lab/docs/proposals
   cat 01-solo-brew-first-docs-proposal.md
   ```

2. **Apply patch to test:**
   ```bash
   cd ~/hedera-evm-lab/repos/solo
   git apply ~/hedera-evm-lab/docs/proposals/01-solo-brew-first.patch --check
   ```

3. **For actual PR submission:**
   - Copy relevant content from proposals
   - Create proper git branch in target repo
   - Follow project's contribution guidelines

## Notes

- All proposals are suggestions based on hedera-evm-lab development experience
- No remote authentication or PR submission was performed
- Patch files are generated locally and may need adjustment for upstream repo state
- Test all changes before proposing upstream

## Directory Structure

```
docs/proposals/
├── 00-summary.md                           # This file
├── 01-solo-brew-first-docs-proposal.md     # Brew-first proposal
├── 01-solo-brew-first.patch                # README.md patch
├── 02-solo-streamlined-readme-proposal.md  # Streamlined README proposal
└── 03-port-conflict-documentation.md       # Port conflict implementation notes
```
