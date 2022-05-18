import { expect } from "chai";
import { ethers } from "hardhat";
import { FeeZapper } from "../typechain";
import { ZapInArgs } from "./types";

describe("FeeZapper", () => {
  let zapper: FeeZapper;

  const TREASURY_MULTISIG_ADDRESS =
    "0x6bcC0E231A4Ac051b68DBC62F8882c04e2bA9F77";
  const treasury = TREASURY_MULTISIG_ADDRESS;

  const TEAM_FEE_RECEIVER = "0xb13B5a7C6aD304C863ecF5F0071Fdd8AE3D3f07e";
  const devAccount = TEAM_FEE_RECEIVER;

  const PANCAKESWAP_ROUTER_ADDRESS =
    "0x10ED43C718714eb63d5aA57B78B54704E256024E";
  const ROUTER_ADDRESS = PANCAKESWAP_ROUTER_ADDRESS;

  const BUSD_ADDRESS = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
  const TOKEN_IN_ADDRESS = BUSD_ADDRESS;

  const PAIR_AMETHYST_BUSD_BSC = "0x81722a6457e1825050B999548a35E30d9f11dB5c";
  const PAIR_ADDRESS = PAIR_AMETHYST_BUSD_BSC;

  const AMES_ADDRESS = "0xb9E05B4C168B56F73940980aE6EF366354357009";

  const lpToken0Path = [BUSD_ADDRESS, AMES_ADDRESS];
  const lpToken1Path = [BUSD_ADDRESS];

  let zapInputArgs: ZapInArgs;

  beforeEach(async () => {
    const FeeZapper = await ethers.getContractFactory("FeeZapper");
    zapper = await FeeZapper.deploy(treasury, devAccount);
  });

  function tryZapIn(zapInputArgs: ZapInArgs) {
    return zapper.zapInWithPath(
      zapInputArgs._tokenInAddress,
      zapInputArgs._pairAddress,
      zapInputArgs._tokenInAmount,
      zapInputArgs._routerAddress,
      zapInputArgs._pathTokenInToLp0,
      zapInputArgs._pathTokenInToLp1
    );
  }

  describe("input validation", () => {
    it("should revert with input token address zero", async () => {
      zapInputArgs = {
        _tokenInAddress: ethers.constants.AddressZero,
        _pairAddress: PAIR_ADDRESS,
        _tokenInAmount: 0,
        _routerAddress: ROUTER_ADDRESS,
        _pathTokenInToLp0: [],
        _pathTokenInToLp1: [],
      };

      await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
        "!TokenIn address"
      );
    });

    it("should revert with pair address zero", async () => {
      zapInputArgs = {
        _tokenInAddress: TOKEN_IN_ADDRESS,
        _pairAddress: ethers.constants.AddressZero,
        _tokenInAmount: 0,
        _routerAddress: ROUTER_ADDRESS,
        _pathTokenInToLp0: [],
        _pathTokenInToLp1: [],
      };

      await expect(tryZapIn(zapInputArgs)).to.be.revertedWith("!LP address");
    });

    it("should revert with router address zero", async () => {
      zapInputArgs = {
        _tokenInAddress: TOKEN_IN_ADDRESS,
        _pairAddress: PAIR_ADDRESS,
        _tokenInAmount: 0,
        _routerAddress: ethers.constants.AddressZero,
        _pathTokenInToLp0: [],
        _pathTokenInToLp1: [],
      };

      await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
        "!Router address"
      );
    });

    it("should revert with input amount of zero", async () => {
      zapInputArgs = {
        _tokenInAddress: TOKEN_IN_ADDRESS,
        _pairAddress: PAIR_ADDRESS,
        _tokenInAmount: 0,
        _routerAddress: ROUTER_ADDRESS,
        _pathTokenInToLp0: [],
        _pathTokenInToLp1: [],
      };

      await expect(tryZapIn(zapInputArgs)).to.be.revertedWith("!tokenInAmount");
    });

    it("should revert when routing path is too short", async () => {
      const mockAddressOne = "0x3fF07607c5C8C619C69b1fd4C08aebF069AA10c7";
      const mockAddressTwo = "0x2e86D29cFea7c4f422f7fCCF97986bbBa03e1a7F";

      zapInputArgs = {
        _tokenInAddress: TOKEN_IN_ADDRESS,
        _pairAddress: PAIR_ADDRESS,
        _tokenInAmount: 10,
        _routerAddress: ROUTER_ADDRESS,
        _pathTokenInToLp0: [],
        _pathTokenInToLp1: [],
      };
      await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
        "!_pathTokenInToLp0"
      );

      zapInputArgs._pathTokenInToLp0 = [mockAddressOne, mockAddressTwo];

      await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
        "!_pathTokenInToLp1"
      );
    });
  });
});
