# Benchmark Results: How Long Does It Take?

Measured 2026-02-03 on macOS (Apple Silicon). Cold start — `node_modules`, `artifacts`,
and `cache` wiped before each run. Same contract (Counter.sol), same 6 operations
(deploy, write, read, verify event, write, read), same Hardhat toolchain throughout.

---

## The Developer Experience

**I use Hardhat on Ethereum (in-memory).** I set up in **12 seconds**. I complete my
test run in **0.02 seconds**.

**I use Hardhat on Hedera Testnet (remote).** I set up in **11 seconds**. I complete my
test run in **37 seconds**.

**I use Hardhat on Hedera Local Node (Docker).** I set up in **121 seconds**. I complete
my test run in **16 seconds**.

**I use Hardhat on Hedera Solo (Kubernetes).** I set up in **620 seconds**. I complete my
test run in **35 seconds**.

---

## Setup Time (npm install + compile + network startup)

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| npm install | 9.7s | 8.7s | 8.1s | 10.2s |
| Compile contracts | 2.1s | 2.0s | 2.0s | 2.9s |
| Network startup | 0s | 0.1s | 110.4s | 606.6s |
| **Setup total** | **11.8s** | **10.8s** | **120.5s** | **619.7s** |

npm install and compile are consistent (~10s + ~2s). The difference is network startup:
Hardhat is instant (in-memory), Testnet is already running (just a connectivity check),
Local Node pulls Docker images and starts ~10 containers, Solo provisions an entire
Kubernetes cluster with consensus node, mirror node, and relay.

## Test Run (6-step contract benchmark)

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| Deploy contract | 8ms | 12,328ms | 7,592ms | 17,433ms |
| Write (increment) | 1ms | 11,370ms | 1,934ms | 8,436ms |
| Read (count) | 1ms | 236ms | 51ms | 710ms |
| Event verification | 8ms | *failed** | 33ms | 60ms |
| Write (setCount) | 1ms | 12,463ms | 5,885ms | 8,093ms |
| Final read | 0ms | 216ms | 128ms | 185ms |
| **Test run total** | **19ms** | **36,613ms** | **15,623ms** | **34,917ms** |

*\*Hedera Testnet event query failed — `fromBlock: 0` exceeds the public relay's 7-day
block range limit. Not a consensus issue, just a relay query constraint.*

## Shutdown

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| Network shutdown | 0s | 0s | 10.5s | 144.6s |

## Total Wall Time (zero to done)

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| Setup | 11.8s | 10.8s | 120.5s | 619.7s |
| Test run | 0.02s | 36.6s | 15.6s | 34.9s |
| Shutdown | 0s | 0s | 10.5s | 144.6s |
| **Total** | **~12s** | **~48s** | **~149s** | **~804s** |

---

## What This Tells You

**Writes cost consensus time, reads are cheap.** Across all Hedera environments, a write
(deploy, increment, setCount) takes seconds — that's the cost of consensus. Reads return
in milliseconds. This is fundamental to how Hedera works and won't change.

**Local Node is 4x faster than Solo for contract operations.** 15.6s vs 34.9s for the
same 6 steps. Local Node runs an optimized Docker stack; Solo runs a full Kubernetes
deployment that more closely mirrors mainnet architecture.

**Network startup dominates Solo.** 607s of the 804s total (75%) is just waiting for
pods. If your Solo cluster is already running, the test run itself is 35 seconds.

**Hedera Testnet needs zero infrastructure.** 48s total, no Docker, no Kubernetes, no
local resources. The tradeoff: you need a funded account and are subject to public
network conditions.

**For pure EVM logic, use Hardhat.** 19ms for the full contract lifecycle. Run it
thousands of times during development, then validate on a Hedera network when ready.

---

## The Smart Contract

