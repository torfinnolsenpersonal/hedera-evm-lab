import { expect } from "chai";
import { ethers, network } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import { TestToken } from "../typechain-types";
import { Signer } from "ethers";

// ============================================================================
// EVM BENCHMARK - ERC20 token operations with 3 accounts
// ============================================================================
// Criteria:
// - 3 accounts
// - Deploy ERC20 contract
// - Mint tokens
// - Transfer between accounts
// - eth_call confirms final balances
// ============================================================================

interface ContractEvidence {
  label: string;
  network: string;
  address: string;
  bytecode_sha256: string;
  deploy_tx: string;
  step_tx_hashes: Record<string, string>;
  accounts: string[];
}

const contractEvidence: ContractEvidence = {
  label: process.env.BENCHMARK_LABEL || network.name,
  network: network.name,
  address: "",
  bytecode_sha256: "",
  deploy_tx: "",
  step_tx_hashes: {},
  accounts: [],
};

interface NetworkTiming {
  defaultWaitMs: number;
  intermediateWaitMs: number;
  timeout: number;
}

const NETWORK_TIMINGS: Record<string, NetworkTiming> = {
  hardhat: { defaultWaitMs: 0, intermediateWaitMs: 0, timeout: 10000 },
  anvil: { defaultWaitMs: 0, intermediateWaitMs: 0, timeout: 30000 },
  localnode: { defaultWaitMs: 500, intermediateWaitMs: 300, timeout: 60000 },
  solo: { defaultWaitMs: 2500, intermediateWaitMs: 1500, timeout: 120000 },
  hedera_testnet: { defaultWaitMs: 5000, intermediateWaitMs: 3000, timeout: 180000 },
};

function getNetworkTiming(): NetworkTiming {
  return NETWORK_TIMINGS[network.name] || NETWORK_TIMINGS.solo;
}

interface StepTiming {
  step: string;
  durationMs: number;
}

const stepTimings: StepTiming[] = [];

function recordStep(step: string, startMs: number): void {
  stepTimings.push({ step, durationMs: Date.now() - startMs });
}

async function waitForTx(tx: any, customDelayMs?: number): Promise<any> {
  const timing = getNetworkTiming();
  const delayMs = customDelayMs ?? timing.defaultWaitMs;
  const receipt = await tx.wait();
  if (delayMs > 0) {
    await new Promise(resolve => setTimeout(resolve, delayMs));
  }
  return receipt;
}

// Token amounts (using 18 decimals)
const INITIAL_MINT = ethers.parseEther("10000");
const TRANSFER_AMOUNT = ethers.parseEther("1000");

