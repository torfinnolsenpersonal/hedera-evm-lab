# Solo Quickstart: Deploy a Contract and Explore It

A hands-on walkthrough for deploying a smart contract to a fresh Solo one-shot network using Hardhat and Foundry, generating transactions, and reviewing everything in the local block explorer.

This guide assumes a fresh macOS install with Homebrew available. No existing repos or projects are required -- you'll create everything from scratch.

---

## Prerequisites

Install Solo and its dependencies via Homebrew:

```bash
brew install solo
```

This pulls in `kubectl`, `helm`, and `kind` automatically. You also need Docker Desktop running.

Verify:

```bash
solo --version
docker info >/dev/null 2>&1 && echo "Docker OK"
kubectl version --client --short 2>/dev/null && echo "kubectl OK"
kind --version && echo "kind OK"
```

For the Hardhat path, install Node.js. For the Foundry path, install Foundry:

```bash
# Node.js (for Hardhat)
brew install node

# Foundry (for Forge/Cast)
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

---

## Step 1: Start a Solo One-Shot Network

A one-shot deploy creates a complete Hedera network in a local Kubernetes cluster with a single command. This takes roughly 10-12 minutes on an M-series Mac.

```bash
solo one-shot single deploy
```

When it finishes, you'll see a summary with endpoints and pre-funded accounts. The key endpoints are:

| Service | URL | Notes |
|---------|-----|-------|
| JSON-RPC Relay | `http://127.0.0.1:7546` | Ethereum-compatible RPC |
| Mirror Node REST | `http://localhost:8081/api/v1` | Hedera Mirror Node API |
| Block Explorer | `http://localhost:8080` | HashScan-style explorer |
| Consensus Node gRPC | `localhost:50211` | Native Hedera SDK access |

**Chain ID:** 298 (`0x12a`)

The output also lists ECDSA Alias Accounts (EVM-compatible) with private keys and 10,000 HBAR each. You'll need one of these. The first account is typically:

```
Account ID:     0.0.1012
Public address: 0x67d8d32e9bf1a9968a5ff53b87d777aa8ebbee69
Private Key:    0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524
Balance:        10,000 HBAR
```

Copy the private key and address from your own output -- the exact values may differ.

Verify the network is responding:

```bash
curl -s -X POST http://127.0.0.1:7546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

Expected: `{"jsonrpc":"2.0","id":1,"result":"0x12a"}`

---

## Step 2a: Deploy with Hardhat

### Create a New Project

```bash
mkdir my-solo-project && cd my-solo-project
npm init -y
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
npx hardhat init
```

Select **Create a TypeScript project** when prompted. Accept the defaults.

### Add a Contract

Replace the sample contract with a Counter that generates transactions and events. Create `contracts/Counter.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Counter {
    uint256 public count;
    address public owner;

    event CountChanged(uint256 indexed newCount, address indexed changedBy);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Counter: caller is not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        count = 0;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function increment() public {
        count += 1;
        emit CountChanged(count, msg.sender);
    }

    function decrement() public {
        require(count > 0, "Counter: cannot decrement below zero");
        count -= 1;
        emit CountChanged(count, msg.sender);
    }

    function reset() public onlyOwner {
        count = 0;
        emit CountChanged(count, msg.sender);
    }

    function setCount(uint256 newCount) public onlyOwner {
        count = newCount;
        emit CountChanged(count, msg.sender);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Counter: new owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function getCount() public view returns (uint256) {
        return count;
    }
}
```

### Configure Hardhat for Solo

Edit `hardhat.config.ts` to add the Solo network. You need to add the RPC URL, chain ID, a pre-funded account key from the Solo output, and a longer timeout:

```typescript
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    // Solo network - paste your account key from the solo deploy output
    solo: {
      url: "http://127.0.0.1:7546",
      accounts: [
        // Replace with a private key from your solo one-shot output
        "0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524",
      ],
      chainId: 298,
      timeout: 120000,  // 2 minutes -- Solo needs longer than a local Ethereum node
    },
  },
};

