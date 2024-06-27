import { ethers, getChainId, upgrades } from "hardhat";
import { ProofOfHumanity } from "../../typechain-types";
import { ARBITRATOR_EXTRA_DATA, Addresses, CHALLENGE_DURATION, CLEARING_META_EVIDENCE, 
  FAILED_REV_COOL_DOWN, HUMANITY_LIFESPAN, LOSER_MULTIPLIER, NB_VOUCHES, REGISTRATION_META_EVIDENCE, 
  RENEWAL_DURATION, REQUEST_BASE_DEPOSIT, SHARED_MULTIPLIER, WINNER_MULTIPLIER, supported 
} from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());

  const PoH = await ethers.getContractFactory("ProofOfHumanity", deployer);
  const poh = (await upgrades.deployProxy(PoH, [
    Addresses[chainId].W_NATIVE,
    Addresses[chainId].ARBITRATOR,
    ARBITRATOR_EXTRA_DATA,
    REGISTRATION_META_EVIDENCE,
    CLEARING_META_EVIDENCE,
    REQUEST_BASE_DEPOSIT,
    HUMANITY_LIFESPAN,
    RENEWAL_DURATION,
    FAILED_REV_COOL_DOWN,
    CHALLENGE_DURATION,
    [SHARED_MULTIPLIER, WINNER_MULTIPLIER, LOSER_MULTIPLIER],
    NB_VOUCHES,
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
