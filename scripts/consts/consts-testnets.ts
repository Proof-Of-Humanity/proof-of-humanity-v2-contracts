import { WeiPerEther } from "ethers";
import { AddressSetFixed, InitParamSet } from "./interfaces/i-sets";
import { Chain } from "./chains/chains-testnets";

import { Addresses } from "./addresses/addresses-testnets-new";
//import { Addresses } from "./addresses/addresses-testnets-old";

export { Addresses };

export const InitParams: InitParamSet = {
  ARBITRATOR_EXTRA_DATA: 
  "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
  REQUEST_BASE_DEPOSIT_MAINNET: WeiPerEther / 100n, // Used by pohlegacy to simulate pohv1 in Sepolia
  REQUEST_BASE_DEPOSIT_SIDECHAIN: WeiPerEther / 100n,
  HUMANITY_LIFESPAN: 864000,
  RENEWAL_DURATION: 863940,
  CHALLENGE_DURATION: 60,
  FAILED_REV_COOL_DOWN: 60,
  SHARED_MULTIPLIER: 10000,
  WINNER_MULTIPLIER: 10000,
  LOSER_MULTIPLIER: 20000,
  NB_VOUCHES: 1,
  TRANSFER_COOLDOWN: 7,
}

export const getForeignCCProxy = (chainId: number): string => {
  switch (chainId) {
    case Chain.SEPOLIA: 
      return Addresses[Chain.CHIADO].CROSS_CHAIN;
    case Chain.CHIADO:
      return Addresses[Chain.SEPOLIA].CROSS_CHAIN;
  }
  return '0x0';
}

export const FixedAddresses: Record<number, AddressSetFixed> = {
    [Chain.CHIADO]: {
      LEGACY: "0x", 
      MESSENGER: "0x8448E15d0e706C0298dECA99F0b4744030e59d7d", // AMB on Chiado
      ARBITRATOR: "0x34E520dc1d2Db660113b64724e14CEdCD01Ee879", // Kleros court on Chiado
      W_NATIVE: "0x014A442480DbAD767b7615E55E271799889FA1a7", // Wrapped XDAI on Chiado
    },
    [Chain.SEPOLIA]: {
      LEGACY: "0x",
      MESSENGER: "0xf2546D6648BD2af6a008A7e7C1542BB240329E11", // AMB on Sepolia
      ARBITRATOR: "0x90992fb4E15ce0C59aEFfb376460Fda4Ee19C879", // Kleros court on Sepolia
      W_NATIVE: "0x7b79995e5f793a07bc00c21412e50ecae098e7f9", // Wrapped Eth on Sepolia
    }
};