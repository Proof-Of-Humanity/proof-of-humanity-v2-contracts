import { formatEther, parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import {
  AMBBridgeGateway,
  CrossChainProofOfHumanity,
  ForkModule,
  OptimismBridgeGateway,
  ProofOfHumanity,
  ProofOfHumanityExtended,
  ProofOfHumanityOld,
} from "../typechain-types";
import { Addresses, supported } from "./consts";

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  console.log(`
      Deployer:  ${deployer.address}
      Chain:  ${chainId}
      Balance:   ${formatEther(await deployer.getBalance())} ETH
      Current time: ${(await ethers.provider.getBlock("latest")).timestamp}`);

  // const forkmod = (await ethers.getContractAt(
  //   "ForkModule",
  //   "0x7cd725c8770a602e25cda4bce01e648a3dbcfe3c"
  // )) as ForkModule;
  // console.log("REMOVAL READY", await forkmod.removalReady("0x00de4b13153673bcae2616b67bf822500d325fc3"));

  // const poh = (await ethers.getContractAt(
  //   "ProofOfHumanityExtended",
  //   "0x1B3dE9B7929870e66F8F7FBe8868622Ed3bB0C7c"
  // )) as ProofOfHumanity;
  // const poh = (await ethers.getContractAt(
  //   "ProofOfHumanityExtended",
  //   "0x1B3dE9B7929870e66F8F7FBe8868622Ed3bB0C7c"
  // )) as ProofOfHumanity;
  // // await (await poh.changeDurations(10000000, 100000, 0)).wait();
  // console.log({ challengePeriodDuration: (await poh.challengePeriodDuration()).toNumber() });
  // console.log({ humanityLifespan: (await poh.humanityLifespan()).toNumber() });
  // console.log({ renewalPeriodDuration: (await poh.renewalPeriodDuration()).toNumber() });

  // const gateway = (await ethers.getContractAt(
  //   "AMBBridgeGateway",
  //   "0x10908D725aFC06E8a50e11E3c822A978c0FdbE43"
  // )) as OptimismBridgeGateway;
  // await (await gateway.setForeignGateway("0xB6fd61353B1E32Ae1fBF84A9A9639aFD82DB3499")).wait();

  const poh = (await ethers.getContractAt(
    "ProofOfHumanityExtended",
    "0x1B3dE9B7929870e66F8F7FBe8868622Ed3bB0C7c"
  )) as ProofOfHumanityExtended;
  console.log(
    "AAAAAAAAAAAAAAAAAAAAHHH",
    await poh.getHumanityInfo("0x1db3439a222c519ab44bb1144fc28167b4fa6ee6"),
    await poh.getHumanityInfo("0x00de4b13153673bcae2616b67bf822500d325fc3")
  );

  // const ccpoh = (await ethers.getContractAt(
  //   "CrossChainProofOfHumanity",
  //   Addresses[chainId].HOME_CC
  // )) as CrossChainProofOfHumanity;

  // await ccpoh.removeBridgeGateway("0x7eb9d435cec5a254f1033a63c474a97cbbcdf01a");

  // console.log(await gateway.foreignMessenger("0xE4885BDd3dbCa86Bca7A55c0D24F73Bc2A3069EA"));
  // console.log(await gateway.homeProxy("0xE4885BDd3dbCa86Bca7A55c0D24F73Bc2A3069EA"));
  // console.log(await gateway.homeProxy("0xE4885BDd3dbCa86Bca7A55c0D24F73Bc2A3069EA"));

  // console.log(await poh.isHuman("0x00de4b13153673bcae2616b67bf822500d325fc3"));
  // console.log(
  //   ">>> GAS GAS GAS <<<",
  //   await poh.estimateGas.revokeHumanity("0x00de4b13153673bcae2616b67bf822500d325fc3", "gg", {
  //     value: parseEther("0.02"),
  //   })
  // );

  // const ccPoH = (await ethers.getContractAt(
  //   "CrossChainProofOfHumanity",
  //   Addresses[chainId].HOME_CC
  // )) as CrossChainProofOfHumanity;
  // const opGateway = (await ethers.getContractAt(
  //   "OptimismBridgeGateway",
  //   Addresses[chainId].GATEWAY
  // )) as OptimismBridgeGateway;

  // await (await opGateway.initialize(Addresses[chainId].MESSENGER, ccPoH.address)).wait();
  // await (await ccPoH.addBridgeGateway(Addresses[chainId].GATEWAY, Addresses[chainId].FOREIGN_CC)).wait();
}

// async function main() {
//   const [deployer] = await ethers.getSigners();

//   console.log(`
//     Deployer:  ${deployer.address}
//     Balance:   ${formatEther(await deployer.getBalance())} ETH
//     Current time: ${(await ethers.provider.getBlock("latest")).timestamp}`);

//   const poh = (await ethers.getContractAt("ProofOfHumanity", POH_ADDRESS)) as ProofOfHumanity;

//   console.log(`
//     Soul Lifespan:              ${await poh.humanityLifespan()}
//     Request Base Deposit:       ${await poh.requestBaseDeposit()}
//     Required Number Of Vouches: ${await poh.requiredNumberOfVouches()}`);

//   // const tx = await poh
//   //   .connect(deployer)
//   //   ["claimSoul(uint160,string,string)"](
//   //     3,
//   //     "/ipfs/Qmd3j4yeiBjVLDLq4qxsVUjqob8nhckAM6JrvMFvTxwBwa/registration.json",
//   //     "Test",
//   //     {
//   //       value: ethers.utils.parseEther("0.01"),
//   //     }
//   //   );

//   // let tx = await poh.connect(deployer).changeRequestBaseDeposit(100000000000000);

//   await (await poh.connect(deployer).changeRequiredNumberOfVouches(0)).wait();
//   await (await poh.connect(deployer).changeDurations(10000000, 12000, 0)).wait();

//   // let contr = await poh.getContributions(3, 1, 0, 0, "0xc27519cb10d7d921d7e50926577ce0807e8e6438");
//   // console.log(contr.forRequester.toString(), contr.forChallenger.toString());

//   // contr = await poh.getContributions(3, 0, 0, 0, "0xc27519cb10d7d921d7e50926577ce0807e8e6438");
//   // console.log(contr.forRequester.toString(), contr.forChallenger.toString());

//   // const tx2 = await poh
//   //   .connect(deployer)
//   //   .changeArbitrator(
//   //     "0x9de81cf9b4b46046c1a87fdc71ae55566919be64",
//   //     "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
//   //   );
//   // await tx2.wait();

//   //   console.log(await poh.requiredNumberOfVouches());
//   //   console.log(await poh.requestBaseDeposit());
//   //   console.log(await poh.soulLifespan());

//   //   console.log(`
//   //     Soul Claimed:     ${await poh.isSoulClaimed(3)}
//   //     Registered:       ${await poh.isRegistered(deployer.address)}`);

//   //   console.log(await poh.getSoulInfo(3));
// }

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
