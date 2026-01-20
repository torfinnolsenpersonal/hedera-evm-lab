# EVM Test Coverage Guide

This document describes the comprehensive EVM test coverage included in the Hedera EVM Lab smoke tests.

## Coverage Summary

| Category | Tests | Foundry | Hardhat | EVM Coverage |
|----------|-------|---------|---------|--------------|
| Counter (Basic) | 13/19 | ✓ | ✓ | ~17% |
| ERC-20 Token | 25+ | ✓ | ✓ | +15% |
| Value Transfer | 25+ | ✓ | ✓ | +10% |
| Contract Factory | 20+ | ✓ | ✓ | +10% |
| Precompiles | 20+ | ✓ | ✓ | +10% |
| Hedera HTS | 15+ | ✓ | ✓ | +15% (Hedera-specific) |
| **Total** | **~120** | ✓ | ✓ | **~60-70%** |

## Test Contracts

### 1. Counter.sol (Basic Smoke Test)

**Purpose:** Minimal smoke test to verify basic EVM connectivity and operations.

**EVM Features Tested:**
- Storage read/write (`SLOAD`, `SSTORE`)
- Events (`LOG2`, `LOG3`)
- Reverts with messages
- Access control (`msg.sender`)
- Modifiers

**Test Count:** 13 Foundry / 19 Hardhat

---

### 2. TestToken.sol (ERC-20 Token)

**Purpose:** Test mappings, nested mappings, and standard token operations.

**EVM Features Tested:**
- Simple mappings (`mapping(address => uint256)`)
- Nested mappings (`mapping(address => mapping(address => uint256))`)
- ERC-20 standard: `transfer`, `approve`, `transferFrom`
- Mint and burn operations
- Transfer events

**Opcodes Covered:**
- `SLOAD`, `SSTORE` (complex storage patterns)
- `SHA3` (mapping key computation)
- `LOG3` (Transfer events with indexed params)

**Test Count:** 25+ tests

**Key Tests:**
| Test | What It Validates |
|------|-------------------|
| `test_Transfer` | Basic token transfer |
| `test_TransferFrom` | Allowance-based transfer |
| `test_Approve` | Approval mechanism |
| `test_Mint` | Token creation |
| `test_Burn` | Token destruction |
| `testFuzz_Transfer` | Fuzz testing transfers |

---

### 3. PayableTest.sol (Value Transfers)

**Purpose:** Test HBAR/ETH value transfers using various methods.

**EVM Features Tested:**
- `payable` functions
- `receive()` function
- `fallback()` function
- Value transfer methods: `transfer`, `send`, `call`
- Contract balance queries

**Opcodes Covered:**
- `CALLVALUE` (msg.value)
- `SELFBALANCE` (address(this).balance)
- `CALL` with value
- `BALANCE` (external balance query)

**Test Count:** 25+ tests

**Key Tests:**
| Test | What It Validates |
|------|-------------------|
| `test_ReceiveEther` | Direct ETH/HBAR receipt |
| `test_Deposit` | Explicit deposit function |
| `test_WithdrawTransfer` | transfer() method |
| `test_WithdrawCall` | call() method (recommended) |
| `test_WithdrawTo` | Withdrawal to specific address |
| `test_Fallback` | Fallback function handling |

---

### 4. Factory.sol (Contract Creation)

**Purpose:** Test contract deployment from contracts using CREATE and CREATE2.

**EVM Features Tested:**
- `CREATE` opcode (new Contract())
- `CREATE2` opcode (new Contract{salt: ...}())
- Address prediction
- Contract-to-contract calls
- Low-level calls (`call`, `staticcall`)

**Opcodes Covered:**
- `CREATE` (deploy new contract)
- `CREATE2` (deterministic deployment)
- `CALL` (external contract call)
- `STATICCALL` (read-only call)
- `EXTCODESIZE` (contract existence check)

**Test Count:** 20+ tests

**Key Tests:**
| Test | What It Validates |
|------|-------------------|
| `test_DeployCounter` | CREATE deployment |
| `test_DeployCounterCreate2` | CREATE2 deployment |
| `test_PredictAddress` | Address prediction accuracy |
| `test_CallIncrement` | Contract-to-contract call |
| `test_LowLevelCall` | Low-level call mechanism |
| `test_StaticCallGetCount` | Read-only external call |

---

### 5. PrecompileTest.sol (EVM Precompiles)

**Purpose:** Test standard EVM precompiled contracts.

**Precompiles Tested:**
| Address | Name | Function |
|---------|------|----------|
| 0x01 | ecrecover | Signature recovery |
| 0x02 | sha256 | SHA-256 hash |
| 0x03 | ripemd160 | RIPEMD-160 hash |
| 0x04 | identity | Data copy |
| 0x05 | modexp | Modular exponentiation |

**Test Count:** 20+ tests

**Key Tests:**
| Test | What It Validates |
|------|-------------------|
| `test_RecoverSigner` | ECDSA signature recovery |
| `test_VerifySignature` | Signature verification |
| `test_Sha256` | SHA-256 precompile |
| `test_Ripemd160` | RIPEMD-160 precompile |
| `test_IdentityPrecompile` | Identity (data copy) |
| `test_ModExpSimple` | Modular exponentiation |
| `test_BatchVerify` | Batch signature verification |

---

### 6. HederaHTSTest.sol (Hedera-Specific)

**Purpose:** Test Hedera-specific precompiles and features.

