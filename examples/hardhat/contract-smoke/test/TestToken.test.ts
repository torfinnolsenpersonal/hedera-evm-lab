import { expect } from "chai";
import { ethers, network } from "hardhat";
import { TestToken } from "../typechain-types";

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
 * TestToken Tests
 * EVM Coverage: Mappings, nested mappings, ERC-20 operations, events
 */
describe("TestToken", function () {
  const timing = getNetworkTiming();
  this.timeout(timing.timeout);

  let token: TestToken;
  let owner: any;
  let alice: any;
  let bob: any;

  const INITIAL_SUPPLY = 1000000n; // 1 million tokens
  const DECIMALS = 18n;
  const INITIAL_SUPPLY_WEI = INITIAL_SUPPLY * (10n ** DECIMALS);

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();

    const TestToken = await ethers.getContractFactory("TestToken");
    token = await TestToken.deploy("Test Token", "TEST", INITIAL_SUPPLY);
    await token.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set token name", async function () {
      expect(await token.name()).to.equal("Test Token");
    });

    it("Should set token symbol", async function () {
      expect(await token.symbol()).to.equal("TEST");
    });

    it("Should set decimals to 18", async function () {
      expect(await token.decimals()).to.equal(18);
    });

    it("Should set total supply", async function () {
      expect(await token.totalSupply()).to.equal(INITIAL_SUPPLY_WEI);
    });

    it("Should assign total supply to owner", async function () {
      expect(await token.balanceOf(owner.address)).to.equal(INITIAL_SUPPLY_WEI);
    });
  });

  describe("Transfer", function () {
    it("Should transfer tokens between accounts", async function () {
      const amount = ethers.parseEther("1000");
      const tx = await token.transfer(alice.address, amount);
      await waitForTx(tx);

      expect(await token.balanceOf(alice.address)).to.equal(amount);
    });

    it("Should emit Transfer event", async function () {
      const amount = ethers.parseEther("1000");
      await expect(token.transfer(alice.address, amount))
        .to.emit(token, "Transfer")
        .withArgs(owner.address, alice.address, amount);
    });

    it("Should fail if sender has insufficient balance", async function () {
      const tooMuch = INITIAL_SUPPLY_WEI + 1n;
      await expect(token.transfer(alice.address, tooMuch))
        .to.be.revertedWithCustomError(token, "InsufficientBalance");
    });

    it("Should fail if recipient is zero address", async function () {
      await expect(token.transfer(ethers.ZeroAddress, 100))
        .to.be.revertedWithCustomError(token, "ZeroAddress");
    });

    it("Should allow transfer between non-owner accounts", async function () {
      const amount = ethers.parseEther("500");
      const tx1 = await token.transfer(alice.address, amount);
      await waitForTx(tx1);

      const halfAmount = amount / 2n;
      const tx2 = await token.connect(alice).transfer(bob.address, halfAmount);
      await waitForTx(tx2);

      expect(await token.balanceOf(alice.address)).to.equal(halfAmount);
      expect(await token.balanceOf(bob.address)).to.equal(halfAmount);
    });
  });

  describe("Approval", function () {
    it("Should approve spender", async function () {
      const amount = ethers.parseEther("1000");
      const tx = await token.approve(alice.address, amount);
      await waitForTx(tx);

      expect(await token.allowance(owner.address, alice.address)).to.equal(amount);
    });

    it("Should emit Approval event", async function () {
      const amount = ethers.parseEther("1000");
      await expect(token.approve(alice.address, amount))
        .to.emit(token, "Approval")
        .withArgs(owner.address, alice.address, amount);
    });

    it("Should fail if spender is zero address", async function () {
      await expect(token.approve(ethers.ZeroAddress, 100))
        .to.be.revertedWithCustomError(token, "ZeroAddress");
    });

    it("Should overwrite existing approval", async function () {
      const tx1 = await token.approve(alice.address, 1000);
      await waitForTx(tx1);
      const tx2 = await token.approve(alice.address, 500);
      await waitForTx(tx2);

      expect(await token.allowance(owner.address, alice.address)).to.equal(500);
    });
  });

  describe("TransferFrom", function () {
    const approvalAmount = ethers.parseEther("1000");

    beforeEach(async function () {
      const tx = await token.approve(alice.address, approvalAmount);
      await waitForTx(tx);
    });

    it("Should transfer tokens on behalf of owner", async function () {
      const tx = await token.connect(alice).transferFrom(owner.address, bob.address, approvalAmount);
      await waitForTx(tx);

      expect(await token.balanceOf(bob.address)).to.equal(approvalAmount);
      expect(await token.allowance(owner.address, alice.address)).to.equal(0);
    });

    it("Should emit Transfer event", async function () {
      await expect(token.connect(alice).transferFrom(owner.address, bob.address, approvalAmount))
        .to.emit(token, "Transfer")
        .withArgs(owner.address, bob.address, approvalAmount);
    });

    it("Should fail if allowance is insufficient", async function () {
      const tooMuch = approvalAmount + 1n;
      await expect(token.connect(alice).transferFrom(owner.address, bob.address, tooMuch))
        .to.be.revertedWithCustomError(token, "InsufficientAllowance");
    });

    it("Should reduce allowance after transfer", async function () {
      const transferAmount = approvalAmount / 2n;
      const tx = await token.connect(alice).transferFrom(owner.address, bob.address, transferAmount);
      await waitForTx(tx);

      expect(await token.allowance(owner.address, alice.address)).to.equal(approvalAmount - transferAmount);
    });
  });

  describe("Mint", function () {
    it("Should mint new tokens", async function () {
      const mintAmount = ethers.parseEther("1000");
      const totalBefore = await token.totalSupply();

      const tx = await token.mint(alice.address, mintAmount);
      await waitForTx(tx);

      expect(await token.balanceOf(alice.address)).to.equal(mintAmount);
      expect(await token.totalSupply()).to.equal(totalBefore + mintAmount);
    });

    it("Should emit Transfer event from zero address", async function () {
      const mintAmount = ethers.parseEther("1000");
      await expect(token.mint(alice.address, mintAmount))
        .to.emit(token, "Transfer")
        .withArgs(ethers.ZeroAddress, alice.address, mintAmount);
    });

    it("Should fail if minting to zero address", async function () {
      await expect(token.mint(ethers.ZeroAddress, 100))
        .to.be.revertedWithCustomError(token, "ZeroAddress");
    });
  });

  describe("Burn", function () {
    it("Should burn tokens", async function () {
      const burnAmount = ethers.parseEther("1000");
      const totalBefore = await token.totalSupply();
      const balanceBefore = await token.balanceOf(owner.address);

      const tx = await token.burn(burnAmount);
      await waitForTx(tx);

      expect(await token.balanceOf(owner.address)).to.equal(balanceBefore - burnAmount);
      expect(await token.totalSupply()).to.equal(totalBefore - burnAmount);
    });

    it("Should emit Transfer event to zero address", async function () {
      const burnAmount = ethers.parseEther("1000");
      await expect(token.burn(burnAmount))
        .to.emit(token, "Transfer")
        .withArgs(owner.address, ethers.ZeroAddress, burnAmount);
    });

    it("Should fail if burning more than balance", async function () {
      const tooMuch = INITIAL_SUPPLY_WEI + 1n;
      await expect(token.burn(tooMuch))
        .to.be.revertedWithCustomError(token, "InsufficientBalance");
    });
  });
});
