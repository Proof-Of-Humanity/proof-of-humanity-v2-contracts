import { getChainId, run } from "hardhat";
import { Addresses } from "../consts";

// Shouldn't be used unless verifying MockAMB.
// AMB mediators should provide the corresponding contract addresses

async function main() {
    const chainId = +(await getChainId());

    await run("verify:verify",
        {
            address: Addresses[chainId].MESSENGER
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