# Benchmark Criteria Analysis

**Purpose**: Evaluate how our current test implementation meets the specified benchmark criteria, identify gaps, and provide precise definitions.

---

## Criteria Definitions vs. Current Implementation

### 1. Install Time

| Aspect | Specified Criteria | Current Implementation | Gap Analysis |
|--------|-------------------|------------------------|--------------|
| **Definition** | Time from a completely clean machine (no Docker images, no node_modules) to "ready to start" state | `brew reinstall solo` or `npm install -g @hashgraph/hedera-local` | **Partial match** |
| **Docker images** | Should include Docker image pull time | Not included — assumes images are cached | **Missing**: Need to add `docker image rm` before timing |
| **node_modules** | Should include npm install from scratch | Not included — hardhat project has cached node_modules | **Missing**: Need `rm -rf node_modules` before timing |
| **What we measure** | CLI install only | CLI binary/package installation | **Precise**: Only CLI install, not full environment |

**Recommendation**: Create two install modes:
- `install_cached`: Current behavior (measures CLI install with cached dependencies)
- `install_clean`: Full clean install (rm docker images, rm node_modules, then install)

---

### 2. Cold Start Time

| Aspect | Specified Criteria | Current Implementation | Gap Analysis |
|--------|-------------------|------------------------|--------------|
| **Definition** | Time from `docker compose up` with no existing volumes (fresh database, genesis blockchain state) to SDK transaction-ready | `start_network` function with RPC health check | **Partial match** |
| **Volume state** | No existing volumes | We run `ensure_network_clean()` which calls cleanup, but doesn't explicitly verify volumes are gone | **Imprecise**: Should verify `docker volume ls` is empty |
| **Genesis state** | Fresh blockchain state | Assumed from clean volumes | **OK**: Implied by volume cleanup |
| **Transaction-ready** | SDK transaction-ready | RPC health check (`eth_chainId` returns 0x12a) | **Imprecise**: Health check ≠ transaction-ready |

**Current Cold Start verification**:
```bash
# We check:
curl http://127.0.0.1:7546 -X POST -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Returns: {"result":"0x12a"}
```

**What "SDK transaction-ready" should mean**:
- For HAPI: Can execute `AccountCreateTransaction` via Hedera SDK
- For EVM: Can execute `eth_sendTransaction` and get mined receipt

**Recommendation**: Add actual transaction test after RPC health check:
```typescript
// After health check passes, verify transaction capability
const tx = await signer.sendTransaction({ to: signer.address, value: 0 });
await tx.wait(); // Only "ready" when this succeeds
```

---

### 3. Warm Start Time

| Aspect | Specified Criteria | Current Implementation | Gap Analysis |
|--------|-------------------|------------------------|--------------|
| **Definition** | Time from `docker compose up` with preserved volumes (existing database, blockchain state) to SDK transaction-ready | Solo: `--keep-cluster` mode; Local Node: **Not possible** | **Partial match** |
| **Volume preservation** | Volumes must persist across restart | Solo: Kind cluster persists, pods redeployed; Local Node: `hedera stop` destroys volumes | **Gap for Local Node** |
| **State preservation** | Existing blockchain state | Solo warm: Fresh deploy but cluster resources cached; True warm would keep state | **Imprecise** |

**Solo "warm" is actually "warm infrastructure, cold application"**:
- Kind cluster: Preserved
- Docker images: Cached in cluster
- Hedera pods: Destroyed and redeployed
- Blockchain state: Fresh (not preserved)

**True warm start would require**:
- Pods stopped but not deleted
- Volumes preserved
- `kubectl scale --replicas=0` then `--replicas=1`

**Local Node cannot do warm start** because `hedera stop` runs:
```bash
docker compose down -v  # -v destroys volumes
```

**Recommendation**:
1. Rename current Solo "warm" to "warm_cluster" (infrastructure warm, app cold)
2. Implement true "warm" for Local Node via `docker compose stop` / `docker compose start`
3. Add explicit volume verification before and after

---

### 4. Shutdown Time

| Aspect | Specified Criteria | Current Implementation | Gap Analysis |
|--------|-------------------|------------------------|--------------|
| **Definition** | Time from running state to all containers stopped/removed | `stop_network` function | **Good match** |
| **Verification** | All containers stopped/removed | Verified via `cleanup.sh --verify-only` | **OK** |

**Current implementation matches criteria well.**

---

### 5. HAPI Test Run

