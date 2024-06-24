import { ethers, getChainId, upgrades } from "hardhat";
import { ProofOfHumanity } from "../../typechain-types";
import { Addresses, supported } from "../consts";
import { WeiPerEther } from "ethers";

const ARBITRATOR_EXTRA_DATA =
  "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001";
const REGISTRATION_META_EVIDENCE = "/ipfs/QmZCsgcnRaDf6KM3LkUZ3o5Z7YuRCHEdxbFP7mrnFTx95v";
const CLEARING_META_EVIDENCE = "/ipfs/QmP6YTLEoyVnRTSQTcSW1NMvrp2SLGW6VadHApnFrLBYP8";
const REQUEST_BASE_DEPOSIT = WeiPerEther / 100n;
const HUMANITY_LIFESPAN = 1728000;//864000;
const RENEWAL_DURATION = 863940;
const CHALLENGE_DURATION = 3660;
const FAILED_REV_COOL_DOWN = 3600;
const SHARED_MULTIPLIER = 10000;
const WINNER_MULTIPLIER = 10000;
const LOSER_MULTIPLIER = 20000;
const NB_VOUCHES = 1;

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = +(await getChainId());

  const PoH = await ethers.getContractFactory("ProofOfHumanity", deployer);
  const poh = (await upgrades.deployProxy(PoH, [
    Addresses[chainId].W_NATIVE,
    Addresses[chainId].ARBITRATOR,
    ARBITRATOR_EXTRA_DATA,
    REGISTRATION_META_EVIDENCE,
    CLEARING_META_EVIDENCE,
    REQUEST_BASE_DEPOSIT,
    HUMANITY_LIFESPAN,
    RENEWAL_DURATION,
    FAILED_REV_COOL_DOWN,
    CHALLENGE_DURATION,
    [SHARED_MULTIPLIER, WINNER_MULTIPLIER, LOSER_MULTIPLIER],
    NB_VOUCHES,
  ] as Parameters<ProofOfHumanity["initialize"]>)) as any as ProofOfHumanity;

  console.log(`
    ProofOfHumanity deployed to:
        ${await poh.getAddress()}

        tx# ${poh.deploymentTransaction()?.hash}
  `);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
