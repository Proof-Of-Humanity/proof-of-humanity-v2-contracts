import { ethers, upgrades } from "hardhat";
import { Addresses, supported } from "../consts";
import { CrossChainProofOfHumanity, ProofOfHumanity } from "../../typechain-types";

const TRANSFER_COOLDOWN = 7;

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  const poh = (await ethers.getContractFactory("ProofOfHumanity", deployer)).attach(
    Addresses[chainId].POH
  ) as ProofOfHumanity;

  const CrossChainPoH = await ethers.getContractFactory("CrossChainProofOfHumanity", deployer);
  const crossChainPoH = (await upgrades.deployProxy(CrossChainPoH, [
    Addresses[chainId].POH,
    TRANSFER_COOLDOWN,
  ])) as CrossChainProofOfHumanity;

  console.log(`
    CrossChainProofOfHumanity deployed to:
              ${crossChainPoH.address}

    tx# ${crossChainPoH.deployTransaction.hash}
  `);

  await (await poh.connect(deployer).changeCrossChainProofOfHumanity(crossChainPoH.address)).wait();

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