| Aspect | Specified Criteria | Current Implementation | Gap Analysis |
|--------|-------------------|------------------------|--------------|
| **Definition** | Create 3 accounts, Create FT Token, Mint Token, Transfer Token | **Not implemented** | **Missing entirely** |
| **SDK** | Uses Hedera SDK (HAPI) | N/A | **Need to add** |
| **Confirmation** | After confirmation in mirror node | N/A | **Need to add** |

**Current implementation has NO HAPI tests.** All tests are EVM/JSON-RPC based.

**Required implementation**:
```typescript
// Using @hashgraph/sdk
import { Client, AccountCreateTransaction, TokenCreateTransaction, ... } from "@hashgraph/sdk";

// 1. Create 3 accounts
const account1 = await new AccountCreateTransaction().setInitialBalance(10).execute(client);
const account2 = await new AccountCreateTransaction().setInitialBalance(10).execute(client);
const account3 = await new AccountCreateTransaction().setInitialBalance(10).execute(client);

// 2. Create FT Token
const tokenCreate = await new TokenCreateTransaction()
  .setTokenName("Test Token")
  .setTokenSymbol("TST")
  .setDecimals(8)
  .setInitialSupply(0)
  .execute(client);

// 3. Mint Token
const tokenMint = await new TokenMintTransaction()
  .setTokenId(tokenId)
  .setAmount(1000)
  .execute(client);

// 4. Transfer Token
const tokenTransfer = await new TransferTransaction()
  .addTokenTransfer(tokenId, account1, -100)
  .addTokenTransfer(tokenId, account2, 100)
  .execute(client);

// 5. Verify in mirror node
await waitForMirrorNode(tokenTransfer.transactionId);
```

---

### 6. EVM Test Run

| Aspect | Specified Criteria | Current Implementation | Gap Analysis |
|--------|-------------------|------------------------|--------------|
| **Definition** | Create 3 accounts, Deploy ERC20 contract, Create Token, Mint Token, Transfer Token | Deploy Counter, increment, read, setCount | **Partial match** |
| **Account creation** | Create 3 accounts | Uses 1 pre-funded account | **Missing**: Need 3 accounts |
| **Contract type** | ERC20 | Counter (simple storage) | **Wrong contract type** |
| **Operations** | Create, Mint, Transfer | increment, setCount, read | **Different operations** |
| **Confirmation** | After confirmation from eth_call | Uses `tx.wait()` then delay | **Partial match** |

**Current EVM test operations**:
1. Deploy Counter contract
2. increment() — state change
3. count() — read
4. Event query — CountChanged
5. setCount(42) — state change
6. count() — read verify

**Required EVM test operations**:
1. Create/fund 3 accounts (or use pre-funded test accounts)
2. Deploy ERC20 contract (OpenZeppelin standard)
3. mint(account1, 1000) — create tokens
4. transfer(account2, 100) — transfer tokens
5. balanceOf(account2) — verify via eth_call

---

## Summary Matrix

| Criteria | Implemented? | Accuracy | Needs Work |
|----------|-------------|----------|------------|
| Install Time | ✅ Partial | Low | Add clean install mode (rm images, rm node_modules) |
| Cold Start Time | ✅ Partial | Medium | Add transaction verification, not just RPC health |
| Warm Start Time | ⚠️ Solo only | Low | Fix Local Node warm, clarify Solo "warm" definition |
| Shutdown Time | ✅ Yes | High | Good as-is |
| HAPI Test Run | ❌ No | N/A | Implement from scratch using @hashgraph/sdk |
| EVM Test Run | ⚠️ Partial | Low | Replace Counter with ERC20, add 3 accounts |

---

## Notion Table Format

To import your Notion table, you can:

1. **Export from Notion**: Click "..." menu > Export > Markdown & CSV
2. **Copy as text**: Select table in Notion, Cmd+C, paste here
3. **Share the page**: Give me the Notion page URL (if public) and I can WebFetch it

Once you provide the table, I can:
- Map each row to our current implementation status
- Fill in timing data from our benchmark runs
- Identify which cells need data we don't yet have

---

## Recommended Next Steps

1. **Fix Docker Desktop** — Cannot get reliable data until Docker stops auto-pausing
2. **Implement ERC20 test** — Replace Counter with OpenZeppelin ERC20
3. **Implement HAPI test** — Create new test file using @hashgraph/sdk
4. **Add clean install mode** — Measure from true zero state
5. **Add transaction verification** — Replace RPC health with actual tx send
6. **Clarify warm start** — Define precisely what "warm" means for each network
