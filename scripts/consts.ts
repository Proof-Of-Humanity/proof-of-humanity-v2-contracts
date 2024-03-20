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

export const Addresses: Record<number, AddressSet> = {
  [Chain.GNOSIS]: {
    POH: "0x4a594f0e73223c9a1CE0EfC16da92fFaA193a612",
    POH_Implementation: "0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d",
    CROSS_CHAIN: "0x2C692919Da3B5471F9Ac6ae1C9D1EE54F8111f76",
    CC_Implementation: "0x8363709987bbfbe241f9900eb449dcf517a80e74",
    GATEWAY: "0x0142424ce8ce5E0999e3AB794A0b608511EF90dF", //"0x01E429B428fC06E3577E33E42EE69560E38420C3",
    MESSENGER: "0x6E260AF12b708853d7A7e9A2E9124873c7B0C25F", //"0x", //"0x7EB9D435CEc5A254F1033a63c474a97cBBCDF01A",
    LEGACY: "0x",
    ARBITRATOR: "0x9C1dA9A04925bDfDedf0f6421bC7EEa8305F9002",
    W_NATIVE: "0xe91d153e0b41518a2ce8dd3d7944fa863463a97d",
  },
  [Chain.SEPOLIA]: {
    POH: "0x29defF3DbEf6f79ef20d3fe4f9CFa0547acCeC0D",
    POH_Implementation: "0xa59974FDc4728178D6CdEa305228D4482146f2FD",
    CROSS_CHAIN: "0xd134748B972A320a73EfDe3AfF7a68718F6bA92c",
    CC_Implementation: "0x1b1938b88f98aac56ae6d5beeb72abd6b858061c",
    GATEWAY: "0xfE5DB6640a1AE41176c025F6D32cf37Bd7e43898", //"0xEbC60f7e5F5cD3c98f43F29167E2630491Ba4571",
    MESSENGER: "0xd6E5dB0de4219684E247a570501cDC51E993CDF9", //"0x", //"0x8C2858b87D98262fa79c7b10a47840a81E057B85",
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
