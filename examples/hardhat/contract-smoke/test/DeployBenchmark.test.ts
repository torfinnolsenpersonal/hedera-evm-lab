import { expect } from "chai";
import { ethers, network } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import { Counter } from "../typechain-types";

// ============================================================================
// CONTRACT EVIDENCE - captures verifiable deployment data
// ============================================================================
interface ContractEvidence {
  label: string;
  network: string;
  address: string;
  bytecode_sha256: string;
  deploy_tx: string;
  step_tx_hashes: Record<string, string>;
}

const contractEvidence: ContractEvidence = {
  label: process.env.BENCHMARK_LABEL || network.name,
  network: network.name,
  address: "",
  bytecode_sha256: "",
  deploy_tx: "",
  step_tx_hashes: {},
};

// ============================================================================
// TIMING CONFIGURATION - Adjust based on network characteristics
// ============================================================================
interface NetworkTiming {
  defaultWaitMs: number;
  intermediateWaitMs: number;
  timeout: number;
}

const NETWORK_TIMINGS: Record<string, NetworkTiming> = {
  hardhat: {
    defaultWaitMs: 0,
    intermediateWaitMs: 0,
    timeout: 10000,
  },
  anvil: {
    defaultWaitMs: 0,
    intermediateWaitMs: 0,
    timeout: 30000,
  },
  localnode: {
    defaultWaitMs: 500,
    intermediateWaitMs: 300,
    timeout: 40000,
  },
  solo: {
    defaultWaitMs: 2500,
    intermediateWaitMs: 1500,
    timeout: 90000,
  },
  hedera_testnet: {
    defaultWaitMs: 5000,
    intermediateWaitMs: 3000,
    timeout: 120000,
  },
};

function getNetworkTiming(): NetworkTiming {
  return NETWORK_TIMINGS[network.name] || NETWORK_TIMINGS.solo;
}

// ============================================================================
// PER-STEP TIMING
// ============================================================================
interface StepTiming {
  step: string;
  durationMs: number;
}

const stepTimings: StepTiming[] = [];

function recordStep(step: string, startMs: number): void {
  stepTimings.push({ step, durationMs: Date.now() - startMs });
}

// Helper to wait for transaction with mirror node sync delay
async function waitForTx(tx: any, customDelayMs?: number): Promise<any> {
  const timing = getNetworkTiming();
  const delayMs = customDelayMs ?? timing.defaultWaitMs;
  const receipt = await tx.wait();
  if (delayMs > 0) {
    await new Promise(resolve => setTimeout(resolve, delayMs));
  }
  return receipt;
}

