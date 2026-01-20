import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Factory, ChildFactory, Counter } from "../typechain-types";

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

/**
 * Factory Tests
 * EVM Coverage: CREATE, CREATE2, contract-to-contract calls, address prediction
 */
describe("Factory", function () {
  const timing = getNetworkTiming();
  this.timeout(timing.timeout);

  let factory: Factory;
  let childFactory: ChildFactory;
  let owner: any;

  beforeEach(async function () {
    [owner] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("Factory");
    factory = await Factory.deploy();
    await factory.waitForDeployment();

    const ChildFactory = await ethers.getContractFactory("ChildFactory");
    childFactory = await ChildFactory.deploy();
    await childFactory.waitForDeployment();
  });

  describe("Factory Deployment", function () {
    it("Should set owner", async function () {
      expect(await factory.owner()).to.equal(owner.address);
    });

    it("Should have zero deployed contracts initially", async function () {
      expect(await factory.getDeployedCount()).to.equal(0);
    });
  });

  describe("CREATE Deployment", function () {
    it("Should deploy Counter using CREATE", async function () {
      const tx = await factory.deployCounter();
      const receipt = await waitForTx(tx);

      expect(await factory.getDeployedCount()).to.equal(1);

      const deployed = await factory.deployedContracts(0);
      expect(deployed).to.not.equal(ethers.ZeroAddress);
    });

    it("Should emit ContractDeployed event", async function () {
      await expect(factory.deployCounter())
        .to.emit(factory, "ContractDeployed");
    });

    it("Should deploy functional Counter", async function () {
      const tx = await factory.deployCounter();
      await waitForTx(tx);

      const deployedAddress = await factory.deployedContracts(0);
      const counter = await ethers.getContractAt("Counter", deployedAddress) as Counter;

      expect(await counter.count()).to.equal(0);

      const incTx = await counter.increment();
      await waitForTx(incTx);

      expect(await counter.count()).to.equal(1);
    });

    it("Should deploy multiple Counters with unique addresses", async function () {
      const tx1 = await factory.deployCounter();
      await waitForTx(tx1);

      const tx2 = await factory.deployCounter();
      await waitForTx(tx2);

      const tx3 = await factory.deployCounter();
      await waitForTx(tx3);

      expect(await factory.getDeployedCount()).to.equal(3);

      const addr1 = await factory.deployedContracts(0);
      const addr2 = await factory.deployedContracts(1);
      const addr3 = await factory.deployedContracts(2);

      expect(addr1).to.not.equal(addr2);
      expect(addr2).to.not.equal(addr3);
    });

    it("Should return all deployed addresses", async function () {
      const tx1 = await factory.deployCounter();
      await waitForTx(tx1);

      const tx2 = await factory.deployCounter();
      await waitForTx(tx2);

      const deployed = await factory.getAllDeployed();
      expect(deployed.length).to.equal(2);
    });
  });

  describe("CREATE2 Deployment", function () {
    it("Should deploy Counter using CREATE2", async function () {
      const salt = ethers.keccak256(ethers.toUtf8Bytes("test-salt"));

      const tx = await factory.deployCounterCreate2(salt);
      await waitForTx(tx);

      expect(await factory.getDeployedCount()).to.equal(1);
    });

    it("Should predict CREATE2 address correctly", async function () {
      const salt = ethers.keccak256(ethers.toUtf8Bytes("predict-test"));

      const predicted = await factory.predictAddress(salt);

      const tx = await factory.deployCounterCreate2(salt);
      await waitForTx(tx);

      const deployed = await factory.deployedContracts(0);
      expect(deployed).to.equal(predicted);
    });

    it("Should deploy to different addresses with different salts", async function () {
      const salt1 = ethers.keccak256(ethers.toUtf8Bytes("salt-1"));
      const salt2 = ethers.keccak256(ethers.toUtf8Bytes("salt-2"));

      const tx1 = await factory.deployCounterCreate2(salt1);
      await waitForTx(tx1);

      const tx2 = await factory.deployCounterCreate2(salt2);
      await waitForTx(tx2);

      const addr1 = await factory.deployedContracts(0);
      const addr2 = await factory.deployedContracts(1);

      expect(addr1).to.not.equal(addr2);
    });

    it("Should predict same address for same salt", async function () {
      const salt = ethers.keccak256(ethers.toUtf8Bytes("same-salt"));

      const predicted1 = await factory.predictAddress(salt);
      const predicted2 = await factory.predictAddress(salt);

      expect(predicted1).to.equal(predicted2);
    });
  });

  describe("Contract Interaction", function () {
    let deployedAddress: string;

    beforeEach(async function () {
      const tx = await factory.deployCounter();
      await waitForTx(tx);
      deployedAddress = await factory.deployedContracts(0);
    });

    it("Should call increment on deployed Counter", async function () {
      const tx = await factory.callIncrement(deployedAddress);
      await waitForTx(tx);

      const counter = await ethers.getContractAt("Counter", deployedAddress) as Counter;
      expect(await counter.count()).to.equal(1);
    });

    it("Should emit ContractCalled event", async function () {
      await expect(factory.callIncrement(deployedAddress))
        .to.emit(factory, "ContractCalled")
        .withArgs(deployedAddress, true);
    });

    it("Should call getCount on deployed Counter", async function () {
      const count = await factory.callGetCount(deployedAddress);
      expect(count).to.equal(0);

      const counter = await ethers.getContractAt("Counter", deployedAddress) as Counter;
      const incTx = await counter.increment();
      await waitForTx(incTx);

      const newCount = await factory.callGetCount(deployedAddress);
      expect(newCount).to.equal(1);
    });

    it("Should static call getCount", async function () {
      const count = await factory.staticCallGetCount(deployedAddress);
      expect(count).to.equal(0);
    });

    it("Should make low-level call", async function () {
      const callData = new ethers.Interface(["function increment()"]).encodeFunctionData("increment");

      const tx = await factory.lowLevelCall(deployedAddress, callData);
      await waitForTx(tx);

      const counter = await ethers.getContractAt("Counter", deployedAddress) as Counter;
      expect(await counter.count()).to.equal(1);
    });
  });

  describe("Deploy and Call", function () {
    it("Should deploy and increment in one transaction", async function () {
      const tx = await factory.deployAndIncrement();
      const receipt = await waitForTx(tx);

      expect(await factory.getDeployedCount()).to.equal(1);

      const deployedAddress = await factory.deployedContracts(0);
      const counter = await ethers.getContractAt("Counter", deployedAddress) as Counter;

      expect(await counter.count()).to.equal(1);
    });
  });

  describe("ChildFactory", function () {
    it("Should deploy child with value", async function () {
      const tx = await childFactory.deployChild(42);
      const receipt = await waitForTx(tx);

      // Get deployed address from event
      const events = await childFactory.queryFilter(
        childFactory.filters.ChildDeployed()
      );
      expect(events.length).to.equal(1);

      const childAddress = events[0].args[0];
      const child = await ethers.getContractAt("SimpleChild", childAddress);

      expect(await child.value()).to.equal(42);
      expect(await child.factory()).to.equal(await childFactory.getAddress());
    });

    it("Should emit ChildDeployed event", async function () {
      await expect(childFactory.deployChild(123))
        .to.emit(childFactory, "ChildDeployed");
    });

    it("Should deploy child using CREATE2", async function () {
      const salt = ethers.keccak256(ethers.toUtf8Bytes("child-salt"));

      const tx = await childFactory.deployChildCreate2(99, salt);
      await waitForTx(tx);

      const events = await childFactory.queryFilter(
        childFactory.filters.ChildDeployed()
      );
      const childAddress = events[0].args[0];
      const child = await ethers.getContractAt("SimpleChild", childAddress);

      expect(await child.value()).to.equal(99);
    });

    it("Should predict child CREATE2 address", async function () {
      const salt = ethers.keccak256(ethers.toUtf8Bytes("predict-child"));
      const value = 777;

      const predicted = await childFactory.predictChildAddress(value, salt);

      const tx = await childFactory.deployChildCreate2(value, salt);
      await waitForTx(tx);

      const events = await childFactory.queryFilter(
        childFactory.filters.ChildDeployed()
      );
      const deployed = events[0].args[0];

      expect(deployed).to.equal(predicted);
    });

    it("Should produce different addresses for different values", async function () {
      const salt = ethers.keccak256(ethers.toUtf8Bytes("same-salt"));

      const addr1 = await childFactory.predictChildAddress(100, salt);
      const addr2 = await childFactory.predictChildAddress(200, salt);

      expect(addr1).to.not.equal(addr2);
    });
  });
});
