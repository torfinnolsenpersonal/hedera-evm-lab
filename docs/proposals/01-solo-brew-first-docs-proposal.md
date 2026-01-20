# Proposal: Solo Documentation Updates - Homebrew-First Installation

**For:** Pranali's Docs PR
**Date:** 2026-01-20
**Status:** Proposal (LOCAL ONLY - not for direct submission)

## Summary

This proposal recommends updating Solo documentation to promote Homebrew installation as the primary method for macOS users, with npm as an alternative. This aligns with the Hiero project's official homebrew tap at `hiero-ledger/tools`.

## Rationale

1. **Homebrew provides better version management** - Users can pin specific versions with `brew install hiero-ledger/tools/solo@<version>`
2. **Simpler dependency resolution** - Homebrew handles Node.js version requirements automatically
3. **Consistent with ecosystem** - Other Hedera/Hiero tools are moving toward brew distribution
4. **Easier upgrades** - `brew upgrade solo` vs manual npm global updates

## Proposed Changes

### Change 1: README.md Installation Section

**Current (repos/solo/README.md:69-70):**
```markdown
## Install Solo

* Run `npm install -g @hashgraph/solo`
```

**Proposed:**
```markdown
## Install Solo

### macOS (Recommended)

```bash
# Add the Hiero homebrew tap
brew tap hiero-ledger/tools

# Install latest version
brew install solo

# Or install a specific version
brew install hiero-ledger/tools/solo@0.52.0
```

### npm (Alternative)

```bash
npm install -g @hashgraph/solo
```

> **Note:** On macOS, Homebrew installation is recommended for easier version management and upgrades.
```

### Change 2: Setup Section - Add Homebrew to Prerequisites

**Current (repos/solo/README.md:42-66):**
```markdown
## Setup

* Install [Node](https://nodejs.org/en/download). You may also use [nvm](https://github.com/nvm-sh/nvm)...
```

**Proposed addition after Node.js section:**
```markdown
* (macOS only) Install [Homebrew](https://brew.sh/) for easier Solo management:
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
```

### Change 3: Documentation Site Updates

For the Solo documentation site at `https://solo.hiero.org/`, update the "Getting Started" and "Installation" pages with:

1. **Primary installation path:** Homebrew (macOS)
2. **Secondary installation path:** npm (cross-platform)
3. **Version pinning guidance** for production/CI environments

Suggested content for installation page:

```markdown
## Installation

### macOS (Homebrew - Recommended)

Homebrew provides the easiest installation and upgrade experience on macOS:

1. **Add the Hiero tap:**
   ```bash
   brew tap hiero-ledger/tools
   ```

2. **Install Solo:**
   ```bash
   brew install solo
   ```

3. **Verify installation:**
   ```bash
   solo --version
   ```

#### Version Pinning

For CI/CD or production environments where you need a specific version:

```bash
# Install specific version
brew install hiero-ledger/tools/solo@0.52.0

# List available versions
brew search hiero-ledger/tools/solo
```

#### Upgrading

```bash
brew upgrade solo
```

### npm (Cross-Platform)

For Linux, Windows (WSL2), or if you prefer npm:

```bash
npm install -g @hashgraph/solo
```

#### Prerequisites for npm installation

- Node.js >= 22.0.0 (use [nvm](https://github.com/nvm-sh/nvm) for version management)
- npm >= 9.8.1
```

## Files to Update

| File | Section | Change Type |
|------|---------|-------------|
| `README.md` | Install Solo | Major rewrite |
| `README.md` | Setup | Add Homebrew prerequisite |
| `docs/site/content/en/docs/getting-started.md` | Installation | Add Homebrew section |
| `docs/site/content/en/templates/step-by-step-guide.template.md` | Prerequisites | Add Homebrew option |

## Patch File

See `01-solo-brew-first.patch` for the exact changes to README.md.

## Testing Checklist

- [ ] Verify `brew tap hiero-ledger/tools` works
- [ ] Verify `brew install solo` installs correctly
- [ ] Verify `brew install hiero-ledger/tools/solo@<version>` works for pinning
- [ ] Verify `solo --version` reports correct version
- [ ] Verify `solo one-shot single deploy` works after brew install
- [ ] Test on both Intel and Apple Silicon Macs

## Notes

- This proposal is for documentation changes only
- No code changes required
- The `hiero-ledger/tools` tap must be maintained by the Hiero team
- Consider adding CI checks to verify brew formula stays current with npm releases
