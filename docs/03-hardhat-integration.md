# Hardhat Integration Guide

This guide covers integrating Hardhat with both Hiero Local Node and Solo for Hedera EVM development.

## Overview

Hardhat connects to Hedera networks via the JSON-RPC Relay, which exposes an Ethereum-compatible JSON-RPC API. Both Local Node and Solo provide this relay on port 7546.

## Prerequisites

- Node.js >= 18.0.0
- Running Hedera network (Local Node or Solo)
- See `01-setup-and-prereqs.md` for installation

## Approach A: Hardhat with Local Node (Recommended)

### Network Configuration

Create or update `hardhat.config.ts`:

```typescript
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

// Default test accounts from Local Node (Alias ECDSA)
// These are pre-funded with 10,000 HBAR each
const LOCAL_NODE_ACCOUNTS = [
  "0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524",
  "0x2e1d968b041d84dd120a5860cee60cd83f9374ef527ca86996317ada3d0d03e7",
  "0x45a5a7108a18dd5013cf2d5857a28144beadc9c70b3bdbd914e38df4e804b8d8",
  "0x6e9d61a325be3f6675cf8b7676c70e4a004d2308e3e182370a41f5653d52c6bd",
  "0x0b58b1bd44469ac9f813b5aeaf6213ddaea26720f0b2f133d08b6f234130a64f",
];

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "localnode",
  networks: {
    // Hiero Local Node
    localnode: {
      url: process.env.LOCAL_NODE_RPC_URL || "http://127.0.0.1:7546",
      accounts: LOCAL_NODE_ACCOUNTS,
      chainId: 298,
      timeout: 60000, // Hedera has longer finality
    },
    // Hardhat's built-in network for fast unit tests
    hardhat: {
      chainId: 31337,
    },
  },
};

export default config;
```

### Account Addresses (for reference)

The accounts above correspond to these addresses:

| Account ID | Address | Private Key |
|------------|---------|-------------|
| 0.0.1012 | 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69 | 0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524 |
| 0.0.1013 | 0x05FbA803Be258049A27B820088bab1cAD2058871 | 0x2e1d968b041d84dd120a5860cee60cd83f9374ef527ca86996317ada3d0d03e7 |
| 0.0.1014 | 0x927E41Ff8307835A1C081e0d7fD250625F2D4D0E | 0x45a5a7108a18dd5013cf2d5857a28144beadc9c70b3bdbd914e38df4e804b8d8 |
| 0.0.1015 | 0xc37f417fA09933335240FCA72DD257BFBdE9C275 | 0x6e9d61a325be3f6675cf8b7676c70e4a004d2308e3e182370a41f5653d52c6bd |
| 0.0.1016 | 0xD927017F5a6a7A92458b81468Dc71FCE6115B325 | 0x0b58b1bd44469ac9f813b5aeaf6213ddaea26720f0b2f133d08b6f234130a64f |

Evidence: `repos/hiero-local-node/README.md:194-204`

### Environment Variables

Create `.env`:

```bash
# Local Node settings
LOCAL_NODE_RPC_URL=http://127.0.0.1:7546
LOCAL_NODE_CHAIN_ID=298

# Mirror Node (for verification/queries)
MIRROR_NODE_URL=http://127.0.0.1:5551
```

## Approach B: Hardhat with Solo

### Network Configuration

```typescript
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

// Solo uses the same JSON-RPC relay
// Create accounts with: solo ledger account create --deployment solo-deployment --hbar-amount 100
const SOLO_ACCOUNTS = process.env.SOLO_PRIVATE_KEYS?.split(",") || [];

const config: HardhatUserConfig = {
  solidity: "0.8.24",
  defaultNetwork: "solo",
  networks: {
    solo: {
      url: process.env.SOLO_RPC_URL || "http://127.0.0.1:7546",
      accounts: SOLO_ACCOUNTS,
      chainId: 298,
      timeout: 120000, // Solo may need more time
    },
  },
};

export default config;
```

### Creating Accounts in Solo

Solo doesn't auto-create test accounts. Create them manually:

```bash
# Create an account with ECDSA key (MetaMask compatible)
solo ledger account create --deployment solo-deployment --hbar-amount 1000 --generate-ecdsa-key

# The output will show the private key - save it!
# Add it to your .env file
```

## Hedera-Specific Gotchas

### 1. Gas and Transaction Fees

Hedera uses HBAR for gas, not gwei. The gas price is handled by the relay.

```typescript
// No need to specify gasPrice - the relay handles it
const tx = await contract.someFunction();
await tx.wait(); // Wait for finality
```

### 2. Transaction Receipts and Finality

Hedera has ~3-5 second finality. Always wait for transaction confirmation:

