// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/HederaHTSTest.sol";

/**
 * @title HederaHTSTestTest
 * @dev Hedera-specific precompile tests - validates HTS, PRNG, Exchange Rate
 * Note: Many tests will be skipped when not running on Hedera network
 * EVM Coverage: Hedera precompiles 0x167, 0x168, 0x169
 */
contract HederaHTSTestTest is Test {
    HederaHTSTest public htsTest;
    HederaCapabilityChecker public checker;

    bool isHedera;

    function setUp() public {
        htsTest = new HederaHTSTest();
        checker = new HederaCapabilityChecker();

        // Check if we're on Hedera
        isHedera = checker.isHederaChainId();
    }

    // ============ Capability Checker Tests ============

    function test_GetChainId() public view {
        uint256 chainId = checker.getChainId();
        assertTrue(chainId > 0);
        console.log("Chain ID:", chainId);
    }

    function test_IsHederaChainId() public view {
        bool result = checker.isHederaChainId();
        console.log("Is Hedera Chain ID:", result);

        // If chain ID is 298 (local), it should be true
        if (block.chainid == 298) {
            assertTrue(result);
        }
    }

    function test_CheckCapabilities() public view {
        HederaCapabilityChecker.NetworkCapabilities memory caps = checker.checkCapabilities();

        console.log("Chain ID:", caps.chainId);
        console.log("Is Hedera:", caps.isHedera);
        console.log("Has HTS:", caps.hasHTS);
        console.log("Has PRNG:", caps.hasPRNG);
        console.log("Has Exchange Rate:", caps.hasExchangeRate);
    }

    // ============ Network Detection Tests ============

    function test_IsHederaNetwork() public view {
        bool result = htsTest.isHederaNetwork();
        console.log("isHederaNetwork():", result);

        // This may return false in fork mode without actual Hedera backend
    }

    // ============ PRNG Tests (Hedera-only) ============

    function test_GetRandomSeed() public {
        if (!isHedera) {
            console.log("Skipping PRNG test - not on Hedera network");
            return;
        }

        bytes32 seed = htsTest.getRandomSeed();
        assertTrue(seed != bytes32(0));
        console.log("Random seed generated");
    }

    function test_GetRandomInRange() public {
        if (!isHedera) {
            console.log("Skipping PRNG range test - not on Hedera network");
            return;
        }

        uint256 random = htsTest.getRandomInRange(1, 100);
        assertTrue(random >= 1 && random <= 100);
        console.log("Random in range [1,100]:", random);
    }

    function test_MultipleRandomSeeds() public {
        if (!isHedera) {
            console.log("Skipping multiple PRNG test - not on Hedera network");
            return;
        }

        bytes32 seed1 = htsTest.getRandomSeed();
        bytes32 seed2 = htsTest.getRandomSeed();

        // Seeds should be different (with high probability)
        // Note: In test environments, they might be the same due to deterministic block
        console.log("Seed 1 generated");
        console.log("Seed 2 generated");
    }

    // ============ Exchange Rate Tests (Hedera-only) ============

    function test_ConvertTinycentsToTinybars() public {
        if (!isHedera) {
            console.log("Skipping exchange rate test - not on Hedera network");
            return;
        }

        uint256 tinycents = 1000000; // 1 cent
        uint256 tinybars = htsTest.convertTinycentsToTinybars(tinycents);
        assertTrue(tinybars > 0);
        console.log("Tinycents:", tinycents, "-> Tinybars:", tinybars);
    }

    function test_ConvertTinybarsToTinycents() public {
        if (!isHedera) {
            console.log("Skipping exchange rate test - not on Hedera network");
            return;
        }

        uint256 tinybars = 100000000; // 1 HBAR
        uint256 tinycents = htsTest.convertTinybarsToTinycents(tinybars);
        assertTrue(tinycents > 0);
        console.log("Tinybars:", tinybars, "-> Tinycents:", tinycents);
    }

    // ============ HTS Basic Tests (Hedera-only) ============

    function test_CheckAssociationNonExistent() public view {
        if (!isHedera) {
            console.log("Skipping HTS association check - not on Hedera network");
            return;
        }

        // Check association with a non-existent token
        bool isAssociated = htsTest.checkAssociation(address(this), address(0x1234));
        assertFalse(isAssociated);
    }

    // ============ Low-Level Call Tests ============

    function test_CallHTSPrecompile() public {
        if (!isHedera) {
            console.log("Skipping HTS precompile call - not on Hedera network");
            return;
        }

        bytes memory data = abi.encodeWithSignature(
            "isAssociated(address,address)",
            address(this),
            address(0x1234)
        );

        (bool success, ) = htsTest.callHTS(data);
        console.log("HTS call success:", success);
    }

    function test_CallExchangeRatePrecompile() public {
        if (!isHedera) {
            console.log("Skipping exchange rate precompile call - not on Hedera network");
            return;
        }

        bytes memory data = abi.encodeWithSignature("tinycentsToTinybars(uint256)", 100);
        (bool success, bytes memory result) = htsTest.callExchangeRate(data);

        console.log("Exchange rate call success:", success);
        if (success && result.length > 0) {
            uint256 tinybars = abi.decode(result, (uint256));
            console.log("Result (tinybars):", tinybars);
        }
    }

    function test_CallPRNGPrecompile() public {
        if (!isHedera) {
            console.log("Skipping PRNG precompile call - not on Hedera network");
            return;
        }

        bytes memory data = abi.encodeWithSignature("getPseudorandomSeed()");
        (bool success, bytes memory result) = htsTest.callPRNG(data);

        console.log("PRNG call success:", success);
        if (success && result.length >= 32) {
            bytes32 seed = abi.decode(result, (bytes32));
            console.log("Random seed obtained");
        }
    }

    // ============ Integration Tests ============

    function test_FullCapabilityReport() public view {
        console.log("");
        console.log("=== Hedera Capability Report ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("Block Timestamp:", block.timestamp);

        HederaCapabilityChecker.NetworkCapabilities memory caps = checker.checkCapabilities();

        console.log("");
        console.log("Network Detection:");
        console.log("  Is Hedera (chain ID):", caps.isHedera);
        console.log("  HTS Available:", caps.hasHTS);
        console.log("  PRNG Available:", caps.hasPRNG);
        console.log("  Exchange Rate Available:", caps.hasExchangeRate);
        console.log("");
    }

    // ============ Fork Mode Compatibility Tests ============
    // These tests work in both Hedera fork mode and regular EVM

    function test_ContractDeployment() public view {
        // Verify our test contracts deployed successfully
        assertTrue(address(htsTest) != address(0));
        assertTrue(address(checker) != address(0));
    }

    function test_BlockProperties() public view {
        // These should work on any EVM
        assertTrue(block.chainid > 0);
        assertTrue(block.number >= 0);
        assertTrue(block.timestamp > 0);
    }

    function test_AddressCodeSize() public view {
        // Check that deployed contract has code
        uint256 codeSize;
        address target = address(htsTest);
        assembly {
            codeSize := extcodesize(target)
        }
        assertTrue(codeSize > 0);
    }
}

/**
 * @title HederaIntegrationTest
 * @dev Full integration tests that only run on actual Hedera network
 * These tests require actual Hedera infrastructure
 */
contract HederaIntegrationTest is Test {
    HederaHTSTest public htsTest;
    HederaCapabilityChecker public checker;

    modifier onlyHedera() {
        if (block.chainid != 295 && block.chainid != 296 &&
            block.chainid != 297 && block.chainid != 298) {
            console.log("Skipping - not on Hedera network (chain ID:", block.chainid, ")");
            return;
        }
        _;
    }

    function setUp() public {
        htsTest = new HederaHTSTest();
        checker = new HederaCapabilityChecker();
    }

    function test_HederaFullIntegration() public onlyHedera {
        console.log("Running full Hedera integration test...");

        // Test PRNG
        bytes32 seed = htsTest.getRandomSeed();
        assertTrue(seed != bytes32(0), "PRNG should return non-zero seed");
        console.log("PRNG: OK");

        // Test Exchange Rate
        uint256 tinybars = htsTest.convertTinycentsToTinybars(1000000);
        assertTrue(tinybars > 0, "Exchange rate should return positive value");
        console.log("Exchange Rate: OK");

        console.log("Full integration test passed!");
    }
}
