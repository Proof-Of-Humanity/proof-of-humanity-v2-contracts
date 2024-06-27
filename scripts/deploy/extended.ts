import { ethers, getChainId, upgrades } from "hardhat";
import { ForkModule, ProofOfHumanityExtended } from "../../typechain-types";
import { ARBITRATOR_EXTRA_DATA, Addresses, CHALLENGE_DURATION, CLEARING_META_EVIDENCE, 
  FAILED_REV_COOL_DOWN, HUMANITY_LIFESPAN, LOSER_MULTIPLIER, NB_VOUCHES, REGISTRATION_META_EVIDENCE, 
  RENEWAL_DURATION, REQUEST_BASE_DEPOSIT, SHARED_MULTIPLIER, WINNER_MULTIPLIER, supported 
} from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());

  const PoH = await ethers.getContractFactory("ProofOfHumanityExtended", deployer);
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
  ] as Parameters<ProofOfHumanityExtended["initialize"]>)) as any as ProofOfHumanityExtended;

  console.log(`
    ProofOfHumanityExtended deployed to:
              ${await poh.getAddress()}

    tx# ${poh.deploymentTransaction()?.hash}
  `);

  const ForkMod = await ethers.getContractFactory("ForkModule", deployer);
  const forkmod = (await upgrades.deployProxy(ForkMod, [
    Addresses[chainId].LEGACY,
    await poh.getAddress(),
  ] as Parameters<ForkModule["initialize"]>)) as any as ForkModule;

  console.log("Forkmod deployed to:", await forkmod.getAddress());

  await poh.changeForkModule(await forkmod.getAddress());

  console.log("Forkmod changed to:", await forkmod.getAddress());
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
