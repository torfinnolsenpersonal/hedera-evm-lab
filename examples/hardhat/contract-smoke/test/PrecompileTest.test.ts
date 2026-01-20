import { expect } from "chai";
import { ethers, network } from "hardhat";
import { PrecompileTest } from "../typechain-types";

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
 * PrecompileTest Tests
 * EVM Coverage: ecrecover (0x01), sha256 (0x02), ripemd160 (0x03), identity (0x04), modexp (0x05)
 */
describe("PrecompileTest", function () {
  const timing = getNetworkTiming();
  this.timeout(timing.timeout);

  let precompileTest: PrecompileTest;
  let signer: any;

  beforeEach(async function () {
    [signer] = await ethers.getSigners();

    const PrecompileTest = await ethers.getContractFactory("PrecompileTest");
    precompileTest = await PrecompileTest.deploy();
    await precompileTest.waitForDeployment();
  });

  describe("Keccak256 (EVM native)", function () {
    it("Should compute keccak256 hash", async function () {
      const data = ethers.toUtf8Bytes("hello");
      const hash = await precompileTest.computeKeccak256(data);

      const expected = ethers.keccak256(data);
      expect(hash).to.equal(expected);
    });

    it("Should compute keccak256 of empty data", async function () {
      const hash = await precompileTest.computeKeccak256("0x");
      const expected = ethers.keccak256("0x");
      expect(hash).to.equal(expected);
    });

    it("Should be deterministic", async function () {
      const data = ethers.toUtf8Bytes("test");
      const hash1 = await precompileTest.computeKeccak256(data);
      const hash2 = await precompileTest.computeKeccak256(data);
      expect(hash1).to.equal(hash2);
    });
  });

  describe("SHA-256 (Precompile 0x02)", function () {
    it("Should compute sha256 hash", async function () {
      const hash = await precompileTest.computeSha256(ethers.toUtf8Bytes("hello"));
      // Known SHA-256 hash of "hello"
      expect(hash).to.equal("0x2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
    });

    it("Should compute sha256 of string", async function () {
      const hash = await precompileTest.computeSha256String("hello");
      expect(hash).to.equal("0x2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
    });

    it("Should compute sha256 of empty data", async function () {
      const hash = await precompileTest.computeSha256("0x");
      // Known SHA-256 hash of empty string
      expect(hash).to.equal("0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    });

    it("Should differ from keccak256", async function () {
      const data = ethers.toUtf8Bytes("test");
      const sha = await precompileTest.computeSha256(data);
      const keccak = await precompileTest.computeKeccak256(data);
      expect(sha).to.not.equal(keccak);
    });

    it("Should compare hashes", async function () {
      const [sha, keccak] = await precompileTest.compareHashes(ethers.toUtf8Bytes("compare"));
      expect(sha).to.not.equal(ethers.ZeroHash);
      expect(keccak).to.not.equal(ethers.ZeroHash);
      expect(sha).to.not.equal(keccak);
    });
  });

  describe("RIPEMD-160 (Precompile 0x03)", function () {
    it("Should compute ripemd160 hash", async function () {
      const hash = await precompileTest.computeRipemd160(ethers.toUtf8Bytes("hello"));
      // Known RIPEMD-160 hash of "hello" (20 bytes)
      expect(hash.toLowerCase()).to.equal("0x108f07b8382412612c048d07d13f814118445acd");
    });

    it("Should compute ripemd160 of empty data", async function () {
      const hash = await precompileTest.computeRipemd160("0x");
      // Known RIPEMD-160 hash of empty string
      expect(hash.toLowerCase()).to.equal("0x9c1185a5c5e9fc54612808977ee8f548b2258d31");
    });
  });

  describe("Identity (Precompile 0x04)", function () {
    it("Should return input data unchanged", async function () {
      const input = ethers.toUtf8Bytes("test data");
      const output = await precompileTest.identityCall(input);

      expect(ethers.hexlify(output)).to.equal(ethers.hexlify(input));
    });

    it("Should handle empty input", async function () {
      const output = await precompileTest.identityCall("0x");
      expect(output).to.equal("0x");
    });
  });

  describe("ModExp (Precompile 0x05)", function () {
    it("Should compute modular exponentiation (2^3 mod 5 = 3)", async function () {
      const result = await precompileTest.modExpSimple(2, 3, 5);
      expect(result).to.equal(3);
    });

    it("Should compute larger modexp (3^7 mod 11 = 9)", async function () {
      const result = await precompileTest.modExpSimple(3, 7, 11);
      expect(result).to.equal(9);
    });

    it("Should compute x^0 mod y = 1", async function () {
      const result = await precompileTest.modExpSimple(5, 0, 7);
      expect(result).to.equal(1);
    });
  });

  describe("ECDSA Recovery (Precompile 0x01)", function () {
    it("Should recover signer from signature", async function () {
      const message = "test message";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(message));

      // Sign the message
      const signature = await signer.signMessage(ethers.getBytes(messageHash));
      const sig = ethers.Signature.from(signature);

      // Create the prefixed hash (what ethers actually signs)
      const prefixedHash = ethers.hashMessage(ethers.getBytes(messageHash));

      const recovered = await precompileTest.recoverSigner(
        prefixedHash,
        sig.v,
        sig.r,
        sig.s
      );

      expect(recovered).to.equal(signer.address);
    });

    it("Should verify valid signature", async function () {
      const message = "verify this";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(message));
      const prefixedHash = ethers.hashMessage(ethers.getBytes(messageHash));

      const signature = await signer.signMessage(ethers.getBytes(messageHash));
      const sig = ethers.Signature.from(signature);

      const isValid = await precompileTest.verifySignature(
        prefixedHash,
        sig.v,
        sig.r,
        sig.s,
        signer.address
      );

      expect(isValid).to.be.true;
    });

    it("Should reject wrong signer", async function () {
      const message = "wrong signer test";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(message));
      const prefixedHash = ethers.hashMessage(ethers.getBytes(messageHash));

      const signature = await signer.signMessage(ethers.getBytes(messageHash));
      const sig = ethers.Signature.from(signature);

      const isValid = await precompileTest.verifySignature(
        prefixedHash,
        sig.v,
        sig.r,
        sig.s,
        "0x1234567890123456789012345678901234567890" // Wrong address
      );

      expect(isValid).to.be.false;
    });

    it("Should return zero address for invalid signature", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes("test"));

      const recovered = await precompileTest.recoverSigner(
        messageHash,
        27,
        ethers.ZeroHash,
        ethers.ZeroHash
      );

      expect(recovered).to.equal(ethers.ZeroAddress);
    });
  });

  describe("EIP-191 Signed Messages", function () {
    it("Should create eth signed message hash", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes("test"));
      const ethSignedHash = await precompileTest.toEthSignedMessageHash(messageHash);

      const expected = ethers.hashMessage(ethers.getBytes(messageHash));
      expect(ethSignedHash).to.equal(expected);
    });

    it("Should hash message", async function () {
      const hash = await precompileTest.hashMessage("hello");
      const expected = ethers.keccak256(ethers.toUtf8Bytes("hello"));
      expect(hash).to.equal(expected);
    });

    it("Should verify message signature", async function () {
      const message = "Sign this message";

      // Sign using ethers (which adds prefix)
      const signature = await signer.signMessage(message);
      const sig = ethers.Signature.from(signature);

      const isValid = await precompileTest.verifyMessageSignature(
        message,
        sig.v,
        sig.r,
        sig.s,
        signer.address
      );

      expect(isValid).to.be.true;
    });
  });

  describe("Batch Verification", function () {
    it("Should batch verify multiple signatures", async function () {
      const messages = ["message0", "message1", "message2"];
      const hashes: string[] = [];
      const vs: number[] = [];
      const rs: string[] = [];
      const ss: string[] = [];
      const signers: string[] = [];

      for (const message of messages) {
        const messageHash = ethers.keccak256(ethers.toUtf8Bytes(message));
        const prefixedHash = ethers.hashMessage(ethers.getBytes(messageHash));

        const signature = await signer.signMessage(ethers.getBytes(messageHash));
        const sig = ethers.Signature.from(signature);

        hashes.push(prefixedHash);
        vs.push(sig.v);
        rs.push(sig.r);
        ss.push(sig.s);
        signers.push(signer.address);
      }

      const results = await precompileTest.batchVerify(hashes, vs, rs, ss, signers);

      expect(results[0]).to.be.true;
      expect(results[1]).to.be.true;
      expect(results[2]).to.be.true;
    });

    it("Should detect invalid signature in batch", async function () {
      const messages = ["message0", "message1", "message2"];
      const hashes: string[] = [];
      const vs: number[] = [];
      const rs: string[] = [];
      const ss: string[] = [];
      const signers: string[] = [];

      for (const message of messages) {
        const messageHash = ethers.keccak256(ethers.toUtf8Bytes(message));
        const prefixedHash = ethers.hashMessage(ethers.getBytes(messageHash));

        const signature = await signer.signMessage(ethers.getBytes(messageHash));
        const sig = ethers.Signature.from(signature);

        hashes.push(prefixedHash);
        vs.push(sig.v);
        rs.push(sig.r);
        ss.push(sig.s);
        signers.push(signer.address);
      }

      // Make middle signature invalid
      signers[1] = "0x1234567890123456789012345678901234567890";

      const results = await precompileTest.batchVerify(hashes, vs, rs, ss, signers);

      expect(results[0]).to.be.true;
      expect(results[1]).to.be.false; // Invalid
      expect(results[2]).to.be.true;
    });
  });
});
