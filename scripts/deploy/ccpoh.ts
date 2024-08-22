import { ethers, getChainId, upgrades } from "hardhat";
import { CrossChainProofOfHumanity, ProofOfHumanity, ProofOfHumanity__factory } from "../../typechain-types";
import { getRouteToConsts, supported } from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());
  const module = await getRouteToConsts(chainId);

  const poh = new ProofOfHumanity__factory(deployer).attach(module.Addresses[chainId].POH) as ProofOfHumanity;

  const CrossChainPoH = await ethers.getContractFactory("CrossChainProofOfHumanity", deployer);
  const crossChainPoH = (await upgrades.deployProxy(CrossChainPoH, [
    module.Addresses[chainId].POH,
    module.InitParams.TRANSFER_COOLDOWN,
  ])) as any as CrossChainProofOfHumanity;

  console.log(`
    CrossChainProofOfHumanity deployed to:
              ${await crossChainPoH.getAddress()}

    tx# ${crossChainPoH.deploymentTransaction()?.hash}
  `);

  await poh.changeCrossChainProofOfHumanity(await crossChainPoH.getAddress());

  console.log(`
    CrossChain changed:
              ${await poh.crossChainProofOfHumanity()}
  `);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
