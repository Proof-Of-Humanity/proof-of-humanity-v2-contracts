import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "solidity-coverage";
import "@openzeppelin/hardhat-upgrades";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.3",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      chainId: 1,
    },
    sokol: {
      chainId: 77,
      url: "https://sokol.poa.network/",
    },
    xdai: {
      chainId: 100,
      url: "https://rpc.xdaichain.com/",
    },
    kovan: {
      chainId: 42,
      url: `https://kovan.infura.io/v3/${process.env.INFURA_API_KEY!}`,
    },
    mainnet: {
      chainId: 1,
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY!}`,
    },
  },
};

export default config;
