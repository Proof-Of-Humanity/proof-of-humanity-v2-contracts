import { formatEther } from "ethers";
import { ethers } from "hardhat";
import { Chain as ChainTestnets, SUPPORTED_NETWORKS as SUPPORTED_NETWORKS_TESTNETS } from "./consts/chains/chains-testnets";
import { Chain as ChainMainnets, SUPPORTED_NETWORKS as SUPPORTED_NETWORKS_MAINNETS } from "./consts/chains/chains-mainnets";

const SUPPORTED_NETWORKS = 
[
    ...SUPPORTED_NETWORKS_TESTNETS,
    ...SUPPORTED_NETWORKS_MAINNETS
]

export const REGISTRATION_META_EVIDENCE = "/ipfs/QmadJhyPxhk5AYrdE6JMwhC7TpsA47YZwFP28VKkr1ffJF";
export const CLEARING_META_EVIDENCE = "/ipfs/QmRqKmjVk1FcCRcTnuZmMG6SZEBB9LkUJb7Z4SVhJGHEfw";

export const getRouteToConsts = async (chainId: number) => {
    if (chainId == ChainTestnets.CHIADO || chainId == ChainTestnets.SEPOLIA)
        return import("./consts/consts-testnets");
    else if (chainId == ChainMainnets.MAINNET || chainId == ChainMainnets.GNOSIS)
        return import("./consts/consts-mainnets");
    else throw new Error("Network not supported");
};

export const supported = async () => {
    const [deployer] = await ethers.getSigners();
  
    console.log(`
      Wallet:  ${deployer.address}
      Balance:   ${formatEther(await ethers.provider.getBalance(deployer))} ETH
    `);
  
    if (!SUPPORTED_NETWORKS.includes(+(await ethers.provider.getNetwork()).chainId.toString()))
      throw new Error("Network not supported");
  };
  