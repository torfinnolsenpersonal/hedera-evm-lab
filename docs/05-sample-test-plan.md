# Sample Test Plan for Hedera EVM Development

## Objective

Validate that smart contracts can be deployed, executed, and tested on Hedera local networks (Local Node and Solo) using industry-standard EVM tooling (Hardhat and Foundry).

## Scope

- Contract deployment
- State-changing transactions
- State reading
- Event emission and validation
- Revert handling (negative cases)
- Cross-tool compatibility

## Prerequisites

1. Hedera network running (Local Node OR Solo - not both)
2. Node.js >= 20.0.0 (22+ for Solo)
3. Foundry installed
4. Dependencies installed in example projects

## Important: Shared Proxy Conflict

**Both Local Node and Solo use port 7546 for the JSON-RPC relay.**

This means:
- You cannot run both simultaneously
- Stop one network before starting the other
- If tests fail with connection errors, check for port conflicts

To manage this:
```bash
# Check what's using port 7546
lsof -i :7546

# Stop Local Node
./scripts/stop-local-node.sh

# Stop Solo
./scripts/stop-solo.sh
```

## Test Environments

### Environment A: Hiero Local Node

| Setting | Value |
|---------|-------|
| RPC URL | http://127.0.0.1:7546 |
| Chain ID | 298 |
| Test Accounts | Auto-generated (10 ECDSA, 10 Alias ECDSA, 10 ED25519) |
| Startup Command | `./scripts/start-local-node.sh` |

### Environment B: Solo

| Setting | Value |
|---------|-------|
| RPC URL | http://127.0.0.1:7546 |
| Chain ID | 298 |
| Test Accounts | Must be created manually |
| Startup Command | `./scripts/start-solo.sh` |

## Test Cases

### TC-01: Deploy Contract

**Objective:** Verify contract deployment succeeds

**Steps:**
1. Start network
2. Deploy Counter contract
3. Verify contract address is returned
4. Verify initial state (count = 0, owner = deployer)

**Expected Result:**
- Transaction succeeds
- Contract address is valid (non-zero)
- `count()` returns 0
- `owner()` returns deployer address

**Hardhat:**
```bash
cd examples/hardhat/contract-smoke
npm install
npx hardhat run scripts/deploy.ts --network localnode
```

**Foundry:**
```bash
cd examples/foundry/contract-smoke
source .env
forge script script/Deploy.s.sol:DeployCounter --rpc-url $RPC_URL --broadcast
```

### TC-02: State-Changing Transaction

**Objective:** Verify transactions modify contract state

**Steps:**
1. Call `increment()` on deployed Counter
2. Wait for transaction confirmation
3. Read `count()` value

**Expected Result:**
- Transaction succeeds
- `count()` returns 1

**Verification:**
```bash
# Foundry
cast send $CONTRACT "increment()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast call $CONTRACT "count()(uint256)" --rpc-url $RPC_URL
```

### TC-03: Read State

**Objective:** Verify state can be read without transaction

**Steps:**
1. Call `getCount()` (view function)
2. Call `owner()` (view function)

**Expected Result:**
- No transaction required
- Values returned correctly

**Verification:**
```bash
cast call $CONTRACT "getCount()(uint256)" --rpc-url $RPC_URL
cast call $CONTRACT "owner()(address)" --rpc-url $RPC_URL
```

### TC-04: Event Validation

**Objective:** Verify events are emitted correctly

**Steps:**
1. Call `increment()`
2. Query for `CountChanged` events

**Expected Result:**
- Event emitted with correct parameters:
  - `newCount`: incremented value
  - `changedBy`: caller address

**Hardhat Test:**
```typescript
await expect(counter.increment())
  .to.emit(counter, "CountChanged")
  .withArgs(1, owner.address);
```

**Foundry Test:**
```solidity
vm.expectEmit(true, true, false, true);
emit CountChanged(1, owner);
counter.increment();
```

### TC-05: Negative Case - Revert Validation

**Objective:** Verify reverts are handled correctly

**Steps:**
1. With count = 0, call `decrement()`
2. As non-owner, call `reset()`

**Expected Result:**
- `decrement()` reverts with "cannot decrement below zero"
- `reset()` reverts with "not owner" or custom error

**Hardhat Test:**
```typescript
await expect(counter.decrement()).to.be.revertedWith(
  "Counter: cannot decrement below zero"
);
```

**Foundry Test:**
```solidity
vm.expectRevert(Counter.CannotDecrementBelowZero.selector);
counter.decrement();
```

