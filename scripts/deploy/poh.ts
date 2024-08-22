import { ethers, getChainId, upgrades } from "hardhat";
import { ProofOfHumanity } from "../../typechain-types";
import { CLEARING_META_EVIDENCE, REGISTRATION_META_EVIDENCE, getRouteToConsts, supported } from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());

  const module = await getRouteToConsts(chainId);
  
  const PoH = await ethers.getContractFactory("ProofOfHumanity", deployer);
  const poh = (await upgrades.deployProxy(PoH, [
    module.FixedAddresses[chainId].W_NATIVE,
    module.FixedAddresses[chainId].ARBITRATOR,
    module.InitParams.ARBITRATOR_EXTRA_DATA,
    REGISTRATION_META_EVIDENCE,
    CLEARING_META_EVIDENCE,
    module.InitParams.REQUEST_BASE_DEPOSIT_SIDECHAIN,
    module.InitParams.HUMANITY_LIFESPAN,
    module.InitParams.RENEWAL_DURATION,
    module.InitParams.FAILED_REV_COOL_DOWN,
    module.InitParams.CHALLENGE_DURATION,
    [module.InitParams.SHARED_MULTIPLIER, module.InitParams.WINNER_MULTIPLIER, module.InitParams.LOSER_MULTIPLIER],
    module.InitParams.NB_VOUCHES,
  ] as Parameters<ProofOfHumanity["initialize"]>)) as any as ProofOfHumanity;

  console.log(`
    ProofOfHumanity deployed to:
        ${await poh.getAddress()}

        tx# ${poh.deploymentTransaction()?.hash}
  `);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
