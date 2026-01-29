# Notes on Test Configuration

This document explains the timing configurations used in tests to accommodate differences between Local Node and Solo environments. Understanding these configurations is essential for developers using Solo for testing their dApps.

## Quick Reference

**TL;DR: Solo needs ~5x longer wait times than Local Node due to Mirror Node sync latency.**

| Parameter | Local Node | Solo | Hardhat | Notes |
|-----------|------------|------|---------|-------|
| Post-TX Wait | 500ms | 2500ms | 0ms | Wait after state-changing transaction |
| Intermediate Wait | 300ms | 1500ms | 0ms | Wait between sequential transactions |
| Test Timeout | 40-60s | 90-120s | 10-20s | Mocha test timeout |
| Network Timeout | 60s | 120s | N/A | Hardhat network config |
| Startup Stabilization | 10s | 30s | N/A | Wait after network ready |

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
}
```

**Why 2x timeout for Solo?** Solo's Kubernetes-based architecture adds network overhead for RPC calls. The longer timeout prevents false failures from network latency.

---

## 2. Test File Timing Configuration

Each test file contains a timing configuration block. Here's the canonical pattern:

**Location in each test file:** Lines 14-30

```typescript
const NETWORK_TIMINGS: Record<string, NetworkTiming> = {
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
  hardhat: {
    defaultWaitMs: 0,         // Instant (in-memory)
    intermediateWaitMs: 0,
    timeout: 10000,
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

## 8. Summary Table

| Configuration Point | Local Node Value | Solo Value | Multiplier |
|---------------------|------------------|------------|------------|
| `hardhat.config.ts` network timeout | 60000ms | 120000ms | 2x |
| `defaultWaitMs` (post-TX delay) | 500ms | 2500ms | 5x |
| `intermediateWaitMs` (between TXs) | 300ms | 1500ms | 5x |
| Mocha test timeout | 40000ms | 90000ms | 2.25x |
| Startup stabilization delay | 10s | 30s | 3x |
| Health check poll interval | 2s | 5s | 2.5x |

---

*Last updated: 2026-01-28 based on test run data*
