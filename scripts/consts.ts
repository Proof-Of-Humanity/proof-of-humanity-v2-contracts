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
  CHIADO = 10200,
  MAINNET = 1,
}

export const Addresses: Record<number, AddressSet> = {
  [Chain.GNOSIS]: {
    POH: "0x4a594f0e73223c9a1CE0EfC16da92fFaA193a612",
    POH_Implementation: "0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d",
    CROSS_CHAIN: "0x2C692919Da3B5471F9Ac6ae1C9D1EE54F8111f76",
    CC_Implementation: "0x8363709987bbfbe241f9900eb449dcf517a80e74",
    GATEWAY: "0x0142424ce8ce5E0999e3AB794A0b608511EF90dF", 
    MESSENGER: "0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59",
    LEGACY: "0x",
    ARBITRATOR: "0x9C1dA9A04925bDfDedf0f6421bC7EEa8305F9002",
    W_NATIVE: "0xe91d153e0b41518a2ce8dd3d7944fa863463a97d",
  },
  [Chain.CHIADO]: {
    POH: "0x2505C87AA36d9ed18514Ea7473Ac58aeDeb50849",
    POH_Implementation: "0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d",
    CROSS_CHAIN: "0xBEd896A3DEa0E065F05Ba83Fa63322c7b9d67838",
    CC_Implementation: "0x4a594f0e73223c9a1CE0EfC16da92fFaA193a612",
    GATEWAY: "0x56350e6827263B8521192d4979D341dA7582A996",
    MESSENGER: "0x8448E15d0e706C0298dECA99F0b4744030e59d7d",
    LEGACY: "0x",
    ARBITRATOR: "0x34E520dc1d2Db660113b64724e14CEdCD01Ee879",
    W_NATIVE: "0x014A442480DbAD767b7615E55E271799889FA1a7",
    //PROXY_ADMIN: "0x856B71a157377dd43CCAC11430fe50d0912a46b4",
  },
  [Chain.SEPOLIA]: {
    POH: "0x29defF3DbEf6f79ef20d3fe4f9CFa0547acCeC0D",
    POH_Implementation: "0xa59974FDc4728178D6CdEa305228D4482146f2FD",
    CROSS_CHAIN: "0xd134748B972A320a73EfDe3AfF7a68718F6bA92c",
    CC_Implementation: "0x1b1938b88f98aac56ae6d5beeb72abd6b858061c",
    GATEWAY: "0x3787Aa5c2c03A1AC49555F84750e9503ba9A9043",
    MESSENGER: "0xf2546D6648BD2af6a008A7e7C1542BB240329E11",
    LEGACY: "0x08Db8FD559cb4e3668f994553871c7eBa7c3941a",
    ARBITRATOR: "0x90992fb4E15ce0C59aEFfb376460Fda4Ee19C879",
    W_NATIVE: "0x7b79995e5f793a07bc00c21412e50ecae098e7f9",
  },
  [Chain.MAINNET]: {
    POH: "0x",
    POH_Implementation: "0x",
    CROSS_CHAIN: "0x",
    CC_Implementation: "0x",
    GATEWAY: "0x",
    MESSENGER: "0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e",
    LEGACY: "0x",
    ARBITRATOR: "0x",
    W_NATIVE: "0x",
  },
};

export const SUPPORTED_NETWORKS = [
  Chain.SEPOLIA, 
  Chain.GNOSIS, 
  Chain.CHIADO, 
  Chain.MAINNET
];

export const supported = async () => {
  const [deployer] = await ethers.getSigners();

  console.log(`
    Wallet:  ${deployer.address}
    Balance:   ${formatEther(await ethers.provider.getBalance(deployer))} ETH
  `);

  if (!SUPPORTED_NETWORKS.includes(+(await ethers.provider.getNetwork()).chainId.toString()))
    throw new Error("Network not supported");
};
