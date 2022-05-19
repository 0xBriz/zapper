import { ethers } from "hardhat";

async function main() {
  const TREASURY_MULTISIG_ADDRESS =
    "0x6bcC0E231A4Ac051b68DBC62F8882c04e2bA9F77";
  const treasury = TREASURY_MULTISIG_ADDRESS;

  const TEAM_FEE_RECEIVER = "0xb13B5a7C6aD304C863ecF5F0071Fdd8AE3D3f07e";
  const devAccount = TEAM_FEE_RECEIVER;

  const FeeZapper = await ethers.getContractFactory("FeeZapper");
  const zapper = await FeeZapper.deploy(treasury, devAccount);
  console.log("FeeZapper deployed to:", zapper.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
