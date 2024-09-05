import { AddressSet } from "../interfaces/i-sets";
import { Chain } from "../chains/chains-mainnets";
import { NULL_Address, POH_V1_Address } from "../../consts";

export const Addresses: Record<number, AddressSet> = {
  [Chain.MAINNET]: {
    // Complete while the corresponding scripts are executed
    POH: "0x87c5c294C9d0ACa6b9b2835A99FE0c9A444Aacc1",
    POH_Implementation: "0xF921b42B541bc53a07067B65207F879c9377bf7F",
    CROSS_CHAIN: "0xD8D462ac9F3FAD77Af2ae2640fE7F591F1651A2C",
    CC_Implementation: "0x064B1132D9A9c43Df269FeAD9e80c195Fb9cd916",
    GATEWAY: "0x290e997D7c46BDFf666Ad38506fcFB3082180DF9",
    LEGACY: POH_V1_Address, // Fixed
    //PROXY_ADMIN: "0xf57B69f71DD7499Ca30242390E655e8A6a93b51b",
    //PROXY_ADMIN_CC: "0xec729b0eCf7972236e8926DA4feAAF9BC8F55e65",
    FORK_MODULE: "0x116cB4077afbb9B5c7E0dCd5fc4Ce943Ab624dbF",
    PROXY_TOKEN: "0x"
  },
  [Chain.GNOSIS]: {
    // Complete while the corresponding scripts are executed
    POH: "0xECd1823b3087acEE3C77928b1959c08d31A8F20e",
    POH_Implementation: "0x5efa99c7b0cc04893b2c5551437ff82b19e661c7",
    CROSS_CHAIN: "0xF921b42B541bc53a07067B65207F879c9377bf7F",
    CC_Implementation: "0xc664a8d43601109fc50f3bcf22f29e9119ab2f6d",
    GATEWAY: "0xD8D462ac9F3FAD77Af2ae2640fE7F591F1651A2C",
    LEGACY: NULL_Address, // Fixed
    //PROXY_ADMIN: "0x60BC555eb5a40b7f934A7345aFA3596Ddd388b2B",
    //PROXY_ADMIN_CC: "0x36dfBA40eD6DC28f26163548466170b39BE2916D",
    FORK_MODULE: "0x",
    PROXY_TOKEN: "0x"
  },
};
