import { ethers, getChainId } from "hardhat";
import { ProofOfHumanityProxyV2, ProofOfHumanityProxyV2__factory } from "../../typechain-types";
import { getRouteToConsts, supported } from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());

  const module = await getRouteToConsts(chainId);

  const pohProxyToken = await new ProofOfHumanityProxyV2__factory(deployer).deploy(
    module.Addresses[chainId].POH
  ) as ProofOfHumanityProxyV2;

  console.log(`
    ProofOfHumanityProxy (token interface) deployed to:
              ${await pohProxyToken.getAddress()}

    tx# ${pohProxyToken.deploymentTransaction()?.hash}
  `);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
