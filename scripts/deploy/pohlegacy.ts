import { ethers, getChainId } from "hardhat";
import { ProofOfHumanityOld__factory } from "../../typechain-types";
import { submissionAddresses, submissionNames, submissionUris } from "../consts/manualSubmissions/profiles1";
import { CLEARING_META_EVIDENCE, REGISTRATION_META_EVIDENCE, getRouteToConsts, supported } from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());

  const module = await getRouteToConsts(chainId);

  const pohold = await new ProofOfHumanityOld__factory(deployer).deploy(
    module.FixedAddresses[chainId].ARBITRATOR,
    module.InitSpecificParams.ARBITRATOR_EXTRA_DATA_MAINNET,
    REGISTRATION_META_EVIDENCE,
    CLEARING_META_EVIDENCE,
    module.InitSpecificParams.REQUEST_BASE_DEPOSIT_MAINNET,
    module.InitParams.HUMANITY_LIFESPAN,
    module.InitParams.RENEWAL_DURATION,
    module.InitParams.CHALLENGE_DURATION,
    [module.InitParams.SHARED_MULTIPLIER, module.InitParams.WINNER_MULTIPLIER, module.InitParams.LOSER_MULTIPLIER],
    module.InitParams.NB_VOUCHES
  );

  await pohold.addSubmissionManually(
    submissionAddresses,
    submissionUris,
    submissionNames
  );

  console.log(`
    ProofOfHumanityV1 deployed to:
              ${await pohold.getAddress()}

    tx# ${pohold.deploymentTransaction()?.hash}`);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
