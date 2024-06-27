import { ethers, getChainId, upgrades } from "hardhat";
import { Addresses, TRANSFER_COOLDOWN, supported } from "../consts";
import { CrossChainProofOfHumanity, ProofOfHumanity, ProofOfHumanity__factory } from "../../typechain-types";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());

  const poh = new ProofOfHumanity__factory(deployer).attach(Addresses[chainId].POH) as ProofOfHumanity;

  const CrossChainPoH = await ethers.getContractFactory("CrossChainProofOfHumanity", deployer);
  const crossChainPoH = (await upgrades.deployProxy(CrossChainPoH, [
    Addresses[chainId].POH,
    TRANSFER_COOLDOWN,
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