export default config;
```

**Why `timeout: 120000`?** Solo runs inside Kubernetes with a JSON-RPC relay that communicates through the Mirror Node. This adds network overhead compared to a local Ethereum node. The 2-minute timeout prevents false timeout errors on slower machines.

### Write a Deploy Script

Create `scripts/deploy.ts`:

```typescript
import { ethers } from "hardhat";

async function main() {
  const network = await ethers.provider.getNetwork();
  console.log(`Deploying to chain ${network.chainId}`);

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.formatEther(balance), "HBAR");

  // Deploy
  const Counter = await ethers.getContractFactory("Counter");
  const counter = await Counter.deploy();
  await counter.waitForDeployment();

  const address = await counter.getAddress();
  console.log("Counter deployed to:", address);

  // Verify it works -- increment and read back
  const tx = await counter.increment();
  await tx.wait();

  // Wait for Solo's Mirror Node to sync (see timing note below)
  await new Promise(r => setTimeout(r, 2500));

  const count = await counter.count();
  console.log("Count after increment:", count.toString());
  console.log("\nSave this address:", address);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
```

**The 2500ms wait:** After `tx.wait()` returns, the consensus node has confirmed the transaction, but Solo's Mirror Node may not have indexed it yet. Without this pause, an immediate state read can return stale data. This is the single most important thing to know about testing on Solo. On a local Ethereum node or Hardhat's built-in network, this wait is unnecessary.

### Deploy

```bash
npx hardhat compile
npx hardhat run scripts/deploy.ts --network solo
```

Output:

```
Deploying to chain 298
Deployer: 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69
Balance: 10000.0 HBAR
Counter deployed to: 0xABC123...
Count after increment: 1

Save this address: 0xABC123...
```

Save the contract address for the next steps.

### Generate More Transactions

Open the Hardhat console connected to Solo:

```bash
npx hardhat console --network solo
```

```javascript
// Attach to your deployed contract
const Counter = await ethers.getContractFactory("Counter");
const counter = Counter.attach("0xABC123..."); // <-- your address here

// Read current state
await counter.count();   // 1n
await counter.owner();   // "0x67D8..."

// Send several transactions to generate activity
await (await counter.increment()).wait();
await (await counter.increment()).wait();
await (await counter.increment()).wait();

// Wait for Mirror Node, then read
await new Promise(r => setTimeout(r, 2500));
await counter.count();   // 4n

// Owner-only operation
await (await counter.setCount(42)).wait();
await new Promise(r => setTimeout(r, 2500));
await counter.count();   // 42n

// Query emitted events
const events = await counter.queryFilter(counter.filters.CountChanged());
events.forEach(e => console.log(`Block ${e.blockNumber}: count=${e.args.newCount}`));
```

Each `increment()`, `setCount()`, and `reset()` call creates a transaction with a `CountChanged` event that will be visible in the explorer.

---

## Step 2b: Deploy with Foundry

### Create a New Project

```bash
mkdir my-solo-foundry && cd my-solo-foundry
forge init
```

This creates the standard Foundry layout with `src/`, `test/`, `script/`, and `lib/`.

### Add a Contract

Replace `src/Counter.sol` with:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Counter {
    uint256 public count;
    address public owner;

    event CountChanged(uint256 indexed newCount, address indexed changedBy);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Counter: caller is not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        count = 0;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function increment() public {
        count += 1;
        emit CountChanged(count, msg.sender);
    }

    function decrement() public {
        require(count > 0, "Counter: cannot decrement below zero");
        count -= 1;
        emit CountChanged(count, msg.sender);
    }

    function reset() public onlyOwner {
        count = 0;
        emit CountChanged(count, msg.sender);
    }

    function setCount(uint256 newCount) public onlyOwner {
        count = newCount;
        emit CountChanged(count, msg.sender);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Counter: new owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function getCount() public view returns (uint256) {
        return count;
    }
}
```

