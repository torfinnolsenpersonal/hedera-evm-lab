# Foundry Integration Guide

This guide covers integrating Foundry (forge, cast, anvil) with Hiero Local Node and Solo for Hedera EVM development.

## Overview

Foundry connects to Hedera via the JSON-RPC Relay. While Foundry's built-in `anvil` is not used (we use Hedera's relay instead), `forge` for testing/deployment and `cast` for interactions work well.

## Prerequisites

- Foundry installed (see below)
- Running Hedera network (Local Node or Solo)
- See `01-setup-and-prereqs.md` for Hedera setup

## Installing Foundry

```bash
# macOS/Linux
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify installation
forge --version
cast --version
```

For Windows, use WSL2 and follow Linux instructions.

## Approach A: Foundry with Local Node (Recommended)

### Configuration (foundry.toml)

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.24"
optimizer = true
optimizer_runs = 200

# Hedera Local Node
[rpc_endpoints]
localnode = "http://127.0.0.1:7546"

# Chain ID for Hedera
[profile.default.fuzz]
runs = 256

# EVM version compatible with Hedera
evm_version = "cancun"
```

### Environment Variables (.env)

```bash
# Local Node RPC
RPC_URL=http://127.0.0.1:7546

# Default test account (Alias ECDSA from Local Node)
PRIVATE_KEY=0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524
DEPLOYER_ADDRESS=0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69

# Additional test accounts
PRIVATE_KEY_2=0x2e1d968b041d84dd120a5860cee60cd83f9374ef527ca86996317ada3d0d03e7
ADDRESS_2=0x05FbA803Be258049A27B820088bab1cAD2058871

# Chain ID
CHAIN_ID=298
```

### Pre-funded Accounts

Local Node provides these ECDSA accounts (compatible with Foundry):

| Address | Private Key | Balance |
|---------|-------------|---------|
| 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69 | 0x105d050185ccb907fba04dd92d8de9e32c18305e097ab41dadda21489a211524 | 10,000 HBAR |
| 0x05FbA803Be258049A27B820088bab1cAD2058871 | 0x2e1d968b041d84dd120a5860cee60cd83f9374ef527ca86996317ada3d0d03e7 | 10,000 HBAR |
| 0x927E41Ff8307835A1C081e0d7fD250625F2D4D0E | 0x45a5a7108a18dd5013cf2d5857a28144beadc9c70b3bdbd914e38df4e804b8d8 | 10,000 HBAR |

Evidence: `repos/hiero-local-node/README.md:194-204`

## Approach B: Foundry with Solo

### Configuration

Same `foundry.toml`, but accounts need to be created:

```bash
# Create account in Solo
solo ledger account create --deployment solo-deployment --hbar-amount 1000 --generate-ecdsa-key

# Save the private key from output to .env
```

### Environment for Solo

```bash
# Solo RPC (same port)
RPC_URL=http://127.0.0.1:7546

# Created account private key (from solo ledger account create output)
PRIVATE_KEY=<your-created-key>

CHAIN_ID=298
```

## Using Forge (Testing)

### Sample Contract (src/Counter.sol)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Counter {
    uint256 public count;

    event CountChanged(uint256 newCount);

    function increment() public {
        count += 1;
        emit CountChanged(count);
    }

    function decrement() public {
        require(count > 0, "Counter: cannot decrement below zero");
        count -= 1;
        emit CountChanged(count);
    }

    function reset() public {
        count = 0;
        emit CountChanged(count);
    }
}
```

### Test File (test/Counter.t.sol)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Counter.sol";

contract CounterTest is Test {
    Counter public counter;

    event CountChanged(uint256 newCount);

    function setUp() public {
        counter = new Counter();
    }

    function test_InitialCount() public view {
        assertEq(counter.count(), 0);
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.count(), 1);
    }

    function test_Decrement() public {
        counter.increment();
        counter.decrement();
        assertEq(counter.count(), 0);
    }

    function test_RevertOnDecrementBelowZero() public {
        vm.expectRevert("Counter: cannot decrement below zero");
        counter.decrement();
    }

    function test_EmitEventOnIncrement() public {
        vm.expectEmit(true, true, true, true);
        emit CountChanged(1);
        counter.increment();
    }

    function test_Reset() public {
        counter.increment();
        counter.increment();
        counter.reset();
        assertEq(counter.count(), 0);
    }

    function testFuzz_Increment(uint8 times) public {
        for (uint8 i = 0; i < times; i++) {
            counter.increment();
        }
        assertEq(counter.count(), times);
    }
}
```

### Running Tests

```bash
# Run tests locally (using Foundry's EVM, not Hedera)
forge test -vvv

# Run tests against Local Node (fork mode)
forge test --fork-url http://127.0.0.1:7546 -vvv
```

**Note:** Most unit tests should run locally with `forge test`. Use `--fork-url` when you need to test against actual Hedera state or behavior.

## Using Cast (Interactions)

### Check Balance

```bash
# Load environment
source .env

# Check balance (returns in wei/tinybar)
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL

