import { expect } from "chai";
import { ethers, network } from "hardhat";
import { PayableTest } from "../typechain-types";

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
 * PayableTest Tests
 * EVM Coverage: payable, receive, fallback, value transfers (transfer, send, call)
 */
describe("PayableTest", function () {
  const timing = getNetworkTiming();
  this.timeout(timing.timeout);

  let payableContract: PayableTest;
  let owner: any;
  let alice: any;

  const DEPOSIT_AMOUNT = ethers.parseEther("1");

  beforeEach(async function () {
    [owner, alice] = await ethers.getSigners();

    const PayableTest = await ethers.getContractFactory("PayableTest");
    payableContract = await PayableTest.deploy();
    await payableContract.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set owner on deployment", async function () {
      expect(await payableContract.owner()).to.equal(owner.address);
    });

    it("Should have zero initial balance", async function () {
      expect(await payableContract.getBalance()).to.equal(0);
    });

    it("Should accept ETH/HBAR on deployment", async function () {
      const PayableTest = await ethers.getContractFactory("PayableTest");
      const funded = await PayableTest.deploy({ value: DEPOSIT_AMOUNT });
      await funded.waitForDeployment();

      expect(await funded.getBalance()).to.equal(DEPOSIT_AMOUNT);
      expect(await funded.totalReceived()).to.equal(DEPOSIT_AMOUNT);
    });
  });

  describe("Receive", function () {
    it("Should receive ETH/HBAR directly", async function () {
      const tx = await owner.sendTransaction({
        to: await payableContract.getAddress(),
        value: DEPOSIT_AMOUNT,
      });
      await waitForTx(tx);

      expect(await payableContract.getBalance()).to.equal(DEPOSIT_AMOUNT);
    });

    it("Should emit Received event", async function () {
      await expect(
        owner.sendTransaction({
          to: await payableContract.getAddress(),
          value: DEPOSIT_AMOUNT,
        })
      )
        .to.emit(payableContract, "Received")
        .withArgs(owner.address, DEPOSIT_AMOUNT);
    });

    it("Should update totalReceived", async function () {
      const tx1 = await owner.sendTransaction({
        to: await payableContract.getAddress(),
        value: DEPOSIT_AMOUNT,
      });
      await waitForTx(tx1);

      const tx2 = await owner.sendTransaction({
        to: await payableContract.getAddress(),
        value: DEPOSIT_AMOUNT,
      });
      await waitForTx(tx2);

      expect(await payableContract.totalReceived()).to.equal(DEPOSIT_AMOUNT * 2n);
    });
  });

  describe("Deposit", function () {
    it("Should accept deposits", async function () {
      const tx = await payableContract.deposit({ value: DEPOSIT_AMOUNT });
      await waitForTx(tx);

      expect(await payableContract.getBalance()).to.equal(DEPOSIT_AMOUNT);
    });

    it("Should emit Received event on deposit", async function () {
      await expect(payableContract.deposit({ value: DEPOSIT_AMOUNT }))
        .to.emit(payableContract, "Received")
        .withArgs(owner.address, DEPOSIT_AMOUNT);
    });

    it("Should revert on zero deposit", async function () {
      await expect(payableContract.deposit({ value: 0 }))
        .to.be.revertedWithCustomError(payableContract, "ZeroAmount");
    });
  });

  describe("Withdraw", function () {
    beforeEach(async function () {
      const tx = await payableContract.deposit({ value: DEPOSIT_AMOUNT });
      await waitForTx(tx);
    });

    it("Should withdraw using transfer", async function () {
      const balanceBefore = await ethers.provider.getBalance(owner.address);

      const tx = await payableContract.withdrawTransfer();
      const receipt = await waitForTx(tx);

      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const balanceAfter = await ethers.provider.getBalance(owner.address);

      expect(await payableContract.getBalance()).to.equal(0);
      expect(balanceAfter).to.be.closeTo(
        balanceBefore + DEPOSIT_AMOUNT - gasUsed,
        ethers.parseEther("0.01") // Allow small variance for gas estimation
      );
    });

    it("Should withdraw using call", async function () {
      const tx = await payableContract.withdrawCall();
      await waitForTx(tx);

      expect(await payableContract.getBalance()).to.equal(0);
    });

    it("Should emit Withdrawn event", async function () {
      await expect(payableContract.withdrawCall())
        .to.emit(payableContract, "Withdrawn")
        .withArgs(owner.address, DEPOSIT_AMOUNT);
    });

    it("Should revert if empty", async function () {
      await payableContract.withdrawCall();

      await expect(payableContract.withdrawCall())
        .to.be.revertedWithCustomError(payableContract, "InsufficientBalance");
    });

    it("Should only allow owner to withdraw", async function () {
      await expect(payableContract.connect(alice).withdrawCall())
        .to.be.revertedWithCustomError(payableContract, "NotOwner");
    });
  });

  describe("Withdraw To", function () {
    beforeEach(async function () {
      const tx = await payableContract.deposit({ value: DEPOSIT_AMOUNT });
      await waitForTx(tx);
    });

    it("Should withdraw to specific address", async function () {
      const aliceBalanceBefore = await ethers.provider.getBalance(alice.address);
      const halfAmount = DEPOSIT_AMOUNT / 2n;

      const tx = await payableContract.withdrawTo(alice.address, halfAmount);
      await waitForTx(tx);

      expect(await ethers.provider.getBalance(alice.address)).to.equal(aliceBalanceBefore + halfAmount);
      expect(await payableContract.getBalance()).to.equal(halfAmount);
    });

    it("Should emit Withdrawn event with recipient", async function () {
      const halfAmount = DEPOSIT_AMOUNT / 2n;

      await expect(payableContract.withdrawTo(alice.address, halfAmount))
        .to.emit(payableContract, "Withdrawn")
        .withArgs(alice.address, halfAmount);
    });

    it("Should revert on insufficient balance", async function () {
      await expect(payableContract.withdrawTo(alice.address, DEPOSIT_AMOUNT + 1n))
        .to.be.revertedWithCustomError(payableContract, "InsufficientBalance");
    });

    it("Should revert on zero amount", async function () {
      await expect(payableContract.withdrawTo(alice.address, 0))
        .to.be.revertedWithCustomError(payableContract, "ZeroAmount");
    });
  });

  describe("Ownership", function () {
    it("Should transfer ownership", async function () {
      const tx = await payableContract.transferOwnership(alice.address);
      await waitForTx(tx);

      expect(await payableContract.owner()).to.equal(alice.address);
    });

    it("Should allow new owner to withdraw", async function () {
      const depositTx = await payableContract.deposit({ value: DEPOSIT_AMOUNT });
      await waitForTx(depositTx);

      const transferTx = await payableContract.transferOwnership(alice.address);
      await waitForTx(transferTx);

      const aliceBalanceBefore = await ethers.provider.getBalance(alice.address);

      const withdrawTx = await payableContract.connect(alice).withdrawCall();
      const receipt = await waitForTx(withdrawTx);

      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const aliceBalanceAfter = await ethers.provider.getBalance(alice.address);

      expect(aliceBalanceAfter).to.be.closeTo(
        aliceBalanceBefore + DEPOSIT_AMOUNT - gasUsed,
        ethers.parseEther("0.01")
      );
    });

    it("Should prevent old owner from withdrawing", async function () {
      const depositTx = await payableContract.deposit({ value: DEPOSIT_AMOUNT });
      await waitForTx(depositTx);

      const transferTx = await payableContract.transferOwnership(alice.address);
      await waitForTx(transferTx);

      await expect(payableContract.withdrawCall())
        .to.be.revertedWithCustomError(payableContract, "NotOwner");
    });
  });

  describe("Fallback", function () {
    it("Should handle calls with data via fallback", async function () {
      const tx = await owner.sendTransaction({
        to: await payableContract.getAddress(),
        value: DEPOSIT_AMOUNT,
        data: "0x12345678", // Some arbitrary data
      });
      await waitForTx(tx);

      expect(await payableContract.getBalance()).to.equal(DEPOSIT_AMOUNT);
      expect(await payableContract.totalReceived()).to.equal(DEPOSIT_AMOUNT);
    });

    it("Should emit FallbackCalled event", async function () {
      const data = "0x12345678";

      await expect(
        owner.sendTransaction({
          to: await payableContract.getAddress(),
          value: DEPOSIT_AMOUNT,
          data: data,
        })
      )
        .to.emit(payableContract, "FallbackCalled")
        .withArgs(owner.address, DEPOSIT_AMOUNT, data);
    });
  });
});
