import { ethers } from "hardhat";

async function main() {
  const Zapper = await ethers.getContractFactory("Zapper");
  const zapper = await Zapper.deploy();
  console.log("Zapper deployed to:", zapper.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
