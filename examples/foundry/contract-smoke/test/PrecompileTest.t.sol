// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PrecompileTest.sol";

/**
 * @title PrecompileTestTest
 * @dev EVM precompile tests - validates ecrecover, sha256, ripemd160, etc.
 * EVM Coverage: Precompiles 0x01-0x05, keccak256, signature verification
 */
contract PrecompileTestTest is Test {
    PrecompileTest public precompileTest;

    // Test signer (generated for tests)
    uint256 constant SIGNER_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address constant SIGNER_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        precompileTest = new PrecompileTest();
    }

    // ============ Keccak256 Tests (EVM native) ============

    function test_Keccak256() public view {
        bytes32 hash = precompileTest.computeKeccak256(bytes("hello"));
        assertEq(hash, keccak256("hello"));
    }

    function test_Keccak256Empty() public view {
        bytes32 hash = precompileTest.computeKeccak256(bytes(""));
        assertEq(hash, keccak256(""));
    }

    function test_Keccak256Deterministic() public view {
        bytes32 hash1 = precompileTest.computeKeccak256(bytes("test"));
        bytes32 hash2 = precompileTest.computeKeccak256(bytes("test"));
        assertEq(hash1, hash2);
    }

    // ============ SHA-256 Tests (Precompile 0x02) ============

    function test_Sha256() public view {
        bytes32 hash = precompileTest.computeSha256(bytes("hello"));
        // Known SHA-256 hash of "hello"
        assertEq(hash, 0x2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824);
    }

    function test_Sha256String() public view {
        bytes32 hash = precompileTest.computeSha256String("hello");
        assertEq(hash, 0x2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824);
    }

    function test_Sha256Empty() public view {
        bytes32 hash = precompileTest.computeSha256(bytes(""));
        // Known SHA-256 hash of empty string
        assertEq(hash, 0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855);
    }

    function test_Sha256DifferentFromKeccak() public view {
        bytes memory data = bytes("test");
        bytes32 sha = precompileTest.computeSha256(data);
        bytes32 keccak = precompileTest.computeKeccak256(data);
        assertTrue(sha != keccak);
    }

    function test_CompareHashes() public view {
        (bytes32 sha, bytes32 keccak) = precompileTest.compareHashes(bytes("compare"));
        assertTrue(sha != bytes32(0));
        assertTrue(keccak != bytes32(0));
        assertTrue(sha != keccak);
    }

    // ============ RIPEMD-160 Tests (Precompile 0x03) ============

    function test_Ripemd160() public view {
        bytes20 hash = precompileTest.computeRipemd160(bytes("hello"));
        // Known RIPEMD-160 hash of "hello"
        assertEq(hash, bytes20(0x108f07b8382412612c048d07d13f814118445acd));
    }

    function test_Ripemd160Empty() public view {
        bytes20 hash = precompileTest.computeRipemd160(bytes(""));
        // Known RIPEMD-160 hash of empty string
        assertEq(hash, bytes20(0x9c1185a5c5e9fc54612808977ee8f548b2258d31));
    }

    // ============ Identity Precompile Tests (Precompile 0x04) ============

    function test_IdentityPrecompile() public view {
        bytes memory input = bytes("test data");
        bytes memory output = precompileTest.identityCall(input);
        assertEq(keccak256(output), keccak256(input));
    }

    function test_IdentityEmpty() public view {
        bytes memory input = bytes("");
        bytes memory output = precompileTest.identityCall(input);
        assertEq(output.length, 0);
    }

    // ============ ModExp Tests (Precompile 0x05) ============

    function test_ModExpSimple() public view {
        // 2^3 mod 5 = 8 mod 5 = 3
        uint256 result = precompileTest.modExpSimple(2, 3, 5);
        assertEq(result, 3);
    }

    function test_ModExpLarger() public view {
        // 3^7 mod 11 = 2187 mod 11 = 9
        uint256 result = precompileTest.modExpSimple(3, 7, 11);
        assertEq(result, 9);
    }

    function test_ModExpOne() public view {
        // x^0 mod y = 1 (for y > 1)
        uint256 result = precompileTest.modExpSimple(5, 0, 7);
        assertEq(result, 1);
    }

    // ============ ECDSA Recovery Tests (Precompile 0x01) ============

    function test_RecoverSigner() public {
        // Create a message hash
        bytes32 messageHash = keccak256("test message");

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, messageHash);

        // Recover the signer
        address recovered = precompileTest.recoverSigner(messageHash, v, r, s);

        assertEq(recovered, SIGNER_ADDRESS);
    }

    function test_VerifySignature() public {
        bytes32 messageHash = keccak256("verify this");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, messageHash);

        bool valid = precompileTest.verifySignature(
            messageHash, v, r, s, SIGNER_ADDRESS
        );

        assertTrue(valid);
    }

    function test_VerifySignatureWrongSigner() public {
        bytes32 messageHash = keccak256("wrong signer test");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, messageHash);

        bool valid = precompileTest.verifySignature(
            messageHash, v, r, s, address(0x1234)
        );

        assertFalse(valid);
    }

    function test_VerifySignatureWrongMessage() public {
        bytes32 originalHash = keccak256("original message");
        bytes32 wrongHash = keccak256("wrong message");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, originalHash);

        address recovered = precompileTest.recoverSigner(wrongHash, v, r, s);

        assertTrue(recovered != SIGNER_ADDRESS);
    }

    function test_RecoverSignerInvalidSignature() public view {
        bytes32 messageHash = keccak256("test");

        // Invalid signature values
        address recovered = precompileTest.recoverSigner(
            messageHash,
            27,
            bytes32(0),
            bytes32(0)
        );

        // Should return address(0) for invalid signatures
        assertEq(recovered, address(0));
    }

    // ============ EIP-191 Signed Message Tests ============

    function test_ToEthSignedMessageHash() public view {
        bytes32 messageHash = keccak256("test");
        bytes32 ethSigned = precompileTest.toEthSignedMessageHash(messageHash);

        bytes32 expected = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        assertEq(ethSigned, expected);
    }

    function test_HashMessage() public view {
        bytes32 hash = precompileTest.hashMessage("hello");
        assertEq(hash, keccak256("hello"));
    }

    function test_VerifyMessageSignature() public {
        string memory message = "Sign this message";

        // Create the prefixed hash (what a wallet would sign)
        bytes32 messageHash = keccak256(abi.encodePacked(message));
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        // Sign the prefixed hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, ethSignedHash);

        bool valid = precompileTest.verifyMessageSignature(
            message, v, r, s, SIGNER_ADDRESS
        );

        assertTrue(valid);
    }

    // ============ Batch Verify Tests ============

    function test_BatchVerify() public {
        uint256 count = 3;
        bytes32[] memory hashes = new bytes32[](count);
        uint8[] memory vs = new uint8[](count);
        bytes32[] memory rs = new bytes32[](count);
        bytes32[] memory ss = new bytes32[](count);
        address[] memory signers = new address[](count);

        // Create multiple signatures
        for (uint256 i = 0; i < count; i++) {
            hashes[i] = keccak256(abi.encodePacked("message", i));
            (vs[i], rs[i], ss[i]) = vm.sign(SIGNER_PRIVATE_KEY, hashes[i]);
            signers[i] = SIGNER_ADDRESS;
        }

        bool[] memory results = precompileTest.batchVerify(hashes, vs, rs, ss, signers);

        for (uint256 i = 0; i < count; i++) {
            assertTrue(results[i]);
        }
    }

    function test_BatchVerifyWithInvalid() public {
        uint256 count = 3;
        bytes32[] memory hashes = new bytes32[](count);
        uint8[] memory vs = new uint8[](count);
        bytes32[] memory rs = new bytes32[](count);
        bytes32[] memory ss = new bytes32[](count);
        address[] memory signers = new address[](count);

        // Create signatures, but make one invalid
        for (uint256 i = 0; i < count; i++) {
            hashes[i] = keccak256(abi.encodePacked("message", i));
            (vs[i], rs[i], ss[i]) = vm.sign(SIGNER_PRIVATE_KEY, hashes[i]);
            signers[i] = SIGNER_ADDRESS;
        }

        // Make middle signature invalid by changing expected signer
        signers[1] = address(0x1234);

        bool[] memory results = precompileTest.batchVerify(hashes, vs, rs, ss, signers);

        assertTrue(results[0]);
        assertFalse(results[1]); // This one should fail
        assertTrue(results[2]);
    }

    // ============ Fuzz Tests ============

    function testFuzz_Sha256(bytes memory data) public view {
        bytes32 hash = precompileTest.computeSha256(data);
        assertTrue(hash != bytes32(0) || data.length == 0);
    }

    function testFuzz_Keccak256(bytes memory data) public view {
        bytes32 hash = precompileTest.computeKeccak256(data);
        assertEq(hash, keccak256(data));
    }

    function testFuzz_Identity(bytes memory data) public view {
        bytes memory output = precompileTest.identityCall(data);
        assertEq(keccak256(output), keccak256(data));
    }

    function testFuzz_SignAndRecover(bytes32 messageHash) public {
        vm.assume(messageHash != bytes32(0));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, messageHash);
        address recovered = precompileTest.recoverSigner(messageHash, v, r, s);

        assertEq(recovered, SIGNER_ADDRESS);
    }
}
