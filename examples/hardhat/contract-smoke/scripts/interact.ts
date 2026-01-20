import { ethers } from "hardhat";

// Update this with your deployed contract address
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "";

async function main() {
  if (!CONTRACT_ADDRESS) {
    console.error("Please set CONTRACT_ADDRESS environment variable");
    console.error("Example: CONTRACT_ADDRESS=0x... npx hardhat run scripts/interact.ts --network localnode");
    process.exit(1);
  }

  const network = await ethers.provider.getNetwork();
  console.log("=== Interacting with Counter Contract ===");
  console.log(`Network: ${network.name} (Chain ID: ${network.chainId})`);
  console.log(`Contract: ${CONTRACT_ADDRESS}`);
  console.log("");

  // Get signer
  const [signer] = await ethers.getSigners();
  console.log("Signer address:", signer.address);
  console.log("");

  // Attach to deployed contract
  const Counter = await ethers.getContractFactory("Counter");
  const counter = Counter.attach(CONTRACT_ADDRESS);

  // Read current state
  console.log("=== Current State ===");
  const count = await counter.count();
  const owner = await counter.owner();
  console.log("Current count:", count.toString());
  console.log("Owner:", owner);
  console.log("");

  // Increment
  console.log("=== Incrementing ===");
  const tx1 = await counter.increment();
  console.log("Transaction hash:", tx1.hash);
  const receipt1 = await tx1.wait();
  console.log("Transaction confirmed in block:", receipt1?.blockNumber);

  const countAfterIncrement = await counter.count();
  console.log("Count after increment:", countAfterIncrement.toString());
  console.log("");

  // Check events
  console.log("=== Events ===");
  const filter = counter.filters.CountChanged();
  const events = await counter.queryFilter(filter, -100);
  console.log(`Found ${events.length} CountChanged events`);
  for (const event of events.slice(-3)) { // Show last 3
    console.log(`  Block ${event.blockNumber}: count = ${event.args?.newCount}`);
  }
  console.log("");

  // Final state
  console.log("=== Final State ===");
  const finalCount = await counter.count();
  console.log("Final count:", finalCount.toString());
  console.log("");
  console.log("=== Interaction Complete ===");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
