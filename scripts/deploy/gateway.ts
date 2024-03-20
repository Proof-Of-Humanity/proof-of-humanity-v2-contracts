import { ethers, getChainId } from "hardhat";
import {
  AMBBridgeGateway__factory,
  MockAMB__factory as CentralizedAMB__factory,
  CrossChainProofOfHumanity,
  CrossChainProofOfHumanity__factory,
} from "../../typechain-types";
import { Addresses, Chain, supported } from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId()) as Chain;

  const FOREIGN_CC_PROXY =
    chainId === Chain.GNOSIS ? Addresses[Chain.SEPOLIA].CROSS_CHAIN : Addresses[Chain.GNOSIS].CROSS_CHAIN;

  var messengerAddress = Addresses[chainId].MESSENGER;
  // If the messenger was deployed before we must have its corresponding address in Addresses[chainId].MESSENGER, 
  // otherwise we need to do a deployment of the messenger and use that address for deploying the bridge.
  if (Addresses[chainId].MESSENGER === "0x") {
    const amb = await new CentralizedAMB__factory(deployer).deploy();
    messengerAddress = await amb.getAddress();
    
    console.log(`
    CentralizedAMB deployed to: ${messengerAddress}

      tx# ${amb.deploymentTransaction()?.hash}
    `);
  }

  const bridgeGateway = await new AMBBridgeGateway__factory(deployer).deploy(
    messengerAddress,
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