describe("EVM Benchmark", function () {
  const timing = getNetworkTiming();
  this.timeout(timing.timeout);

  let token: TestToken;
  let accounts: Signer[];
  let addresses: string[];

  before(async function () {
    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log(`║         EVM BENCHMARK - ${network.name.padEnd(31)}║`);
    console.log("╠══════════════════════════════════════════════════════════╣");
    console.log(`║  Test: ERC20 deploy + mint + transfer with 3 accounts    ║`);
    console.log(`║  Default Wait:   ${(timing.defaultWaitMs + "ms").padEnd(38)}║`);
    console.log(`║  Timeout:        ${(timing.timeout + "ms").padEnd(38)}║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");

    // Get exactly 3 accounts
    const allSigners = await ethers.getSigners();
    if (allSigners.length < 3) {
      throw new Error(`Need at least 3 accounts, got ${allSigners.length}`);
    }
    accounts = allSigners.slice(0, 3);
    addresses = await Promise.all(accounts.map(a => a.getAddress()));

    console.log("Accounts:");
    for (let i = 0; i < 3; i++) {
      console.log(`  [${i}] ${addresses[i]}`);
    }
    console.log("");

    contractEvidence.accounts = addresses;
  });

  after(function () {
    const totalMs = stepTimings.reduce((sum, s) => sum + s.durationMs, 0);
    const formatSec = (ms: number) => (ms / 1000).toFixed(1) + "s";

    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log(`║         EVM BENCHMARK RESULTS - ${network.name.padEnd(23)}║`);
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

    // Print parseable timing data for benchmark script
    console.log(`[TIMING] evm_total=${totalMs}`);
    for (const s of stepTimings) {
      const key = s.step.toLowerCase().replace(/[^a-z0-9]+/g, "_");
      console.log(`[TIMING] ${key}=${s.durationMs}`);
    }

    // Evidence output
    console.log(`[EVIDENCE] contract_address=${contractEvidence.address}`);
    console.log(`[EVIDENCE] deploy_tx=${contractEvidence.deploy_tx}`);
    console.log(`[EVIDENCE] bytecode_sha256=${contractEvidence.bytecode_sha256}`);
    console.log(`[EVIDENCE] accounts=${contractEvidence.accounts.join(",")}`);
    for (const [step, hash] of Object.entries(contractEvidence.step_tx_hashes)) {
      console.log(`[EVIDENCE] tx_${step}=${hash}`);
    }

    // Write JSON artifact if BENCHMARK_EVIDENCE_DIR is set
    const evidenceDir = process.env.BENCHMARK_EVIDENCE_DIR;
    if (evidenceDir) {
      try {
        if (!fs.existsSync(evidenceDir)) {
          fs.mkdirSync(evidenceDir, { recursive: true });
        }
        const artifactPath = path.join(evidenceDir, `${contractEvidence.label}-evm-evidence.json`);
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

  it("Step 1: Deploy ERC20 contract", async function () {
    const start = Date.now();

    const TestToken = await ethers.getContractFactory("TestToken");
    token = await TestToken.deploy("Benchmark Token", "BENCH", 0);
    await token.waitForDeployment();

    // Allow mirror node sync after deploy
    if (timing.defaultWaitMs > 0) {
      await new Promise(resolve => setTimeout(resolve, timing.defaultWaitMs));
    }

    recordStep("Deploy ERC20", start);

    const address = await token.getAddress();
    expect(address).to.be.properAddress;

    contractEvidence.address = address;
    const deployTx = token.deploymentTransaction();
    if (deployTx) {
      contractEvidence.deploy_tx = deployTx.hash;
    }
    try {
      const deployedBytecode = await ethers.provider.getCode(address);
      contractEvidence.bytecode_sha256 = ethers.keccak256(deployedBytecode);
    } catch {
      // Non-critical
    }
  });

  it("Step 2: Mint tokens to account[0]", async function () {
    const start = Date.now();

    const tx = await token.mint(addresses[0], INITIAL_MINT);
    await waitForTx(tx);

    recordStep("Mint tokens", start);
    contractEvidence.step_tx_hashes["mint"] = tx.hash;

    // Verify mint
    const balance = await token.balanceOf(addresses[0]);
    expect(balance).to.equal(INITIAL_MINT);
  });

  it("Step 3: Transfer to account[1]", async function () {
    const start = Date.now();

    const tx = await token.connect(accounts[0]).transfer(addresses[1], TRANSFER_AMOUNT);
    await waitForTx(tx);

    recordStep("Transfer to acc[1]", start);
    contractEvidence.step_tx_hashes["transfer_1"] = tx.hash;
  });

  it("Step 4: Transfer to account[2]", async function () {
    const start = Date.now();

    const tx = await token.connect(accounts[0]).transfer(addresses[2], TRANSFER_AMOUNT);
    await waitForTx(tx);

    recordStep("Transfer to acc[2]", start);
    contractEvidence.step_tx_hashes["transfer_2"] = tx.hash;
  });

  it("Step 5: eth_call confirms final balances", async function () {
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

    console.log("\nFinal balances:");
    console.log(`  account[0]: ${ethers.formatEther(bal0)} BENCH`);
    console.log(`  account[1]: ${ethers.formatEther(bal1)} BENCH`);
    console.log(`  account[2]: ${ethers.formatEther(bal2)} BENCH`);
  });
});
