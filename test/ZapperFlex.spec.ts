import { expect } from "chai";
import { MockContract, MockProvider } from "ethereum-waffle";
import { Wallet } from "ethers";
import { ethers, waffle } from "hardhat";
import mockRouterABI from "../artifacts/contracts/mocks/RouterMock.sol/RouterMock.json";
import pairMockABI from "../artifacts/contracts/mocks/PairMock.sol/PairMock.json";
import inputTokenMockABI from "../artifacts/contracts/mocks/InputTokenMock.sol/InputTokenMock.json";
import { ZapInArgs, ZERO } from "./types";
import { ZapperFlex } from "../typechain";

describe("ZapperFlex", () => {
  let user: Wallet;
  let provider: MockProvider;
  let zapper: ZapperFlex;
  let routerMock: MockContract;
  let pairMock: MockContract;
  let inputTokenMock: MockContract;

  let zapInputArgs: ZapInArgs;

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

    const ZapperFlex = await ethers.getContractFactory("ZapperFlex");
    zapper = await ZapperFlex.deploy();
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

  describe("zapInWithPath()", () => {
    describe("input validation", () => {
      it("should revert with input token address zero", async () => {
        zapInputArgs = {
          _tokenInAddress: ethers.constants.AddressZero,
          _pairAddress: pairMock.address,
          _tokenInAmount: ZERO,
          _routerAddress: routerMock.address,
          _pathTokenInToLp0: [],
          _pathTokenInToLp1: [],
        };

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "!TokenIn address"
        );
      });

      it("should revert with pair address zero", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: ethers.constants.AddressZero,
          _tokenInAmount: ZERO,
          _routerAddress: routerMock.address,
          _pathTokenInToLp0: [],
          _pathTokenInToLp1: [],
        };

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith("!LP address");
      });

      it("should revert with router address zero", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: ZERO,
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
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: ZERO,
          _routerAddress: routerMock.address,
          _pathTokenInToLp0: [],
          _pathTokenInToLp1: [],
        };

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "!tokenInAmount"
        );
      });

      it("should revert when routing path is too short", async () => {
        const mockAddressOne = "0x3fF07607c5C8C619C69b1fd4C08aebF069AA10c7";
        const mockAddressTwo = "0x2e86D29cFea7c4f422f7fCCF97986bbBa03e1a7F";

        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: ethers.utils.parseEther("10"),
          _routerAddress: routerMock.address,
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

    describe("_validatePairForRouter()", () => {
      const mockAddressOne = "0x3fF07607c5C8C619C69b1fd4C08aebF069AA10c7";
      const mockAddressTwo = "0x2e86D29cFea7c4f422f7fCCF97986bbBa03e1a7F";

      it("should revert if the first address in both paths != _tokenInAddress", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: ethers.utils.parseEther("10"),
          _routerAddress: routerMock.address,
          _pathTokenInToLp0: [mockAddressOne, mockAddressTwo],
          _pathTokenInToLp1: [mockAddressOne, mockAddressTwo],
        };

        await pairMock.mock.factory.returns(mockAddressOne);
        await routerMock.mock.factory.returns(mockAddressTwo);

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "_tokenInToLp0[0] != _tokenInAddress"
        );

        // Make first one pass
        zapInputArgs._pathTokenInToLp0 = [
          inputTokenMock.address,
          mockAddressTwo,
        ];
        zapInputArgs._pathTokenInToLp1 = [mockAddressOne, mockAddressTwo];

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "_tokenInToLp1[0] != _tokenInAddress"
        );
      });

      it("should revert if the pair factory does not match the router factory", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: ethers.utils.parseEther("10"),
          _routerAddress: routerMock.address,
          _pathTokenInToLp0: [inputTokenMock.address, mockAddressTwo],
          _pathTokenInToLp1: [inputTokenMock.address, mockAddressTwo],
        };
        await pairMock.mock.factory.returns(mockAddressOne);
        await routerMock.mock.factory.returns(mockAddressTwo);
        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "Mismatched factories"
        );
      });

      it("should revert if the input token is not in the LP pair", async () => {
        zapInputArgs = {
          _tokenInAddress: inputTokenMock.address,
          _pairAddress: pairMock.address,
          _tokenInAmount: ethers.utils.parseEther("10"),
          _routerAddress: routerMock.address,
          _pathTokenInToLp0: [inputTokenMock.address, mockAddressOne],
          _pathTokenInToLp1: [inputTokenMock.address, mockAddressTwo],
        };

        // Make factories match first for next test step
        await pairMock.mock.factory.returns(mockAddressOne);
        await routerMock.mock.factory.returns(mockAddressOne);

        // Expects the last two items in the paths array to be the lP combo
        await pairMock.mock.token0.returns(
          "0xb783e21fb34108a24a5c805765ebc9999ac541a2"
        );

        // mapped to last item in the path array to pass here
        await pairMock.mock.token1.returns(mockAddressTwo);

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "!lpToken0 not in pair"
        );

        // Make this pass first
        await pairMock.mock.token0.returns(mockAddressOne);
        // Same address just to test failure
        await pairMock.mock.token1.returns(mockAddressOne);

        await expect(tryZapIn(zapInputArgs)).to.be.revertedWith(
          "!lpToken1 not in pair"
        );
      });
    });
  });
});
