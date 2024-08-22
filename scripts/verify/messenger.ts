import { getChainId, run } from "hardhat";
import { getRouteToConsts } from "../consts";

// Shouldn't be used unless verifying MockAMB.
// AMB mediators should provide the corresponding contract addresses

async function main() {
    const chainId = +(await getChainId());
    const module = await getRouteToConsts(chainId);

    await run("verify:verify",
        {
            address: module.FixedAddresses[chainId].MESSENGER
        }
    )

    console.log("Messenger verified");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });