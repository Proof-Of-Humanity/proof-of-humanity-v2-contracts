import { AddressSet } from "../interfaces/i-sets";
import { Chain } from "../chains/chains-testnets";

export const Addresses: Record<number, AddressSet> = {
  [Chain.CHIADO]: {
    // Complete while the corresponding scripts are executed
    POH: "0x2F0f39c3CF5cffc0DeACEb69d3fD883734D67687",
    POH_Implementation: "0x2cff45c3c5a5acba63a9ba4979de05c27dd2ac0d",
    CROSS_CHAIN: "0x2f33051DF37Edf2286E3b2B3c7883E1A13D82071",
    CC_Implementation: "0x4a594f0e73223c9a1ce0efc16da92ffaa193a612",
    GATEWAY: "0x52C6FC2ffFa6F984A4663Fb8781d11640803720A",
    //PROXY_ADMIN: "",

    // The following are fixed
    /* MESSENGER: FixedAddresses[Chain.CHIADO].MESSENGER,
    LEGACY: "0x",
    ARBITRATOR: FixedAddresses[Chain.CHIADO].ARBITRATOR, 
    W_NATIVE: FixedAddresses[Chain.CHIADO].W_NATIVE, */
  },
  [Chain.SEPOLIA]: {
    // Complete while the corresponding scripts are executed
    POH: "0x0D4674De96459e00A101656b799ba016fBc45dC1",
    POH_Implementation: "0xF2D1294225ee75CBf10a9bd2e9Fc35ba55E4b782",
    CROSS_CHAIN: "0xDb7070C1AE12f83E709FF22c4c51993a570FDF84",
    CC_Implementation: "0x252f5A28d26b2EfC5E28dD74E277B8f2dE7c1716",
    GATEWAY: "0xdD6c7e64D85D5aae6A09f8Ca3Bf0668B163Ac35F",
    //PROXY_ADMIN: "0x156b2D2c2f3b2767a05CB817E059ca63D3dDa420",
    
    // The following are fixed
    /* MESSENGER: FixedAddresses[Chain.SEPOLIA].MESSENGER,
    LEGACY: "0xDC605c9094cDdF2af1704c25D7D69A97a08c7E30",
    ARBITRATOR: FixedAddresses[Chain.SEPOLIA].ARBITRATOR,
    W_NATIVE: FixedAddresses[Chain.SEPOLIA].W_NATIVE, */
  }
};