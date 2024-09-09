import { AddressSet } from "../interfaces/i-sets";
import { Chain } from "../chains/chains-mainnets";
import { NULL_Address, POH_V1_Address } from "../../consts";

export const Addresses: Record<number, AddressSet> = {
  [Chain.MAINNET]: {
    // Complete while the corresponding scripts are executed
    POH: "0xbE9834097A4E97689d9B667441acafb456D0480A",
    POH_Implementation: "0x9EcDfADA6376D221Ed1513c9F52cC44a39E89657",
    CROSS_CHAIN: "0xa478095886659168E8812154fB0DE39F103E74b2",
    CC_Implementation: "0x7BBf4551E1324CE7F87050377aE3EF645F08DBfd",
    GATEWAY: "0xddafACf8B4a5087Fc89950FF7155c76145376c1e",
    LEGACY: POH_V1_Address, // Fixed
    //PROXY_ADMIN: "0x546bd92b3cDbf2000746a513B96659c926445c50",
    //PROXY_ADMIN_CC: "0x91b3Cb9e5A276ede97C3EE6088d5956DD01BcaA2",
    FORK_MODULE: "0x068a27Db9c3B8595D03be263d52c813cb2C99cCB",
    //FORK_Implementation: "0xfd6a2eDAeef62E9cd828053fdd0d944Ff04a4f66",
    //FORK_ADMIN: "0x6DeD4EBAaB8011F8cbf223bb36B82bcDd363179C",
    PROXY_TOKEN: "0xf39F77AC0c0a009ad26572451267eCbD74F9c79c"
  },
  [Chain.GNOSIS]: {
    // Complete while the corresponding scripts are executed
    POH: "0xa4AC94C4fa65Bb352eFa30e3408e64F72aC857bc",
    POH_Implementation: "0x85B88E38FB6cbc8059009902F76C47f902373F52",
    CROSS_CHAIN: "0x16044E1063C08670f8653055A786b7CC2034d2b0",
    CC_Implementation: "0x20C27AB7863dC31CEaBd300Fa2787B723D490162",
    GATEWAY: "0x6Ef5073d79c42531352d1bF5F584a7CBd270c6B1",
    LEGACY: NULL_Address, // Fixed
    //PROXY_ADMIN: "0xdEF33793a7924f876b20BE435Da5C234CE60a437",
    //PROXY_ADMIN_CC: "0x35eC1E9abb85365520CA0F099859064CE1678094",
    FORK_MODULE: "0x",
    PROXY_TOKEN: "0xfD01A2067b35A5f2aa3d5785fDcbb6f945a3a0Ab"
  },
};
