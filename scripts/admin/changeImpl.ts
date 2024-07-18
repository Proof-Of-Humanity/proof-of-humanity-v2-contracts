
import { ethers, upgrades, getChainId, artifacts } from "hardhat";
import { Addresses } from "../consts";

async function main() {
  const [signer] = await ethers.getSigners();
  console.log(">>>>>> SIGNER: ", signer.address);
  
  const chainId = +(await getChainId());

  const artifact = await artifacts.readArtifact("ProofOfHumanity");

  const PoH = await ethers.getContractFactoryFromArtifact(artifact, signer);
  await upgrades.upgradeProxy(Addresses[chainId].POH, PoH, {redeployImplementation: 'always'});

  console.log("Done!");
}

main();

//yarn hardhat run scripts/admin/changeImpl.ts --network gnosis