### Create a Deploy Script

Create `script/Deploy.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Counter.sol";

contract DeployCounter is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        Counter counter = new Counter();
        console.log("Counter deployed to:", address(counter));

        counter.increment();
        console.log("Count after increment:", counter.count());

        vm.stopBroadcast();
    }
}
```

### Configure Environment

Create a `.env` file with a private key from your Solo output:

```bash
RPC_URL=http://127.0.0.1:7546
PRIVATE_KEY=0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524
CHAIN_ID=298
```

You can also add Solo's RPC to `foundry.toml`:

```toml
[rpc_endpoints]
solo = "http://127.0.0.1:7546"
```

### Deploy

```bash
source .env
forge script script/Deploy.s.sol:DeployCounter \
  --rpc-url $RPC_URL \
  --broadcast
```

### Generate Transactions with `cast`

Set the contract address from the deploy output:

```bash
export CONTRACT_ADDRESS=0xDEF456...
```

```bash
# Read current count
cast call $CONTRACT_ADDRESS "count()" --rpc-url $RPC_URL

# Increment (state-changing transaction)
cast send $CONTRACT_ADDRESS "increment()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Send a few more
cast send $CONTRACT_ADDRESS "increment()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $CONTRACT_ADDRESS "increment()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Read updated count (hex-encoded)
cast call $CONTRACT_ADDRESS "count()" --rpc-url $RPC_URL
# Returns: 0x0000...0004

# Set count to 42 (owner-only)
cast send $CONTRACT_ADDRESS "setCount(uint256)" 42 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Verify
cast call $CONTRACT_ADDRESS "count()" --rpc-url $RPC_URL
# Returns: 0x0000...002a (42)

# Check owner
cast call $CONTRACT_ADDRESS "owner()" --rpc-url $RPC_URL

# Inspect a specific transaction receipt
cast receipt <TX_HASH> --rpc-url $RPC_URL
```

### Running Tests Against Solo

Foundry tests can run in fork mode against the live Solo network:

```bash
forge test --fork-url $RPC_URL -vv
```

**Foundry fork mode limitation:** Hedera's system precompiles (HTS at `0x167`, Exchange Rate at `0x168`, PRNG at `0x169`) are not accessible in fork mode. These precompiles exist at the consensus layer, not as deployed EVM bytecode, so Foundry's forked EVM sees them as empty addresses. If your contracts call these precompiles, those tests will fail with "call to non-contract address." All standard EVM operations (keccak256, ecrecover, modexp, etc.) work normally. This is a Foundry limitation, not a Solo issue.

---

## Step 3: Review in the Block Explorer

Open the explorer at **http://localhost:8080**.

This is a HashScan-style block explorer connected to the Solo network's Mirror Node. It displays accounts, transactions, contracts, and tokens.

### Find Your Contract

1. Copy the contract address from the deploy output (e.g., `0xABC123...`)
2. Paste it into the explorer's search bar
3. You'll see the contract detail page with:
   - **Contract address** (both EVM and Hedera account ID format)
   - **Balance** (0 HBAR for a non-payable contract)
   - **Creator account** (your deployer address)
   - **Creation timestamp**

### View Transactions

On the contract page, click the **Transactions** tab to see all transactions against this contract:

- The **deployment transaction** (contract creation)
- Each **increment()** call
- The **setCount(42)** call
- Each transaction shows: hash, timestamp, sender, status (SUCCESS), and gas used

### Review a Specific Transaction

Click any transaction hash to see:
- **From / To** addresses
- **Function called** (decoded if ABI is known)
- **Gas used** vs gas limit
- **Input data** (raw calldata)
- **Logs/Events** emitted (e.g., `CountChanged(newCount=4, changedBy=0x67D8...)`)

### Query the Mirror Node REST API Directly

The explorer reads from the Mirror Node REST API, which you can also query from the command line:

