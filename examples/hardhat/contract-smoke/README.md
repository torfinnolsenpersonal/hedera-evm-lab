# Hardhat Smoke Test for Hedera

A minimal Hardhat project to test EVM smart contracts on Hedera Local Node or Solo.

## Prerequisites

- Node.js >= 18.0.0
- Running Hedera network (Local Node or Solo)

## Setup

```bash
# Install dependencies
npm install

# Copy environment template
cp .env.example .env
```

## Running with Local Node

1. Start Local Node:
```bash
# From hedera-evm-lab root
./scripts/start-local-node.sh
```

2. Run tests:
```bash
# Using hardhat network (fast, no Hedera)
npm test

# Against Local Node
npm run test:localnode
```

3. Deploy:
```bash
npm run deploy
```

4. Interact (after deploy):
```bash
CONTRACT_ADDRESS=0x... npm run interact
```

## Running with Solo

1. Start Solo:
```bash
# From hedera-evm-lab root
./scripts/start-solo.sh
```

2. Run tests:
```bash
npm run test:solo
```

3. Deploy:
```bash
npm run deploy:solo
```

## Expected Test Output

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

## Network Configuration

- **Local Node RPC**: http://127.0.0.1:7546
- **Chain ID**: 298 (0x12a)
- **Pre-funded Accounts**: See hardhat.config.ts

## Troubleshooting

### Connection Refused
Ensure the network is running:
```bash
curl http://127.0.0.1:7546 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```

### Tests Timeout
Increase timeout in hardhat.config.ts or use the hardhat network for unit tests.

### Wrong Chain ID
Verify hardhat.config.ts has chainId: 298.
