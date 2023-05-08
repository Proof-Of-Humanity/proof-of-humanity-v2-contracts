import { ethers } from "hardhat";
import { ProofOfHumanityOld__factory } from "../../typechain-types";
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

  const pohold = await new ProofOfHumanityOld__factory(deployer).deploy(
    Addresses[chainId].ARBITRATOR,
    ARBITRATOR_EXTRA_DATA,
    REGISTRATION_META_EVIDENCE,
    CLEARING_META_EVIDENCE,
    REQUEST_BASE_DEPOSIT,
    HUMANITY_LIFESPAN,
    RENEWAL_DURATION,
    CHALLENGE_DURATION,
    [SHARED_MULTIPLIER, WINNER_MULTIPLIER, LOSER_MULTIPLIER],
    NB_VOUCHES
  );

  await (
    await pohold.addSubmissionManually(
      ["0x1db3439a222c519ab44bb1144fc28167b4fa6ee6", "0x00de4b13153673bcae2616b67bf822500d325fc3"],
      [
        "/ipfs/QmQ3zm9y76sPT5Qyaxfpbtmdp8LNNGPrg2CrNYqbzGFokk/registration.json",
        "/ipfs/QmPa696yBz22Mv8uHEjJJQ7jYCYbLtuJN7HTgHPe12QtaR/registration.json",
      ],
      ["Vitalik", "Kevin"]
    )
  ).wait();

  console.log(`
    ProofOfHumanityV1 deployed to:
              ${pohold.address}

    tx# ${pohold.deployTransaction.hash}`);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