// ============================================================================
// DEPLOY BENCHMARK
// ============================================================================
describe("Deploy Benchmark", function () {
  const timing = getNetworkTiming();
  this.timeout(timing.timeout);

  let counter: Counter;
  let owner: any;

  before(async function () {
    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log(`║         DEPLOY BENCHMARK - ${network.name.padEnd(28)}║`);
    console.log("╠══════════════════════════════════════════════════════════╣");
    console.log(`║  Default Wait:   ${(timing.defaultWaitMs + "ms").padEnd(38)}║`);
    console.log(`║  Intermediate:   ${(timing.intermediateWaitMs + "ms").padEnd(38)}║`);
    console.log(`║  Timeout:        ${(timing.timeout + "ms").padEnd(38)}║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");

    [owner] = await ethers.getSigners();
  });

  after(function () {
    const totalMs = stepTimings.reduce((sum, s) => sum + s.durationMs, 0);

    console.log("\n╔══════════════════════════════════════════════════════════╗");
    console.log(`║         DEPLOY BENCHMARK - ${network.name.padEnd(28)}║`);
    console.log("╠══════════════════════════════════════════════════════════╣");
    for (const s of stepTimings) {
      const label = `║  ${s.step}`;
      const value = `${s.durationMs}ms`;
      console.log(`${label.padEnd(42)}${value.padStart(14)} ║`);
    }
    console.log("╠══════════════════════════════════════════════════════════╣");
    const totalLabel = "║  TOTAL";
    const totalValue = `${totalMs}ms`;
    console.log(`${totalLabel.padEnd(42)}${totalValue.padStart(14)} ║`);
    console.log("╚══════════════════════════════════════════════════════════╝\n");

    // Evidence: always print [EVIDENCE] summary lines (parseable, backward compatible)
    console.log(`[EVIDENCE] contract_address=${contractEvidence.address}`);
    console.log(`[EVIDENCE] deploy_tx=${contractEvidence.deploy_tx}`);
    console.log(`[EVIDENCE] bytecode_sha256=${contractEvidence.bytecode_sha256}`);
    for (const [step, hash] of Object.entries(contractEvidence.step_tx_hashes)) {
      console.log(`[EVIDENCE] tx_${step}=${hash}`);
    }

    // Evidence: write JSON artifact if BENCHMARK_EVIDENCE_DIR is set
    const evidenceDir = process.env.BENCHMARK_EVIDENCE_DIR;
    if (evidenceDir) {
      try {
        if (!fs.existsSync(evidenceDir)) {
          fs.mkdirSync(evidenceDir, { recursive: true });
        }
        const artifactPath = path.join(
          evidenceDir,
          `${contractEvidence.label}-contract-evidence.json`
        );
        fs.writeFileSync(artifactPath, JSON.stringify(contractEvidence, null, 2));
        console.log(`[EVIDENCE] artifact_written=${artifactPath}`);
      } catch (err) {
        console.log(`[EVIDENCE] artifact_write_error=${err}`);
      }
    }
  });

  it("Step 1: Deploy Counter contract", async function () {
    const start = Date.now();

    const Counter = await ethers.getContractFactory("Counter");
    counter = await Counter.deploy();
    await counter.waitForDeployment();

    // Allow mirror node sync after deploy
    if (timing.defaultWaitMs > 0) {
      await new Promise(resolve => setTimeout(resolve, timing.defaultWaitMs));
    }

    recordStep("Deploy contract", start);

    const address = await counter.getAddress();
    expect(address).to.be.properAddress;

    // Evidence: capture contract address, deploy tx hash, bytecode hash
    contractEvidence.address = address;
    const deployTx = counter.deploymentTransaction();
    if (deployTx) {
      contractEvidence.deploy_tx = deployTx.hash;
    }
    try {
      const deployedBytecode = await ethers.provider.getCode(address);
      contractEvidence.bytecode_sha256 = ethers.keccak256(deployedBytecode);
    } catch {
      // Non-critical; some networks may not support getCode immediately
    }
  });

  it("Step 2: Write - increment()", async function () {
    const start = Date.now();

    const tx = await counter.increment();
    await waitForTx(tx);

    recordStep("Write (increment)", start);
    contractEvidence.step_tx_hashes["increment"] = tx.hash;
  });

  it("Step 3: Read - count()", async function () {
    const start = Date.now();

    const count = await counter.count();
    expect(count).to.equal(1);

    recordStep("Read (count)", start);
  });

  it("Step 4: Event verification - CountChanged", async function () {
    const start = Date.now();

    // Query for CountChanged events
    const filter = counter.filters.CountChanged();
    const events = await counter.queryFilter(filter);
    expect(events.length).to.be.greaterThan(0);

    const lastEvent = events[events.length - 1];
    expect(lastEvent.args?.newCount).to.equal(1);
    expect(lastEvent.args?.changedBy).to.equal(owner.address);

    recordStep("Event verification", start);
  });

  it("Step 5: Write - setCount(42)", async function () {
    const start = Date.now();

    const tx = await counter.setCount(42);
    await waitForTx(tx);

    recordStep("Write (setCount)", start);
    contractEvidence.step_tx_hashes["setCount"] = tx.hash;
  });

  it("Step 6: Final read - verify count() == 42", async function () {
    const start = Date.now();

    const count = await counter.count();
    expect(count).to.equal(42);

    recordStep("Final read", start);
  });
});
