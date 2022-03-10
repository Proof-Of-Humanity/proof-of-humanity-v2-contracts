import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { HashZero } from "@ethersproject/constants";
import { ethers } from "hardhat";
import {
  MockAMB,
  MockAMB__factory,
  MockArbitrator,
  MockArbitrator__factory,
  ProofOfHumanity,
  ProofOfHumanityBridgeProxy,
  ProofOfHumanityBridgeProxy__factory,
  ProofOfHumanity__factory,
} from "../typechain-types";
import { expectRevert, getCurrentTimestamp, increaseTime } from "../utils/test-helpers";
import { BigNumber } from "ethers";

let [mainChainID, sideChainID] = [HashZero, HashZero];

let amb: MockAMB;
let arbitrator: MockArbitrator;
let [mainPoH, sidePoH]: ProofOfHumanity[] = [];
let [mainBridgeProxy, sideBridgeProxy]: ProofOfHumanityBridgeProxy[] = [];

let [governor, alice, bob, eve, jack, mike, robert]: SignerWithAddress[] = [];

const arbitratorExtraData = "0x85";
const submissionBaseDeposit = 5000;
const arbitrationCost = 1000;
const submissionDuration = 86400;
const challengePeriodDuration = 600;
const renewalPeriodDuration = 6000;
const nbVouches = 2;

const appealTimeOut = 180;

const sharedStakeMultiplier = 5000;
const winnerStakeMultiplier = 2000;
const loserStakeMultiplier = 8000;

const requesterTotalCost = BigNumber.from(arbitrationCost + submissionBaseDeposit);

const registrationMetaEvidence = "registrationMetaEvidence.json";
const clearingMetaEvidence = "clearingMetaEvidence.json";

let startingTimestamp: number;

