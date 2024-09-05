import { AddressSet } from "../interfaces/i-sets";
import { Chain } from "../chains/chains-mainnets";
import { NULL_Address, POH_V1_Address } from "../../consts";

export const Addresses: Record<number, AddressSet> = {
  [Chain.MAINNET]: {
    // Complete while the corresponding scripts are executed
    POH: "0x6cbEdC1920090EA4F28A38C1CD61c8D37b2cc323",
    POH_Implementation: "0xe6573F65efAbc351b69F9b73ed8e95772698938b",
    CROSS_CHAIN: "0xD6F4E9d906CD7736a83e0AFa7EE9491658B4afA7",
    CC_Implementation: "0x064B1132D9A9c43Df269FeAD9e80c195Fb9cd916",
    GATEWAY: "0xb89D480e56Fe4915466eAbE64733adb6EfEfFc81",
    LEGACY: POH_V1_Address,
    //PROXY_ADMIN: "",
    FORK_MODULE: "0xcA4E378D1815790c0d160e2cEcb8011903DD0555",
    PROXY_TOKEN: "0x"
  },
  [Chain.GNOSIS]: {
    // Complete while the corresponding scripts are executed
    POH: "0xe6573F65efAbc351b69F9b73ed8e95772698938b",
    POH_Implementation: "0xf183073784092ce088f85Ec74d3841ACe8Ba0609", // upgradedProxy reference to this implementation
    //POH_Implementation: "0xF230c60C40D70a6AE8Bd20c92243A1Cf67c6C2A7", // Old implementation (Unverified) triggered by the contractFactory
    CROSS_CHAIN: "0x6cbEdC1920090EA4F28A38C1CD61c8D37b2cc323",
    CC_Implementation: "0xc664a8d43601109fc50f3bcf22f29e9119ab2f6d",
    GATEWAY: "0xcA4E378D1815790c0d160e2cEcb8011903DD0555",
    LEGACY: NULL_Address,
    //PROXY_ADMIN: ""
    FORK_MODULE: "0x",
    PROXY_TOKEN: "0x"
  },
};
