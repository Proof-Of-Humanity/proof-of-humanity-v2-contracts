import { ethers, getChainId } from "hardhat";
import {
  AMBBridgeGateway__factory,
  MockAMB__factory as CentralizedAMB__factory,
  CrossChainProofOfHumanity,
  CrossChainProofOfHumanity__factory,
} from "../../typechain-types";
import { getRouteToConsts, supported } from "../consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());
  const module = await getRouteToConsts(chainId);

  const FOREIGN_CC_PROXY = module.getForeignCCProxy(chainId);
  var messengerAddress = module.FixedAddresses[chainId].MESSENGER; 
  // Address of the AMB mediator (ETH-GNO only) specified in Addresses[chainId].MESSENGER
  // If no address is found the centralized AMB (Mock) will be deployed and its address used for deploying the AMB bridge afterwards.
  if (module.FixedAddresses[chainId].MESSENGER === "0x") {
    const amb = await new CentralizedAMB__factory(deployer).deploy();
    messengerAddress = await amb.getAddress();
    
    console.log(`
    CentralizedAMB deployed to: ${messengerAddress}

      tx# ${amb.deploymentTransaction()?.hash}
    `);
  }

  const bridgeGateway = await new AMBBridgeGateway__factory(deployer).deploy(
    messengerAddress,
    module.Addresses[chainId].CROSS_CHAIN
  );

  console.log(`
    Gateway deployed to:
              ${await bridgeGateway.getAddress()}

    tx# ${bridgeGateway.deploymentTransaction()?.hash}
  `);

  const crossChainPoH = new CrossChainProofOfHumanity__factory(deployer).attach(
    module.Addresses[chainId].CROSS_CHAIN
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
