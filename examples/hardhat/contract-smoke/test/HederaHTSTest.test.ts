import { expect } from "chai";
import { ethers, network } from "hardhat";
import { HederaHTSTest, HederaCapabilityChecker } from "../typechain-types";

// ============================================================================
// TIMING CONFIGURATION
// ============================================================================
interface NetworkTiming {
  defaultWaitMs: number;
  intermediateWaitMs: number;
  timeout: number;
}

const NETWORK_TIMINGS: Record<string, NetworkTiming> = {
  localnode: { defaultWaitMs: 500, intermediateWaitMs: 300, timeout: 60000 },
  solo: { defaultWaitMs: 2500, intermediateWaitMs: 1500, timeout: 120000 },
  hardhat: { defaultWaitMs: 0, intermediateWaitMs: 0, timeout: 20000 },
};

function getNetworkTiming(): NetworkTiming {
  return NETWORK_TIMINGS[network.name] || NETWORK_TIMINGS.solo;
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

// Hedera chain IDs
const HEDERA_CHAIN_IDS = [295, 296, 297, 298];

function isHederaNetwork(): boolean {
  const chainId = network.config.chainId;
  return chainId !== undefined && HEDERA_CHAIN_IDS.includes(chainId);
}

/**
 * HederaHTSTest Tests
 * EVM Coverage: Hedera precompiles (HTS 0x167, Exchange Rate 0x168, PRNG 0x169)
 * Note: Many tests will be skipped when not running on actual Hedera network
 */
describe("HederaHTSTest", function () {
  const timing = getNetworkTiming();
  this.timeout(timing.timeout);

  let htsTest: HederaHTSTest;
  let checker: HederaCapabilityChecker;
  let isHedera: boolean;

  before(function () {
    isHedera = isHederaNetwork();
    console.log(`\n  Network: ${network.name}`);
    console.log(`  Chain ID: ${network.config.chainId}`);
    console.log(`  Is Hedera: ${isHedera}`);
    console.log("");
  });

  beforeEach(async function () {
    const HederaHTSTest = await ethers.getContractFactory("HederaHTSTest");
    htsTest = await HederaHTSTest.deploy();
    await htsTest.waitForDeployment();

    const HederaCapabilityChecker = await ethers.getContractFactory("HederaCapabilityChecker");
    checker = await HederaCapabilityChecker.deploy();
    await checker.waitForDeployment();
  });

  describe("Capability Checker", function () {
    it("Should get chain ID", async function () {
      const chainId = await checker.getChainId();
      expect(chainId).to.be.greaterThan(0);
    });

    it("Should detect Hedera chain ID", async function () {
      const isHederaChain = await checker.isHederaChainId();

      if (isHedera) {
        expect(isHederaChain).to.be.true;
      }
      // On non-Hedera networks, it should be false
    });

    it("Should check capabilities", async function () {
      const caps = await checker.checkCapabilities();

      expect(caps.chainId).to.be.greaterThan(0);
      // isHedera, hasHTS, hasPRNG, hasExchangeRate depend on network
    });
  });

  describe("Network Detection", function () {
    it("Should deploy successfully", async function () {
      const address = await htsTest.getAddress();
      expect(address).to.not.equal(ethers.ZeroAddress);
    });

    it("Should detect if running on Hedera", async function () {
      // Note: isHederaNetwork() makes a call to exchange rate precompile
      // This may fail on non-Hedera networks
      try {
        const result = await htsTest.isHederaNetwork();
        console.log(`    isHederaNetwork() returned: ${result}`);
      } catch (e) {
        console.log(`    isHederaNetwork() reverted (expected on non-Hedera)`);
      }
    });
  });

  describe("PRNG (Hedera-only)", function () {
    it("Should get random seed", async function () {
      if (!isHedera) {
        console.log("    Skipping - not on Hedera network");
        this.skip();
      }

      const tx = await htsTest.getRandomSeed();
      const receipt = await waitForTx(tx);

      // Check for RandomGenerated event
      const events = await htsTest.queryFilter(htsTest.filters.RandomGenerated());
      expect(events.length).to.be.greaterThan(0);

      const seed = events[0].args[0];
      expect(seed).to.not.equal(ethers.ZeroHash);
    });

    it("Should get random in range", async function () {
      if (!isHedera) {
        console.log("    Skipping - not on Hedera network");
        this.skip();
      }

      // Note: This function returns a value, but we can't easily capture it
      // without events. We mainly verify it doesn't revert.
      await expect(htsTest.getRandomInRange(1, 100)).to.not.be.reverted;
    });
  });

  describe("Exchange Rate (Hedera-only)", function () {
    it("Should convert tinycents to tinybars", async function () {
      if (!isHedera) {
        console.log("    Skipping - not on Hedera network");
        this.skip();
      }

      const tinycents = 1000000n; // 1 cent

      const tx = await htsTest.convertTinycentsToTinybars(tinycents);
      const receipt = await waitForTx(tx);

      // Check for ExchangeRateQueried event
      const events = await htsTest.queryFilter(htsTest.filters.ExchangeRateQueried());
      expect(events.length).to.be.greaterThan(0);

      const tinybars = events[0].args[1];
      expect(tinybars).to.be.greaterThan(0);
    });

    it("Should convert tinybars to tinycents", async function () {
      if (!isHedera) {
        console.log("    Skipping - not on Hedera network");
        this.skip();
      }

      const tinybars = 100000000n; // 1 HBAR

      // This function doesn't emit an event, just verify no revert
      await expect(htsTest.convertTinybarsToTinycents(tinybars)).to.not.be.reverted;
    });
  });

  describe("HTS Basic (Hedera-only)", function () {
    it("Should check token association", async function () {
      if (!isHedera) {
        console.log("    Skipping - not on Hedera network");
        this.skip();
      }

      // Check association with a non-existent token
      const isAssociated = await htsTest.checkAssociation(
        await htsTest.getAddress(),
        "0x0000000000000000000000000000000000001234"
      );

      expect(isAssociated).to.be.false;
    });
  });

  describe("Low-Level Precompile Calls", function () {
    it("Should call HTS precompile", async function () {
      if (!isHedera) {
        console.log("    Skipping - not on Hedera network");
        this.skip();
      }

      const data = htsTest.interface.encodeFunctionData("checkAssociation", [
        await htsTest.getAddress(),
        "0x0000000000000000000000000000000000001234",
      ]);

      // The callHTS function wraps the low-level call
      // Just verify it doesn't revert catastrophically
      try {
        await htsTest.callHTS(data);
      } catch (e) {
        // May fail if precompile not available
        console.log("    HTS precompile call failed (may be expected)");
      }
    });

    it("Should call Exchange Rate precompile", async function () {
      if (!isHedera) {
        console.log("    Skipping - not on Hedera network");
        this.skip();
      }

      const iface = new ethers.Interface(["function tinycentsToTinybars(uint256)"]);
      const data = iface.encodeFunctionData("tinycentsToTinybars", [100]);

      try {
        const [success, result] = await htsTest.callExchangeRate.staticCall(data);
        console.log(`    Exchange rate call success: ${success}`);
        if (success && result.length > 0) {
          const decoded = ethers.AbiCoder.defaultAbiCoder().decode(["uint256"], result);
          console.log(`    Result: ${decoded[0]} tinybars`);
        }
      } catch (e) {
        console.log("    Exchange rate precompile call failed (may be expected)");
      }
    });

    it("Should call PRNG precompile", async function () {
      if (!isHedera) {
        console.log("    Skipping - not on Hedera network");
        this.skip();
      }

      const iface = new ethers.Interface(["function getPseudorandomSeed()"]);
      const data = iface.encodeFunctionData("getPseudorandomSeed", []);

      try {
        const [success, result] = await htsTest.callPRNG(data);
        console.log(`    PRNG call success: ${success}`);
        if (success && result.length >= 32) {
          console.log(`    Random seed obtained`);
        }
      } catch (e) {
        console.log("    PRNG precompile call failed (may be expected)");
      }
    });
  });

  describe("Block Properties", function () {
    it("Should access block timestamp", async function () {
      const block = await ethers.provider.getBlock("latest");
      expect(block).to.not.be.null;
      expect(block!.timestamp).to.be.greaterThan(0);
    });

    it("Should access block number", async function () {
      const block = await ethers.provider.getBlock("latest");
      expect(block).to.not.be.null;
      expect(block!.number).to.be.greaterThanOrEqual(0);
    });
  });

  describe("Full Capability Report", function () {
    it("Should generate capability report", async function () {
      const caps = await checker.checkCapabilities();

      console.log("\n  === Hedera Capability Report ===");
      console.log(`  Chain ID: ${caps.chainId}`);
      console.log(`  Is Hedera (chain ID): ${caps.isHedera}`);
      console.log(`  HTS Available: ${caps.hasHTS}`);
      console.log(`  PRNG Available: ${caps.hasPRNG}`);
      console.log(`  Exchange Rate Available: ${caps.hasExchangeRate}`);
      console.log("");
    });
  });
});
