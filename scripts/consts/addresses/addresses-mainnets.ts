import { AddressSet } from "../interfaces/i-sets";
import { Chain } from "../chains/chains-mainnets";

export const Addresses: Record<number, AddressSet> = {
  [Chain.MAINNET]: {
    // Complete while the corresponding scripts are executed
    POH: "0x",
    POH_Implementation: "0x",
    CROSS_CHAIN: "0x",
    CC_Implementation: "0x",
    GATEWAY: "0x",
    //PROXY_ADMIN: "",
    //FORK_MODULE: "0x",

    /* // The following are fixed
    MESSENGER: FixedAddressesMainnets[Chain.MAINNET].MESSENGER,
    LEGACY: POH_V1,
    ARBITRATOR: FixedAddressesMainnets[Chain.MAINNET].ARBITRATOR,
    W_NATIVE: FixedAddressesMainnets[Chain.MAINNET].W_NATIVE, */
  },
  [Chain.GNOSIS]: {
    // Complete while the corresponding scripts are executed
    POH: "0x",
    POH_Implementation: "0x",
    CROSS_CHAIN: "0x",
    CC_Implementation: "0x",
    GATEWAY: "0x",
    //PROXY_ADMIN: "",

    /* // The following are fixed
    MESSENGER: FixedAddressesMainnets[Chain.GNOSIS].MESSENGER,
    LEGACY: "0x",
    ARBITRATOR: FixedAddressesMainnets[Chain.GNOSIS].ARBITRATOR,
    W_NATIVE: FixedAddressesMainnets[Chain.GNOSIS].W_NATIVE, */
  },
};