### TC-06: Multiple Transactions

**Objective:** Verify sequential transactions work correctly

**Steps:**
1. Deploy contract
2. Call `increment()` 5 times
3. Call `decrement()` 2 times
4. Read final count

**Expected Result:**
- Final count = 3
- All transactions succeed

### TC-07: Ownership Transfer

**Objective:** Verify ownership management works

**Steps:**
1. Check initial owner
2. Transfer ownership to new address
3. Verify new owner can call owner-only functions
4. Verify old owner cannot call owner-only functions

**Expected Result:**
- Ownership transfers correctly
- Access control enforced

## Test Execution Commands

### Full Hardhat Test Suite

```bash
cd examples/hardhat/contract-smoke
npm install
npm test                          # Local Hardhat network (fast)
npm run test:localnode           # Against Local Node
npm run test:solo                # Against Solo
```

### Full Foundry Test Suite

```bash
cd examples/foundry/contract-smoke
forge install foundry-rs/forge-std --no-commit
forge test -vvv                  # Local Foundry EVM (fast)
forge test --fork-url http://127.0.0.1:7546 -vvv  # Against Hedera
```

## Expected Outcomes

### Passing Tests

**Hardhat (19 tests):**
```
  Counter
    Deployment
      ✓ Should set initial count to 0
      ✓ Should set the deployer as owner
    Increment
      ✓ Should increment the counter
      ✓ Should increment multiple times
      ✓ Should emit CountChanged event
      ✓ Should allow anyone to increment
    Decrement
      ✓ Should decrement the counter
      ✓ Should revert when decrementing below zero
      ✓ Should emit CountChanged event
    Reset
      ✓ Should reset the counter to zero
      ✓ Should only allow owner to reset
      ✓ Should emit CountChanged event
    SetCount
      ✓ Should set count to specific value
      ✓ Should only allow owner to set count
    Ownership
      ✓ Should transfer ownership
      ✓ Should emit OwnershipTransferred event
      ✓ Should not allow transfer to zero address
      ✓ Should only allow owner to transfer ownership
      ✓ New owner should be able to reset

  19 passing
```

**Foundry (100+ tests across all contracts):**
```
Counter Tests (13 tests):
[PASS] test_InitialCountIsZero()
[PASS] test_DeployerIsOwner()
[PASS] test_Increment()
[PASS] testFuzz_Increment(uint8)
...

TestToken Tests (25+ tests - ERC-20):
[PASS] test_TokenName()
[PASS] test_Transfer()
[PASS] test_Approve()
[PASS] test_TransferFrom()
[PASS] testFuzz_Transfer(uint256)
...

PayableTest Tests (25+ tests - Value Transfers):
[PASS] test_ReceiveEther()
[PASS] test_Deposit()
[PASS] test_WithdrawCall()
...

Factory Tests (20+ tests - CREATE/CREATE2):
[PASS] test_DeployCounter()
[PASS] test_DeployCounterCreate2()
[PASS] test_PredictAddress()
...

PrecompileTest Tests (20+ tests - EVM Precompiles):
[PASS] test_RecoverSigner()
[PASS] test_Sha256()
[PASS] test_ModExpSimple()
...

HederaHTSTest Tests (15+ tests - Hedera-specific):
[PASS] test_GetRandomSeed() (Hedera only)
[PASS] test_CheckCapabilities()
...

Suite result: ok. 100+ passed; 0 failed
```

For detailed test coverage, see `docs/07-evm-test-coverage.md`.

## Failure Triage

### Connection Refused
1. Check network is running: `curl http://127.0.0.1:7546`
2. Check for port conflicts: `lsof -i :7546`
3. Restart network

### Transaction Timeout
1. Hedera has ~3-5 second finality - this is normal
2. Increase timeout in hardhat.config.ts
3. Check network health

### Wrong Chain ID
1. Verify chainId is 298 in config
2. Check network: `cast chain-id --rpc-url http://127.0.0.1:7546`

### Insufficient Funds
1. Use pre-funded Local Node accounts
2. For Solo, create account: `solo ledger account create --hbar-amount 1000`

## Log Collection

### Local Node Logs
```bash
# Docker container logs
docker logs network-node 2>&1 | tail -100
docker logs mirror-node-rest 2>&1 | tail -100

# Log directory
ls ./network-logs/node/
```

### Solo Logs
```bash
# Pod logs
kubectl logs -n solo network-node1-0 --tail=100

# Diagnostic dump
solo consensus diagnostics all --deployment solo-deployment

# Log directory
ls ~/.solo/logs/
```
