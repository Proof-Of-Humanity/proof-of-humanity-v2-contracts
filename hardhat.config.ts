import * as dotenv from "dotenv";
import { extendEnvironment, HardhatUserConfig, task } from "hardhat/config";
import "@typechain/hardhat";
import "@nomicfoundation/hardhat-toolbox";
import "solidity-coverage";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "hardhat-deploy-ethers";

dotenv.config();

extendEnvironment((hre) => {
  console.log("Hello world!");
});

task("Accounts", "Prints the accounts", async (_taskArgs, hre) => {
  console.log(hre.getChainId());
  console.log(hre.getNamedAccounts());
});

const config: HardhatUserConfig = {
  solidity: { version: "0.8.20", settings: { optimizer: { enabled: true, runs: 3200 }, viaIR: true } },
  networks: {
    hardhat: { chainId: 1, allowUnlimitedContractSize: true },
    mainnet : {
      chainId: 1,
      url: ``,
      accounts: [process.env.PRIVATE_KEY!],
    },
    gnosis: {
      chainId: 100,
      url: `https://rpc.gnosischain.com/`,
      accounts: [process.env.PRIVATE_KEY!],
    },
    chiado: {
      chainId: 10200,
      url: `https://rpc.chiado.gnosis.gateway.fm`,
      accounts: [process.env.PRIVATE_KEY!],
    },
    sepolia: {
      chainId: 11155111,
      url: `https://sepolia.infura.io/v3/${process.env.INFURA_API_KEY!}`,
      accounts: [process.env.PRIVATE_KEY!],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: `${process.env.ETHERSCAN_API_KEY!}`,
      xdai: `${process.env.XDAI_API_KEY!}`,
      chiado: `${process.env.CHIADO_API_KEY!}`,
    },
    customChains: [
      {
        network: "chiado",
        chainId: 10200,
        urls: {
          apiURL: `https://gnosis-chiado.blockscout.com/api`,
          browserURL: `https://blockscout.chiadochain.net`,
        },
      }
    ]
  }
};

export default config;
