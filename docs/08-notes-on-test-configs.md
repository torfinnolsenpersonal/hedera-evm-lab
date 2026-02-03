# Notes on Test Configuration

This document explains the timing configurations used in tests to accommodate differences between Local Node and Solo environments. Understanding these configurations is essential for developers using Solo for testing their dApps.

## Quick Reference

**TL;DR: Solo needs ~5x longer wait times than Local Node due to Mirror Node sync latency.**

| Parameter | Hardhat | Anvil | Local Node | Solo | Hedera Testnet | Notes |
|-----------|---------|-------|------------|------|----------------|-------|
| Post-TX Wait | 0ms | 0ms | 500ms | 2500ms | 5000ms | Wait after state-changing transaction |
| Intermediate Wait | 0ms | 0ms | 300ms | 1500ms | 3000ms | Wait between sequential transactions |
| Test Timeout | 10-20s | 30s | 40-60s | 90-120s | 120s | Mocha test timeout |
| Network Timeout | N/A | 30s | 60s | 120s | 180s | Hardhat network config |
| Startup Stabilization | N/A | N/A | 10s | 30s | N/A (remote) | Wait after network ready |

---

## 1. Hardhat Configuration

**File:** `examples/hardhat/contract-smoke/hardhat.config.ts`

```typescript
networks: {
  localnode: {
    url: "http://127.0.0.1:7546",
    chainId: 298,
    timeout: 60000,    // 60 seconds
  },
  solo: {
    url: "http://127.0.0.1:7546",
    chainId: 298,
    timeout: 120000,   // 120 seconds (2x Local Node)
  },
  anvil: {
    url: "http://127.0.0.1:8545",
    chainId: 31337,
    timeout: 30000,    // 30 seconds
  },
  hedera_testnet: {
    url: "https://testnet.hashio.io/api",
    chainId: 296,
    timeout: 180000,   // 180 seconds (remote network)
  },
}
```

**Why 2x timeout for Solo?** Solo's Kubernetes-based architecture adds network overhead for RPC calls. The longer timeout prevents false failures from network latency.

**Why 180s for Hedera Testnet?** The public testnet has variable load and geographically distributed consensus nodes. Generous timeouts prevent spurious failures from network variability.

---

## 2. Test File Timing Configuration

Each test file contains a timing configuration block. Here's the canonical pattern:

**Location in each test file:** Lines 14-30

```typescript
const NETWORK_TIMINGS: Record<string, NetworkTiming> = {
  hardhat: {
    defaultWaitMs: 0,         // Instant (in-memory)
    intermediateWaitMs: 0,
    timeout: 10000,
  },
  anvil: {
    defaultWaitMs: 0,         // Instant (local Ethereum)
    intermediateWaitMs: 0,
    timeout: 30000,
  },
  localnode: {
    defaultWaitMs: 500,       // Wait after state-changing tx
    intermediateWaitMs: 300,  // Wait between sequential txs
    timeout: 40000,           // Mocha test timeout
  },
  solo: {
    defaultWaitMs: 2500,      // 5x longer for mirror node sync
    intermediateWaitMs: 1500, // 5x longer
    timeout: 90000,           // 2.25x longer
  },
  hedera_testnet: {
    defaultWaitMs: 5000,      // Remote network, variable latency
    intermediateWaitMs: 3000,
    timeout: 120000,
  },
};
```

### Files with this configuration:

| File | Purpose |
|------|---------|
| `test/Counter.test.ts` | Basic contract operations |
| `test/TestToken.test.ts` | ERC-20 token operations |
| `test/PayableTest.test.ts` | ETH/HBAR transfers |
| `test/Factory.test.ts` | Contract deployment patterns |
| `test/PrecompileTest.test.ts` | EVM precompile calls |
| `test/HederaHTSTest.test.ts` | Hedera-specific precompiles |

---

## 3. The `waitForTx()` Helper Functions

Every test file includes these helper functions to manage timing:

```typescript
// Wait for transaction and allow Hedera mirror node sync
async function waitForTx(tx: any, customDelayMs?: number): Promise<any> {
  const timing = getNetworkTiming();
  const delayMs = customDelayMs ?? timing.defaultWaitMs;
  const receipt = await tx.wait();

  // Allow time for Hedera mirror node to sync state
  if (delayMs > 0) {
    await new Promise(resolve => setTimeout(resolve, delayMs));
  }
  return receipt;
}

// Shorter wait for intermediate transactions in a sequence
async function waitForTxIntermediate(tx: any): Promise<any> {
  const timing = getNetworkTiming();
  return waitForTx(tx, timing.intermediateWaitMs);
}
```

### Usage Pattern

