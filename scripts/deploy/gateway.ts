import { ethers, getChainId } from "hardhat";
import {
  AMBBridgeGateway,
  AMBBridgeGateway__factory,
  MockAMB__factory as CentralizedAMB__factory,
  CrossChainProofOfHumanity,
  CrossChainProofOfHumanity__factory,
} from "../../typechain-types";
import { getRouteToConsts, supported } from "../consts";
import { getForeignChain } from "../consts/chains/chains";

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

  const THIS_GATEWAY = await bridgeGateway.getAddress();
  console.log(`
    Gateway deployed to:
              ${THIS_GATEWAY}

    tx# ${bridgeGateway.deploymentTransaction()?.hash}
  `);

  const crossChainPoH = new CrossChainProofOfHumanity__factory(deployer).attach(
    module.Addresses[chainId].CROSS_CHAIN
  ) as CrossChainProofOfHumanity;

  await crossChainPoH.addBridgeGateway(THIS_GATEWAY, FOREIGN_CC_PROXY);
  console.log("Gateway added to CrossChainPoH");

  const FOREIGN_CHAIN = getForeignChain(chainId);
  const FOREIGN_GATEWAY = module.Addresses[FOREIGN_CHAIN].GATEWAY;
  if (FOREIGN_GATEWAY === "0x") {
    console.log("Foreign gateway not found. Deploy on sidechain and set it manually afterwards!");
  } else {
    await bridgeGateway.setForeignGateway(FOREIGN_GATEWAY);
    console.log("Foreign gateway has been set on this gateway");
    console.log("Looking for foreign gateway to set this gateway!");
    const foreignBridgeGateway = new AMBBridgeGateway__factory(deployer).attach(FOREIGN_GATEWAY) as AMBBridgeGateway;
    await foreignBridgeGateway.setForeignGateway(THIS_GATEWAY);
    console.log("Great! This gateway has been set on the foreign gateway as well. You are done!");
  };
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
