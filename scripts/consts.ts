import { formatEther } from "ethers";
import { ethers } from "hardhat";
import { isTestnet, SUPPORTED_NETWORKS } from "./consts/chains/chains";

// Policy referred for deployments: /ipfs/QmTWdrNJ1KBsnNcMq5PeZQyvJfnwJexvDwnbLqZsVh2L21
export const REGISTRATION_META_EVIDENCE = "/ipfs/QmSRrYV3vg5q6CFpZDQgwSo6dPe81V5XBhST47G3aQYU5H";
export const CLEARING_META_EVIDENCE = "/ipfs/QmTCbojsdDDGvtGFmLj46QtfBbkNhMbgfu8VSmsx7TznSj";
export const POH_V1_Address = "0xC5E9dDebb09Cd64DfaCab4011A0D5cEDaf7c9BDb"; // PoH v1
export const NULL_Address = "0x";

export const getRouteToConsts = async (chainId: number) => {
    if (isTestnet(chainId))
        return import("./consts/consts-testnets");
    else return import("./consts/consts-mainnets");
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
  