```bash
# Get contract info
curl -s http://localhost:8081/api/v1/contracts/$CONTRACT_ADDRESS | jq .

# Get contract results (transactions)
curl -s "http://localhost:8081/api/v1/contracts/$CONTRACT_ADDRESS/results" | jq .

# Get recent blocks
curl -s "http://localhost:8081/api/v1/blocks?limit=5&order=desc" | jq .

# Get account info
curl -s "http://localhost:8081/api/v1/accounts/0.0.1012" | jq .

# Get event logs for the contract
curl -s "http://localhost:8081/api/v1/contracts/$CONTRACT_ADDRESS/results/logs" | jq .
```

---

## Step 4: Cleanup

When finished, tear down the Solo network:

```bash
solo one-shot single destroy
```

If that fails (it sometimes does with namespace issues), force cleanup:

```bash
kind delete cluster --name solo
```

Verify everything is clean:

```bash
kind get clusters          # Should be empty
docker ps                  # No solo-related containers
lsof -i :7546 2>/dev/null  # Port should be free
```

---

## Timing: What to Know

Solo's architecture mirrors production Hedera. After a transaction is confirmed by the consensus node, the Mirror Node must ingest and index it before the explorer or REST API can show it. This is the key difference from a local Ethereum node where state is available instantly.

| What You're Doing | Expected Delay | Why |
|-------------------|---------------|-----|
| `tx.wait()` returns | ~2-4 seconds | Consensus confirmation via relay |
| Transaction visible in explorer | 2-5 seconds after receipt | Mirror Node ingestion |
| Events queryable via REST API | 2-5 seconds after receipt | Mirror Node indexing |
| `eth_call` reads latest state | Near-instant after receipt | Reads from relay cache |

### Recommended Wait Times for Tests

If you're writing automated tests against Solo, add a post-transaction delay before reading state:

```typescript
// Hardhat example
const tx = await contract.someFunction();
await tx.wait();
await new Promise(r => setTimeout(r, 2500)); // Wait for Mirror Node
const value = await contract.someValue();     // Now reads fresh state
```

| Parameter | Recommended Value | Purpose |
|-----------|-------------------|---------|
| Post-TX wait | 2500ms | Pause after a state-changing TX before reading state |
| Intermediate wait | 1500ms | Pause between sequential TXs in a batch |
| Test timeout | 90000ms | Maximum time for a single Mocha/Jest test case |
| Hardhat network timeout | 120000ms | Set in `hardhat.config.ts` under `timeout` |

These waits are unnecessary on Hardhat's built-in network or a local Ethereum node. They exist because Solo routes state reads through the Mirror Node, which has an ingestion pipeline between the consensus node and query layer.

---

## Common Issues

**"execution reverted" on value transfers:** Hedera uses tinybars (1 HBAR = 10^8 tinybars), not wei (1 ETH = 10^18 wei). If your tests send `ethers.parseEther("1.0")`, the actual value received by the contract will differ from what Ethereum-targeted tests expect.

**Foundry fork tests fail on precompiles:** Hedera precompiles at addresses `0x167` (HTS), `0x168` (Exchange Rate), and `0x169` (PRNG) are consensus-layer contracts that don't exist as EVM bytecode. Foundry fork mode can't access them. Use Hardhat with `--network solo` for precompile testing instead.

**Explorer shows nothing after deploy:** The Mirror Node needs a few seconds to index. Wait 5 seconds and refresh. If still empty, verify the Mirror Node is responding:

```bash
curl -s http://localhost:8081/api/v1/blocks?limit=1 | jq .
```

**Transaction timeout:** If transactions consistently time out, check pod health:

```bash
kubectl get pods -n solo
```

All pods should be Running. If the relay pod is in CrashLoopBackOff, the network needs redeployment.

**Port 7546 already in use:** Check what's occupying it with `lsof -i :7546` and stop the conflicting process before starting Solo.
