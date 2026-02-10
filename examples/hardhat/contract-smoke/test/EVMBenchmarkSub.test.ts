import { expect } from "chai";
import { ethers, network } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import { TestToken } from "../typechain-types";
import { Wallet } from "ethers";
import {
  Client,
  AccountCreateTransaction,
  PrivateKey,
  Hbar,
} from "@hashgraph/sdk";

// ============================================================================
// EVM BENCHMARK SUB-TEST
// ============================================================================
// Definition: Create 3 accounts, Deploy ERC20 contract, Mint Token, Transfer Token.
// All tests run sequentially after confirmation from eth_call.
// ============================================================================

interface ContractEvidence {
  label: string;
  network: string;
  address: string;
  bytecode_sha256: string;
  deploy_tx: string;
  step_tx_hashes: Record<string, string>;
  accounts: string[];
  hedera_account_ids: string[];
}

const contractEvidence: ContractEvidence = {
  label: process.env.BENCHMARK_LABEL || network.name,
  network: network.name,
  address: "",
  bytecode_sha256: "",
  deploy_tx: "",
  step_tx_hashes: {},
  accounts: [],
  hedera_account_ids: [],
};

interface StepTiming {
  step: string;
  durationMs: number;
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
  rpcUrl: process.env.SOLO_RPC_URL || "http://127.0.0.1:7546",
};

// Token amounts (using 18 decimals)
const INITIAL_MINT = ethers.parseEther("10000");
const TRANSFER_AMOUNT = ethers.parseEther("1000");

