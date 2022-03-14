import { expect } from "chai";
import { MockContract, MockProvider } from "ethereum-waffle";
import { Wallet } from "ethers";
import { ethers, waffle } from "hardhat";
import { Zapper } from "../typechain";
import mockRouterABI from "../artifacts/contracts/mocks/RouterMock.sol/RouterMock.json";
import pairMockABI from "../artifacts/contracts/mocks/PairMock.sol/PairMock.json";
import inputTokenMockABI from "../artifacts/contracts/mocks/InputTokenMock.sol/InputTokenMock.json";

describe("Zapper", () => {
  let user: Wallet;
  let provider: MockProvider;
  let zapper: Zapper;
  let routerMock: MockContract;
  let pairMock: MockContract;
  let inputTokenMock: MockContract;

  let zapInputArgs: {
    _tokenInAddress: string;
    _pairAddress: string;
    _tokenInAmount: number;
    _routerAddress: string;
    _path: string[];
  };

  beforeEach(async () => {
    provider = waffle.provider;
    const wallets = provider.getWallets();
    user = wallets[0];

    routerMock = await waffle.deployMockContract(user, mockRouterABI.abi);
    pairMock = await waffle.deployMockContract(user, pairMockABI.abi);
    inputTokenMock = await waffle.deployMockContract(
      user,
      inputTokenMockABI.abi
    );

    const Zapper = await ethers.getContractFactory("Zapper");
    zapper = await Zapper.deploy();
  });

  function tryZapIn(zapInputArgs: {
    _tokenInAddress: string;
    _pairAddress: string;
    _tokenInAmount: number;
    _routerAddress: string;
    _path: string[];
  }) {
    return zapper.zapInWithPath(
      zapInputArgs._tokenInAddress,
      zapInputArgs._pairAddress,
      zapInputArgs._tokenInAmount,
      zapInputArgs._routerAddress,
      zapInputArgs._path
    );
  }

  describe("zapInWithPath()", () => {
    describe("input validation", () => {
      it("should revert with input token address zero", async () => {
        zapInputArgs = {
          _tokenInAddress: ethers.constants.AddressZero,
          _pairAddress: pairMock.address,
          _tokenInAmount: 0,
          _routerAddress: routerMock.address,
          _path: [],
        };

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "!TokenIn address"
        );
      });

      it("should revert with pair address zero", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: ethers.constants.AddressZero,
          _tokenInAmount: 0,
          _routerAddress: routerMock.address,
          _path: [],
        };

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith("!LP address");
      });

      it("should revert with router address zero", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: 0,
          _routerAddress: ethers.constants.AddressZero,
          _path: [],
        };

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "!Router address"
        );
      });

      it("should revert with input amount of zero", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: 0,
          _routerAddress: routerMock.address,
          _path: [],
        };

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "!tokenInAmount"
        );
      });

      it("should revert when routing path is too short", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: 10,
          _routerAddress: routerMock.address,
          _path: [],
        };

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith("!path");
      });
    });

    describe("_validatePairForRouter()", () => {
      const mockAddressOne = "0x3fF07607c5C8C619C69b1fd4C08aebF069AA10c7";
      const mockAddressTwo = "0x2e86D29cFea7c4f422f7fCCF97986bbBa03e1a7F";

      it("should revert if the pair factory does not match the router factory", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: 10,
          _routerAddress: routerMock.address,
          _path: [mockAddressOne, mockAddressTwo],
        };

        await pairMock.mock.factory.returns(mockAddressOne);
        await routerMock.mock.factory.returns(mockAddressTwo);

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "Incompatible liquidity pair factory"
        );
      });

      it("should revert if the input token is not in the LP pair", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: 10,
          _routerAddress: routerMock.address,
          _path: [mockAddressOne, mockAddressTwo],
        };

        // Make factories match first for next test step
        await pairMock.mock.factory.returns(mockAddressOne);
        await routerMock.mock.factory.returns(mockAddressOne);

        await pairMock.mock.token0.returns(mockAddressOne);
        await pairMock.mock.token1.returns(mockAddressTwo);

        // zapInputArgs token won't be in pair mocked addresses
        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "Input token not present in liquidity pair"
        );
      });
    });

    describe("_getTokenInTokenOut()", () => {
      //
    });
  });
});
