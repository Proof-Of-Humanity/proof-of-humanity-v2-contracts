import { formatEther } from "ethers/lib/utils";
import { ethers } from "hardhat";

interface AddressSet {
  POH: string;
  HOME_CC: string;
  MESSENGER: string;
  GATEWAY: string;
  ARBITRATOR: string;
  W_NATIVE: string;
}

enum Chain {
  GOERLI = 5,
  GNOSIS = 100,
}

export const Addresses: Record<number, AddressSet> = {
  [Chain.GOERLI]: {
    POH: "0x",
    HOME_CC: "0x",
    GATEWAY: "0x",
    MESSENGER: "0x",
    ARBITRATOR: "0x",
    W_NATIVE: "0xb4fbf271143f4fbf7b91a5ded31805e42b2208d6",
  },
  [Chain.GNOSIS]: {
    POH: "0x",
    HOME_CC: "0x",
    GATEWAY: "0x",
    MESSENGER: "0x",
    ARBITRATOR: "0x",
    W_NATIVE: "0xe91d153e0b41518a2ce8dd3d7944fa863463a97d",
  },
};

export const SUPPORTED_NETWORKS = [Chain.GNOSIS];

export const supported = async () => {
  const [deployer] = await ethers.getSigners();

  console.log(`
    Wallet:  ${deployer.address}
    Balance:   ${formatEther(await deployer.getBalance())} ETH
  `);

  if (!SUPPORTED_NETWORKS.includes(await deployer.getChainId())) throw new Error("Network not supported");
};
