import { ethers } from "hardhat";

async function main() {
  const network = await ethers.provider.getNetwork();
  console.log("=== Deploying Counter Contract ===");
  console.log(`Network: ${network.name} (Chain ID: ${network.chainId})`);
  console.log("");

  // Get deployer
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);

  // Check balance
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Deployer balance:", ethers.formatEther(balance), "HBAR");
  console.log("");

  // Deploy
  console.log("Deploying Counter...");
  const Counter = await ethers.getContractFactory("Counter");
  const counter = await Counter.deploy();
  await counter.waitForDeployment();

  const address = await counter.getAddress();
  console.log("Counter deployed to:", address);
  console.log("");

  // Verify deployment
  const initialCount = await counter.count();
  const owner = await counter.owner();
  console.log("Initial count:", initialCount.toString());
  console.log("Owner:", owner);
  console.log("");

  // Test increment
  console.log("Testing increment...");
  const tx = await counter.increment();
  await tx.wait();
  const newCount = await counter.count();
  console.log("Count after increment:", newCount.toString());
  console.log("");

  console.log("=== Deployment Complete ===");
  console.log("");
  console.log("Contract address:", address);
  console.log("Save this address for later use!");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
