import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Counter } from "../typechain-types";

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
  });

  it("Step 2: Write - increment()", async function () {
    const start = Date.now();

    const tx = await counter.increment();
    await waitForTx(tx);

    recordStep("Write (increment)", start);
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
  });

  it("Step 6: Final read - verify count() == 42", async function () {
    const start = Date.now();

    const count = await counter.count();
    expect(count).to.equal(42);

    recordStep("Final read", start);
  });
});
