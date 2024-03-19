import { formatEther } from "ethers";
import { ethers } from "hardhat";

interface AddressSet {
  POH: string;
  POH_Implementation: string;
  CROSS_CHAIN: string;
  CC_Implementation: string;
  MESSENGER: string;
  GATEWAY: string;
  LEGACY: string;
  ARBITRATOR: string;
  W_NATIVE: string;
}

export enum Chain {
  GNOSIS = 100,
  SEPOLIA = 11155111,
}

/* 
Verifying implementation: 0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d
Successfully submitted source code for contract
contracts/ProofOfHumanity.sol:ProofOfHumanity at 0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d
for verification on the block explorer. Waiting for verification result...

Successfully verified contract ProofOfHumanity on the block explorer.
https://gnosisscan.io/address/0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d#code
Verifying proxy: 0x4a594f0e73223c9a1CE0EfC16da92fFaA193a612
Contract at 0x4a594f0e73223c9a1CE0EfC16da92fFaA193a612 already verified.
Linking proxy 0x4a594f0e73223c9a1CE0EfC16da92fFaA193a612 with implementation
Successfully linked proxy to implementation.
Verifying proxy admin: 0x856B71a157377dd43CCAC11430fe50d0912a46b4
Contract at 0x856B71a157377dd43CCAC11430fe50d0912a46b4 already verified. 
*/

export const Addresses: Record<number, AddressSet> = {
  [Chain.GNOSIS]: {
    POH: "0x4a594f0e73223c9a1CE0EfC16da92fFaA193a612",
    POH_Implementation: "0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d",
    //POH: "0xB6412c84eC958cafcC80B688d6F473e399be488f", // OLD
    //POH_Implementation: "0xf230c60c40d70a6ae8bd20c92243a1cf67c6c2a7", ///OLD
    CROSS_CHAIN: "0x2C692919Da3B5471F9Ac6ae1C9D1EE54F8111f76",
    CC_Implementation: "0x8363709987bbfbe241f9900eb449dcf517a80e74",
    GATEWAY: "0x01E429B428fC06E3577E33E42EE69560E38420C3",
    MESSENGER: "0x",
    LEGACY: "0x",
    ARBITRATOR: "0x9C1dA9A04925bDfDedf0f6421bC7EEa8305F9002",
    W_NATIVE: "0xe91d153e0b41518a2ce8dd3d7944fa863463a97d",
  },
  [Chain.SEPOLIA]: {
    POH: "0x29defF3DbEf6f79ef20d3fe4f9CFa0547acCeC0D", //0xf43460a06964947aD1DC59665175af4c5f1C8306 ???
    POH_Implementation: "0xa59974FDc4728178D6CdEa305228D4482146f2FD",
    CROSS_CHAIN: "0xd134748B972A320a73EfDe3AfF7a68718F6bA92c",
    CC_Implementation: "0x1b1938b88f98aac56ae6d5beeb72abd6b858061c",
    GATEWAY: "0xEbC60f7e5F5cD3c98f43F29167E2630491Ba4571",
    MESSENGER: "0x",
    LEGACY: "0x08Db8FD559cb4e3668f994553871c7eBa7c3941a",
    ARBITRATOR: "0x90992fb4E15ce0C59aEFfb376460Fda4Ee19C879",
    W_NATIVE: "0x7b79995e5f793a07bc00c21412e50ecae098e7f9",
  },
};

export const SUPPORTED_NETWORKS = [Chain.SEPOLIA, Chain.GNOSIS];

export const supported = async () => {
  const [deployer] = await ethers.getSigners();

  console.log(`
    Wallet:  ${deployer.address}
    Balance:   ${formatEther(await ethers.provider.getBalance(deployer))} ETH
  `);

  if (!SUPPORTED_NETWORKS.includes(+(await ethers.provider.getNetwork()).chainId.toString()))
    throw new Error("Network not supported");
};
