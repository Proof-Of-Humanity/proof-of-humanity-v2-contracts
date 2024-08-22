import { ethers, getChainId, upgrades } from "hardhat";
import { ForkModule, ProofOfHumanityExtended, ProofOfHumanityExtended__factory } from "../../typechain-types";
import { getRouteToConsts, supported } from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());

  const module = await getRouteToConsts(chainId);

  const poh = new ProofOfHumanityExtended__factory(deployer).attach(module.Addresses[chainId].POH) as ProofOfHumanityExtended;

  
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
