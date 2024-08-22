
import { ethers, upgrades, getChainId, artifacts } from "hardhat";
import { getRouteToConsts } from "../consts";

async function main() {
  const [signer] = await ethers.getSigners();
  console.log(">>>>>> SIGNER: ", signer.address);
  
  const chainId = +(await getChainId());
  const module = await getRouteToConsts(chainId);

  const artifact = await artifacts.readArtifact("ProofOfHumanity");

  const PoH = await ethers.getContractFactoryFromArtifact(artifact, signer);
  await upgrades.upgradeProxy(module.Addresses[chainId].POH, PoH, {redeployImplementation: 'always'});

  console.log("Done!");
}

main();

//yarn hardhat run scripts/admin/changeImpl.ts --network gnosis