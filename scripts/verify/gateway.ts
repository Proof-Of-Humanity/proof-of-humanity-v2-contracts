import { getChainId, run } from "hardhat";
import { getRouteToConsts } from "../consts";

async function main() {
    const chainId = +(await getChainId());
    const module = await getRouteToConsts(chainId);

    await run("verify:verify",
        {
            address: module.Addresses[chainId].GATEWAY,
            constructorArguments: [
                module.FixedAddresses[chainId].MESSENGER,
                module.Addresses[chainId].CROSS_CHAIN
            ]
        }
    )

    console.log("Gateway verified");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });