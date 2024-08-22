import { ethers, getChainId, upgrades } from "hardhat";
import { ForkModule, ProofOfHumanityExtended } from "../../typechain-types";
import { CLEARING_META_EVIDENCE, REGISTRATION_META_EVIDENCE, getRouteToConsts, supported } from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());

  const module = await getRouteToConsts(chainId);

  const PoH = await ethers.getContractFactory("ProofOfHumanityExtended", deployer);
  const poh = (await upgrades.deployProxy(PoH, [
    module.FixedAddresses[chainId].W_NATIVE,
    module.FixedAddresses[chainId].ARBITRATOR,
    module.InitParams.ARBITRATOR_EXTRA_DATA,
    REGISTRATION_META_EVIDENCE,
    CLEARING_META_EVIDENCE,
    module.InitParams.REQUEST_BASE_DEPOSIT_MAINNET,
    module.InitParams.HUMANITY_LIFESPAN,
    module.InitParams.RENEWAL_DURATION,
    module.InitParams.FAILED_REV_COOL_DOWN,
    module.InitParams.CHALLENGE_DURATION,
    [module.InitParams.SHARED_MULTIPLIER, module.InitParams.WINNER_MULTIPLIER, module.InitParams.LOSER_MULTIPLIER],
    module.InitParams.NB_VOUCHES,
  ] as Parameters<ProofOfHumanityExtended["initialize"]>)) as any as ProofOfHumanityExtended;

  console.log(`
    ProofOfHumanityExtended deployed to:
              ${await poh.getAddress()}

    tx# ${poh.deploymentTransaction()?.hash}
  `);

  const ForkMod = await ethers.getContractFactory("ForkModule", deployer);
  const forkmod = (await upgrades.deployProxy(ForkMod, [
    module.Addresses[chainId].LEGACY,
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
