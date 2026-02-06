# Solo Benchmark: Criteria Gap Analysis and Required Modifications

**Generated**: 2026-02-06
**Based on**: Successful run 2026-02-04_08-52-42

---

## Current Solo Timing Data (from successful run)

| Metric | 1st Start (Cold) | 2nd Start (Warm) |
|--------|------------------|------------------|
| Network startup | 884.5s | 30.6s |
| Deploy contract | 14,910ms | 8,803ms |
| Event verification | 927ms | 33ms |
| Final read | 1,226ms | 481ms |
| **Contract ops total** | **38,149ms** | **26,845ms** |
| Shutdown | 3.5s | 2.4s |

---

## Criteria Compliance Matrix

| Criterion | Current Status | Meets Criteria? |
|-----------|---------------|-----------------|
| Install Time | Not measured separately | ❌ NO |
| Cold Start Time | 884.5s (includes image pulls, RPC health only) | ⚠️ PARTIAL |
| Warm Start Time | 30.6s (redeploy, not state-preserved) | ❌ NO |
| Shutdown Time | 3.5s (cluster kept, network stopped) | ✅ YES |
| HAPI Test Run | Not implemented | ❌ NO |
| EVM Test Run | Counter contract, 1 account | ❌ NO |

---

## Criterion-by-Criterion Analysis

### 1. Install Time

**Criterion**: Clean machine (Docker installed, no images) → Ready to start network

**Current behavior**:
- Measures `brew reinstall solo` (~40s for CLI only)
- Does NOT include image pulls

**What's actually needed**:
- CLI install time (~40s)
- Image pull time (~600-700s on first run)
- Total: ~650-750s

**Modification required**:
```bash
# In run-deploy-benchmark.sh, add image pre-pull phase after CLI install
measure_solo_install() {
    START_TIME=$(date +%s%3N)

    # Step 1: CLI install
    brew reinstall solo
    CLI_DONE=$(date +%s%3N)

    # Step 2: Pre-pull all Solo images (simulates what happens on first deploy)
    solo image list | xargs -P 4 -I {} docker pull {}
    IMAGES_DONE=$(date +%s%3N)

    record_timing "solo_install_cli" $((CLI_DONE - START_TIME))
    record_timing "solo_install_images" $((IMAGES_DONE - CLI_DONE))
    record_timing "solo_install_total" $((IMAGES_DONE - START_TIME))
}
```

---

### 2. Cold Start Time

**Criterion**: Fresh volumes → First SDK/RPC transaction completes successfully

**Current behavior**:
- Measures from `start_network solo` to RPC health check response
- Uses `eth_chainId` call as readiness indicator
- Does NOT verify actual SDK transaction capability

