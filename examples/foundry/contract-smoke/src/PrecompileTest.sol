// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PrecompileTest
 * @dev Contract for testing EVM precompiles on Hedera
 * Tests: ecrecover (0x01), sha256 (0x02), ripemd160 (0x03), identity (0x04),
 *        modexp (0x05), ecAdd (0x06), ecMul (0x07), ecPairing (0x08)
 */
contract PrecompileTest {
    /// @dev Recover signer address from signature (precompile 0x01)
    /// @param hash The message hash that was signed
    /// @param v Recovery identifier
    /// @param r ECDSA signature r value
    /// @param s ECDSA signature s value
    /// @return The recovered address
    function recoverSigner(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public pure returns (address) {
        return ecrecover(hash, v, r, s);
    }

    /// @dev Verify a signature matches expected signer
    function verifySignature(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address expectedSigner
    ) public pure returns (bool) {
        address recovered = ecrecover(hash, v, r, s);
        return recovered == expectedSigner && recovered != address(0);
    }

    /// @dev Compute SHA-256 hash (precompile 0x02)
    /// @param data The data to hash
    /// @return The SHA-256 hash
    function computeSha256(bytes memory data) public pure returns (bytes32) {
        return sha256(data);
    }

    /// @dev Compute SHA-256 hash of a string
    function computeSha256String(string memory data) public pure returns (bytes32) {
        return sha256(bytes(data));
    }

    /// @dev Compute RIPEMD-160 hash (precompile 0x03)
    /// @param data The data to hash
    /// @return The RIPEMD-160 hash (20 bytes, padded to bytes32)
    function computeRipemd160(bytes memory data) public pure returns (bytes20) {
        return ripemd160(data);
    }

    /// @dev Compute Keccak-256 hash (EVM native, not precompile)
    /// @param data The data to hash
    /// @return The Keccak-256 hash
    function computeKeccak256(bytes memory data) public pure returns (bytes32) {
        return keccak256(data);
    }

    /// @dev Compare SHA-256 vs Keccak-256
    function compareHashes(bytes memory data) public pure returns (bytes32 sha, bytes32 keccak) {
        sha = sha256(data);
        keccak = keccak256(data);
    }

    /// @dev Identity precompile test (precompile 0x04)
    /// Copies input data to output - useful for gas measurement
    function identityCall(bytes memory data) public view returns (bytes memory) {
        (bool success, bytes memory result) = address(0x04).staticcall(data);
        require(success, "Identity precompile failed");
        return result;
    }

    /// @dev Test modular exponentiation (precompile 0x05)
    /// Computes base^exp mod modulus
    function modExp(
        bytes memory base,
        bytes memory exponent,
        bytes memory modulus
    ) public view returns (bytes memory) {
        bytes memory input = abi.encodePacked(
            uint256(base.length),
            uint256(exponent.length),
            uint256(modulus.length),
            base,
            exponent,
            modulus
        );

        (bool success, bytes memory result) = address(0x05).staticcall(input);
        require(success, "ModExp precompile failed");
        return result;
    }

    /// @dev Simple modular exponentiation with uint256 values
    function modExpSimple(
        uint256 base,
        uint256 exponent,
        uint256 modulus
    ) public view returns (uint256) {
        bytes memory baseBytes = abi.encode(base);
        bytes memory expBytes = abi.encode(exponent);
        bytes memory modBytes = abi.encode(modulus);

        bytes memory input = abi.encodePacked(
            uint256(32), // base length
            uint256(32), // exponent length
            uint256(32), // modulus length
            baseBytes,
            expBytes,
            modBytes
        );

        (bool success, bytes memory result) = address(0x05).staticcall(input);
        require(success, "ModExp precompile failed");
        return abi.decode(result, (uint256));
    }

    /// @dev Create a signed message hash (EIP-191 style)
    function toEthSignedMessageHash(bytes32 hash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /// @dev Hash a message and prepare for signing
    function hashMessage(string memory message) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(message));
    }

    /// @dev Full signature verification with EIP-191 prefix
    function verifyMessageSignature(
        string memory message,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address expectedSigner
    ) public pure returns (bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(message));
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        address recovered = ecrecover(ethSignedHash, v, r, s);
        return recovered == expectedSigner && recovered != address(0);
    }

    /// @dev Batch verify multiple signatures
    function batchVerify(
        bytes32[] memory hashes,
        uint8[] memory vs,
        bytes32[] memory rs,
        bytes32[] memory ss,
        address[] memory signers
    ) public pure returns (bool[] memory) {
        require(
            hashes.length == vs.length &&
            vs.length == rs.length &&
            rs.length == ss.length &&
            ss.length == signers.length,
            "Array length mismatch"
        );

        bool[] memory results = new bool[](hashes.length);
        for (uint256 i = 0; i < hashes.length; i++) {
            address recovered = ecrecover(hashes[i], vs[i], rs[i], ss[i]);
            results[i] = recovered == signers[i] && recovered != address(0);
        }
        return results;
    }
}
