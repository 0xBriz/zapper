import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Zapper } from "../typechain";

describe("Zapper", () => {
  const ROUTER = "0xcF664087a5bB0237a0BAd6742852ec6c8d69A27a";
  let signers: SignerWithAddress[];
  let owner: SignerWithAddress;

  let zapper: Zapper;

  beforeEach(async () => {
    signers = await ethers.getSigners();
    owner = signers[0];

    const Zapper = await ethers.getContractFactory("Zapper");
    zapper = <Zapper>await upgrades.deployProxy(Zapper, [ROUTER], {});
  });

  describe("initialize()", () => {
    it("Should revert when zero address for router", async () => {
      const Zapper = await ethers.getContractFactory("Zapper");
      await expect(
        upgrades.deployProxy(Zapper, [ethers.constants.AddressZero])
      ).to.be.revertedWith("!router");
    });
  });

  it("Should only allow owner to update the router", async () => {
    // const Zapper = await ethers.getContractFactory("Zapper");
    // const zapper = await upgrades.deployProxy(Zapper, [
    //   ethers.constants.AddressZero,
    // ]);
  });
});
