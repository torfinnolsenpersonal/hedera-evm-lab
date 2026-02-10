import { expect } from "chai";
import * as fs from "fs";
import * as path from "path";
import {
  Client,
  AccountCreateTransaction,
  TokenCreateTransaction,
  TokenMintTransaction,
  TransferTransaction,
  TokenAssociateTransaction,
  PrivateKey,
  Hbar,
  TokenType,
  TokenSupplyType,
} from "@hashgraph/sdk";

// ============================================================================
// HAPI BENCHMARK SUB-TEST
// ============================================================================
// Definition: Create 3 accounts, Create FT Token, Mint Token, Transfer token.
// All tests run sequentially after confirmation in mirror node.
// ============================================================================

interface StepTiming {
  step: string;
  durationMs: number;
}

interface HAPIEvidence {
  label: string;
  network: string;
  operator_account: string;
  accounts: string[];
  token_id: string;
  transaction_ids: Record<string, string>;
  timing: {
    steps: StepTiming[];
    total_ms: number;
  };
}

const stepTimings: StepTiming[] = [];

function recordStep(step: string, startMs: number): void {
  stepTimings.push({ step, durationMs: Date.now() - startMs });
}

// Configuration for Solo network
const SOLO_CONFIG = {
  grpcEndpoint: process.env.SOLO_GRPC_ENDPOINT || "127.0.0.1:50211",
  nodeAccountId: process.env.SOLO_NODE_ACCOUNT || "0.0.3",
  operatorId: process.env.SOLO_OPERATOR_ID || "0.0.2",
  operatorKey: process.env.SOLO_OPERATOR_KEY ||
    "302e020100300506032b65700422042091132178e72057a1d7528025956fe39b0b847f200ab59b2fdd367017f3087137",
  mirrorNodeUrl: process.env.SOLO_MIRROR_URL || "http://127.0.0.1:8081",
};

// Mirror node confirmation helper
async function waitForMirrorNode(
  mirrorUrl: string,
  accountId: string,
  tokenId: string,
  expectedBalance: number,
  maxAttempts: number = 10
): Promise<number> {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      const url = `${mirrorUrl}/api/v1/accounts/${accountId}/tokens?token.id=${tokenId}`;
      const response = await fetch(url);
      const data = await response.json() as { tokens?: { balance?: number }[] };
      const balance = data.tokens?.[0]?.balance ?? 0;
      if (balance === expectedBalance) {
        return balance;
      }
    } catch {
      // Retry
    }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  throw new Error(`Mirror node did not confirm balance ${expectedBalance} for ${accountId}`);
}