**Current measurement**: 884.5s (includes image pulls because images weren't cached)

**What's actually needed**:
- Fresh volumes (use `--clean-images` mode)
- Measure until first REAL transaction succeeds (not just health check)
- Transaction should be via SDK or a contract interaction

**Modification required**:
```typescript
// In test setup, add SDK transaction verification
async function verifyTransactionCapability(): Promise<number> {
    const startTime = Date.now();

    // Option A: SDK transaction
    const client = Client.forNetwork({/* solo config */});
    const tx = await new AccountBalanceQuery()
        .setAccountId("0.0.2")
        .execute(client);

    // Option B: RPC transaction (current approach, but make it a real tx)
    const wallet = new ethers.Wallet(OPERATOR_KEY, provider);
    const tx = await wallet.sendTransaction({
        to: wallet.address,
        value: 0
    });
    await tx.wait();

    return Date.now() - startTime;
}
```

**Estimated true cold start** (images cached): ~120-180s

---

### 3. Warm Start Time

**Criterion**: Preserved volumes → First SDK/RPC transaction completes

**Current behavior**:
- Redeploys entire Hedera network on existing kind cluster
- Blockchain state is NOT preserved (new genesis)
- Measures 30.6s but this is a "warm cluster, cold network"

**What's actually needed**:
- Stop pods without destroying PVCs (Persistent Volume Claims)
- Restart pods, reconnect to existing blockchain state
- Verify transaction on pre-existing ledger

**Modification required**:
```bash
# New stop mode in start-solo.sh
stop_solo_warm() {
    # Scale down pods but keep PVCs
    kubectl scale deployment --all --replicas=0 -n solo-${NAMESPACE}
    # OR
    solo network stop --keep-state  # If Solo supports this
}

start_solo_warm() {
    # Scale pods back up
    kubectl scale deployment --all --replicas=1 -n solo-${NAMESPACE}
    # Wait for ready
    wait_for_solo_ready
}
```

**Note**: Solo may not currently support true state preservation. Investigation needed:
- Does `solo network stop` preserve PVCs?
- Can pods reconnect to existing state?
- This may require Solo feature request

---

### 4. Shutdown Time

**Criterion**: Running network → All containers stopped

**Current behavior**:
- Measures `stop_network solo` time
- Uses `solo network stop` which stops Hedera pods
- Kind cluster remains running

**Current measurement**: 2.4-3.5s ✅

**Status**: MEETS CRITERIA

---

### 5. HAPI Test Run

**Criterion**:
- 3 accounts
- Create FT token
- Mint tokens
- Transfer between accounts
- Mirror node confirms final balances

**Current behavior**: NOT IMPLEMENTED

**Required new test file**: `examples/hardhat/contract-smoke/test/HAPIBenchmark.test.ts`

```typescript
import { Client, AccountCreateTransaction, TokenCreateTransaction,
         TokenMintTransaction, TransferTransaction, AccountBalanceQuery,
         PrivateKey, Hbar } from "@hashgraph/sdk";

describe("HAPI Benchmark", function() {
    let client: Client;
    let accounts: { id: string; key: PrivateKey }[] = [];
    let tokenId: string;

    const TIMING: Record<string, number> = {};

    before(async function() {
        this.timeout(120000);

        // Connect to Solo
        client = Client.forNetwork({
            "127.0.0.1:50211": "0.0.3"
        });
        client.setOperator("0.0.2", OPERATOR_KEY);
    });

    it("Step 1: Create 3 accounts", async function() {
        const start = Date.now();

        for (let i = 0; i < 3; i++) {
            const key = PrivateKey.generate();
            const tx = await new AccountCreateTransaction()
                .setKey(key.publicKey)
                .setInitialBalance(new Hbar(100))
                .execute(client);
            const receipt = await tx.getReceipt(client);
            accounts.push({ id: receipt.accountId!.toString(), key });
        }

        TIMING["create_3_accounts"] = Date.now() - start;
    });

    it("Step 2: Create FT token", async function() {
        const start = Date.now();

        const tx = await new TokenCreateTransaction()
            .setTokenName("Benchmark Token")
            .setTokenSymbol("BENCH")
            .setDecimals(2)
            .setInitialSupply(0)
            .setTreasuryAccountId(accounts[0].id)
            .setSupplyKey(accounts[0].key.publicKey)
            .freezeWith(client)
            .sign(accounts[0].key);

        const response = await tx.execute(client);
        const receipt = await response.getReceipt(client);
        tokenId = receipt.tokenId!.toString();

        TIMING["create_token"] = Date.now() - start;
    });

    it("Step 3: Mint tokens", async function() {
        const start = Date.now();

        const tx = await new TokenMintTransaction()
            .setTokenId(tokenId)
            .setAmount(10000)
            .freezeWith(client)
            .sign(accounts[0].key);

        await tx.execute(client);

        TIMING["mint_tokens"] = Date.now() - start;
    });

    it("Step 4: Transfer tokens between accounts", async function() {
        const start = Date.now();

        // Transfer from account[0] to account[1] and account[2]
        const tx = await new TransferTransaction()
            .addTokenTransfer(tokenId, accounts[0].id, -2000)
            .addTokenTransfer(tokenId, accounts[1].id, 1000)
            .addTokenTransfer(tokenId, accounts[2].id, 1000)
            .freezeWith(client)
            .sign(accounts[0].key);

        await tx.execute(client);

        TIMING["transfer_tokens"] = Date.now() - start;
    });

    it("Step 5: Mirror node confirms balances", async function() {
        const start = Date.now();

        // Query mirror node REST API
        const response = await fetch(
            `http://127.0.0.1:8081/api/v1/accounts/${accounts[1].id}/tokens`
        );
        const data = await response.json();

        expect(data.tokens).to.have.length.greaterThan(0);
        expect(data.tokens[0].balance).to.equal(1000);

        TIMING["mirror_confirm"] = Date.now() - start;
    });

    after(function() {
        console.log("\n=== HAPI TIMING DATA ===");
        console.log(JSON.stringify(TIMING, null, 2));
        // Write to timing file
        fs.writeFileSync(
            process.env.TIMING_FILE || "/tmp/hapi-timing.json",
            JSON.stringify(TIMING)
        );
    });
});
```

**Dependencies to add**:
```json
{
  "dependencies": {
    "@hashgraph/sdk": "^2.x"
  }
}
```

---

### 6. EVM Test Run

**Criterion**:
- 3 accounts
- Deploy ERC20 contract
- Mint tokens
- Transfer between accounts
- eth_call confirms final balances

**Current behavior**:
- Uses Counter contract (not ERC20)
- Uses 1 account (operator only)
- No token operations

**Required modifications to**: `examples/hardhat/contract-smoke/test/DeployBenchmark.test.ts`

```typescript
import { ethers } from "hardhat";