# Convert to HBAR (18 decimals)
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL | cast from-wei
```

### Deploy Contract

```bash
# Deploy Counter
forge create src/Counter.sol:Counter \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --legacy

# Note: --legacy may be needed for some Hedera-specific behavior
```

Expected output:
```
[⠃] Compiling...
No files changed, compilation skipped
Deployer: 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69
Deployed to: 0x0000000000000000000000000000000000001234
Transaction hash: 0x...
```

### Interact with Contract

```bash
# Save contract address
export CONTRACT=0x0000000000000000000000000000000000001234

# Read count (call)
cast call $CONTRACT "count()(uint256)" --rpc-url $RPC_URL

# Increment (send transaction)
cast send $CONTRACT "increment()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Read count again
cast call $CONTRACT "count()(uint256)" --rpc-url $RPC_URL
```

### Query Events

```bash
# Get events from contract
cast logs --from-block 0 --to-block latest \
  --address $CONTRACT \
  --rpc-url $RPC_URL
```

## Deployment Script (script/Deploy.s.sol)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Counter.sol";

contract DeployCounter is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        Counter counter = new Counter();
        console.log("Counter deployed to:", address(counter));

        vm.stopBroadcast();
    }
}
```

Run deployment:
```bash
forge script script/Deploy.s.sol:DeployCounter \
  --rpc-url $RPC_URL \
  --broadcast \
  -vvv
```

## Hedera-Specific Considerations

### 1. No Anvil

Don't use `anvil` for Hedera testing - use the actual JSON-RPC relay:
```bash
# Wrong
anvil &
forge test --fork-url http://localhost:8545

# Correct
hedera start  # or solo one-shot single deploy
forge test --fork-url http://127.0.0.1:7546
```

### 2. Gas Handling

Hedera handles gas differently. For most operations, defaults work:
```bash
# Usually works without gas specification
cast send $CONTRACT "increment()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# If needed, specify gas limit
cast send $CONTRACT "increment()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000
```

### 3. Transaction Confirmation

Hedera has ~3-5 second finality. Cast will wait automatically:
```bash
cast send $CONTRACT "increment()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
# Returns after transaction is confirmed
```

### 4. Chain ID Verification

```bash
# Verify chain ID
cast chain-id --rpc-url $RPC_URL
# Expected: 298
```

### 5. Block Number Behavior

Hedera doesn't have traditional blocks:
```bash
cast block-number --rpc-url $RPC_URL
# Returns synthetic block number from relay
```

## Verification Commands

### Test Connection

```bash
# Should return 0x12a (298)
cast chain-id --rpc-url http://127.0.0.1:7546

# Should return balance in wei/tinybar
cast balance 0x67D8d32E9Bf1a9968a5ff53B87d777Aa8EBBEe69 --rpc-url http://127.0.0.1:7546
```

### Expected Test Output

```bash
$ forge test -vvv

[⠢] Compiling...
[⠃] Compiling 2 files with Solc 0.8.24
[⠊] Solc 0.8.24 finished in 1.23s
Compiler run successful!

Ran 7 tests for test/Counter.t.sol:CounterTest
[PASS] test_Decrement() (gas: 31234)
[PASS] test_EmitEventOnIncrement() (gas: 32456)
[PASS] test_Increment() (gas: 28123)
[PASS] test_InitialCount() (gas: 5432)
[PASS] test_Reset() (gas: 34567)
[PASS] test_RevertOnDecrementBelowZero() (gas: 8901)
[PASS] testFuzz_Increment(uint8) (runs: 256, μ: 1234567, ~: 1234567)

Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 1.23s
```

## Troubleshooting

### "Connection Refused"
```bash
# Check if relay is running
curl -s http://127.0.0.1:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
# Expected: {"jsonrpc":"2.0","id":1,"result":"0x12a"}
```

### "Insufficient Funds"
```bash
# Check balance
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL

# For Local Node, use pre-funded accounts
# For Solo, create account with funds:
solo ledger account create --deployment solo-deployment --hbar-amount 1000
```

### "Invalid Signature" or Key Errors
```bash
# Verify private key format (must start with 0x)
echo $PRIVATE_KEY | head -c 4
# Should output: 0x

# Verify address matches
cast wallet address --private-key $PRIVATE_KEY
```

### Slow Transactions
Hedera has ~3-5 second finality. This is normal. Add `--timeout` if needed:
```bash
cast send $CONTRACT "increment()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --timeout 60
```

## Sample Project Structure

```
foundry-hedera-project/
├── foundry.toml
├── .env
├── src/
│   └── Counter.sol
├── test/
│   └── Counter.t.sol
├── script/
│   └── Deploy.s.sol
└── lib/
    └── forge-std/
```

Initialize with:
```bash
forge init foundry-hedera-project
cd foundry-hedera-project
forge install foundry-rs/forge-std
```

## Evidence Files Referenced

- `repos/foundry/README.md` - Foundry overview
- `repos/hiero-local-node/README.md:194-204` - Pre-funded accounts
- `repos/hiero-local-node/.env:64` - RPC URL configuration
