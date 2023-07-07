import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000000,
      },
    },
  },
  networks: {
    myNetwork: {
      url: "http://localhost:5000",
    },
    // goerli: {
    //   url: process.env.ALCHEMY_URL,
    //   accounts: [`0x${process.env.PRIVATE_KEY}`],
    // },
  },
  gasReporter: {
    enabled: true
  }
};

export default config;
