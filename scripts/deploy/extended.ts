import { ethers, upgrades } from "hardhat";
import { ForkModule, ForkModule__factory, ProofOfHumanityExtended } from "../../typechain-types";
import { Addresses, supported } from "../consts";

const PROOF_OF_HUMANITY_OLD = "0x7d6e406af4FD2f7add280c24418721C374aB8663";
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

  const PoH = await ethers.getContractFactory("ProofOfHumanityExtended", deployer);
  const poh = (await upgrades.deployProxy(PoH, [
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
  ] as Parameters<ProofOfHumanityExtended["initialize"]>)) as ProofOfHumanityExtended;

  const ForkMod = await ethers.getContractFactory("ForkModule", deployer);
  const forkmod = (await upgrades.deployProxy(ForkMod, [poh.address, PROOF_OF_HUMANITY_OLD] as Parameters<
    ForkModule["initialize"]
  >)) as ForkModule;

  await (await poh.changeForkModule(forkmod.address)).wait();

  console.log("ProofOfHumanityExtended deployed to:", poh.address);

  console.log(`
    ProofOfHumanityExtended deployed to:
              ${poh.address}

    tx# ${poh.deployTransaction.hash}
  `);
}

supported()
  .then(main)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
