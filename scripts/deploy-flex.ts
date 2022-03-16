import { ethers } from "hardhat";

async function main() {
  const ZapperFlex = await ethers.getContractFactory("ZapperFlex");
  const zapper = await ZapperFlex.deploy();
  console.log("ZapperFlex deployed to:", zapper.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
