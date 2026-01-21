# Hedera EVM Lab - Test Report

**Generated**: 2026-01-20 21:45:00 PST
**Report ID**: 2026-01-20_21-45-00
**Test Type**: Full EVM Suite
**Networks Tested**: Local Node, Solo

---

## Executive Summary

| Framework | Network | Passed | Failed | Total | Pass Rate | Duration |
|-----------|---------|--------|--------|-------|-----------|----------|
| Hardhat | Local Node | 105 | 23 | 128 | 82.0% | ~13 min |
| Hardhat | Solo | 115 | 13 | 128 | 89.8% | ~17 min |
| Foundry | Local Node | 138 | 6 | 144 | 95.8% | ~3 sec |
| Foundry | Solo | 138 | 6 | 144 | 95.8% | ~9 sec |

### Overall Results

- **Total Tests Run**: 544 (272 per network)
- **Total Passed**: 496
- **Total Failed**: 48
- **Overall Pass Rate**: 91.2%

### Key Findings

1. **Solo outperformed Local Node** for Hardhat tests (89.8% vs 82.0%)
2. **Foundry results identical** on both networks (95.8%)
3. **Hedera precompiles** (PRNG, Exchange Rate) fail in Foundry fork mode on both networks
4. **PayableTest** value transfers had inconsistent behavior on Local Node

---

## Environment

- **OS**: Darwin 24.4.0
- **Architecture**: arm64
- **Node.js**: v25.2.1
- **Docker**: 27.5.1
- **Foundry**: forge 1.0.0
- **Solo**: 0.58.1
- **Hedera Local**: Installed via npm

### Repository Versions

| Repository | Commit SHA |
|------------|------------|
| solo | 8e0f0075a53dfd9a0a3d191add9f136f573ee3e4 |
| hiero-local-node | b92cdb897403f358e1bad34c368a13fd7215f586 |

---

## Hardhat Test Results - Local Node

### Summary

- **Passing**: 105
- **Failing**: 23
- **Duration**: ~13 minutes
- **Average per test**: 7,469ms

### Test Suites

| Suite | Passed | Failed | Notes |
|-------|--------|--------|-------|
| Counter | 14 | 5 | Increment/decrement edge cases |
| Factory | 20 | 2 | CREATE/CREATE2 working well |
| HederaHTSTest | 14 | 1 | Token association failure |
| PayableTest | 13 | 12 | Value transfer issues |
| PrecompileTest | 24 | 1 | EIP-191 signature verification |
| TestToken | 20 | 2 | Transfer edge cases |

### Failed Tests

```
1) Counter - Increment - Should increment multiple times
2) Counter - Decrement - Should decrement the counter
3) Counter - Decrement - Should revert when decrementing below zero
4) Counter - Reset - Should reset the counter to zero
5) Counter - Ownership - New owner should be able to reset
6) Factory - CREATE Deployment - Should return all deployed addresses
7) Factory - CREATE2 Deployment - Should deploy to different addresses with different salts
8) HederaHTSTest - HTS Basic - Should check token association
9) PayableTest - Deployment - Should accept ETH/HBAR on deployment
10) PayableTest - Receive - Should receive ETH/HBAR directly
11) PayableTest - Receive - Should emit Received event
12) PayableTest - Receive - Should update totalReceived
13) PayableTest - Deposit - Should accept deposits
14) PayableTest - Deposit - Should emit Received event on deposit
15) PayableTest - Withdraw - Should emit Withdrawn event
16) PayableTest - Withdraw To - Should withdraw to specific address
17) PayableTest - Withdraw To - Should emit Withdrawn event with recipient
18) PayableTest - Ownership - Should transfer ownership
19) PayableTest - Fallback - Should handle calls with data via fallback
20) PayableTest - Fallback - Should emit FallbackCalled event
21) PrecompileTest - EIP-191 - Should verify message signature
22) TestToken - Transfer - Should allow transfer between non-owner accounts
23) TestToken - Burn - Should burn tokens
```

### Timing Analysis (Gap Analysis)

| Test | Duration |
|------|----------|
| Should increment multiple times | 13,936ms |
| Should emit CountChanged event | 10,433ms |
| Should revert when decrementing below zero | 8,337ms |
| Should reset the counter to zero | 9,924ms |
| Should only allow owner to reset | 12,293ms |

---

## Hardhat Test Results - Solo

### Summary

- **Passing**: 115
- **Failing**: 13
- **Duration**: ~17 minutes
- **Average per test**: 10,649ms

### Test Suites

| Suite | Passed | Failed | Notes |
|-------|--------|--------|-------|
| Counter | 19 | 0 | All passing |
| Factory | 22 | 0 | All passing |
| HederaHTSTest | 14 | 1 | Token association failure |
| PayableTest | 15 | 10 | Fewer failures than Local Node |
| PrecompileTest | 24 | 1 | EIP-191 signature verification |
| TestToken | 21 | 1 | Minor transfer edge case |

### Failed Tests

```
1) HederaHTSTest - HTS Basic - Should check token association
2) PayableTest - Deployment - Should accept ETH/HBAR on deployment
3) PayableTest - Receive - Should receive ETH/HBAR directly
4) PayableTest - Receive - Should emit Received event
5) PayableTest - Receive - Should update totalReceived
6) PayableTest - Deposit - Should accept deposits
7) PayableTest - Deposit - Should emit Received event on deposit
8) PayableTest - Withdraw - Should emit Withdrawn event
9) PayableTest - Withdraw To - Should withdraw to specific address
10) PayableTest - Withdraw To - Should emit Withdrawn event with recipient
11) PayableTest - Fallback - Should handle calls with data via fallback
12) PayableTest - Fallback - Should emit FallbackCalled event
13) PrecompileTest - EIP-191 - Should verify message signature
```