describe("EVM Benchmark", function() {
    let erc20: Contract;
    let accounts: Signer[];

    const TIMING: Record<string, number> = {};

    before(async function() {
        // Get 3 accounts
        accounts = (await ethers.getSigners()).slice(0, 3);
        expect(accounts.length).to.be.gte(3, "Need at least 3 accounts");
    });

    it("Step 1: Deploy ERC20 contract", async function() {
        const start = Date.now();

        const ERC20 = await ethers.getContractFactory("BenchmarkToken");
        erc20 = await ERC20.deploy("Benchmark Token", "BENCH", 18);
        await erc20.waitForDeployment();

        TIMING["deploy_erc20"] = Date.now() - start;
    });

    it("Step 2: Mint tokens to account[0]", async function() {
        const start = Date.now();

        const tx = await erc20.mint(
            await accounts[0].getAddress(),
            ethers.parseEther("10000")
        );
        await tx.wait();

        TIMING["mint_tokens"] = Date.now() - start;
    });

    it("Step 3: Transfer to account[1]", async function() {
        const start = Date.now();

        const tx = await erc20.connect(accounts[0]).transfer(
            await accounts[1].getAddress(),
            ethers.parseEther("1000")
        );
        await tx.wait();

        TIMING["transfer_to_acc1"] = Date.now() - start;
    });

    it("Step 4: Transfer to account[2]", async function() {
        const start = Date.now();

        const tx = await erc20.connect(accounts[0]).transfer(
            await accounts[2].getAddress(),
            ethers.parseEther("1000")
        );
        await tx.wait();

        TIMING["transfer_to_acc2"] = Date.now() - start;
    });

    it("Step 5: eth_call confirms balances", async function() {
        const start = Date.now();

        const bal0 = await erc20.balanceOf(await accounts[0].getAddress());
        const bal1 = await erc20.balanceOf(await accounts[1].getAddress());
        const bal2 = await erc20.balanceOf(await accounts[2].getAddress());

        expect(bal0).to.equal(ethers.parseEther("8000"));
        expect(bal1).to.equal(ethers.parseEther("1000"));
        expect(bal2).to.equal(ethers.parseEther("1000"));

        TIMING["confirm_balances"] = Date.now() - start;
    });

    after(function() {
        console.log("\n=== EVM TIMING DATA ===");
        console.log(JSON.stringify(TIMING, null, 2));
    });
});
```

**New contract needed**: `contracts/BenchmarkToken.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BenchmarkToken is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
```

**Account configuration needed** in `hardhat.config.ts`:
```typescript
solo: {
    url: "http://127.0.0.1:7546",
    accounts: [
        OPERATOR_PRIVATE_KEY,
        ACCOUNT_1_PRIVATE_KEY,  // Need 2 additional funded accounts
        ACCOUNT_2_PRIVATE_KEY,
    ],
}
```

---

## Summary of Required Changes

| File | Change |
|------|--------|
| `scripts/run-deploy-benchmark.sh` | Add image pull timing to install phase |
| `scripts/start-solo.sh` | Add SDK transaction verification after RPC health |
| `scripts/start-solo.sh` | Add warm restart mode (if Solo supports state preservation) |
| `test/HAPIBenchmark.test.ts` | NEW - HAPI test with 3 accounts, FT token ops |
| `test/DeployBenchmark.test.ts` | Rewrite to use ERC20, 3 accounts |
| `contracts/BenchmarkToken.sol` | NEW - ERC20 with mint function |
| `hardhat.config.ts` | Configure 3 accounts per network |
| `package.json` | Add @hashgraph/sdk dependency |

---

## Estimated Timeline After Modifications

| Criterion | Expected Value |
|-----------|---------------|
| Install Time (CLI + images) | ~650-750s |
| Cold Start Time (images cached) | ~120-180s |
| Warm Start Time (state preserved) | ~15-30s (TBD based on Solo support) |
| Shutdown Time | ~3s |
| HAPI Test Run | ~10-30s (5 operations) |
| EVM Test Run | ~30-60s (5 operations) |

---

## Next Steps

1. **Verify Solo state preservation**: Test if `solo network stop` + restart preserves ledger state
2. **Create BenchmarkToken.sol**: Simple ERC20 with mint
3. **Create HAPIBenchmark.test.ts**: New test file using @hashgraph/sdk
4. **Modify DeployBenchmark.test.ts**: Switch to ERC20, add accounts
5. **Update timing extraction**: Parse new timing format from tests
6. **Add image pull timing**: Separate install from cold start properly
