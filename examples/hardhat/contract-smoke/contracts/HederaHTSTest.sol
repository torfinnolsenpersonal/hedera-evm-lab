// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IHederaTokenService
 * @dev Minimal interface for Hedera Token Service precompile (0x167)
 * Full interface: https://github.com/hashgraph/hedera-smart-contracts
 */
interface IHederaTokenService {
    /// Response codes from Hedera
    /// SUCCESS = 22

    /// @dev Token info struct (simplified)
    struct TokenInfo {
        bool deleted;
        bool defaultKycStatus;
        bool pauseStatus;
        int64 maxSupply;
        int64 totalSupply;
        string name;
        string symbol;
        string memo;
        uint8 decimals;
    }

    /// @dev Get token info
    function getTokenInfo(address token) external returns (int64 responseCode, TokenInfo memory tokenInfo);

    /// @dev Get fungible token info
    function getFungibleTokenInfo(address token) external returns (int64 responseCode, TokenInfo memory tokenInfo);

    /// @dev Check if account is associated with token
    function isAssociated(address account, address token) external view returns (bool);

    /// @dev Associate tokens with calling account
    function associateToken(address account, address token) external returns (int64 responseCode);

    /// @dev Dissociate tokens from calling account
    function dissociateToken(address account, address token) external returns (int64 responseCode);

    /// @dev Transfer tokens
    function transferToken(address token, address from, address to, int64 amount) external returns (int64 responseCode);

    /// @dev Transfer NFT
    function transferNFT(address token, address from, address to, int64 serialNumber) external returns (int64 responseCode);

    /// @dev Mint fungible tokens
    function mintToken(address token, int64 amount, bytes[] memory metadata) external returns (int64 responseCode, int64 newTotalSupply, int64[] memory serialNumbers);

    /// @dev Burn fungible tokens
    function burnToken(address token, int64 amount, int64[] memory serialNumbers) external returns (int64 responseCode, int64 newTotalSupply);
}

/**
 * @title IPrngSystemContract
 * @dev Interface for Hedera PRNG precompile (0x169)
 */
interface IPrngSystemContract {
    /// @dev Generate a 256-bit pseudorandom seed
    function getPseudorandomSeed() external returns (bytes32);
}

/**
 * @title IExchangeRate
 * @dev Interface for Hedera Exchange Rate precompile (0x168)
 */
interface IExchangeRate {
    /// @dev Get the current exchange rate
    function tinycentsToTinybars(uint256 tinycents) external returns (uint256);
    function tinybarsToTinycents(uint256 tinybars) external returns (uint256);
}

/**
 * @title HederaHTSTest
 * @dev Contract for testing Hedera-specific precompiles
 * Note: These tests require a running Hedera network (Local Node or Solo)
 * and will not work on standard EVM networks
 */
