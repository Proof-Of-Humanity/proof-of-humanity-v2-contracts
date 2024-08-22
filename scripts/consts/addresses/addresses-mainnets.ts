import { AddressSet } from "../interfaces/i-sets";
import { Chain } from "../chains/chains-mainnets";
import { NULL_Address, POH_V1_Address } from "../../consts";

export const Addresses: Record<number, AddressSet> = {
  [Chain.MAINNET]: {
    // Complete while the corresponding scripts are executed
    POH: NULL_Address,
    POH_Implementation: NULL_Address,
    CROSS_CHAIN: NULL_Address,
    CC_Implementation: NULL_Address,
    GATEWAY: NULL_Address,
    LEGACY: POH_V1_Address,
    //PROXY_ADMIN: "",
    //FORK_MODULE: NULL_Address,
  },
  [Chain.GNOSIS]: {
    // Complete while the corresponding scripts are executed
    POH: NULL_Address,
    POH_Implementation: NULL_Address,
    CROSS_CHAIN: NULL_Address,
    CC_Implementation: NULL_Address,
    GATEWAY: NULL_Address,
    LEGACY: NULL_Address,
    //PROXY_ADMIN: ""
  },
};
