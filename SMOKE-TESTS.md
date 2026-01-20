# Hedera EVM Smoke Test Reference

This document explains the scope, dependencies, connection details, and observable outputs for the two smoke suites in `hedera-evm-lab`. Each suite deploys and exercises the same `Counter` contract against either the Hiero Local Node or Solo networks through their JSON-RPC relays, and every transaction they submit can be independently verified through Hashscan or the Mirror Node REST APIs highlighted below.

## Target Networks and Observability

| Network | Startup Script | JSON-RPC (HTTP/WS) | Mirror Node REST | Hashscan / Explorer |
|---------|----------------|--------------------|------------------|---------------------|
| Hiero Local Node | `./scripts/start-local-node.sh` | `http://127.0.0.1:7546` / `ws://127.0.0.1:8546` | `http://127.0.0.1:5551` | `http://127.0.0.1:8090` (Local Hashscan) |
| Solo | `./scripts/start-solo.sh` | `http://127.0.0.1:7546` | `http://localhost:8081/api/v1` (default) | `http://localhost:8080` (Explorer UI) |

- Both environments expose Chain ID `298 (0x12a)` and may not run simultaneously because they default to the same RPC port (see `docs/05-sample-test-plan.md`).
- Hashscan / Explorer can be pointed at `LOCALNET` (for Local Node) or at the Solo deployment by visiting the URLs printed by the startup scripts.
- Mirror Node verification relies on the REST API’s transaction and contract-result endpoints. Examples later in this file show how to query them.

## Hardhat Contract Smoke Suite (`examples/hardhat/contract-smoke`)

### Dependencies

- Node.js ≥ 18 with npm (per the project `README.md`).
- Hardhat dev dependencies declared in `package.json`: `hardhat`, `@nomicfoundation/hardhat-toolbox`, `ts-node`, `typescript`, and `dotenv`.
- Running Hedera environment (Local Node or Solo). The `run-hardhat-smoke.sh` script refuses to run unless `eth_chainId` on port 7546 returns `0x12a`.
- Optional: `SOLO_PRIVATE_KEYS` environment variable that lists Hedera private keys for Solo testing; otherwise the suite falls back to the Hiero Local Node prefunded accounts listed at the top of `hardhat.config.ts`.

### Network Attachment

- `hardhat.config.ts` wires three networks:
  - `localnode`: RPC URL defaults to `http://127.0.0.1:7546`, Chain ID `298`, and uses the prefunded Alias-ECDSA accounts that ship with Hiero Local Node (`0x105d…1524`, etc.).
  - `solo`: RPC URL defaults to `http://127.0.0.1:7546` as well but expects user-provided keys through `SOLO_PRIVATE_KEYS`.
  - `hardhat`: the in-memory Hardhat network for quick unit iterations (Chain ID `31337`), not connected to Hedera.
- Each test waits with `waitForTx` helpers so mirror-node-aware workflows have time to see confirmed state.

### Counter Contract Behavior

| Function | Access Control | Behavior | Evidence and Mirror Signals |
|----------|----------------|----------|-----------------------------|
| `increment()` | Public | Increases `count` and emits `CountChanged(newCount, msg.sender)` | Mirror node shows a contract call with opcode writes + `CountChanged` log whose indexed topics contain the new count and caller. |
| `decrement()` | Public | Requires `count > 0`, then decrements and emits `CountChanged` | Mirror node will include a revert status if called at `count = 0`. |
| `reset()` | Only owner | Sets `count = 0` and emits `CountChanged` | Transaction status `SUCCESS` plus owner address in `changedBy`. |
| `setCount(uint256)` | Only owner | Sets `count` to `newCount` | Mirror node contract result shows the raw parameter and the event. |
| `transferOwnership(address)` | Only owner, disallows zero address | Emits `OwnershipTransferred` and updates `owner` | Mirror node log topics reveal both the old and new owners. |
| `getCount()` / public state vars | View | Used to assert post-state without another transaction | Matches `eth_call` and `mirror-node /contracts/{address}/results/latest`. |

### Test Flow and Observable Output

The suite lives in `test/Counter.test.ts`. When run via `npm run test:localnode` or `npx hardhat test --network solo`:

1. **Before hook**: Prints an ASCII dashboard summarizing the active network, wait durations, and timeout. This is often the first thing to screenshot when documenting a run.
2. **Deployment block**: Confirms constructor initialized `count = 0` and `owner = deployer`.
3. **Increment block**: Sends up to three sequential `increment()` transactions, confirms anyone may call it, and asserts that `CountChanged` events include the expected arguments.
4. **Decrement block**: Proves positive decrements succeed, decrements below zero revert, and emitted events contain the expected owner/counter pair.
5. **Reset block**: Requires ownership to reset the counter, emitting `CountChanged(0, owner)`.
6. **SetCount block**: Validates direct owner updates versus non-owner reverts.
7. **Ownership block**: Covers the cases around transferring ownership, preventing zero-address transfers, and ensuring the new owner may exercise privileged functions.
8. **After hook**: Prints a “Timing Summary (Gap Analysis)” table that shows deployment times, per-test duration, and totals. These numbers help correlate directly with Mirror Node timestamps.

The helper script `scripts/deploy.ts` logs deployer balance, contract address, and the `CountChanged` state after a test increment. `scripts/interact.ts` prints the transaction hash, block number, and the most recent `CountChanged` events, which serves as the easiest source for grabbing hashes to verify via Mirror Node or Hashscan.

### Independent Verification

1. **Capture contract and transaction identifiers**
   - When using the smoke script (`./scripts/run-hardhat-smoke.sh localnode`), rerun `npx hardhat run scripts/interact.ts --network <network>` with `CONTRACT_ADDRESS` exported; this script logs a transaction hash (`tx.hash`) and the last few `CountChanged` events.
   - The transaction hash can also be obtained via `hardhat test --verbose` (Hardhat logs each `eth_sendRawTransaction`).
2. **Hashscan / Explorer**
   - Local Node: open `http://127.0.0.1:8090`, switch to `LOCALNET`, and search for the contract address or pasted transaction hash. The Explorer view shows emitted events in the `Logs` tab (topics correspond to `CountChanged` and `OwnershipTransferred`).
   - Solo: open `http://localhost:8080`, select the Solo deployment, and search by contract or transaction hash. You can cross-reference with `solo ledger account create` outputs to ensure funding accounts exist.
3. **Mirror Node REST queries**
   - Local Node example:
     ```bash
     CONTRACT=0x... # address from scripts/interact.ts
     curl "http://127.0.0.1:5551/api/v1/contracts/$CONTRACT/results?order=desc&limit=5"
     ```
     The `logs` section in the latest result includes decoded `CountChanged` topics (`newCount` and `changedBy`), confirming the smoke test’s assertions.
   - Solo example:
     ```bash
     TX=0.0.12345@1700000000.000000001?scheduled=false
     curl "http://localhost:8081/api/v1/transactions/$TX"
     ```
     The response shows `result: SUCCESS`, the payer account, and child contract-call records, matching the ownership or counter updates asserted in the tests.
4. **Timestamp correlation**
   - Use the `Timing Summary` output to find when each test ran, then compare with the `consensus_timestamp` in Mirror Node responses to prove they line up (typically within a second on Local Node and a few seconds on Solo).

## Foundry Contract Smoke Suite (`examples/foundry/contract-smoke`)

### Dependencies

- Foundry toolchain (`forge`, `cast`, optionally `anvil`) installed via `foundryup`.
- `forge-std` library (auto-installed by `scripts/run-foundry-smoke.sh`).
- `.env` file seeded from `.env.example`, providing `RPC_URL`, `PRIVATE_KEY`, and `DEPLOYER_ADDRESS`.
- Running Hedera network; `./scripts/run-foundry-smoke.sh --fork` checks that port 7546 returns Chain ID `0x12a` before executing forked tests. Running without `--fork` keeps execution purely local.

### Network Attachment

- `foundry.toml` configures `localnode` and `solo` RPC endpoints pointing at `http://127.0.0.1:7546`. Chain ID is set to `298` and compiler settings match the Hardhat project (Solidity `0.8.24`, optimizer 200 runs).
- Forked tests use `forge test --fork-url $RPC_URL -vvv`, which mirrors on-chain state. Deployments use `forge script ... --rpc-url $RPC_URL --broadcast`.
- Because both networks share the port, the same port-conflict warning from the Hardhat section applies: stop one environment before starting the other.

### Counter Contract Behavior

Foundry’s `Counter.sol` mirrors the Hardhat version but adds custom errors for gas-efficient revert checks.