```typescript
const tx = await contract.doSomething();
const receipt = await tx.wait(); // Wait for confirmation
console.log("Transaction hash:", receipt.hash);
```

### 3. Block Times

Hedera doesn't have traditional blocks like Ethereum. The relay simulates block behavior.

```typescript
// Don't rely on block.number for timing
// Use timestamps instead
const timestamp = (await ethers.provider.getBlock("latest"))?.timestamp;
```

### 4. Event Logs

Events work but may have slight delays due to mirror node sync:

```typescript
// Listen for events
contract.on("Transfer", (from, to, value) => {
  console.log(`Transfer: ${from} -> ${to}: ${value}`);
});

// Or query past events
const filter = contract.filters.Transfer();
const events = await contract.queryFilter(filter, -1000); // Last 1000 blocks
```

### 5. Revert Messages

Enable dev mode for better revert messages:

```bash
# Local Node
hedera start --dev

# In Hardhat, catch reverts:
try {
  await contract.failingFunction();
} catch (error: any) {
  console.log("Revert reason:", error.reason);
}
```

### 6. Contract Size Limits

Hedera has a 24KB contract size limit (same as Ethereum):

```typescript
// In hardhat.config.ts
solidity: {
  version: "0.8.24",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200, // Optimize for deployment size
    },
  },
},
```

## Deployment Script Example

```typescript
// scripts/deploy.ts
import { ethers } from "hardhat";

async function main() {
  console.log("Deploying to Hedera Local Node...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Deployer balance:", ethers.formatEther(balance), "HBAR");

  // Deploy contract
  const Counter = await ethers.getContractFactory("Counter");
  const counter = await Counter.deploy();
  await counter.waitForDeployment();

  const address = await counter.getAddress();
  console.log("Counter deployed to:", address);

  // Verify deployment
  const count = await counter.count();
  console.log("Initial count:", count.toString());
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
```

## Test Example

```typescript
// test/Counter.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";

describe("Counter", function () {
  it("Should increment the counter", async function () {
    const Counter = await ethers.getContractFactory("Counter");
    const counter = await Counter.deploy();
    await counter.waitForDeployment();

    // Get initial count
    expect(await counter.count()).to.equal(0);

    // Increment
    const tx = await counter.increment();
    await tx.wait(); // Wait for Hedera finality

    // Check new count
    expect(await counter.count()).to.equal(1);
  });

  it("Should emit event on increment", async function () {
    const Counter = await ethers.getContractFactory("Counter");
    const counter = await Counter.deploy();
    await counter.waitForDeployment();

    await expect(counter.increment())
      .to.emit(counter, "CountChanged")
      .withArgs(1);
  });
});
```

## Running Tests

```bash
# Start Local Node first
hedera start --limits=false

# Or start Solo
solo one-shot single deploy

# Run tests
npx hardhat test --network localnode  # For Local Node
npx hardhat test --network solo       # For Solo

# Run specific test
npx hardhat test test/Counter.test.ts --network localnode
```

## Verification Commands

### Verify Hardhat can connect:

```bash
# Check chain ID
npx hardhat console --network localnode
> (await ethers.provider.getNetwork()).chainId
298n

# Check accounts
> const signers = await ethers.getSigners()
> signers[0].address
'0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69'

# Check balance
> await ethers.provider.getBalance(signers[0].address)
10000000000000000000000n  // 10000 HBAR in tinybar
```

### Expected Output for Successful Deploy:

```
Deploying to Hedera Local Node...
Deployer address: 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69
Deployer balance: 10000.0 HBAR
Counter deployed to: 0x0000000000000000000000000000000000001234
Initial count: 0
```

## Troubleshooting

### Connection Refused
- Ensure Local Node or Solo is running
- Check RPC URL: `curl http://127.0.0.1:7546 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'`
- Expected response: `{"jsonrpc":"2.0","id":1,"result":"0x12a"}`

### Transaction Timeout
- Increase timeout in hardhat.config.ts
- Check network health: `hedera status` or `kubectl get pods -n solo`

### Insufficient Funds
- Use pre-funded Local Node accounts
- For Solo, create accounts: `solo ledger account create --deployment solo-deployment --hbar-amount 1000`

### Wrong Chain ID
- Ensure chainId is 298 in hardhat.config.ts
- Verify: `npx hardhat console --network localnode` then `(await ethers.provider.getNetwork()).chainId`

## Evidence Files Referenced

- `repos/hiero-local-node/README.md:454-474` - Hardhat config example
- `repos/hiero-local-node/README.md:194-204` - Pre-funded accounts
- `repos/hiero-local-node/.env:58` - Chain ID configuration
