# Solo Quickstart: Deploy a Contract and Explore It

A hands-on walkthrough for deploying a smart contract to a fresh Solo one-shot network using Hardhat and Foundry, generating transactions, and reviewing everything in the local block explorer.

This guide assumes a fresh macOS install with Homebrew available. Everything runs locally.

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

Verify the network is responding:

```bash
curl -s -X POST http://127.0.0.1:7546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

Expected: `{"jsonrpc":"2.0","id":1,"result":"0x12a"}`

---

## Step 2a: Deploy with Hardhat

### Setup

From the repo root:

```bash
cd examples/hardhat/contract-smoke
npm install
```

Create a `.env` file (or use the defaults which match Solo's pre-funded accounts):

```bash
cp .env.example .env
```

The `hardhat.config.ts` already has a `solo` network configured:

```typescript
solo: {
  url: "http://127.0.0.1:7546",
  accounts: [...],   // Pre-funded ECDSA keys
  chainId: 298,
  timeout: 120000,   // 2 minutes - Solo needs more time than Local Node
}
```

### Deploy the Counter Contract

```bash
npx hardhat run scripts/deploy.ts --network solo
```

Output:

```
=== Deploying Counter Contract ===
Network: solo (Chain ID: 298)

Deployer address: 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69
Deployer balance: 10000.0 HBAR

Deploying Counter...
Counter deployed to: 0xABC123...

Initial count: 0
Owner: 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69

Testing increment...
Count after increment: 1

=== Deployment Complete ===

Contract address: 0xABC123...
Save this address for later use!
```

**Save the contract address** -- you'll need it for the next steps.

### Generate Transactions

Use the interact script to send more transactions:

```bash
CONTRACT_ADDRESS=0xABC123... npx hardhat run scripts/interact.ts --network solo
```

This reads the current count, increments it, and queries recent `CountChanged` events.

You can also interact directly via the Hardhat console:

```bash
npx hardhat console --network solo
```

```javascript
const Counter = await ethers.getContractFactory("Counter");
const counter = Counter.attach("0xABC123...");

// Read state
await counter.count();        // 1n
await counter.owner();        // "0x67D8..."

// Generate transactions
await (await counter.increment()).wait();
await (await counter.increment()).wait();
await (await counter.increment()).wait();
await counter.count();        // 4n

// Set count directly (owner only)
await (await counter.setCount(42)).wait();
await counter.count();        // 42n

// Query events
const events = await counter.queryFilter(counter.filters.CountChanged());
events.forEach(e => console.log(`Block ${e.blockNumber}: count=${e.args.newCount}`));
```

**Solo timing note:** After each `tx.wait()`, the transaction is confirmed by the consensus node, but the Mirror Node (which the explorer reads from) may take 2-3 seconds to index it. If you check the explorer immediately and don't see your transaction, wait a few seconds and refresh.

### Run the Test Suite

```bash
npx hardhat test --network solo
```

The tests have built-in Solo timing: 2500ms post-transaction wait, 1500ms between sequential transactions, and 90-second test timeout. These accommodate the Mirror Node sync delay that Solo's production-like architecture requires. See `docs/08-notes-on-test-configs.md` for full details.

---

## Step 2b: Deploy with Foundry

### Setup

From the repo root:

```bash
cd examples/foundry/contract-smoke
```

Create a `.env` file:

```bash
cp .env.example .env
```

The `.env` contains:

```bash
RPC_URL=http://127.0.0.1:7546
PRIVATE_KEY=0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524
DEPLOYER_ADDRESS=0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69
CHAIN_ID=298
```

### Deploy the Counter Contract

```bash
source .env
forge script script/Deploy.s.sol:DeployCounter \
  --rpc-url $RPC_URL \
  --broadcast
```

Output:

```
=== Deploying Counter Contract ===
Deployer: 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69
Counter deployed to: 0xDEF456...
Count after increment: 1
=== Deployment Complete ===
```

### Generate Transactions with `cast`

```bash
# Read current count
cast call $CONTRACT_ADDRESS "count()" --rpc-url $RPC_URL

# Increment (state-changing)
cast send $CONTRACT_ADDRESS "increment()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Increment a few more times
cast send $CONTRACT_ADDRESS "increment()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $CONTRACT_ADDRESS "increment()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Read updated count
cast call $CONTRACT_ADDRESS "count()" --rpc-url $RPC_URL
# Returns: 0x0000...0004 (4 in hex)