| Function / Error | Behavior | Mirror / Hashscan Evidence |
|------------------|----------|----------------------------|
| `increment()` | Emits `CountChanged` after increment | Verify via Mirror Node logs identical to Hardhat. |
| `decrement()` | Reverts with `CannotDecrementBelowZero` when empty | Mirror Node transaction result will contain `result: CONTRACT_REVERT_EXECUTED` and raw error data. |
| `reset()` | Only owner; uses custom `NotOwner` error | Mirror Node record shows payer vs. contract as expected, and the revert code appears if owner condition fails. |
| `setCount()` | Only owner; no additional logic | Mirror Node logs show `CountChanged(newCount, owner)`. |
| `transferOwnership()` | Only owner; reverts `ZeroAddress` | Ownership changes can be correlated through event topics `[OwnershipTransferred]`. |

### Test Flow and Observable Output

`test/Counter.t.sol` contains eleven deterministic tests plus a fuzz test:

- `test_InitialCountIsZero` / `test_DeployerIsOwner`: Read-only assertions.
- `test_Increment`, `test_IncrementEmitsEvent`, `test_AnyoneCanIncrement`: Validate general increments, event emission, and access control.
- `test_Decrement`, `test_DecrementRevertsWhenZero`: Exercises both success and revert flows.
- `test_Reset` / `test_ResetOnlyOwner`: Confirm ownership restriction with `vm.prank` for adversarial callers.
- `test_SetCount`, `test_TransferOwnership`, `test_TransferOwnershipRevertsOnZeroAddress`: Cover the remaining write paths.
- `testFuzz_Increment(uint8 times)`: Confirms sequential increments behave linearly over multiple random counts.

Running `forge test -vvv` prints a per-test `PASS` plus gas metrics (`gas: 28xxx`) that document relative costs. When using `./scripts/run-foundry-smoke.sh --fork`, the transaction traces originate from the live Hedera network, so any revert or state change corresponds to an observable Mirror Node record.

Deployment and manual verification rely on `script/Deploy.s.sol` within the Foundry project:

1. `forge script script/Deploy.s.sol:DeployCounter --rpc-url $RPC_URL --broadcast -vvv` signs and submits the deployment and a follow-up `increment()` call. The CLI prints transaction hashes, and the JSON artifacts in `broadcast/` preserve them for later reference.
2. After deployment, `cast` can read back state or send more transactions (`cast call $CONTRACT "count()(uint256)"` and `cast send ... "increment()"`).

### Independent Verification

1. **Gather hashes**
   - Transaction hashes are printed directly during `forge script ... --broadcast`. They are also preserved in `broadcast/DeployCounter.s.sol/<chain-id>/run-latest.json`.
   - For forked tests, use `RUST_LOG=debug forge test --fork-url ...` to capture JSON-RPC payloads (including `eth_sendRawTransaction` hex) that correspond to the Mirror Node entries.
2. **Hashscan / Explorer**
   - Local Node: `http://127.0.0.1:8090` ⇒ search for the deployment transaction hash or the `0x...` contract address.
   - Solo: `http://localhost:8080` ⇒ choose the Solo environment and search as above.
3. **Mirror Node REST**
   - Contract results for Local Node:
     ```bash
     CONTRACT=0x...
     curl "http://127.0.0.1:5551/api/v1/contracts/$CONTRACT/results/logs?order=desc&limit=3"
     ```
     The payload lists `count` and `changedBy` in the decoded log data so you can match `forge test` expectations (e.g., verifying that anyone could increment).
   - Solo transaction record:
     ```bash
     HASH=0x... # `forge script` output
     curl "http://localhost:8081/api/v1/transactions/$HASH"
     ```
     Check the `result` (should be `SUCCESS` for state-changing tests) and confirm emitted logs align with event expectations.
4. **Cross-checking counts**
   - After Foundry smoke tests run, use `cast call $CONTRACT "count()(uint256)" --rpc-url $RPC_URL` and compare with the `state_changes` field returned by the Mirror Node transaction record to verify on-chain state matches the local read.

## Verification Checklist After Any Smoke Run

1. Record the contract address and every transaction hash surfaced by `scripts/interact.ts` (Hardhat) or `forge script` (Foundry).
2. Use Hashscan / Explorer to confirm each transaction finalized on the intended network, inspect the event logs, and ensure the payer account aligns with the signer you configured.
3. Query the Mirror Node REST API for the same hashes to capture a machine-readable record (`result`, `consensus_timestamp`, `logs` payload, and `state_changes`).
4. Compare Mirror Node timestamps with the timing metrics printed by the Hardhat suite or with the wall-clock time of the Foundry run to prove determinism across tooling.
5. Archive the commands and responses above with your test report so the smoke run is reproducible and independently auditable.

By following this playbook, every Hardhat and Foundry smoke-test execution in `hedera-evm-lab` can be traced from CLI output to explorer UI and raw Mirror Node records on both Local Node and Solo networks.
