import { Chain as ChainTestnets, SUPPORTED_NETWORKS as SUPPORTED_NETWORKS_TESTNETS } from "./chains-testnets";
import { Chain as ChainMainnets, SUPPORTED_NETWORKS as SUPPORTED_NETWORKS_MAINNETS } from "./chains-mainnets";

export const SUPPORTED_NETWORKS = 
[
    ...SUPPORTED_NETWORKS_TESTNETS,
    ...SUPPORTED_NETWORKS_MAINNETS
]

export const isTestnet = (chainId: number) => {
    if (chainId == ChainTestnets.CHIADO || chainId == ChainTestnets.SEPOLIA)
        return true;
    else if (chainId == ChainMainnets.MAINNET || chainId == ChainMainnets.GNOSIS)
        return false;
    else throw new Error("Network not supported");
};