### Improvements Over Local Node

Solo passed these tests that failed on Local Node:
- Counter increment/decrement edge cases
- Counter ownership transfer scenarios
- Factory CREATE2 address predictions
- TestToken burn functionality
- PayableTest ownership transfer

---

## Foundry Test Results - Local Node

### Summary

- **Passing**: 138
- **Failing**: 6
- **Skipped**: 0
- **Total**: 144
- **Duration**: ~3 seconds

### Test Suites

| Suite | Passed | Failed | Notes |
|-------|--------|--------|-------|
| Counter | 13 | 0 | All passing |
| Factory | 27 | 0 | All passing |
| HederaHTSTest | 12 | 5 | Precompile access issues in fork |
| HederaIntegration | 0 | 1 | PRNG precompile failure |
| PayableTest | 30 | 0 | All passing |
| PrecompileTest | 29 | 0 | All passing |
| TestToken | 27 | 0 | All passing |

### Failed Tests

```
[FAIL: call to non-contract address 0x0000000000000000000000000000000000000168] test_ConvertTinybarsToTinycents()
[FAIL: call to non-contract address 0x0000000000000000000000000000000000000168] test_ConvertTinycentsToTinybars()
[FAIL: call to non-contract address 0x0000000000000000000000000000000000000169] test_GetRandomInRange()
[FAIL: call to non-contract address 0x0000000000000000000000000000000000000169] test_GetRandomSeed()
[FAIL: call to non-contract address 0x0000000000000000000000000000000000000169] test_MultipleRandomSeeds()
[FAIL: call to non-contract address 0x0000000000000000000000000000000000000169] test_HederaFullIntegration()
```

### Root Cause

All 6 failures are due to Hedera-specific precompiles (0x168 = Exchange Rate, 0x169 = PRNG) not being accessible through Foundry's fork mode RPC connection. These precompiles exist at system addresses that the forked connection cannot reach.

---

## Foundry Test Results - Solo

### Summary

- **Passing**: 138
- **Failing**: 6
- **Skipped**: 0
- **Total**: 144
- **Duration**: ~9 seconds

### Test Suites

| Suite | Passed | Failed | Notes |
|-------|--------|--------|-------|
| Counter | 13 | 0 | All passing |
| Factory | 27 | 0 | All passing |
| HederaHTSTest | 12 | 5 | Same precompile issues |
| HederaIntegration | 0 | 1 | Same PRNG failure |
| PayableTest | 30 | 0 | All passing |
| PrecompileTest | 29 | 0 | All passing |
| TestToken | 27 | 0 | All passing |

### Failed Tests

Identical to Local Node - same 6 Hedera precompile tests fail in fork mode.

---

## EVM Feature Coverage

### Features Tested Successfully

| Category | Features | Status |
|----------|----------|--------|
| **Storage** | SLOAD, SSTORE, mappings, nested mappings | Pass |
| **Events** | LOG0-LOG4, indexed parameters | Pass |
| **Calls** | CALL, STATICCALL, DELEGATECALL | Pass |
| **Create** | CREATE, CREATE2, address prediction | Pass |
| **Precompiles** | ecrecover (0x01), sha256 (0x02), ripemd160 (0x03), identity (0x04), modexp (0x05) | Pass |
| **ERC Standards** | ERC-20 (transfer, approve, transferFrom, mint, burn) | Pass |
| **Access Control** | Ownership, modifiers, require/revert | Pass |
| **Value Transfer** | payable, receive, fallback, transfer, send, call | Partial |

### Features With Issues

| Feature | Issue | Network | Framework |
|---------|-------|---------|-----------|
| PRNG Precompile (0x169) | Not accessible in fork mode | Both | Foundry |
| Exchange Rate (0x168) | Not accessible in fork mode | Both | Foundry |
| EIP-191 Signatures | Verification mismatch | Both | Hardhat |
| Value Transfer Events | Inconsistent event emission | Local Node | Hardhat |
| HTS Token Association | Check returns unexpected result | Both | Hardhat |

---

## Recommendations

### For Development

1. **Use Solo for CI/CD** - Higher pass rate (89.8% vs 82.0%)
2. **Use Foundry for local testing** - Faster execution, consistent results
3. **Skip Hedera precompile tests in Foundry fork mode** - Known limitation

### For Test Suite Improvements

1. **PayableTest**: Review value assertion precision (wei vs HBAR conversion)
2. **EIP-191 Test**: Investigate signature format differences on Hedera
3. **HTS Association**: Update expected behavior for non-existent tokens

### For Documentation

1. Document Foundry fork mode limitations with Hedera precompiles
2. Add expected timing differences between Solo and Local Node
3. Note that Solo provides more production-like behavior

---

## Appendix: Test Contracts

| Contract | Purpose | Tests |
|----------|---------|-------|
| Counter.sol | Basic storage, events, access control | 13-19 |
| TestToken.sol | ERC-20 implementation | 25-27 |
| PayableTest.sol | Value transfers (receive, fallback, withdraw) | 25-30 |
| Factory.sol | CREATE/CREATE2 deployment | 20-27 |
| PrecompileTest.sol | Standard EVM precompiles | 24-29 |
| HederaHTSTest.sol | Hedera-specific precompiles | 12-17 |

---

*Report generated by hedera-evm-lab test framework*
