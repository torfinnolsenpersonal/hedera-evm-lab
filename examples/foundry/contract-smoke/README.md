# Foundry Smoke Test for Hedera

A minimal Foundry project to test EVM smart contracts on Hedera Local Node or Solo.

## Prerequisites

- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- Running Hedera network (Local Node OR Solo - not both simultaneously!)

## Important: Shared Proxy Port Conflict

Both Local Node and Solo use port 7546 for the JSON-RPC relay by default. **Do not run both simultaneously** - this will cause port conflicts and unpredictable behavior.

Choose one:
- Local Node: `./scripts/start-local-node.sh`
- Solo: `./scripts/start-solo.sh`

Stop one before starting the other.

## Setup

```bash
# Install forge-std
forge install foundry-rs/forge-std --no-commit

# Copy environment template
cp .env.example .env
```

## Running Tests

```bash
# Run tests locally (Foundry EVM, fast)
forge test -vvv

# Run against Hedera network (fork mode)
source .env
forge test --fork-url $RPC_URL -vvv
```

## Deployment

```bash
source .env

# Deploy to Local Node or Solo
forge script script/Deploy.s.sol:DeployCounter \
  --rpc-url $RPC_URL \
  --broadcast \
  -vvv
```

## Using Cast

```bash
source .env

# Check chain ID
cast chain-id --rpc-url $RPC_URL
# Expected: 298

# Check balance
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL

# Deploy (alternative method)
forge create src/Counter.sol:Counter \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Interact with deployed contract
export CONTRACT=<deployed-address>
cast call $CONTRACT "count()(uint256)" --rpc-url $RPC_URL
cast send $CONTRACT "increment()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Expected Test Output

```
Running 10 tests for test/Counter.t.sol:CounterTest
[PASS] test_AnyoneCanIncrement() (gas: 28xxx)
[PASS] test_Decrement() (gas: 31xxx)
[PASS] test_DecrementRevertsWhenZero() (gas: 8xxx)
[PASS] test_DeployerIsOwner() (gas: 5xxx)
[PASS] test_Increment() (gas: 28xxx)
[PASS] test_IncrementEmitsEvent() (gas: 28xxx)
[PASS] test_InitialCountIsZero() (gas: 5xxx)
[PASS] test_Reset() (gas: 29xxx)
[PASS] test_ResetOnlyOwner() (gas: 10xxx)
[PASS] testFuzz_Increment(uint8) (runs: 256)

Suite result: ok. 10 passed; 0 failed
```

## Troubleshooting

### Connection Refused
Check network is running:
```bash
curl http://127.0.0.1:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

### Port Already in Use
Stop the other network first:
```bash
./scripts/stop-local-node.sh  # or
./scripts/stop-solo.sh
```
