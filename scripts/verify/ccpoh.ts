import { getChainId, run } from "hardhat";
import { Addresses } from "../consts";


async function main() {
    const chainId = +(await getChainId());
    await run("verify:verify",
        {
            address: Addresses[chainId].CC_Implementation
        }
    )

    console.log("CrossChain ProofOfHumanity Implementation verified");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });