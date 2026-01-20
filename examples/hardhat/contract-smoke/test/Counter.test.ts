import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Counter } from "../typechain-types";

// ============================================================================
// TIMING CONFIGURATION - Adjust based on network characteristics
// ============================================================================
interface NetworkTiming {
  defaultWaitMs: number;      // Wait after state-changing tx before reading
  intermediateWaitMs: number; // Wait between sequential txs
  timeout: number;            // Mocha test timeout
}

const NETWORK_TIMINGS: Record<string, NetworkTiming> = {
  localnode: {
    defaultWaitMs: 500,       // Local Node has faster finality
    intermediateWaitMs: 300,
    timeout: 40000,
  },
  solo: {
    defaultWaitMs: 2500,      // Solo needs more time for mirror node sync
    intermediateWaitMs: 1500,
    timeout: 90000,
  },
  hardhat: {
    defaultWaitMs: 0,         // Hardhat network is instant
    intermediateWaitMs: 0,
    timeout: 10000,
  },
};

// Get timing config for current network
function getNetworkTiming(): NetworkTiming {
  const networkName = network.name;
  return NETWORK_TIMINGS[networkName] || NETWORK_TIMINGS.solo; // Default to conservative
}

// ============================================================================
// TIMING INSTRUMENTATION - For gap analysis
// ============================================================================
interface TimingRecord {
  testName: string;
  network: string;
  deployTimeMs: number;
  txTimes: { operation: string; durationMs: number }[];
  totalTimeMs: number;
}

const timingRecords: TimingRecord[] = [];
let currentRecord: TimingRecord | null = null;
let testStartTime: number = 0;

function startTiming(testName: string): void {
  testStartTime = Date.now();
  currentRecord = {
    testName,
    network: network.name,
    deployTimeMs: 0,
    txTimes: [],
    totalTimeMs: 0,
  };
}

function recordTx(operation: string, startTime: number): void {
  if (currentRecord) {
    currentRecord.txTimes.push({
      operation,
      durationMs: Date.now() - startTime,
    });
  }
}

function endTiming(): void {
  if (currentRecord) {
    currentRecord.totalTimeMs = Date.now() - testStartTime;
    timingRecords.push(currentRecord);
    currentRecord = null;
  }
}

// Helper to wait for transaction and allow Hedera mirror node sync
async function waitForTx(tx: any, customDelayMs?: number): Promise<any> {
  const timing = getNetworkTiming();
  const delayMs = customDelayMs ?? timing.defaultWaitMs;

  const txStart = Date.now();
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

describe("Counter", function () {
  const timing = getNetworkTiming();
  this.timeout(timing.timeout);

  let counter: Counter;
  let owner: any;
  let other: any;

  before(function () {
    console.log("\n╔════════════════════════════════════════════════════════════╗");
    console.log("║              HEDERA EVM LAB - TEST RUN                     ║");
    console.log("╠════════════════════════════════════════════════════════════╣");
    console.log(`║  Network:        ${network.name.padEnd(40)}║`);
    console.log(`║  Default Wait:   ${(timing.defaultWaitMs + "ms").padEnd(40)}║`);
    console.log(`║  Intermediate:   ${(timing.intermediateWaitMs + "ms").padEnd(40)}║`);
    console.log(`║  Timeout:        ${(timing.timeout + "ms").padEnd(40)}║`);
    console.log("╚════════════════════════════════════════════════════════════╝\n");
  });

  after(function () {
    // Print timing summary for gap analysis
    console.log("\n╔════════════════════════════════════════════════════════════╗");
    console.log("║              TIMING SUMMARY (Gap Analysis)                 ║");
    console.log("╠════════════════════════════════════════════════════════════╣");
    console.log(`║  Network: ${network.name.padEnd(48)}║`);
    console.log("╠════════════════════════════════════════════════════════════╣");

    let totalTime = 0;
    for (const record of timingRecords) {
      totalTime += record.totalTimeMs;
      const testLine = `║  ${record.testName.substring(0, 45).padEnd(45)} ${(record.totalTimeMs + "ms").padStart(10)} ║`;
      console.log(testLine);
    }

    console.log("╠════════════════════════════════════════════════════════════╣");
    console.log(`║  TOTAL TEST TIME: ${(totalTime + "ms").padEnd(39)}║`);
    console.log(`║  AVG PER TEST:    ${(Math.round(totalTime / timingRecords.length) + "ms").padEnd(39)}║`);
    console.log("╚════════════════════════════════════════════════════════════╝\n");
  });

  beforeEach(async function () {
    startTiming(this.currentTest?.title || "unknown");
    [owner, other] = await ethers.getSigners();

    const deployStart = Date.now();
    const Counter = await ethers.getContractFactory("Counter");
    counter = await Counter.deploy();
    await counter.waitForDeployment();

    if (currentRecord) {
      currentRecord.deployTimeMs = Date.now() - deployStart;
    }
  });

  afterEach(function () {
    endTiming();
  });

  describe("Deployment", function () {
    it("Should set initial count to 0", async function () {
      expect(await counter.count()).to.equal(0);
    });

    it("Should set the deployer as owner", async function () {
      expect(await counter.owner()).to.equal(owner.address);
    });
  });

  describe("Increment", function () {
    it("Should increment the counter", async function () {
      const tx = await counter.increment();
      await waitForTx(tx);
      expect(await counter.count()).to.equal(1);
    });

    it("Should increment multiple times", async function () {
      const tx1 = await counter.increment();
      await waitForTxIntermediate(tx1);
      const tx2 = await counter.increment();
      await waitForTxIntermediate(tx2);
      const tx3 = await counter.increment();
      await waitForTx(tx3);
      expect(await counter.count()).to.equal(3);
    });

    it("Should emit CountChanged event", async function () {
      await expect(counter.increment())
        .to.emit(counter, "CountChanged")
        .withArgs(1, owner.address);
    });

    it("Should allow anyone to increment", async function () {
      const tx = await counter.connect(other).increment();
      await waitForTx(tx);
      expect(await counter.count()).to.equal(1);
    });
  });

  describe("Decrement", function () {
    beforeEach(async function () {
      const tx1 = await counter.increment();
      await waitForTxIntermediate(tx1);
      const tx2 = await counter.increment();
      await waitForTxIntermediate(tx2);
    });

    it("Should decrement the counter", async function () {
      const tx = await counter.decrement();
      await waitForTx(tx);
      expect(await counter.count()).to.equal(1);
    });

    it("Should revert when decrementing below zero", async function () {
      const tx1 = await counter.decrement();
      await waitForTxIntermediate(tx1);
      const tx2 = await counter.decrement();
      await waitForTxIntermediate(tx2);
      await expect(counter.decrement()).to.be.revertedWith(
        "Counter: cannot decrement below zero"
      );
    });

    it("Should emit CountChanged event", async function () {
      await expect(counter.decrement())
        .to.emit(counter, "CountChanged")
        .withArgs(1, owner.address);
    });
  });

  describe("Reset", function () {
    beforeEach(async function () {
      const tx1 = await counter.increment();
      await waitForTxIntermediate(tx1);
      const tx2 = await counter.increment();
      await waitForTxIntermediate(tx2);
    });

    it("Should reset the counter to zero", async function () {
      const tx = await counter.reset();
      await waitForTx(tx);
      expect(await counter.count()).to.equal(0);
    });

    it("Should only allow owner to reset", async function () {
      await expect(counter.connect(other).reset()).to.be.revertedWith(
        "Counter: caller is not owner"
      );
    });

    it("Should emit CountChanged event", async function () {
      await expect(counter.reset())
        .to.emit(counter, "CountChanged")
        .withArgs(0, owner.address);
    });
  });

  describe("SetCount", function () {
    it("Should set count to specific value", async function () {
      const tx = await counter.setCount(42);
      await waitForTx(tx);
      expect(await counter.count()).to.equal(42);
    });

    it("Should only allow owner to set count", async function () {
      await expect(counter.connect(other).setCount(100)).to.be.revertedWith(
        "Counter: caller is not owner"
      );
    });
  });

  describe("Ownership", function () {
    it("Should transfer ownership", async function () {
      const tx = await counter.transferOwnership(other.address);
      await waitForTx(tx);
      expect(await counter.owner()).to.equal(other.address);
    });

    it("Should emit OwnershipTransferred event", async function () {
      await expect(counter.transferOwnership(other.address))
        .to.emit(counter, "OwnershipTransferred")
        .withArgs(owner.address, other.address);
    });

    it("Should not allow transfer to zero address", async function () {
      await expect(
        counter.transferOwnership(ethers.ZeroAddress)
      ).to.be.revertedWith("Counter: new owner is zero address");
    });

    it("Should only allow owner to transfer ownership", async function () {
      await expect(
        counter.connect(other).transferOwnership(other.address)
      ).to.be.revertedWith("Counter: caller is not owner");
    });

    it("New owner should be able to reset", async function () {
      const tx1 = await counter.increment();
      await waitForTxIntermediate(tx1);
      const tx2 = await counter.transferOwnership(other.address);
      await waitForTx(tx2); // Full wait before ownership check
      const tx3 = await counter.connect(other).reset();
      await waitForTx(tx3);
      expect(await counter.count()).to.equal(0);
    });
  });
});