contract HederaHTSTest {
    // Hedera precompile addresses
    address constant HTS_PRECOMPILE = address(0x167);
    address constant EXCHANGE_RATE_PRECOMPILE = address(0x168);
    address constant PRNG_PRECOMPILE = address(0x169);

    event RandomGenerated(bytes32 seed);
    event ExchangeRateQueried(uint256 tinycents, uint256 tinybars);
    event TokenAssociated(address indexed account, address indexed token, int64 responseCode);

    error HederaPrecompileFailed(int64 responseCode);
    error PrecompileCallFailed();

    /// @dev Check if running on Hedera by testing precompile availability
    function isHederaNetwork() public view returns (bool) {
        // Try to call the exchange rate precompile
        // This will fail on non-Hedera networks
        (bool success, ) = EXCHANGE_RATE_PRECOMPILE.staticcall(
            abi.encodeWithSignature("tinycentsToTinybars(uint256)", 100)
        );
        return success;
    }

    /// @dev Get pseudorandom number from Hedera PRNG (0x169)
    function getRandomSeed() public returns (bytes32) {
        (bool success, bytes memory result) = PRNG_PRECOMPILE.call(
            abi.encodeWithSignature("getPseudorandomSeed()")
        );
        if (!success) revert PrecompileCallFailed();

        bytes32 seed = abi.decode(result, (bytes32));
        emit RandomGenerated(seed);
        return seed;
    }

    /// @dev Get random number in range using PRNG
    function getRandomInRange(uint256 min, uint256 max) public returns (uint256) {
        require(max > min, "Invalid range");
        bytes32 seed = getRandomSeed();
        return min + (uint256(seed) % (max - min + 1));
    }

    /// @dev Convert tinycents to tinybars using exchange rate (0x168)
    function convertTinycentsToTinybars(uint256 tinycents) public returns (uint256) {
        (bool success, bytes memory result) = EXCHANGE_RATE_PRECOMPILE.call(
            abi.encodeWithSignature("tinycentsToTinybars(uint256)", tinycents)
        );
        if (!success) revert PrecompileCallFailed();

        uint256 tinybars = abi.decode(result, (uint256));
        emit ExchangeRateQueried(tinycents, tinybars);
        return tinybars;
    }

    /// @dev Convert tinybars to tinycents using exchange rate (0x168)
    function convertTinybarsToTinycents(uint256 tinybars) public returns (uint256) {
        (bool success, bytes memory result) = EXCHANGE_RATE_PRECOMPILE.call(
            abi.encodeWithSignature("tinybarsToTinycents(uint256)", tinybars)
        );
        if (!success) revert PrecompileCallFailed();

        return abi.decode(result, (uint256));
    }

    /// @dev Associate a token with an account (0x167)
    function associateToken(address account, address token) public returns (int64) {
        (bool success, bytes memory result) = HTS_PRECOMPILE.call(
            abi.encodeWithSignature("associateToken(address,address)", account, token)
        );
        if (!success) revert PrecompileCallFailed();

        int64 responseCode = abi.decode(result, (int64));
        emit TokenAssociated(account, token, responseCode);
        return responseCode;
    }

    /// @dev Check if account is associated with token
    function checkAssociation(address account, address token) public view returns (bool) {
        (bool success, bytes memory result) = HTS_PRECOMPILE.staticcall(
            abi.encodeWithSignature("isAssociated(address,address)", account, token)
        );
        if (!success) return false;
        return abi.decode(result, (bool));
    }

    /// @dev Direct low-level call to HTS precompile
    function callHTS(bytes memory data) public returns (bool, bytes memory) {
        return HTS_PRECOMPILE.call(data);
    }

    /// @dev Direct low-level call to Exchange Rate precompile
    function callExchangeRate(bytes memory data) public returns (bool, bytes memory) {
        return EXCHANGE_RATE_PRECOMPILE.call(data);
    }

    /// @dev Direct low-level call to PRNG precompile
    function callPRNG(bytes memory data) public returns (bool, bytes memory) {
        return PRNG_PRECOMPILE.call(data);
    }
}

/**
 * @title HederaCapabilityChecker
 * @dev Utility contract to check Hedera-specific capabilities
 */
contract HederaCapabilityChecker {
    struct NetworkCapabilities {
        bool isHedera;
        bool hasHTS;
        bool hasPRNG;
        bool hasExchangeRate;
        uint256 chainId;
    }

    /// @dev Check all Hedera capabilities
    function checkCapabilities() public view returns (NetworkCapabilities memory) {
        NetworkCapabilities memory caps;
        caps.chainId = block.chainid;
        caps.isHedera = (block.chainid == 295 || block.chainid == 296 || block.chainid == 297 || block.chainid == 298);

        // Check HTS
        (bool htsSuccess, ) = address(0x167).staticcall(
            abi.encodeWithSignature("isAssociated(address,address)", address(this), address(0))
        );
        caps.hasHTS = htsSuccess;

        // Check PRNG (note: may need to be a call, not staticcall)
        caps.hasPRNG = caps.isHedera; // PRNG available on all Hedera networks

        // Check Exchange Rate
        (bool erSuccess, ) = address(0x168).staticcall(
            abi.encodeWithSignature("tinycentsToTinybars(uint256)", 100)
        );
        caps.hasExchangeRate = erSuccess;

        return caps;
    }

    /// @dev Get chain ID
    function getChainId() public view returns (uint256) {
        return block.chainid;
    }

    /// @dev Check if this is a Hedera network based on chain ID
    function isHederaChainId() public view returns (bool) {
        // Hedera chain IDs: mainnet=295, testnet=296, previewnet=297, localnet=298
        return block.chainid == 295 || block.chainid == 296 ||
               block.chainid == 297 || block.chainid == 298;
    }
}
