import { AddressSetFixed, InitSpecificParamSet, InitGeneralParamSet } from "./interfaces/i-sets";
import { Chain } from "./chains/chains-mainnets";

import { Addresses } from "./addresses/addresses-mainnets";
//import { Addresses } from "./addresses/addresses-mainnets-old";
//import { Addresses } from "./addresses/addresses-mainnets-old2";

export { Addresses };

export const InitSpecificParams: InitSpecificParamSet = {
  ARBITRATOR_EXTRA_DATA_MAINNET: 
  "0x00000000000000000000000000000000000000000000000000000000000000170000000000000000000000000000000000000000000000000000000000000001", // PoH Court ID (MAIN) #23
  ARBITRATOR_EXTRA_DATA_SIDECHAIN: 
  "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001", // PoH Court ID (GNOSIS) #0
  REQUEST_BASE_DEPOSIT_MAINNET: 47500000000000000n, // 0.0475 ETHs
  REQUEST_BASE_DEPOSIT_SIDECHAIN: 110000000000000000000n, // 110 XDAI
}

export const InitParams: InitGeneralParamSet = {
  HUMANITY_LIFESPAN: 31557600,
  RENEWAL_DURATION: 7889400, // Three months before expiration
  CHALLENGE_DURATION: 302400,
  FAILED_REV_COOL_DOWN: 302400,
  SHARED_MULTIPLIER: 10000,
  WINNER_MULTIPLIER: 10000,
  LOSER_MULTIPLIER: 20000,
  NB_VOUCHES: 1,
  TRANSFER_COOLDOWN: 3600, // Set to 1 hour
}

export const getForeignCCProxy = (chainId: number): string => {
  switch (chainId) {
    case Chain.GNOSIS: 
      return Addresses[Chain.MAINNET].CROSS_CHAIN;
    case Chain.MAINNET:
      return Addresses[Chain.GNOSIS].CROSS_CHAIN;
  }
  return '0x0';
}

export const FixedAddresses: Record<number, AddressSetFixed> = {
    [Chain.MAINNET]: {
      MESSENGER: "0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e", // AMB on Mainnet
      ARBITRATOR: "0x988b3A538b618C7A603e1c11Ab82Cd16dbE28069", // Athena (Kleros court on mainnet)
      W_NATIVE: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // Wrapped Eth (WETH)
    },
    [Chain.GNOSIS]: {
      MESSENGER: "0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59", // AMB on Gnosis
      ARBITRATOR: "0x9C1dA9A04925bDfDedf0f6421bC7EEa8305F9002", // Kleros court on Gnosis
      W_NATIVE: "0xe91d153e0b41518a2ce8dd3d7944fa863463a97d", // Wrapped XDAI (WXDAI)
    }
};