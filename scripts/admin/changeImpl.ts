import { ethers, upgrades, getChainId } from "hardhat";
import { Addresses } from "../consts";

async function main() {
    /* const [signer] = await ethers.getSigners();
    console.log(">>>>>> ", signer); */
  const chainId = +(await getChainId());
  const PoH = await ethers.getContractFactory("ProofOfHumanity");
  await upgrades.validateImplementation(PoH);
  const deployment = await upgrades.forceImport(Addresses[chainId].POH, PoH);
  /* await upgrades.prepareUpgrade(Addresses[chainId].POH, PoH); */
  //await upgrades.upgradeProxy(Addresses[chainId].POH, PoH);
  console.log("PoH upgraded");
}

main();