describe("ProofOfHumanityBridgeProxy", () => {
  beforeEach("Initializing the contracts", async () => {
    [governor, alice, bob, eve, jack, mike, robert] = await ethers.getSigners();

    arbitrator = await new MockArbitrator__factory(governor).deploy(
      arbitrationCost,
      governor.address,
      arbitratorExtraData,
      appealTimeOut
    );

    await arbitrator.changeArbitrator(arbitrator.address);
    await arbitrator.connect(robert).createDispute(3, arbitratorExtraData, { value: arbitrationCost }); // Create a dispute so the index in tests will not be a default value.

    amb = await new MockAMB__factory(governor).deploy();
    mainPoH = await new ProofOfHumanity__factory(governor).deploy(
      arbitrator.address,
      arbitratorExtraData,
      registrationMetaEvidence,
      clearingMetaEvidence,
      submissionBaseDeposit,
      submissionDuration,
      renewalPeriodDuration,
      challengePeriodDuration,
      [sharedStakeMultiplier, winnerStakeMultiplier, loserStakeMultiplier],
      nbVouches
    );
    sidePoH = await new ProofOfHumanity__factory(governor).deploy(
      arbitrator.address,
      arbitratorExtraData,
      registrationMetaEvidence,
      clearingMetaEvidence,
      submissionBaseDeposit,
      submissionDuration,
      renewalPeriodDuration,
      challengePeriodDuration,
      [sharedStakeMultiplier, winnerStakeMultiplier, loserStakeMultiplier],
      nbVouches
    );
    mainBridgeProxy = await new ProofOfHumanityBridgeProxy__factory(governor).deploy(amb.address, mainPoH.address);
    sideBridgeProxy = await new ProofOfHumanityBridgeProxy__factory(governor).deploy(amb.address, sidePoH.address);

    await mainBridgeProxy.setForeignProxy(sideBridgeProxy.address, mainChainID);
    await sideBridgeProxy.setForeignProxy(mainBridgeProxy.address, sideChainID);

    startingTimestamp = await getCurrentTimestamp();

    await mainPoH.connect(governor).addSubmissionManually(alice.address, startingTimestamp);
    await mainPoH.connect(governor).addSubmissionManually(bob.address, startingTimestamp);

    await sidePoH.connect(governor).addSubmissionManually(eve.address, startingTimestamp);
    await sidePoH.connect(governor).addSubmissionManually(jack.address, startingTimestamp);
    await sidePoH.connect(governor).addSubmissionManually(mike.address, startingTimestamp);

    // console.log({ gov: governor.address, mainPoH: await mainPoH.governor() });
    await mainPoH.connect(governor).changeGovernor(mainBridgeProxy.address);
    await sidePoH.connect(governor).changeGovernor(sideBridgeProxy.address);
  });

  it("Should initiate values correctly", async () => {
    expect(await mainBridgeProxy.governor()).to.equal(governor.address);
    expect(await mainBridgeProxy.amb()).to.equal(amb.address);
    expect(await mainBridgeProxy.proofOfHumanity()).to.equal(mainPoH.address);
    expect(await mainBridgeProxy.foreignChainID()).to.equal(mainChainID);
    expect(await mainBridgeProxy.foreignProxy()).to.equal(sideBridgeProxy.address);

    expect(await mainPoH.submissionCounter()).to.equal(2);
    expect(await sidePoH.submissionCounter()).to.equal(3);

    expect(await mainPoH.governor()).to.equal(mainBridgeProxy.address);
    expect(await sidePoH.governor()).to.equal(sideBridgeProxy.address);

    expect(await mainPoH.isRegistered(alice.address)).to.be.true;
    expect(await mainPoH.isRegistered(jack.address)).to.be.false;
  });

  it("Should only allow authorized AMB", async () => {
    await expectRevert(sideBridgeProxy.receiveSubmissionUpdate(bob.address, true), "Only the AMB allowed");
    await expectRevert(
      mainBridgeProxy.receiveSubmissionTransfer(
        mike.address,
        (
          await mainPoH.getSubmissionInfo(mike.address)
        ).submissionTime
      ),
      "Only the AMB allowed"
    );
  });

  it("Should update submissions status to the foreign proxy", async () => {
    await expectRegistered(jack).on({ main: false, side: true });
    await sideBridgeProxy.updateSubmission(jack.address);
    await expectRegistered(jack).on({ main: true, side: true });

    await expectRegistered(alice).on({ main: true, side: false });
    await mainBridgeProxy.updateSubmission(alice.address);
    await expectRegistered(alice).on({ side: true });
  });

  it("Should not allow to update/transfer submissions from a non-primary chain", async () => {
    await expectRevert(mainBridgeProxy.updateSubmission(jack.address), "Must update from primary chain");
    await expectRevert(sideBridgeProxy.updateSubmission(robert.address), "Must update from primary chain");

    await expectRevert(mainBridgeProxy.connect(jack).transferSubmission(), "Wrong status");
    await expectRevert(sideBridgeProxy.connect(alice).transferSubmission(), "Wrong status");
    await expectRevert(mainBridgeProxy.connect(robert).transferSubmission(), "Wrong status");
    await expectRevert(sideBridgeProxy.connect(robert).transferSubmission(), "Wrong status");
  });

  it("Should correctly update/transfer submissions that are expired", async () => {
    await sideBridgeProxy.updateSubmission(jack.address);
    await expectRegistered(jack).on({ main: true, side: true });

    await increaseTime(submissionDuration + 1);
    await expectRegistered(jack).on({ main: true, side: false });

    await sideBridgeProxy.updateSubmission(jack.address);
    await expectRegistered(jack).on({ main: false, side: false });

    await expectRegistered(alice).on({ main: false, side: false });
    await expectRevert(sideBridgeProxy.connect(alice).transferSubmission(), "Wrong status");
    await mainBridgeProxy.connect(alice).transferSubmission();
    await expectRegistered(alice).on({ main: false, side: false });
  });

  it("Should transfer submissions to the foreign proxy", async () => {
    await expectRegistered(jack).on({ main: false, side: true });
    expect((await mainPoH.getSubmissionInfo(jack.address)).submissionTime).to.equal(0);
    await sideBridgeProxy.connect(jack).transferSubmission();
    await expectRegistered(jack).on({ main: true, side: true });
    expect((await mainPoH.getSubmissionInfo(jack.address)).submissionTime).to.equal(startingTimestamp);
  });

  it("Should not transfer submissions that are vouching", async () => {
    await sidePoH.connect(robert).addSubmission("evidence1", "", { value: requesterTotalCost });
    await sidePoH.connect(eve).addVouch(robert.address);
    await sidePoH.connect(jack).addVouch(robert.address);
    await sidePoH.changeStateToPending(robert.address, [eve.address, jack.address], [], []);
    expect((await sidePoH.getSubmissionInfo(eve.address)).hasVouched).to.be.true;

    await expectRevert(sideBridgeProxy.connect(eve).transferSubmission(), "Must not vouch at the moment");
    await expectRevert(sideBridgeProxy.connect(jack).transferSubmission(), "Must not vouch at the moment");
  });
});

const expectRegistered = (submission: SignerWithAddress) => ({
  async on({ side, main }: { side?: boolean; main?: boolean }) {
    if (typeof main !== "undefined")
      expect(await mainBridgeProxy.isRegistered(submission.address), "Wrong registration status on main").to.equal(
        main
      );
    if (typeof side !== "undefined")
      expect(await sideBridgeProxy.isRegistered(submission.address), "Wrong registration status on side").to.equal(
        side
      );
  },
});