describe("EVM Benchmark Sub-Test", function () {
  this.timeout(300000); // 5 minutes (account creation + EVM ops)

  let token: TestToken;
  let wallets: Wallet[] = [];
  let addresses: string[] = [];
  let hederaClient: Client;

  before(async function () {
    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log("║         EVM BENCHMARK SUB-TEST                           ║");
    console.log("╠══════════════════════════════════════════════════════════╣");
    console.log("║  Create 3 accounts → Deploy ERC20 → Mint → Transfer      ║");
    console.log("║  All confirmations via eth_call                          ║");
    console.log(`║  RPC: ${SOLO_CONFIG.rpcUrl.padEnd(49)}║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");

    // Create Hedera client for account creation
    const hederaNetwork: Record<string, string> = {};
    hederaNetwork[SOLO_CONFIG.grpcEndpoint] = SOLO_CONFIG.nodeAccountId;

    hederaClient = Client.forNetwork(hederaNetwork);
    hederaClient.setOperator(
      SOLO_CONFIG.operatorId,
      PrivateKey.fromStringED25519(SOLO_CONFIG.operatorKey)
    );
  });

  after(async function () {
    if (hederaClient) {
      hederaClient.close();
    }

    const totalMs = stepTimings.reduce((sum, s) => sum + s.durationMs, 0);
    const formatSec = (ms: number) => (ms / 1000).toFixed(1) + "s";

    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log("║         EVM BENCHMARK SUB-TEST RESULTS                   ║");
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
    console.log(`[TIMING] evm_sub_total=${totalMs}`);
    for (const s of stepTimings) {
      const key = s.step.toLowerCase().replace(/[^a-z0-9]+/g, "_");
      console.log(`[TIMING] ${key}=${s.durationMs}`);
    }

    // Evidence output
    console.log(`[EVIDENCE] contract_address=${contractEvidence.address}`);
    console.log(`[EVIDENCE] deploy_tx=${contractEvidence.deploy_tx}`);
    console.log(`[EVIDENCE] accounts=${contractEvidence.accounts.join(",")}`);
    console.log(`[EVIDENCE] hedera_account_ids=${contractEvidence.hedera_account_ids.join(",")}`);

    // Write JSON artifact if BENCHMARK_EVIDENCE_DIR is set
    const evidenceDir = process.env.BENCHMARK_EVIDENCE_DIR;
    if (evidenceDir) {
      try {
        if (!fs.existsSync(evidenceDir)) {
          fs.mkdirSync(evidenceDir, { recursive: true });
        }
        const artifactPath = path.join(evidenceDir, `${contractEvidence.label}-evm-sub-evidence.json`);
        const data = {
          ...contractEvidence,
          timing: {
            steps: stepTimings,
            total_ms: totalMs,
          },
        };
        fs.writeFileSync(artifactPath, JSON.stringify(data, null, 2));
        console.log(`[EVIDENCE] artifact_written=${artifactPath}`);
      } catch (err) {
        console.log(`[EVIDENCE] artifact_write_error=${err}`);
      }
    }
  });

  it("Step 1: Create 3 accounts via HAPI", async function () {
    const start = Date.now();

    console.log("  Creating 3 ECDSA accounts via Hedera SDK...");

    for (let i = 0; i < 3; i++) {
      // Generate ECDSA key for EVM compatibility
      const key = PrivateKey.generateECDSA();

      const tx = await new AccountCreateTransaction()
        .setKey(key.publicKey)
        .setInitialBalance(new Hbar(1000)) // Fund with 1000 HBAR for gas
        .setAlias(key.publicKey.toEvmAddress())
        .execute(hederaClient);

      const receipt = await tx.getReceipt(hederaClient);
      const accountId = receipt.accountId!.toString();

      // Create ethers wallet from the ECDSA private key
      const provider = new ethers.JsonRpcProvider(SOLO_CONFIG.rpcUrl);
      const wallet = new Wallet(key.toStringRaw(), provider);
      wallets.push(wallet);

      const evmAddress = await wallet.getAddress();
      addresses.push(evmAddress);

      contractEvidence.accounts.push(evmAddress);
      contractEvidence.hedera_account_ids.push(accountId);

      console.log(`    account[${i}]: ${accountId} → ${evmAddress}`);
    }

    // Wait for mirror node to sync the new accounts
    console.log("  Waiting for accounts to be available via RPC...");
    await new Promise(resolve => setTimeout(resolve, 5000));

    recordStep("Create 3 accounts", start);
    expect(wallets.length).to.equal(3);
  });

  it("Step 2: Deploy ERC20 contract", async function () {
    const start = Date.now();

    const TestToken = await ethers.getContractFactory("TestToken", wallets[0]);
    token = await TestToken.deploy("Benchmark Token", "BENCH", 0);
    await token.waitForDeployment();

    // Wait for mirror node sync
    await new Promise(resolve => setTimeout(resolve, 3000));

    recordStep("Deploy ERC20", start);

    const address = await token.getAddress();
    expect(address).to.be.properAddress;

    contractEvidence.address = address;
    const deployTx = token.deploymentTransaction();
    if (deployTx) {
      contractEvidence.deploy_tx = deployTx.hash;
    }

    console.log(`  Contract deployed: ${address}`);
  });

  it("Step 3: Mint tokens to account[0]", async function () {
    const start = Date.now();

    const tx = await token.mint(addresses[0], INITIAL_MINT);
    const receipt = await tx.wait();

    // Wait for confirmation
    await new Promise(resolve => setTimeout(resolve, 2500));

    recordStep("Mint tokens", start);
    contractEvidence.step_tx_hashes["mint"] = tx.hash;

    // Verify mint via eth_call
    const balance = await token.balanceOf(addresses[0]);
    expect(balance).to.equal(INITIAL_MINT);

    console.log(`  Minted ${ethers.formatEther(INITIAL_MINT)} BENCH to account[0]`);
  });

  it("Step 4: Transfer to account[1]", async function () {
    const start = Date.now();

    const tx = await token.connect(wallets[0]).transfer(addresses[1], TRANSFER_AMOUNT);
    await tx.wait();

    // Wait for confirmation
    await new Promise(resolve => setTimeout(resolve, 2500));

    recordStep("Transfer to acc[1]", start);
    contractEvidence.step_tx_hashes["transfer_1"] = tx.hash;

    console.log(`  Transferred ${ethers.formatEther(TRANSFER_AMOUNT)} BENCH to account[1]`);
  });

  it("Step 5: Transfer to account[2]", async function () {
    const start = Date.now();

    const tx = await token.connect(wallets[0]).transfer(addresses[2], TRANSFER_AMOUNT);
    await tx.wait();

    // Wait for confirmation
    await new Promise(resolve => setTimeout(resolve, 2500));

    recordStep("Transfer to acc[2]", start);
    contractEvidence.step_tx_hashes["transfer_2"] = tx.hash;

    console.log(`  Transferred ${ethers.formatEther(TRANSFER_AMOUNT)} BENCH to account[2]`);
  });

  it("Step 6: eth_call confirms all balances", async function () {
    const start = Date.now();

    // Read all three balances via eth_call
    const bal0 = await token.balanceOf(addresses[0]);
    const bal1 = await token.balanceOf(addresses[1]);
    const bal2 = await token.balanceOf(addresses[2]);

    // Verify expected balances
    // account[0]: 10000 - 1000 - 1000 = 8000
    // account[1]: 1000
    // account[2]: 1000
    expect(bal0).to.equal(ethers.parseEther("8000"));
    expect(bal1).to.equal(ethers.parseEther("1000"));
    expect(bal2).to.equal(ethers.parseEther("1000"));

    recordStep("Confirm balances", start);

    console.log("\n  Final balances (confirmed via eth_call):");
    console.log(`    account[0]: ${ethers.formatEther(bal0)} BENCH ✓`);
    console.log(`    account[1]: ${ethers.formatEther(bal1)} BENCH ✓`);
    console.log(`    account[2]: ${ethers.formatEther(bal2)} BENCH ✓`);
  });
});
