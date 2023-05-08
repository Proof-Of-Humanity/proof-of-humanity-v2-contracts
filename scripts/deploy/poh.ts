import { ethers, upgrades } from "hardhat";
import { ProofOfHumanity } from "../../typechain-types";
import { Addresses, supported } from "../consts";

const ARBITRATOR_EXTRA_DATA =
  "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001";
const REGISTRATION_META_EVIDENCE =
  "/ipfs/QmXDiiBAizCPoLqHvcfTzuMT7uvFEe1j3s4TgoWWd4k5np/proof-of-humanity-registry-policy-v1.3.pdf";
const CLEARING_META_EVIDENCE =
  "/ipfs/QmXDiiBAizCPoLqHvcfTzuMT7uvFEe1j3s4TgoWWd4k5np/proof-of-humanity-registry-policy-v1.3.pdf";
const REQUEST_BASE_DEPOSIT = 100000000000000;
const HUMANITY_LIFESPAN = 10000000;
const RENEWAL_DURATION = 100000;
const CHALLENGE_DURATION = 0;
const SHARED_MULTIPLIER = 10000;
const WINNER_MULTIPLIER = 10000;
const LOSER_MULTIPLIER = 20000;
const NB_VOUCHES = 0;

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  const ProofOfHumanity = await ethers.getContractFactory("ProofOfHumanity", deployer);
  const proofOfHumanity = (await upgrades.deployProxy(ProofOfHumanity, [
    Addresses[chainId].W_NATIVE,
    Addresses[chainId].ARBITRATOR,
    ARBITRATOR_EXTRA_DATA,
    REGISTRATION_META_EVIDENCE,
    CLEARING_META_EVIDENCE,
    REQUEST_BASE_DEPOSIT,
    HUMANITY_LIFESPAN,
    RENEWAL_DURATION,
    CHALLENGE_DURATION,
    [SHARED_MULTIPLIER, WINNER_MULTIPLIER, LOSER_MULTIPLIER],
    NB_VOUCHES,
  ] as Parameters<ProofOfHumanity["initialize"]>)) as ProofOfHumanity;

  console.log(`
    ProofOfHumanity deployed to:
              ${proofOfHumanity.address}

    tx# ${proofOfHumanity.deployTransaction.hash}`);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