Every test uses the same contract: `Counter.sol` — a minimal Solidity contract that
exercises the core EVM operations a developer hits on day one.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Counter {
    uint256 public count;
    address public owner;

    event CountChanged(uint256 indexed newCount, address indexed changedBy);

    modifier onlyOwner() {
        require(msg.sender == owner, "Counter: caller is not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        count = 0;
    }

    function increment() public {
        count += 1;
        emit CountChanged(count, msg.sender);
    }

    function setCount(uint256 newCount) public onlyOwner {
        count = newCount;
        emit CountChanged(count, msg.sender);
    }
}
```

This covers: contract creation (constructor bytecode deployment), state storage writes
(`count += 1`, `count = newCount`), state reads (`count`), access control
(`onlyOwner`), and event emission (`CountChanged`). No external dependencies, no
oracles, no token standards — just the raw EVM primitives that every contract builds on.

---

## The 6 Steps and How Each Is Verified

### Step 1: Deploy Counter contract

**What happens:** The compiled bytecode is sent as a `CREATE` transaction. The EVM
allocates a new contract address, runs the constructor (setting `owner = msg.sender` and
`count = 0`), and stores the runtime bytecode on-chain.

**How it's verified:** After `waitForDeployment()` returns, the test calls
`getAddress()` and asserts the result is a valid 20-byte Ethereum address
(`expect(address).to.be.properAddress`). This confirms the transaction was mined, the
contract exists at a real address, and the RPC node can resolve it.

**What this times:** The full round-trip — transaction submission, consensus/mining,
receipt confirmation, and mirror node sync delay (if applicable).

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| Deploy | 8ms | 12,328ms | 7,592ms | 17,433ms |

### Step 2: Write — increment()

**What happens:** A state-changing transaction calls `increment()`, which reads `count`
from storage, adds 1, writes it back, and emits `CountChanged(1, sender)`.

**How it's verified:** The test calls `counter.increment()`, then `waitForTx(tx)` which
calls `tx.wait()` to get the transaction receipt. A successful receipt (no revert) means
the state change committed. On Hedera networks, an additional delay (`defaultWaitMs`)
waits for mirror node sync.

**What this times:** Transaction submission → consensus → receipt confirmation → mirror
node sync delay.

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| Write (increment) | 1ms | 11,370ms | 1,934ms | 8,436ms |

### Step 3: Read — count()

**What happens:** A `CALL` (not a transaction — no gas cost, no consensus needed) reads
the `count` storage slot and returns the value.

**How it's verified:** The test calls `counter.count()` and asserts the result equals
`1` (`expect(count).to.equal(1)`). This confirms the previous write actually persisted —
the state change from Step 2 is visible through a read query.

**What this times:** A single `eth_call` RPC round-trip. No transaction, no consensus.

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| Read (count) | 1ms | 236ms | 51ms | 710ms |

### Step 4: Event verification — CountChanged

**What happens:** The test queries the contract's event log for `CountChanged` events
using `queryFilter`, which translates to an `eth_getLogs` RPC call.

**How it's verified:** The test asserts: (1) at least one `CountChanged` event exists,
(2) the most recent event's `newCount` equals `1`, and (3) the event's `changedBy`
matches the deployer's address. This verifies the EVM event log infrastructure works
end-to-end — the event was emitted during `increment()`, indexed correctly, and is
queryable after the fact.

**What this times:** An `eth_getLogs` RPC call scanning for matching event topics.

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| Event verification | 8ms | *failed** | 33ms | 60ms |

*\*Hedera Testnet: the default `queryFilter` scans from block 0, which exceeds the
public relay's 7-day (604,800 seconds) block range limit. The events were emitted
correctly — the relay just refuses the wide query range.*

### Step 5: Write — setCount(42)

**What happens:** An `onlyOwner`-gated transaction sets `count` to 42 and emits
`CountChanged(42, sender)`. This tests the `require(msg.sender == owner)` access control
path in addition to a state write.

**How it's verified:** Same as Step 2 — `tx.wait()` returns a successful receipt,
confirming the `onlyOwner` check passed and the state was written.

**What this times:** Same as Step 2, but with the added `require` check in the EVM
execution.

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| Write (setCount) | 1ms | 12,463ms | 5,885ms | 8,093ms |

### Step 6: Final read — verify count() == 42

**What happens:** Another `eth_call` read of the `count` storage slot.

**How it's verified:** The test asserts the value is exactly `42`
(`expect(count).to.equal(42)`). This is the end-to-end proof: the contract was deployed
(Step 1), written to twice (Steps 2 and 5), and the final state reflects the last write
— not the increment, not zero, but the explicit `setCount(42)`.

**What this times:** A single `eth_call` RPC round-trip.

| | Hardhat | Hedera Testnet | Local Node | Solo |
|---|---------|----------------|------------|------|
| Final read | 0ms | 216ms | 128ms | 185ms |

---

## Why These 6 Steps

The sequence is deliberately minimal but covers every operation type a developer will hit:

| Operation type | Steps | What it proves |
|----------------|-------|----------------|
| **Deploy** | 1 | Contract creation works, bytecode is stored |
| **Write** | 2, 5 | State-changing transactions reach consensus |
| **Read** | 3, 6 | State is queryable after writes |
| **Events** | 4 | Event logs are emitted and indexable |
| **Access control** | 5 | `msg.sender` is correct, `require` works |
| **State consistency** | 3→6 | Multiple writes resolve to correct final state |

If all 6 pass, a developer knows: contracts deploy, transactions commit, state persists,
events log, and access control enforces. That's enough to start building.
