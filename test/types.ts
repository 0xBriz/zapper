import { ethers } from "ethers";

export const ZERO = ethers.constants.Zero;

export interface ZapInArgs {
  _tokenInAddress: string;
  _pairAddress: string;
  _tokenInAmount: ethers.BigNumber;
  _routerAddress: string;
  _pathTokenInToLp0: string[];
  _pathTokenInToLp1: string[];
}
