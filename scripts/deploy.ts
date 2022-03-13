import { ethers, upgrades } from "hardhat";

async function main() {
  const ZapperUpgradeable = await ethers.getContractFactory(
    "ZapperUpgradeable"
  );
  const zapper = await upgrades.deployProxy(ZapperUpgradeable);
  console.log("ZapperUpgradeable deployed to:", zapper.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
