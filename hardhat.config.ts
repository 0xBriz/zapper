import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@openzeppelin/hardhat-upgrades";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.4",
  networks: {
    bsc_mainnet: {
      url: process.env.BSC_MAINNET_URL || "",
      accounts:
        process.env.BSC_MAINNET_DEV_KEY !== undefined
          ? [process.env.BSC_MAINNET_DEV_KEY]
          : [],
    },
    harmony_mainnet: {
      url: process.env.HARMONY_MAINNET_URL || "",
      accounts:
        process.env.HARMONY_MAINNET_DEV_KEY !== undefined
          ? [process.env.HARMONY_MAINNET_DEV_KEY]
          : [],
    },
  },

  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