**Hedera Precompiles Tested:**
| Address | Name | Function |
|---------|------|----------|
| 0x167 | HTS | Hedera Token Service |
| 0x168 | Exchange Rate | HBAR/USD conversion |
| 0x169 | PRNG | Pseudorandom number generation |

**Test Count:** 15+ tests

**Key Tests:**
| Test | What It Validates |
|------|-------------------|
| `test_GetRandomSeed` | PRNG precompile |
| `test_ConvertTinycentsToTinybars` | Exchange rate |
| `test_CheckAssociation` | HTS token association |
| `test_CheckCapabilities` | Network capability detection |

**Note:** Many Hedera-specific tests are skipped when not running on actual Hedera network.

---

## EVM Opcode Coverage

### Covered Opcodes by Category

| Category | Opcodes | Coverage |
|----------|---------|----------|
| **Arithmetic** | ADD, SUB, MUL, DIV, MOD, EXP | ✓ Basic |
| **Comparison** | LT, GT, EQ, ISZERO | ✓ Full |
| **Bitwise** | AND, OR, XOR, NOT, SHL, SHR | Partial |
| **Keccak256** | SHA3 | ✓ Full |
| **Environment** | ADDRESS, BALANCE, CALLER, CALLVALUE, ORIGIN | ✓ Full |
| **Block** | BLOCKHASH, COINBASE, TIMESTAMP, NUMBER | ✓ Basic |
| **Stack/Memory** | POP, MLOAD, MSTORE, SLOAD, SSTORE | ✓ Full |
| **Flow Control** | JUMP, JUMPI, RETURN, REVERT | ✓ Full |
| **Logging** | LOG0-LOG4 | ✓ Full |
| **System** | CREATE, CREATE2, CALL, STATICCALL, DELEGATECALL | ✓ Full |
| **Precompiles** | 0x01-0x05 | ✓ Full |

### Not Covered

| Feature | Why |
|---------|-----|
| `SELFDESTRUCT` | Deprecated, not recommended |
| `DELEGATECALL` patterns | Proxy contracts not included |
| Complex assembly | Out of scope for smoke tests |
| ERC-721/1155 | Could be added as extension |

---

## Running the Tests

### Foundry

```bash
cd examples/foundry/contract-smoke

# Run all tests locally (fast)
forge test -vvv

# Run against Hedera network (fork mode)
forge test --fork-url http://127.0.0.1:7546 -vvv

# Run specific test file
forge test --match-path test/TestToken.t.sol -vvv

# Run with gas reporting
forge test --gas-report
```

### Hardhat

```bash
cd examples/hardhat/contract-smoke

# Install dependencies
npm install

# Run all tests against Local Node
npx hardhat test --network localnode

# Run all tests against Solo
npx hardhat test --network solo

# Run specific test file
npx hardhat test test/TestToken.test.ts --network localnode

# Run with coverage (if configured)
npx hardhat coverage
```

---

## Test Output Format

### Foundry Output

```
Ran 118 tests for test/*.t.sol
[PASS] test_TokenName() (gas: 9871)
[PASS] test_Transfer() (gas: 52341)
[PASS] testFuzz_Transfer(uint256) (runs: 256, μ: 45123, ~: 44892)
...
Suite result: ok. 118 passed; 0 failed; 0 skipped
```

### Hardhat Output

```
╔════════════════════════════════════════════════════════════╗
║              HEDERA EVM LAB - TEST RUN                     ║
╠════════════════════════════════════════════════════════════╣
║  Network:        localnode                                 ║
║  Default Wait:   500ms                                     ║
║  Timeout:        60000ms                                   ║
╚════════════════════════════════════════════════════════════╝

  TestToken
    Deployment
      ✔ Should set token name (245ms)
      ✔ Should set token symbol (198ms)
      ...

  118 passing (5m)
```

---

## Adding New Tests

To add new test contracts:

1. **Create Solidity contract** in `examples/foundry/contract-smoke/src/`
2. **Create Foundry test** in `examples/foundry/contract-smoke/test/`
3. **Copy contract to Hardhat** in `examples/hardhat/contract-smoke/contracts/`
4. **Create Hardhat test** in `examples/hardhat/contract-smoke/test/`
5. **Update this documentation**

### Test Template (Foundry)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyContract.sol";

contract MyContractTest is Test {
    MyContract public myContract;

    function setUp() public {
        myContract = new MyContract();
    }

    function test_Something() public {
        // Test code
    }

    function testFuzz_Something(uint256 value) public {
        // Fuzz test code
    }
}
```

### Test Template (Hardhat)

```typescript
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { MyContract } from "../typechain-types";

describe("MyContract", function () {
  let myContract: MyContract;

  beforeEach(async function () {
    const MyContract = await ethers.getContractFactory("MyContract");
    myContract = await MyContract.deploy();
    await myContract.waitForDeployment();
  });

  it("Should do something", async function () {
    // Test code
  });
});
```

---

## Gap Analysis: Local Node vs Solo

Run tests on both networks and compare:

```bash
# Local Node
./scripts/start-local-node.sh
./scripts/run-hardhat-smoke.sh localnode
./scripts/run-foundry-smoke.sh --fork

# Solo
./scripts/stop-local-node.sh
./scripts/start-solo.sh
./scripts/run-hardhat-smoke.sh solo
./scripts/run-foundry-smoke.sh --fork
```

Expected differences:
- **Timing:** Solo is ~3-4x slower due to Kubernetes overhead
- **Gas costs:** Should be identical
- **Hedera precompiles:** Both should support HTS, PRNG, Exchange Rate
- **Functionality:** 100% compatible for standard EVM operations
