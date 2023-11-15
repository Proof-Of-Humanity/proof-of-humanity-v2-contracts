import { ethers, getChainId } from "hardhat";
import {
  AMBBridgeGateway__factory,
  CentralizedAMB__factory,
  CrossChainProofOfHumanity,
  CrossChainProofOfHumanity__factory,
} from "../../typechain-types";
import { Addresses, Chain, supported } from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId()) as Chain;

  const FOREIGN_CC_PROXY =
    chainId === Chain.GNOSIS ? Addresses[Chain.SEPOLIA].CROSS_CHAIN : Addresses[Chain.GNOSIS].CROSS_CHAIN;

  const amb = await new CentralizedAMB__factory(deployer).deploy();

  console.log(`
  CentralizedAMB deployed to:
              ${await amb.getAddress()}

    tx# ${amb.deploymentTransaction()?.hash}
  `);

  const bridgeGateway = await new AMBBridgeGateway__factory(deployer).deploy(
    // Addresses[chainId].MESSENGER,
    await amb.getAddress(),
    Addresses[chainId].CROSS_CHAIN
  );

  console.log(`
    Gateway deployed to:
              ${await bridgeGateway.getAddress()}

    tx# ${bridgeGateway.deploymentTransaction()?.hash}
  `);

  const crossChainPoH = new CrossChainProofOfHumanity__factory(deployer).attach(
    Addresses[chainId].CROSS_CHAIN
  ) as CrossChainProofOfHumanity;

  await crossChainPoH.addBridgeGateway(await bridgeGateway.getAddress(), FOREIGN_CC_PROXY);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