# Set count to 42 (owner-only function)
cast send $CONTRACT_ADDRESS "setCount(uint256)" 42 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Verify
cast call $CONTRACT_ADDRESS "count()" --rpc-url $RPC_URL
# Returns: 0x0000...002a (42 in hex)

# Check owner
cast call $CONTRACT_ADDRESS "owner()" --rpc-url $RPC_URL

# Get a transaction receipt
cast receipt <TX_HASH> --rpc-url $RPC_URL
```

### Run the Foundry Test Suite

Foundry tests run in fork mode against the live network:

```bash
forge test --fork-url $RPC_URL -vv
```

**Foundry fork mode limitation:** Hedera's system precompiles (HTS at `0x167`, Exchange Rate at `0x168`, PRNG at `0x169`) are not accessible in fork mode because they exist at the consensus layer, not as deployed contracts. Six tests that call these precompiles will fail with "call to non-contract address". All standard EVM tests pass. This is a known Foundry limitation, not a Solo issue.

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

### View Contract State

The explorer's contract detail page shows:
- **Bytecode** (the deployed contract bytecode)
- **State** changes per transaction

### Review a Specific Transaction

Click any transaction hash to see:
- **From / To** addresses
- **Function called** (decoded if ABI is known)
- **Gas used** vs gas limit
- **Input data** (raw calldata)
- **Logs/Events** emitted (e.g., `CountChanged(newCount=4, changedBy=0x67D8...)`)

### Query the Mirror Node REST API Directly

The explorer reads from the Mirror Node REST API, which you can also query directly:

```bash
# Get contract info
curl -s http://localhost:8081/api/v1/contracts/$CONTRACT_ADDRESS | jq .

# Get contract results (transactions)
curl -s "http://localhost:8081/api/v1/contracts/$CONTRACT_ADDRESS/results" | jq .

# Get recent blocks
curl -s "http://localhost:8081/api/v1/blocks?limit=5&order=desc" | jq .

# Get account info
curl -s "http://localhost:8081/api/v1/accounts/0.0.1012" | jq .

# Get transaction logs (events)
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

## Timing Characteristics to Know

Solo's architecture mirrors production Hedera. After a transaction is confirmed by the consensus node, the Mirror Node must ingest and index it before the explorer or REST API can show it. This creates observable delays:

| What You're Doing | Expected Delay | Why |
|-------------------|---------------|-----|
| `tx.wait()` returns | ~2-4 seconds | Consensus confirmation |
| Transaction visible in explorer | 2-5 seconds after receipt | Mirror Node ingestion |
| Events queryable via REST API | 2-5 seconds after receipt | Mirror Node indexing |
| `eth_call` reads latest state | Near-instant after receipt | Reads from relay cache |

In practice, if you deploy a contract and immediately open the explorer, you'll see it. If you send a rapid burst of transactions and check the explorer, the last one or two may not appear for a few seconds.

For programmatic testing, the test files in this repo use these wait values:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `defaultWaitMs` | 2500ms | Pause after a state-changing TX before reading state |
| `intermediateWaitMs` | 1500ms | Pause between sequential TXs in a batch |
| `timeout` | 90000ms | Maximum time for a single test case |

These are unnecessary on Local Node (which uses 500ms / 300ms / 40s) because Local Node's relay reads state directly from the filesystem rather than through the Mirror Node. See `docs/08-notes-on-test-configs.md` for the full explanation.

---

## Common Issues

**"execution reverted" on value transfers:** Hedera uses tinybars (1 HBAR = 10^8 tinybars), not wei (1 ETH = 10^18 wei). If your tests send `ethers.parseEther("1.0")`, the actual value received by the contract will be different than expected. Use Hedera-appropriate amounts.

**Foundry fork tests fail on precompiles:** Hedera precompiles at addresses `0x167` (HTS), `0x168` (Exchange Rate), and `0x169` (PRNG) are consensus-layer contracts that don't exist as EVM bytecode. Foundry fork mode can't access them. Use Hardhat with `--network solo` for precompile testing instead.

**Explorer shows nothing after deploy:** The Mirror Node needs a few seconds to index. Wait 5 seconds and refresh. If still empty, check that port 8081 is responding:

```bash
curl -s http://localhost:8081/api/v1/blocks?limit=1 | jq .
```

**Transaction timeout:** Solo's default network timeout in Hardhat is 120 seconds. If transactions consistently time out, check pod health:

```bash
kubectl get pods -n solo
```

All pods should be Running. If the relay pod is in CrashLoopBackOff, the network needs redeployment.

**Port 7546 already in use:** Solo and Local Node both use port 7546. Only run one at a time. Check with `lsof -i :7546`.
