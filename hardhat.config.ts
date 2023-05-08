import * as dotenv from "dotenv";
import { extendEnvironment, HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-etherscan";
import "solidity-coverage";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "hardhat-deploy";

dotenv.config();

extendEnvironment((hre) => {
  console.log("Hello world!");
});

task("Accounts", "Prints the accounts", async (_taskArgs, hre) => {
  console.log(hre.getChainId());
  console.log(hre.getNamedAccounts());
});

const config: HardhatUserConfig = {
  solidity: { version: "0.8.18", settings: { optimizer: { enabled: true, runs: 2000 }, viaIR: true } },
  networks: {
    hardhat: { chainId: 1, allowUnlimitedContractSize: true },
    // mainnet: { chainId: 1, url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY!}` },
    gnosis: {
      chainId: 100,
      url: `https://rpc.gnosischain.com/`,
      accounts: [process.env.PRIVATE_KEY!],
    },
    goerli: {
      chainId: 5,
      url: `https://goerli.infura.io/v3/${process.env.INFURA_API_KEY!}`,
      accounts: [process.env.PRIVATE_KEY!],
    },
    "optimism-goerli": {
      chainId: 420,
      url: `https://goerli.optimism.io`,
      accounts: [process.env.PRIVATE_KEY!],
    },
  },
  etherscan: { apiKey: process.env.ETHERSCAN_API_KEY },
};

export default config;
