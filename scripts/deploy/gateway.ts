import { ethers } from "hardhat";
import {
  AMBBridgeGateway__factory,
  CrossChainProofOfHumanity,
  OptimismBridgeGateway__factory,
} from "../../typechain-types";
import { Addresses, supported } from "../consts";

const FOREIGN_CC_PROXY = "0x27c9C7EC137229EEb8E22d9f03084D385b424C78";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  // const bridgeGateway = await new OptimismBridgeGateway__factory(deployer).deploy(
  const bridgeGateway = await new AMBBridgeGateway__factory(deployer).deploy(
    Addresses[chainId].MESSENGER,
    Addresses[chainId].HOME_CC
  );

  console.log(`
      Gateway deployed to:
                ${bridgeGateway.address}
  
      tx# ${bridgeGateway.deployTransaction.hash}
    `);

  const crossChainPoH = (await ethers.getContractFactory("CrossChainProofOfHumanity", deployer)).attach(
    Addresses[chainId].HOME_CC
  ) as CrossChainProofOfHumanity;
  await crossChainPoH.connect(deployer).addBridgeGateway(bridgeGateway.address, FOREIGN_CC_PROXY);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
