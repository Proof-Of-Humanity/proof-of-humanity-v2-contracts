import { getProxyAdminFactory } from "@openzeppelin/hardhat-upgrades/dist/utils";
import { ethers } from "hardhat";
import hre from "hardhat";

async function main() {
    const [signer] = await ethers.getSigners();
    const Contract = await ethers.getContractAt("ProofOfHumanity", "0xB6412c84eC958cafcC80B688d6F473e399be488f");
    const connectedContract = Contract.connect(signer);
    const admin = connectedContract.attach("0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d");
    
    /* const adminFactory = await getProxyAdminFactory(hre, signer);
    const contractNew = adminFactory.attach("0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d"); */
    /* const contract = Contract.attach("0x2CfF45C3C5A5ACbA63a9BA4979de05c27dd2AC0d"); */
    /* const result = await contract.myFunction(); */
    /* console.log(result); */
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
  