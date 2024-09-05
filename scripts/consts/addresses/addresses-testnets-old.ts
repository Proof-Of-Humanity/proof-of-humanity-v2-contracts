import { AddressSet } from "../interfaces/i-sets";
import { Chain } from "../chains/chains-testnets";
import { NULL_Address } from "../../consts";

export const Addresses: Record<number, AddressSet> = {
  [Chain.CHIADO]: { // OLD
    // Complete while the corresponding scripts are executed
    POH: "0x2505C87AA36d9ed18514Ea7473Ac58aeDeb50849",
    POH_Implementation: "0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d",
    CROSS_CHAIN: "0xBEd896A3DEa0E065F05Ba83Fa63322c7b9d67838",
    CC_Implementation: "0x4a594f0e73223c9a1CE0EfC16da92fFaA193a612",
    GATEWAY: "0x56350e6827263B8521192d4979D341dA7582A996",
    LEGACY: NULL_Address,
    //PROXY_ADMIN: "0x856B71a157377dd43CCAC11430fe50d0912a46b4"
    FORK_MODULE: "0x",
    PROXY_TOKEN: "0x"
  },
  [Chain.SEPOLIA]: { // OLD
    // Complete while the corresponding scripts are executed
    POH: "0x29defF3DbEf6f79ef20d3fe4f9CFa0547acCeC0D",
    POH_Implementation: "0xa59974FDc4728178D6CdEa305228D4482146f2FD",
    CROSS_CHAIN: "0xd134748B972A320a73EfDe3AfF7a68718F6bA92c",
    CC_Implementation: "0x1b1938b88f98aac56ae6d5beeb72abd6b858061c",
    GATEWAY: "0x3787Aa5c2c03A1AC49555F84750e9503ba9A9043",
    LEGACY: "0x08Db8FD559cb4e3668f994553871c7eBa7c3941a",
    FORK_MODULE: "0x",
    PROXY_TOKEN: "0x"
  },
  /* 
  // Contracts were deployed on Gnosis instead of Chiado in the first development version of PoHv2 
  [Chain.GNOSIS]: { 
    // Complete while the corresponding scripts are executed
    POH: "0x4a594f0e73223c9a1CE0EfC16da92fFaA193a612",
    POH_Implementation: "0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d",
    CROSS_CHAIN: "0x2C692919Da3B5471F9Ac6ae1C9D1EE54F8111f76",
    CC_Implementation: "0x8363709987bbfbe241f9900eb449dcf517a80e74",
    GATEWAY: "0x0142424ce8ce5E0999e3AB794A0b608511EF90dF", 
    LEGACY: NULL_Address,
  }
  */
};