describe("HAPI Benchmark Sub-Test", function () {
  this.timeout(180000); // 3 minutes

  let client: Client;
  let operatorId: string;
  let accounts: { id: string; key: PrivateKey }[] = [];
  let tokenId: string;

  const evidence: HAPIEvidence = {
    label: process.env.BENCHMARK_LABEL || "solo_hapi_sub",
    network: "solo",
    operator_account: "",
    accounts: [],
    token_id: "",
    transaction_ids: {},
    timing: { steps: [], total_ms: 0 },
  };

  before(async function () {
    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log("║         HAPI BENCHMARK SUB-TEST                          ║");
    console.log("╠══════════════════════════════════════════════════════════╣");
    console.log("║  Create 3 accounts → Create FT → Mint → Transfer         ║");
    console.log("║  All confirmations via Mirror Node                       ║");
    console.log(`║  GRPC: ${SOLO_CONFIG.grpcEndpoint.padEnd(48)}║`);
    console.log(`║  Mirror: ${SOLO_CONFIG.mirrorNodeUrl.padEnd(46)}║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");

    // Create client for Solo network
    const network: Record<string, string> = {};
    network[SOLO_CONFIG.grpcEndpoint] = SOLO_CONFIG.nodeAccountId;

    client = Client.forNetwork(network);
    client.setOperator(
      SOLO_CONFIG.operatorId,
      PrivateKey.fromStringED25519(SOLO_CONFIG.operatorKey)
    );

    operatorId = SOLO_CONFIG.operatorId;
    evidence.operator_account = operatorId;
  });

  after(async function () {
    if (client) {
      client.close();
    }

    const totalMs = stepTimings.reduce((sum, s) => sum + s.durationMs, 0);
    const formatSec = (ms: number) => (ms / 1000).toFixed(1) + "s";
    evidence.timing.steps = stepTimings;
    evidence.timing.total_ms = totalMs;

    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log("║         HAPI BENCHMARK SUB-TEST RESULTS                  ║");
    console.log("╠══════════════════════════════════════════════════════════╣");
    for (const s of stepTimings) {
      const label = `║  ${s.step}`;
      const value = formatSec(s.durationMs);
      console.log(`${label.padEnd(42)}${value.padStart(14)} ║`);
    }
    console.log("╠══════════════════════════════════════════════════════════╣");
    const totalLabel = "║  TOTAL";
    const totalValue = formatSec(totalMs);
    console.log(`${totalLabel.padEnd(42)}${totalValue.padStart(14)} ║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");

    // Print parseable timing data
    console.log(`[TIMING] hapi_sub_total=${totalMs}`);
    for (const s of stepTimings) {
      const key = s.step.toLowerCase().replace(/[^a-z0-9]+/g, "_");
      console.log(`[TIMING] ${key}=${s.durationMs}`);
    }

    // Evidence output
    console.log(`[EVIDENCE] operator_account=${evidence.operator_account}`);
    console.log(`[EVIDENCE] token_id=${evidence.token_id}`);
    console.log(`[EVIDENCE] accounts=${evidence.accounts.join(",")}`);

    // Write JSON artifact if BENCHMARK_EVIDENCE_DIR is set
    const evidenceDir = process.env.BENCHMARK_EVIDENCE_DIR;
    if (evidenceDir) {
      try {
        if (!fs.existsSync(evidenceDir)) {
          fs.mkdirSync(evidenceDir, { recursive: true });
        }
        const artifactPath = path.join(evidenceDir, `${evidence.label}-hapi-sub-evidence.json`);
        fs.writeFileSync(artifactPath, JSON.stringify(evidence, null, 2));
        console.log(`[EVIDENCE] artifact_written=${artifactPath}`);
      } catch (err) {
        console.log(`[EVIDENCE] artifact_write_error=${err}`);
      }
    }
  });

  it("Step 1: Create 3 accounts", async function () {
    const start = Date.now();

    for (let i = 0; i < 3; i++) {
      const key = PrivateKey.generateED25519();
      const tx = await new AccountCreateTransaction()
        .setKey(key.publicKey)
        .setInitialBalance(new Hbar(100))
        .execute(client);

      const receipt = await tx.getReceipt(client);
      const accountId = receipt.accountId!.toString();
      accounts.push({ id: accountId, key });
      evidence.accounts.push(accountId);
      evidence.transaction_ids[`create_account_${i}`] = tx.transactionId.toString();

      console.log(`  Created account[${i}]: ${accountId}`);
    }

    recordStep("Create 3 accounts", start);
    expect(accounts.length).to.equal(3);
  });

  it("Step 2: Create FT token", async function () {
    const start = Date.now();

    // Account[0] will be the treasury and have supply key
    const treasuryKey = accounts[0].key;

    const tx = await new TokenCreateTransaction()
      .setTokenName("Benchmark Token")
      .setTokenSymbol("BENCH")
      .setDecimals(2)
      .setInitialSupply(0)
      .setTreasuryAccountId(accounts[0].id)
      .setSupplyType(TokenSupplyType.Infinite)
      .setTokenType(TokenType.FungibleCommon)
      .setSupplyKey(treasuryKey.publicKey)
      .freezeWith(client)
      .sign(treasuryKey);

    const response = await tx.execute(client);
    const receipt = await response.getReceipt(client);
    tokenId = receipt.tokenId!.toString();
    evidence.token_id = tokenId;
    evidence.transaction_ids["create_token"] = response.transactionId.toString();

    console.log(`  Created token: ${tokenId}`);

    recordStep("Create FT token", start);
    expect(tokenId).to.match(/^\d+\.\d+\.\d+$/);
  });

  it("Step 3: Associate token with accounts 1 and 2", async function () {
    const start = Date.now();

    // Associate token with account[1]
    const tx1 = await new TokenAssociateTransaction()
      .setAccountId(accounts[1].id)
      .setTokenIds([tokenId])
      .freezeWith(client)
      .sign(accounts[1].key);
    const response1 = await tx1.execute(client);
    await response1.getReceipt(client);
    evidence.transaction_ids["associate_1"] = response1.transactionId.toString();

    // Associate token with account[2]
    const tx2 = await new TokenAssociateTransaction()
      .setAccountId(accounts[2].id)
      .setTokenIds([tokenId])
      .freezeWith(client)
      .sign(accounts[2].key);
    const response2 = await tx2.execute(client);
    await response2.getReceipt(client);
    evidence.transaction_ids["associate_2"] = response2.transactionId.toString();

    console.log(`  Associated token with accounts 1 and 2`);

    recordStep("Associate token", start);
  });

  it("Step 4: Mint tokens", async function () {
    const start = Date.now();

    const tx = await new TokenMintTransaction()
      .setTokenId(tokenId)
      .setAmount(10000) // 100.00 tokens with 2 decimals
      .freezeWith(client)
      .sign(accounts[0].key);

    const response = await tx.execute(client);
    const receipt = await response.getReceipt(client);
    evidence.transaction_ids["mint"] = response.transactionId.toString();

    console.log(`  Minted ${receipt.totalSupply} tokens to treasury`);

    recordStep("Mint tokens", start);
    expect(receipt.totalSupply?.toNumber()).to.equal(10000);
  });

  it("Step 5: Transfer tokens", async function () {
    const start = Date.now();

    // Transfer from account[0] to account[1] and account[2]
    const tx = await new TransferTransaction()
      .addTokenTransfer(tokenId, accounts[0].id, -2000) // -20.00 tokens
      .addTokenTransfer(tokenId, accounts[1].id, 1000)  // +10.00 tokens
      .addTokenTransfer(tokenId, accounts[2].id, 1000)  // +10.00 tokens
      .freezeWith(client)
      .sign(accounts[0].key);

    const response = await tx.execute(client);
    await response.getReceipt(client);
    evidence.transaction_ids["transfer"] = response.transactionId.toString();

    console.log(`  Transferred 10.00 BENCH to each of accounts 1 and 2`);

    recordStep("Transfer tokens", start);
  });

  it("Step 6: Mirror node confirms all balances", async function () {
    const start = Date.now();

    // Wait for and confirm each balance via mirror node
    console.log("\n  Waiting for mirror node confirmation...");

    const bal0 = await waitForMirrorNode(
      SOLO_CONFIG.mirrorNodeUrl,
      accounts[0].id,
      tokenId,
      8000 // 80.00 tokens
    );
    console.log(`    account[0]: ${bal0 / 100} BENCH ✓`);

    const bal1 = await waitForMirrorNode(
      SOLO_CONFIG.mirrorNodeUrl,
      accounts[1].id,
      tokenId,
      1000 // 10.00 tokens
    );
    console.log(`    account[1]: ${bal1 / 100} BENCH ✓`);

    const bal2 = await waitForMirrorNode(
      SOLO_CONFIG.mirrorNodeUrl,
      accounts[2].id,
      tokenId,
      1000 // 10.00 tokens
    );
    console.log(`    account[2]: ${bal2 / 100} BENCH ✓`);

    recordStep("Mirror node confirm", start);

    expect(bal0).to.equal(8000);
    expect(bal1).to.equal(1000);
    expect(bal2).to.equal(1000);
  });
});