```typescript
// After a state-changing transaction, use waitForTx()
const tx = await counter.increment();
await waitForTx(tx);  // Uses defaultWaitMs (500ms local, 2500ms solo)

// For multiple sequential transactions, use intermediate for all but last
const tx1 = await counter.increment();
await waitForTxIntermediate(tx1);  // 300ms local, 1500ms solo
const tx2 = await counter.increment();
await waitForTxIntermediate(tx2);
const tx3 = await counter.increment();
await waitForTx(tx3);  // Full wait before assertions
```

---

## 4. Shell Script Delays

### Startup Scripts

| Script | Location | Delay | Purpose |
|--------|----------|-------|---------|
| `start-local-node.sh` | Line 159 | `sleep 2` | Wait between health check attempts |
| `start-solo.sh` | Line 197 | `sleep 5` | Wait between health check attempts |

### Test Orchestration (`run-all.sh`)

| Location | Delay | Purpose |
|----------|-------|---------|
| Line 121 | `sleep 10` | Wait for Local Node to stabilize after startup |
| Line 172 | `sleep 30` | Wait for Solo to stabilize after startup |
| Line 270 | `sleep 5` | Wait before starting Solo (after Local Node tests) |

### Cleanup Scripts

| Script | Delay | Purpose |
|--------|-------|---------|
| `cleanup.sh` | `sleep 0.5` | Wait after killing a process |
| `cleanup.sh` | `sleep 1` | Wait after killing kubectl port-forwards |
| `cleanup.sh` | `sleep 1` | Wait before final port verification |

---

## 5. Why Solo Needs Extra Time

### The Architectural Difference

**Local Node** uses a direct filesystem record stream parser:
```
Consensus Node → Record Stream File → [Direct Parse] → JSON-RPC Relay
                                       (filesystem)
```
- The JSON-RPC relay reads transaction records directly from the consensus node's record stream files
- This is essentially a "shortcut" where the relay parses the stream files from the filesystem
- **Result:** Near-instant state availability after transaction confirmation

**Solo** uses the Mirror Node as an intermediary (production-like):
```
Consensus Node → Record Stream → Mirror Node Importer → Mirror Node DB → JSON-RPC Relay
                                  (network hop)          (query)
```
- After consensus, transactions must flow through the Mirror Node importer
- The Mirror Node ingests record streams, processes them, and exposes them via REST/gRPC APIs
- The JSON-RPC relay queries the Mirror Node to get state information
- **Result:** Additional latency (~2-3 seconds) while waiting for Mirror Node to sync

### Impact on Tests

When a test:
1. Sends a transaction
2. Waits for receipt
3. Immediately queries state

**On Local Node:** The state is available almost instantly because of direct filesystem parsing.

**On Solo:** The state may not be visible yet because the Mirror Node hasn't finished ingesting and indexing the transaction record. Without the extra delay, tests fail with stale state reads.

---

## 6. Recommendations for Manual vs Automated Testing

### Manual Testing (Interactive Development)

When running tests manually during development:

```bash
# For Local Node - faster iteration
npx hardhat test --network localnode

# For Solo - use longer timeouts
npx hardhat test --network solo
```

**Tips:**
- Use Local Node for rapid iteration during development
- Only switch to Solo for integration testing or when testing Hedera-specific features
- If a test times out on Solo, try running it in isolation

### Automated Testing (CI/CD)

For CI/CD pipelines, use the `run-all.sh` script which handles timing automatically:

```bash
# Test against Local Node only (faster)
./scripts/run-all.sh localnode

# Test against Solo only
./scripts/run-all.sh solo

# Test both (comprehensive)
./scripts/run-all.sh both
```

**CI/CD Timing Considerations:**

| Metric | Local Node | Solo |
|--------|------------|------|
| Startup time | ~60s | ~12 minutes |
| Test suite (67 Hardhat + 144 Foundry) | ~3-5 min | ~15-20 min |
| Total CI time | ~5 min | ~30+ min |

**Recommendation:** Use Local Node for PR checks (fast feedback), Solo for nightly/release builds (production parity).

---

## 7. Tuning Parameters for Your Tests

If you're writing new tests, use this template:

```typescript
// At the top of your test file
interface NetworkTiming {
  defaultWaitMs: number;
  intermediateWaitMs: number;
  timeout: number;
}

const NETWORK_TIMINGS: Record<string, NetworkTiming> = {
  localnode: { defaultWaitMs: 500, intermediateWaitMs: 300, timeout: 40000 },
  solo: { defaultWaitMs: 2500, intermediateWaitMs: 1500, timeout: 90000 },
  hardhat: { defaultWaitMs: 0, intermediateWaitMs: 0, timeout: 10000 },
};

function getNetworkTiming(): NetworkTiming {
  return NETWORK_TIMINGS[network.name] || NETWORK_TIMINGS.solo;
}

// In your describe block
describe("MyContract", function () {
  const timing = getNetworkTiming();
  this.timeout(timing.timeout);

  // ... tests
});
```

### When to Increase Wait Times

