import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

// Default test accounts from Hiero Local Node (Alias ECDSA)
// Pre-funded with 10,000 HBAR each
// Evidence: repos/hiero-local-node/README.md:194-204
const LOCAL_NODE_ACCOUNTS = [
  "0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524",
  "0x2e1d968b041d84dd120a5860cee60cd83f9374ef527ca86996317ada3d0d03e7",
  "0x45a5a7108a18dd5013cf2d5857a28144beadc9c70b3bdbd914e38df4e804b8d8",
  "0x6e9d61a325be3f6675cf8b7676c70e4a004d2308e3e182370a41f5653d52c6bd",
  "0x0b58b1bd44469ac9f813b5aeaf6213ddaea26720f0b2f133d08b6f234130a64f",
];

// Solo accounts (create with: solo ledger account create)
const SOLO_ACCOUNTS = process.env.SOLO_PRIVATE_KEYS?.split(",") || LOCAL_NODE_ACCOUNTS;

// Anvil default deterministic accounts (same as Hardhat Network defaults)
// Each account is funded with 10,000 ETH
const ANVIL_ACCOUNTS = [
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
  "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a",
];

// Hedera Testnet account (requires HEDERA_TESTNET_PRIVATE_KEY env var)
const HEDERA_TESTNET_ACCOUNTS = process.env.HEDERA_TESTNET_PRIVATE_KEY
  ? [process.env.HEDERA_TESTNET_PRIVATE_KEY]
  : [];

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "localnode",
  networks: {
    // Hiero Local Node
    // Evidence: repos/hiero-local-node/README.md:576
    localnode: {
      url: process.env.LOCAL_NODE_RPC_URL || "http://127.0.0.1:7546",
      accounts: LOCAL_NODE_ACCOUNTS,
      chainId: 298, // 0x12a
      timeout: 60000,
    },
    // Solo Network
    // Evidence: repos/solo/docs/site/content/en/docs/env.md:21
    solo: {
      url: process.env.SOLO_RPC_URL || "http://127.0.0.1:7546",
      accounts: SOLO_ACCOUNTS,
      chainId: 298,
      timeout: 120000,
    },
    // Hardhat's built-in network for fast unit tests
    hardhat: {
      chainId: 31337,
    },
    // Anvil (Foundry's local Ethereum node) for baseline benchmarking
    anvil: {
      url: "http://127.0.0.1:8545",
      accounts: ANVIL_ACCOUNTS,
      chainId: 31337,
      timeout: 30000,
    },
    // Hedera Testnet (remote)
    hedera_testnet: {
      url: process.env.HEDERA_TESTNET_RPC_URL || "https://testnet.hashio.io/api",
      accounts: HEDERA_TESTNET_ACCOUNTS,
      chainId: 296, // 0x128
      timeout: 180000,
    },
  },
};

export default config;