You may need longer waits for:
- **Complex state changes**: Multi-step operations that modify multiple storage slots
- **Events with indexed parameters**: Event indexing adds slight delay
- **Cross-contract calls**: Factory patterns, proxy contracts
- **Token operations**: HTS operations may need additional sync time

### Debugging Timing Issues

If tests fail intermittently on Solo:

1. **Increase `defaultWaitMs`**: Try 3000-5000ms
2. **Add explicit waits before assertions**:
   ```typescript
   await waitForTx(tx);
   await new Promise(r => setTimeout(r, 1000)); // Extra 1s
   expect(await contract.value()).to.equal(expected);
   ```
3. **Check Mirror Node sync**: The mirror node REST API at `http://localhost:8081/api/v1/` shows sync status

---

## 8. Deploy Benchmark

The deploy benchmark (`test/DeployBenchmark.test.ts`) is a focused timing test that measures the core developer workflow across all five networks. It runs six timed steps:

1. **Deploy** the Counter contract
2. **Write** call `increment()`
3. **Read** call `count()`
4. **Event check** verify `CountChanged` event emitted
5. **Second write** call `setCount(42)`
6. **Final read** verify `count() == 42`

### Running the Deploy Benchmark

```bash
cd examples/hardhat/contract-smoke

# Against Hardhat (in-memory)
npm run benchmark

# Against Anvil (local Ethereum)
npm run benchmark:anvil

# Against Local Node
npm run benchmark:localnode

# Against Solo
npm run benchmark:solo

# Against Hedera Testnet (requires HEDERA_TESTNET_PRIVATE_KEY)
HEDERA_TESTNET_PRIVATE_KEY=0x... npm run benchmark:hedera_testnet
```

Or use the orchestrator script to run across multiple networks and generate a report:

```bash
./scripts/run-deploy-benchmark.sh anvil          # Single network
./scripts/run-deploy-benchmark.sh local          # anvil + localnode + solo
./scripts/run-deploy-benchmark.sh all            # All four networks
```

Reports are saved to `reports/YYYY-MM-DD_HH-MM-SS_deploy-benchmark.md`.

---

## 9. Anvil (Ethereum Baseline)

Anvil is Foundry's local Ethereum node, used here as a pure-EVM baseline for benchmarking. Since Anvil processes transactions instantly (no consensus delay, no mirror node), it represents the theoretical best-case performance for EVM operations.

| Parameter | Value | Notes |
|-----------|-------|-------|
| RPC URL | `http://127.0.0.1:8545` | Default Anvil port |
| Chain ID | 31337 (0x7a69) | Same as Hardhat Network |
| Post-TX Wait | 0ms | Instant block mining |
| Intermediate Wait | 0ms | No sync delay |
| Test Timeout | 30s | Generous for a local node |
| Network Timeout | 30s | Hardhat config |

### Startup

```bash
./scripts/start-anvil.sh    # Start on port 8545
./scripts/stop-anvil.sh     # Stop and free port
```

Anvil ships with 10 deterministic accounts, each funded with 10,000 ETH. Account #0 private key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`.

---

## 10. Hedera Testnet

Hedera Testnet is the public test network, used to benchmark against real Hedera infrastructure with geographically distributed consensus nodes.

| Parameter | Value | Notes |
|-----------|-------|-------|
| RPC URL | `https://testnet.hashio.io/api` | Default; override with `HEDERA_TESTNET_RPC_URL` |
| Chain ID | 296 (0x128) | Hedera Testnet |
| Post-TX Wait | 5000ms | Remote network + mirror node sync |
| Intermediate Wait | 3000ms | Variable network latency |
| Test Timeout | 120s | Generous for remote calls |
| Network Timeout | 180s | Hardhat config |

### Environment Setup

```bash
# Required
export HEDERA_TESTNET_PRIVATE_KEY=0x...

# Optional (defaults to https://testnet.hashio.io/api)
export HEDERA_TESTNET_RPC_URL=https://testnet.hashio.io/api
```

The account must be funded with HBAR on testnet. Create one at [portal.hedera.com](https://portal.hedera.com).

---

## 11. Summary Table

| Configuration Point | Hardhat | Anvil | Local Node | Solo | Hedera Testnet |
|---------------------|---------|-------|------------|------|----------------|
| `hardhat.config.ts` network timeout | N/A | 30000ms | 60000ms | 120000ms | 180000ms |
| `defaultWaitMs` (post-TX delay) | 0ms | 0ms | 500ms | 2500ms | 5000ms |
| `intermediateWaitMs` (between TXs) | 0ms | 0ms | 300ms | 1500ms | 3000ms |
| Mocha test timeout | 10000ms | 30000ms | 40000ms | 90000ms | 120000ms |
| Startup stabilization delay | N/A | N/A | 10s | 30s | N/A |
| Health check poll interval | N/A | N/A | 2s | 5s | N/A |

---

*Last updated: 2026-02-03 based on test run data*
