import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { AddressZero, Zero, One, Two } from "@ethersproject/constants";
import { checkContract, expectEvent, expectRevert, getCurrentTimestamp, increaseTime } from "../utils/test-helpers";
import {
  MockArbitrator,
  MockArbitrator__factory,
  ProofOfHumanityExtended,
  ProofOfHumanityExtended__factory,
  ProofOfHumanityOld,
  ProofOfHumanityOld__factory,
} from "../typechain-types";
import { BigNumber, BigNumberish } from "ethers";
import { Party, Reason, Status } from "../utils/enums";
import { RoundInfo } from "../utils/types";

let arbitrator: MockArbitrator;
let [oldPoH]: ProofOfHumanityOld[] = [];
let [poh]: ProofOfHumanityExtended[] = [];

let [
  governor,
  requester,
  requester2,
  challenger1,
  challenger2,
  voucher1,
  voucher2,
  voucher3,
  voucher4,
  other,
  other2,
]: SignerWithAddress[] = [];

// Promisify signTypedData, note that MetaMask defaults to eth_signTypedData_v1 instead of eth_signTypedData_v4.
const signTypedData = async (
  provider: SignerWithAddress,
  [vouchedSubmission, voucherExpirationTimestamp]: [string, BigNumberish]
) =>
  await provider._signTypedData(
    { name: "Proof of Humanity", chainId: 1, verifyingContract: poh.address },
    {
      IsHumanVoucher: [
        { name: "vouchedSubmission", type: "address" },
        { name: "voucherExpirationTimestamp", type: "uint256" },
      ],
    },
    { vouchedSubmission, voucherExpirationTimestamp }
  );

const MULTIPLIER_DIVISOR = 10000;
const arbitratorExtraData = "0x85";
const arbitrationCost = 1000;
const submissionBaseDeposit = 5000;
const submissionDuration = 86400;
const challengePeriodDuration = 600;
const renewalPeriodDuration = 6000;
const nbVouches = 2;
const requesterTotalCost = BigNumber.from(arbitrationCost + submissionBaseDeposit);

const appealTimeOut = 180;

const sharedStakeMultiplier = 5000;
const winnerStakeMultiplier = 2000;
const loserStakeMultiplier = 8000;

const gasPrice = 875000000;

const registrationMetaEvidence = "registrationMetaEvidence.json";
const clearingMetaEvidence = "clearingMetaEvidence.json";

let startingTimestamp: number;

describe("ProofOfHumanityExtended (interacting with old contract)", () => {
  beforeEach("Initializing the contracts", async () => {
    [governor, requester, requester2, challenger1, challenger2, voucher1, voucher2, voucher3, voucher4, other, other2] =
      await ethers.getSigners();

    arbitrator = await new MockArbitrator__factory(governor).deploy(
      arbitrationCost,
      governor.address,
      arbitratorExtraData,
      appealTimeOut
    );

    await arbitrator.changeArbitrator(arbitrator.address);
    await arbitrator.connect(other).createDispute(3, arbitratorExtraData, { value: arbitrationCost }); // Create a dispute so the index in tests will not be a default value.

    oldPoH = await new ProofOfHumanityOld__factory(governor).deploy(
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
    poh = await new ProofOfHumanityExtended__factory(governor).deploy(
      oldPoH.address,
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

    startingTimestamp = await getCurrentTimestamp();

    await oldPoH
      .connect(governor)
      .addSubmissionManually([voucher1.address, voucher2.address], ["evidence1", "evidence2"], []);
    await oldPoH.connect(voucher3).addSubmission("", "", { value: requesterTotalCost });
    await oldPoH.connect(voucher1).addVouch(voucher3.address);
    await oldPoH.connect(voucher2).addVouch(voucher3.address);
    await oldPoH.connect(governor).changeStateToPending(voucher3.address, [voucher1.address, voucher2.address], [], []);
    await increaseTime(challengePeriodDuration + 1);
    await oldPoH.executeRequest(voucher3.address);

    await oldPoH.connect(governor).changeGovernor(poh.address);

    await poh.connect(governor).addSubmissionManually(voucher4.address, startingTimestamp);
  });

  it("Should set the correct values in constructor", async () => {
    expect(await poh.oldProofOfHumanity()).to.equal(oldPoH.address);
    expect(await poh.governor()).to.equal(governor.address);
    expect(await oldPoH.governor()).to.equal(poh.address);
    expect(await poh.submissionBaseDeposit()).to.equal(submissionBaseDeposit);
    expect(await poh.submissionDuration()).to.equal(submissionDuration);
    expect(await poh.renewalPeriodDuration()).to.equal(renewalPeriodDuration);
    expect(await poh.challengePeriodDuration()).to.equal(challengePeriodDuration);
    expect(await poh.sharedStakeMultiplier()).to.equal(sharedStakeMultiplier);
    expect(await poh.winnerStakeMultiplier()).to.equal(winnerStakeMultiplier);
    expect(await poh.loserStakeMultiplier()).to.equal(loserStakeMultiplier);
    expect(await poh.requiredNumberOfVouches()).to.equal(nbVouches);

    await checkArbitratorDataList(0).for({
      arbitrator: arbitrator.address,
      metaEvidenceUpdates: Zero,
      arbitratorExtraData,
    });
    expect(await poh.getArbitratorDataListCount()).to.equal(1);
  });

  it("Should set correct values in manually added/removed submissions", async () => {
    expect(await poh.submissionCounter()).to.equal(1);
    expect(await oldPoH.submissionCounter()).to.equal(3);

    await checkSubmissionInfo(voucher1.address).for({
      registered: false,
      status: Status.None,
      submissionTime: Zero,
    });
    await checkSubmissionInfo(voucher4.address).for({
      registered: true,
      status: Status.None,
      submissionTime: BigNumber.from(startingTimestamp),
    });

    await checkSubmissionInfo(voucher1.address).onOld.for({ registered: true });
    await poh.connect(governor).removeSubmissionManually(voucher1.address);
    await checkSubmissionInfo(voucher1.address).for({ registered: false });
    await checkSubmissionInfo(voucher1.address).onOld.for({ registered: false });

    await poh.connect(governor).removeSubmissionManually(voucher4.address);
    await checkSubmissionInfo(voucher4.address).for({ registered: false });
    await poh.connect(governor).addSubmissionManually(voucher4.address, startingTimestamp);
    await checkSubmissionInfo(voucher4.address).for({ registered: true, status: Status.None });
    expect(await poh.submissionCounter()).to.equal(1);

    await poh.connect(governor).addSubmissionManually(other.address, startingTimestamp);
    expect(await poh.submissionCounter()).to.equal(2);
  });

  it("Should set correct values after creating a request to add new submission", async () => {
    // Change metaevidence so arbitrator data ID is not 0
    await poh.connect(governor).changeMetaEvidence("1", "2");

    const oldBalance = await requester.getBalance();
    const addSubmissionTX = await (
      await poh.connect(requester).addSubmission("evidence1", "", { gasPrice, value: BigNumber.from(10).pow(18) })
    ).wait();
    if (!addSubmissionTX) return;
    const txFee = addSubmissionTX.gasUsed.mul(gasPrice);

    await checkSubmissionInfo(requester.address).for({
      registered: false,
      status: Status.Vouching,
      numberOfRequests: One,
    });
    await checkRequestInfo(requester.address, 0).for({ arbitratorDataID: 1, requester: AddressZero });
    await checkArbitratorDataList(1).for({ arbitrator: arbitrator.address, arbitratorExtraData });
    await checkRoundInfo(requester.address, 0, 0, 0).for({
      paidFeesForRequester: 6000,
      sideFunded: Party.Requester,
      feeRewards: 6000,
    });

    const contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(contribution[1], "Requester contribution has not been registered correctly").to.equal(6000);

    expect(await requester.getBalance(), "The requester has incorrect balance after making a submission").to.eql(
      oldBalance.sub(requesterTotalCost.add(txFee))
    );

    expectEvent(addSubmissionTX, 0).named("AddSubmission").with({ _submissionID: requester.address, _requestID: 0 });
    expectEvent(addSubmissionTX, 1)
      .named("Evidence")
      .with({ _arbitrator: arbitrator.address, _party: requester.address, _evidence: "evidence1" });

    expect(
      parseInt(addSubmissionTX.events![1].args!._evidenceGroupID.toString()),
      "The event has wrong evidence group ID"
    ).to.equal(parseInt(requester.address, 16));

    await expectRevert(
      poh.connect(requester).addSubmission("", "", { value: BigNumber.from(10).pow(18) }),
      "Wrong status"
    );
    await expectRevert(poh.connect(governor).removeSubmissionManually(requester.address), "Wrong status");
  });

  it("Should not allow to add submission registered on the old contract", async () => {
    await expectRevert(
      poh.connect(voucher1).addSubmission("", "", { value: BigNumber.from(10).pow(18) }),
      "Wrong status"
    );
    await expectRevert(
      poh.connect(voucher3).addSubmission("", "", { value: BigNumber.from(10).pow(18) }),
      "Wrong status"
    );
  });

  it("Should correctly fund the new submission", async () => {
    await poh.connect(requester).addSubmission("evidence1", "", { value: 200 });
    await checkRoundInfo(requester.address, 0, 0, 0).for({
      paidFeesForRequester: 200,
      sideFunded: Party.None,
      feeRewards: 200,
    });

    let contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(contribution[1], "Requester contribution has not been registered correctly").to.equal(200);

    // Let the requester fund the submission once more to see if the sum of both payments is correct.
    await poh.connect(requester).fundSubmission(requester.address, { value: 300 });
    await checkRoundInfo(requester.address, 0, 0, 0).for({
      paidFeesForRequester: 500,
      sideFunded: Party.None,
      feeRewards: 500,
    });

    contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(
      contribution[1],
      "Requester contribution has not been registered correctly after the 2nd payment of the requester"
    ).to.equal(500);

    // Check that the payment of the first crowdfunder has been registered correctly.
    await poh.connect(voucher1).fundSubmission(requester.address, { value: 5000 });
    await checkRoundInfo(requester.address, 0, 0, 0).for({
      paidFeesForRequester: 5500,
      sideFunded: Party.None,
      feeRewards: 5500,
    });

    contribution = await poh.getContributions(requester.address, 0, 0, 0, voucher1.address);
    expect(contribution[1], "First crowdfunder contribution has not been registered correctly").to.equal(5000);

    // Check the second crowdfunder.
    await poh.connect(other).fundSubmission(requester.address, { value: BigNumber.from(10).pow(18) });
    await checkRoundInfo(requester.address, 0, 0, 0).for({
      paidFeesForRequester: requesterTotalCost,
      sideFunded: Party.Requester,
      feeRewards: requesterTotalCost,
    });

    contribution = await poh.getContributions(requester.address, 0, 0, 0, other.address);
    expect(contribution[1], "Second crowdfunder contribution has not been registered correctly").to.equal(500);

    // Check that already registered or absent submission can't be funded.
    await expectRevert(poh.connect(voucher1).fundSubmission(voucher1.address), "Wrong status");
    await expectRevert(poh.connect(other).fundSubmission(other.address), "Wrong status");
  });

  it("Should set correct values after creating a request to remove a submission", async () => {
    await expectRevert(
      poh.connect(requester).removeSubmission(voucher4.address, "evidence1", { value: requesterTotalCost.sub(1) }),
      "You must fully fund your side"
    );

    const txRemove = await (
      await poh.connect(requester).removeSubmission(voucher4.address, "evidence1", {
        value: requesterTotalCost.add(1), // Overpay a little to see if the registered payment is correct.
      })
    ).wait();

    await checkSubmissionInfo(voucher4.address).for({
      status: Status.PendingRemoval,
      numberOfRequests: One,
      registered: true,
    });
    await checkRoundInfo(voucher4.address, 0, 0, 0).for({
      paidFeesForRequester: requesterTotalCost,
      sideFunded: Party.Requester,
      feeRewards: requesterTotalCost,
    });

    const contribution = await poh.getContributions(voucher4.address, 0, 0, 0, requester.address);
    expect(contribution[1], "Requester contribution has not been registered correctly").to.equal(requesterTotalCost);

    expectEvent(txRemove, 0)
      .named("RemoveSubmission")
      .with({ _requester: requester.address, _submissionID: voucher4.address, _requestID: 0 });

    // Check that it's not possible to make a removal request for a submission that is not registered.
    await expectRevert(
      poh.connect(requester).removeSubmission(other.address, "evidence1", { value: requesterTotalCost }),
      "Wrong status"
    );

    await poh.connect(other).addSubmission("evidence1", "", { value: requesterTotalCost });
    await expectRevert(
      poh.connect(requester).removeSubmission(other.address, "evidence1", { value: requesterTotalCost }),
      "Wrong status"
    );

    // Check that it's not possible to make a request during renewal period.
    await increaseTime(submissionDuration - renewalPeriodDuration);
    await poh.connect(governor).addSubmissionManually(other2.address, startingTimestamp);
    await expectRevert(
      poh.connect(requester).removeSubmission(other2.address, "evidence1", { value: requesterTotalCost }),
      "Can't remove after renewal"
    );
  });

  it("Should not be possible to reapply before renewal time or with the wrong status", async () => {
    await expectRevert(poh.connect(voucher4).reapplySubmission(".json", ""), "Can't reapply yet");
    await expectRevert(poh.connect(voucher1).reapplySubmission(".json", ""), "Can't reapply yet");
    await increaseTime(submissionDuration - renewalPeriodDuration);

    await poh.connect(voucher4).reapplySubmission(".json", "");
    await checkSubmissionInfo(voucher4.address).for({
      status: Status.Vouching,
      numberOfRequests: One,
      registered: true,
    });
    // Check that it's not possible to reapply 2nd time.
    await expectRevert(poh.connect(voucher4).reapplySubmission(".json", ""), "Wrong status");

    await expectRevert(poh.connect(other).reapplySubmission(".json", ""), "Wrong status");

    // Also check for submission on old contract
    await poh.connect(voucher1).reapplySubmission(".json", "");
    await checkSubmissionInfo(voucher1.address).for({
      status: Status.Vouching,
      numberOfRequests: One,
      registered: false,
    });
    await expectRevert(poh.connect(voucher1).reapplySubmission(".json", ""), "Wrong status");
  });

  it("Should correctly store vouches and change vouching state", async () => {
    await poh.connect(requester).addSubmission("evidence1", "");

    const txVouchAdd = await (await poh.connect(voucher3).addVouch(requester.address)).wait();
    expect(await poh.vouches(voucher3.address, requester.address), "Should register the vouch for the submission").to.be
      .true;
    expectEvent(txVouchAdd, 0)
      .named("VouchAdded")
      .with({ _submissionID: requester.address, _voucher: voucher3.address });

    // Check that the vouch can be removed successfully and then add it again.
    const txVouchRemove = await (await poh.connect(voucher3).removeVouch(requester.address)).wait();
    expect(await poh.vouches(voucher3.address, requester.address), "The vouch should be removed").to.be.false;
    expectEvent(txVouchRemove, 0)
      .named("VouchRemoved")
      .with({ _submissionID: requester.address, _voucher: voucher3.address });

    await poh.connect(voucher3).addVouch(requester.address);
    await poh.connect(voucher4).addVouch(requester.address);

    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [voucher3.address, voucher4.address], [], []),
      "Requester is not funded"
    );

    await poh.connect(requester).fundSubmission(requester.address, { value: requesterTotalCost });
    // Deliberately add "bad" vouchers to see if the count is correct.
    await poh
      .connect(governor)
      .changeStateToPending(
        requester.address,
        [governor.address, voucher3.address, challenger1.address, voucher4.address, other.address],
        [],
        []
      );

    await checkSubmissionInfo(requester.address).for({ status: Status.PendingRegistration });
    await checkSubmissionInfo(voucher3.address).for({ hasVouched: true });
    await checkSubmissionInfo(voucher4.address).for({ hasVouched: true });
    expect(
      await poh.getNumberOfVouches(requester.address, 0),
      "Incorrect number of vouches stored in submission request"
    ).to.equal(2);
  });

  it("Check that invalid vouches are not counted", async () => {
    // Change required number of vouches to 1 to make checks more transparent
    await poh.connect(governor).changeRequiredNumberOfVouches(1);

    await poh.connect(requester).addSubmission("evidence1", "", { value: requesterTotalCost });

    // Empty array of vouchers.
    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [], [], []),
      "Not enough valid vouches"
    );
    // Array with voucher who didn't vouch.
    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher4.address], [], []),
      "Not enough valid vouches"
    );
    // Voucher who already vouched for a different submission.
    await poh.connect(requester2).addSubmission("evidence1", "", { value: requesterTotalCost });
    await poh.connect(voucher2).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester2.address);
    await poh.connect(governor).changeStateToPending(requester2.address, [voucher2.address], [], []);
    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [voucher2.address], [], []),
      "Not enough valid vouches"
    );
    // Voucher whose submission time has expired.
    await poh.connect(governor).changeDurations(9, 0, 0);
    await increaseTime(10);

    await poh.connect(voucher1).addVouch(requester.address);
    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [voucher1.address], [], []),
      "Not enough valid vouches"
    );

    // Change the submission time and nbVouches back to do another checks.
    await poh.connect(governor).changeDurations(submissionDuration, renewalPeriodDuration, challengePeriodDuration);
    await poh.connect(governor).changeRequiredNumberOfVouches(nbVouches);

    // Check that the voucher can't be duplicated.
    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher1.address], [], []),
      "Not enough valid vouches"
    );
  });

  it("Should not use more vouches than needed", async () => {
    await poh.connect(requester).addSubmission("evidence1", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher3).addVouch(requester.address);
    await poh.connect(voucher4).addVouch(requester.address);
    await poh
      .connect(governor)
      .changeStateToPending(requester.address, [voucher1.address, voucher4.address, voucher3.address], [], []);
    await checkSubmissionInfo(voucher1.address).for({ hasVouched: true });
    await checkSubmissionInfo(voucher4.address).for({ hasVouched: true });
    await checkSubmissionInfo(voucher3.address).for({ hasVouched: false });
  });

  it("Should allow signed vouches", async () => {
    await poh.connect(requester).addSubmission("evidence1", "");

    const timeout = (await getCurrentTimestamp()) + 15768000; // Expires in 6 months

    const vouch1 = await signTypedData(voucher1, [requester.address, timeout]);
    const vouch2 = await signTypedData(voucher2, [requester.address, timeout]);
    const vouchInvalid = await signTypedData(voucher1, [requester.address, (await getCurrentTimestamp()) + 1]);

    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [], [vouch1, vouch2], [timeout, timeout]),
      "Requester is not funded"
    );

    await poh.connect(governor).connect(requester).fundSubmission(requester.address, { value: requesterTotalCost });
    // Deliberately add "bad" voucher to see if the count is correct.
    let txChangeState = await (
      await poh.changeStateToPending(
        requester.address,
        [],
        [vouch1, vouchInvalid, vouchInvalid, vouch2, vouch2],
        [timeout, timeout, 1, 0, timeout]
      )
    ).wait();

    // Check vouching events.
    expectEvent(txChangeState, 0)
      .named("VouchAdded")
      .with({ _submissionID: requester.address, _voucher: voucher1.address });
    expectEvent(txChangeState, 1)
      .named("VouchAdded")
      .with({ _submissionID: requester.address, _voucher: voucher2.address });

    await checkSubmissionInfo(requester.address).for({ status: Status.PendingRegistration });
    await checkSubmissionInfo(voucher1.address).for({ hasVouched: true });
    await checkSubmissionInfo(voucher2.address).for({ hasVouched: true });

    expect(
      await poh.getNumberOfVouches(requester.address, 0),
      "Incorrect number of vouches stored in submission request"
    ).to.equal(2);
  });

  it("Check that invalid signed vouches are not counted", async () => {
    // Change required number of vouches to 1 to make checks more transparent
    await poh.connect(governor).changeRequiredNumberOfVouches(1);
    await poh.connect(requester).addSubmission("evidence1", "", { value: requesterTotalCost });

    // Empty array of vouchers.
    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [], [], []),
      "Not enough valid vouches"
    );
    // Array with voucher who didn't vouch.
    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher4.address], [], []),
      "Not enough valid vouches"
    );
    const timeout = (await getCurrentTimestamp()) + 15768000; // Expires in 6 months

    const vouch2_2 = await signTypedData(voucher2, [requester2.address, timeout]);
    const vouch2_1 = await signTypedData(voucher2, [requester.address, timeout]);

    // Voucher who already vouched for a different submission.
    await poh.connect(requester2).addSubmission("evidence1", "", { value: requesterTotalCost });
    await poh.connect(governor).changeStateToPending(requester2.address, [], [vouch2_2], [timeout]);
    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [], [vouch2_1], [timeout]),
      "Not enough valid vouches"
    );
    // Voucher whose submission time has expired.
    await poh.connect(governor).changeDurations(9, 0, 0);
    await increaseTime(10);

    const vouch1_1 = await signTypedData(voucher1, [requester.address, timeout]);

    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [], [vouch1_1], [timeout]),
      "Not enough valid vouches"
    );

    // Change the submission time and nbVouches back to do another checks.
    await poh.connect(governor).changeDurations(submissionDuration, renewalPeriodDuration, challengePeriodDuration);
    await poh.connect(governor).changeRequiredNumberOfVouches(nbVouches);

    // Check that the voucher can't be duplicated.
    await expectRevert(
      poh.connect(governor).changeStateToPending(requester.address, [], [vouch1_1, vouch1_1], [timeout, timeout]),
      "Not enough valid vouches"
    );
  });

  it("Should allow a mixture of signed and stored vouches", async () => {
    await poh.connect(governor).changeRequiredNumberOfVouches(4);
    await poh.connect(requester).addSubmission("evidence1", "", { value: requesterTotalCost });

    const timeout = (await getCurrentTimestamp()) + 15768000; // Expires in 6 months

    await poh.addSubmissionManually(other.address, startingTimestamp);

    const vouch_1 = await signTypedData(voucher1, [requester.address, timeout]);
    const vouch_2 = await signTypedData(voucher4, [requester.address, timeout]);
    await poh.connect(voucher2).addVouch(requester.address);
    await poh.connect(other).addVouch(requester.address);

    await poh
      .connect(governor)
      .changeStateToPending(
        requester.address,
        [voucher2.address, other.address],
        [vouch_1, vouch_2],
        [timeout, timeout]
      );

    await checkSubmissionInfo(requester.address).for({ status: Status.PendingRegistration });
    await checkSubmissionInfo(voucher1.address).for({ hasVouched: true });
    await checkSubmissionInfo(voucher2.address).for({ hasVouched: true });
    await checkSubmissionInfo(voucher4.address).for({ hasVouched: true });
    await checkSubmissionInfo(other.address).for({ hasVouched: true });
  });

  it("Should set correct values and create a dispute after the submission is challenged", async () => {
    // Check that the submission with the wrong status can't be challenged.
    await expectRevert(
      poh.connect(challenger1).challengeRequest(voucher1.address, Reason.Deceased, AddressZero, 1, "evidence2", {
        value: BigNumber.from(10).pow(18),
      }),
      "Wrong status"
    );
    await expectRevert(
      poh.connect(challenger1).challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "evidence2", {
        value: BigNumber.from(10).pow(18),
      }),
      "Wrong status"
    );

    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await expectRevert(
      poh.connect(challenger1).challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "evidence2", {
        value: BigNumber.from(10).pow(18),
      }),
      "Wrong status"
    );

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    // Check the rest of the require statements as well.
    await expectRevert(
      poh.connect(challenger1).challengeRequest(requester.address, Reason.None, AddressZero, 1, "evidence2", {
        value: BigNumber.from(10).pow(18),
      }),
      "Reason must be specified"
    );
    await expectRevert(
      poh.connect(challenger1).challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "evidence2", {
        value: arbitrationCost - 1,
      }),
      "You must fully fund your side"
    );

    const oldBalance = await challenger1.getBalance();
    // Deliberately overpay to see if the payment is registered correctly
    const txChallenge = await (
      await poh.connect(challenger1).challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "evidence2", {
        gasPrice: gasPrice,
        value: BigNumber.from(10).pow(18),
      })
    ).wait();
    const newBalance = await challenger1.getBalance();
    const txFee = txChallenge.gasUsed.mul(gasPrice);

    // Check that the request can't be challenged again with another reason.
    await expectRevert(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, Reason.IncorrectSubmission, AddressZero, 0, "evidence2", {
          value: BigNumber.from(10).pow(18),
        }),
      "The request is disputed"
    );

    await expectRevert(
      poh.connect(challenger1).challengeRequest(requester.address, Reason.Duplicate, voucher1.address, 1, "evidence2", {
        value: BigNumber.from(10).pow(18),
      }),
      "Another reason is active"
    );

    expect(newBalance, "The challenger has incorrect balance after making a submission").to.eql(
      oldBalance.sub(arbitrationCost).sub(txFee)
    );

    await checkRequestInfo(requester.address, 0).for({
      currentReason: Reason.Deceased,
      nbParallelDisputes: 1,
      lastChallengeID: 1,
      usedReasons: 2,
    });

    await checkChallengeInfo(requester.address, 0, 0).for({
      lastRoundID: 1,
      challenger: challenger1.address,
      disputeID: One,
      duplicateSubmissionChainID: Zero,
    });
    await checkDisputeData(arbitrator.address, 1).for({ challengeID: Zero, submissionID: requester.address });
    await checkRoundInfo(requester.address, 0, 0, 0).for({
      paidFeesForChallenger: 1000,
      sideFunded: Party.None,
      feeRewards: 6000,
    });

    // Also briefly check the round that was created beforehand for the new challenge.
    await checkRoundInfo(requester.address, 0, 1, 0).for({ feeRewards: 0 });

    const dispute = await arbitrator.disputes(1);
    expect(dispute[0], "Arbitrable not set up properly").to.equal(poh.address);
    expect(dispute[1], "Number of choices not set up properly").to.equal(2);

    expectEvent(txChallenge, 2)
      .named("Dispute")
      .with({ _arbitrator: arbitrator.address, _disputeID: 1, _metaEvidenceID: 0 });
    expect(
      parseInt(txChallenge.events![2].args!._evidenceGroupID.toString()),
      "The Dispute event has wrong evidence group ID"
    ).to.equal(parseInt(requester.address, 16));

    expectEvent(txChallenge, 3)
      .named("Evidence")
      .with({ _arbitrator: arbitrator.address, _party: challenger1.address, _evidence: "evidence2" });
    expect(
      parseInt(txChallenge.events![3].args!._evidenceGroupID.toString()),
      "The Dispute event has wrong evidence group ID"
    ).to.equal(parseInt(requester.address, 16));

    // Check that the request can't just be executed after challenge.
    await increaseTime(challengePeriodDuration + 1);
    await expectRevert(poh.connect(governor).executeRequest(requester.address), "The request is disputed");
  });

  it("Should not be possible to challenge after timeout", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);
    await increaseTime(challengePeriodDuration + 1);
    await expectRevert(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "evidence2", { value: arbitrationCost }),
      "Time to challenge has passed"
    );
  });

  it("Should set correct values in parallel disputes", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    await expectRevert(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, Reason.Duplicate, AddressZero, 1, "", { value: arbitrationCost }),
      "Wrong duplicate status"
    );
    await expectRevert(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, Reason.Duplicate, requester.address, Reason.IncorrectSubmission, "", {
          value: arbitrationCost,
        }),
      "Can't be a duplicate of itself"
    );

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Duplicate, voucher2.address, 1, "", { value: arbitrationCost });

    await expectRevert(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, Reason.Duplicate, voucher2.address, 1, "", { value: arbitrationCost }),
      "Duplicate address already used"
    );
    expect(
      await poh.checkRequestDuplicates(requester.address, 0, voucher2.address, 1),
      "The duplicate should be marked as used"
    ).to.be.true;

    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, Reason.Duplicate, voucher3.address, 1, "", { value: arbitrationCost });
    await checkRequestInfo(requester.address, 0).for({ nbParallelDisputes: 2, lastChallengeID: 2, usedReasons: 4 });

    await checkChallengeInfo(requester.address, 0, 0).for({
      lastRoundID: 1,
      challenger: challenger1.address,
      disputeID: One,
      duplicateSubmissionChainID: One,
    });
    await checkDisputeData(arbitrator.address, 1).for({ challengeID: Zero, submissionID: requester.address });

    await checkChallengeInfo(requester.address, 0, 1).for({
      lastRoundID: 1,
      challenger: challenger2.address,
      disputeID: Two,
      duplicateSubmissionChainID: One,
    });
    await checkDisputeData(arbitrator.address, 2).for({ challengeID: One, submissionID: requester.address });

    await checkRoundInfo(requester.address, 0, 0, 0).for({ feeRewards: 6000 });
    await checkRoundInfo(requester.address, 0, 1, 0).for({ feeRewards: 0 }); // The second challenge doesn't count the requester's payment, so feeRewards should stay 0.
  });

  it("Should set correct values when challenging a removal request", async () => {
    // All checks for correct values have already been done in previous tests. Here just check conditions that are unique for this type of challenge.
    await poh.connect(requester).removeSubmission(voucher4.address, "", { value: requesterTotalCost });
    await expectRevert(
      poh
        .connect(challenger1)
        .challengeRequest(voucher4.address, Reason.IncorrectSubmission, AddressZero, 0, "", { value: arbitrationCost }),
      "Reason must be left empty"
    );

    await poh
      .connect(challenger1)
      .challengeRequest(voucher4.address, 0, AddressZero, 1, "", { value: arbitrationCost });
    await checkRequestInfo(voucher4.address, 0).for({ currentReason: Reason.None, lastChallengeID: 1, usedReasons: 0 });
  });

  it("Should successfully execute a request if it has not been challenged", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    await expectRevert(poh.connect(governor).executeRequest(requester.address), "Can't execute yet");

    await increaseTime(challengePeriodDuration + 1);

    const oldBalance = await requester.getBalance();
    await poh.connect(governor).executeRequest(requester.address);
    const newBalance = await requester.getBalance();

    await checkSubmissionInfo(requester.address).for({ status: Status.None, registered: true });

    await checkRequestInfo(requester.address, 0).for({ resolved: true });
    expect(newBalance, "The requester was not reimbursed correctly").to.eql(oldBalance.add(requesterTotalCost));

    const contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(contribution[1], "Contribution of the requester should be 0").to.equal(0);
    // Check that it's not possible to execute two times in a row.
    await expectRevert(poh.connect(governor).executeRequest(requester.address), "Incorrect status.");

    // Check that the vouchers have been processed.
    await checkSubmissionInfo(voucher1.address).for({ hasVouched: false });
    await checkSubmissionInfo(voucher2.address).for({ hasVouched: false });

    // Also check removal request.
    await poh.connect(requester2).removeSubmission(requester.address, "", { value: requesterTotalCost });
    await increaseTime(challengePeriodDuration + 1);

    await poh.connect(governor).executeRequest(requester.address);
    await checkSubmissionInfo(requester.address).for({ status: Status.None, registered: false });
    await checkRequestInfo(requester.address, 1).for({ resolved: true });
  });

  it("Should demand correct appeal fees and register that appeal fee has been paid", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    await expectRevert(
      poh
        .connect(challenger1)
        .fundAppeal(requester.address, 0, Party.Challenger, { value: BigNumber.from(10).pow(18) }),
      "No dispute to appeal"
    );

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "", { value: arbitrationCost });

    await arbitrator.giveRuling(1, Party.Challenger);

    // Appeal fee is the same as arbitration fee for this arbitrator.
    const loserAppealFee = arbitrationCost + (arbitrationCost * loserStakeMultiplier) / MULTIPLIER_DIVISOR; // 1000 + 1000 * 0.8 = 1800

    await expectRevert(
      poh.connect(challenger1).fundAppeal(requester.address, 0, Party.None, { value: loserAppealFee }), // Check that not possible to fund 0 side.
      "revert"
    );

    await expectRevert(
      poh
        .connect(challenger1)
        .fundAppeal(requester.address, 1, Party.Challenger, { value: BigNumber.from(10).pow(18) }),
      "Challenge out of bounds"
    );

    // Deliberately overpay to check that only required fee amount will be registered.
    await poh
      .connect(requester)
      .fundAppeal(requester.address, 0, Party.Requester, { value: BigNumber.from(10).pow(18) });

    await expectRevert(
      poh.connect(requester).fundAppeal(requester.address, 0, Party.Requester, { value: BigNumber.from(10).pow(18) }),
      "Side is already funded"
    );

    // Appeal rounds start with 1.
    await checkRoundInfo(requester.address, 0, 0, 1).for({
      paidFeesForRequester: 1800,
      sideFunded: Party.Requester,
      paidFeesForChallenger: 0,
      feeRewards: 1800,
    });

    const winnerAppealFee = arbitrationCost + (arbitrationCost * winnerStakeMultiplier) / MULTIPLIER_DIVISOR; // 1200

    // Increase time to make sure winner can pay in 2nd half.
    await increaseTime(appealTimeOut / 2 + 1);

    await poh.connect(challenger1).fundAppeal(requester.address, 0, Party.Challenger, { value: winnerAppealFee });

    await checkRoundInfo(requester.address, 0, 0, 1).for({
      paidFeesForChallenger: 1200,
      sideFunded: Party.None,
      feeRewards: 2000,
    });

    // If both sides pay their fees it starts new appeal round. Check that both sides have their values set to default.
    await checkRoundInfo(requester.address, 0, 0, 2).for({ sideFunded: Party.None });

    // Resolve the first challenge to see if the new challenge will set correct values as well.
    await arbitrator.giveRuling(2, Party.Requester);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(2, Party.Requester);

    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, Reason.IncorrectSubmission, AddressZero, 0, "", { value: arbitrationCost });
    await arbitrator.giveRuling(3, Party.None); // Give 0 ruling to check shared multiplier this time.wait().

    await poh
      .connect(requester)
      .fundAppeal(requester.address, 1, Party.Requester, { value: BigNumber.from(10).pow(18) });

    await checkRoundInfo(requester.address, 0, 1, 1).for({
      paidFeesForRequester: 1500, // With shared multiplier = 5000 the sharedFee is 1500
      sideFunded: Party.Requester,
      feeRewards: 1500,
    });

    await poh.connect(challenger1).fundAppeal(requester.address, 1, Party.Challenger, { value: 1500 });

    await checkRoundInfo(requester.address, 0, 1, 1).for({
      paidFeesForChallenger: 1500, // With shared multiplier = 5000 the sharedFee is 1500
      sideFunded: Party.None,
      feeRewards: 2000,
    });
    await checkRoundInfo(requester.address, 0, 1, 2).for({ sideFunded: Party.None });
  });

  it("Should not be possible to fund appeal if the timeout has passed", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "", { value: arbitrationCost });
    await arbitrator.giveRuling(1, Party.Requester);

    const loserAppealFee = arbitrationCost + (arbitrationCost * winnerStakeMultiplier) / MULTIPLIER_DIVISOR;

    await increaseTime(appealTimeOut / 2 + 1);
    await expectRevert(
      poh.connect(challenger1).fundAppeal(requester.address, 0, Party.Challenger, { value: loserAppealFee }),
      "Appeal period is over for loser"
    );
    const winnerAppealFee = arbitrationCost + (arbitrationCost * winnerStakeMultiplier) / MULTIPLIER_DIVISOR;

    await increaseTime(appealTimeOut / 2 + 1);
    await expectRevert(
      poh.connect(requester).fundAppeal(requester.address, 0, Party.Requester, { value: winnerAppealFee }),
      "Appeal period is over"
    );
  });

  it("Should correctly reset the challenge period if the requester wins", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "", { value: arbitrationCost });

    await arbitrator.giveRuling(1, Party.Requester);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.Requester);

    await checkRequestInfo(requester.address, 0).for({ disputed: false, currentReason: Reason.None });

    // Check that it's not possible to challenge with the same reason.
    await expectRevert(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "", { value: arbitrationCost }),
      "The reason has already been used"
    );

    // Also check that the execution of the request is still possible if there is no dispute.
    await increaseTime(challengePeriodDuration + 1);
    const oldBalance = await requester.getBalance();
    await poh.connect(governor).executeRequest(requester.address);
    const newBalance = await requester.getBalance();
    expect(newBalance, "The requester was not reimbursed correctly").to.eql(oldBalance.add(requesterTotalCost));

    await checkSubmissionInfo(requester.address).for({ status: Status.None, registered: true });
    await checkRequestInfo(requester.address, 0).for({ resolved: true });
  });

  it("Should register the submission if the requester won in all 4 reasons", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "", { value: arbitrationCost });
    await arbitrator.giveRuling(1, Party.Requester);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.Requester);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.IncorrectSubmission, AddressZero, 0, "", { value: arbitrationCost });
    await arbitrator.giveRuling(2, Party.Requester);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(2, Party.Requester);

    // Make a parallel request to see if it's handled correctly.
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Duplicate, voucher1.address, 1, "", { value: arbitrationCost });
    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, Reason.Duplicate, voucher2.address, 1, "", { value: arbitrationCost });
    await arbitrator.giveRuling(3, Party.Requester);
    await arbitrator.giveRuling(4, Party.Requester);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(3, Party.Requester);
    await arbitrator.giveRuling(4, Party.Requester);

    // Check that the info stored in the request is correct so far.
    await checkSubmissionInfo(requester.address).for({ registered: false });

    await checkRequestInfo(requester.address, 0).for({ resolved: false, lastChallengeID: 4, usedReasons: 7 });

    // Check the data of a random challenge as well.
    await checkChallengeInfo(requester.address, 0, 3).for({ disputeID: BigNumber.from(4), ruling: Party.Requester });

    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, Reason.DoesNotExist, AddressZero, 1, "", { value: arbitrationCost });
    await arbitrator.giveRuling(5, Party.Requester);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(5, Party.Requester);

    await checkRequestInfo(requester.address, 0).for({ resolved: true, nbParallelDisputes: 0, usedReasons: 15 });

    await checkSubmissionInfo(requester.address).for({ status: Status.None });
    expect(await poh.isRegistered(requester.address), "The submission should be registered").to.be.true;
  });

  it("Should set correct values if arbitrator refuses to rule", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    // Make a parallel request to see if it's handled correctly.
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Duplicate, voucher1.address, 1, "", { value: arbitrationCost });
    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, Reason.Duplicate, voucher2.address, 1, "", { value: arbitrationCost });
    await arbitrator.giveRuling(1, Party.None);
    await arbitrator.giveRuling(2, Party.Requester);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.None);
    await arbitrator.giveRuling(2, Party.Requester);

    // The requester didn't win the first dispute so his request should be declined in the end.
    await checkSubmissionInfo(requester.address).for({ status: Status.None });
    expect(await poh.isRegistered(requester.address), "The submission should not be registered").to.be.false;

    await checkRequestInfo(requester.address, 0).for({
      resolved: true,
      requesterLost: true,
      ultimateChallenger: AddressZero,
    });
    await checkChallengeInfo(requester.address, 0, 0).for({ ruling: Party.None });
    await checkChallengeInfo(requester.address, 0, 1).for({ ruling: Party.Requester });
  });

  it("Should set correct values if challenger wins", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.IncorrectSubmission, AddressZero, 0, "", { value: arbitrationCost });
    await arbitrator.giveRuling(1, Party.Challenger);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.Challenger);

    await checkSubmissionInfo(requester.address).for({ status: Status.None, registered: false });
    await checkRequestInfo(requester.address, 0).for({
      resolved: true,
      requesterLost: true,
      ultimateChallenger: challenger1.address,
    });
    await checkChallengeInfo(requester.address, 0, 0).for({ ruling: Party.Challenger });
  });

  it("Should switch the winning challenger in reason Duplicate", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    // Voucher1 is the earliest submission so challenger2 should be the ultimate challenger in the end.
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Duplicate, voucher3.address, 99, "", { value: arbitrationCost });
    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, Reason.Duplicate, voucher1.address, 1, "", { value: arbitrationCost });
    await poh
      .connect(other)
      .challengeRequest(requester.address, Reason.Duplicate, voucher2.address, 1, "", { value: arbitrationCost });
    await arbitrator.giveRuling(1, Party.Challenger);
    await arbitrator.giveRuling(2, Party.Challenger);
    await arbitrator.giveRuling(3, Party.Challenger);
    await increaseTime(appealTimeOut + 1);

    await arbitrator.giveRuling(1, Party.Challenger);
    await checkRequestInfo(requester.address, 0).for({ resolved: false, ultimateChallenger: challenger1.address });

    await arbitrator.giveRuling(2, Party.Challenger);
    await checkRequestInfo(requester.address, 0).for({ ultimateChallenger: challenger2.address });

    await arbitrator.giveRuling(3, Party.Challenger);
    await checkRequestInfo(requester.address, 0).for({ resolved: true, ultimateChallenger: challenger2.address });
  });

  it("Should set correct values if requester wins removal request", async () => {
    await poh.connect(requester).removeSubmission(voucher4.address, "", { value: requesterTotalCost });
    await poh
      .connect(challenger1)
      .challengeRequest(voucher4.address, Reason.None, AddressZero, 1, "", { value: arbitrationCost });
    await arbitrator.giveRuling(1, Party.Requester);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.Requester);

    await checkSubmissionInfo(voucher4.address).for({ status: Status.None, registered: false });
    await checkRequestInfo(voucher4.address, 0).for({ resolved: true });
    await checkChallengeInfo(voucher4.address, 0, 0).for({ ruling: Party.Requester });
  });

  it("Should set correct values if challenger wins removal request", async () => {
    await poh.connect(requester).removeSubmission(voucher4.address, "", { value: requesterTotalCost });
    await poh
      .connect(challenger1)
      .challengeRequest(voucher4.address, Reason.None, AddressZero, 1, "", { value: arbitrationCost });
    await arbitrator.giveRuling(1, Party.Challenger);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.Challenger);

    await checkSubmissionInfo(voucher4.address).for({ status: Status.None, registered: true });
    await checkRequestInfo(voucher4.address, 0).for({ resolved: true });
    await checkChallengeInfo(voucher4.address, 0, 0).for({ ruling: Party.Challenger });
  });

  it("Should change the ruling if the loser paid appeal fee while winner did not", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Deceased, AddressZero, 1, "", { value: arbitrationCost });
    await arbitrator.giveRuling(1, Party.Requester);

    await poh
      .connect(challenger1)
      .fundAppeal(requester.address, 0, Party.Challenger, { value: BigNumber.from(10).pow(18) });

    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.Requester);

    await checkRequestInfo(requester.address, 0).for({ ultimateChallenger: challenger1.address });
    await checkChallengeInfo(requester.address, 0, 0).for({ ruling: Party.Challenger });
  });

  it("Should process vouches correctly", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher4).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher4.address], [], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.IncorrectSubmission, AddressZero, 0, "", { value: arbitrationCost });
    await arbitrator.giveRuling(1, Party.Challenger);
    await increaseTime(appealTimeOut + 1);
    await expectRevert(poh.connect(governor).processVouches(requester.address, 0, 1), "Submission must be resolved");
    // Let challenger win to make the test more transparent.
    await arbitrator.giveRuling(1, Party.Challenger);

    await poh.connect(governor).processVouches(requester.address, 0, 1);
    await checkSubmissionInfo(voucher1.address).for({ hasVouched: false, registered: false });
    await checkSubmissionInfo(voucher4.address).for({ hasVouched: true });

    await poh.connect(governor).processVouches(requester.address, 0, 1);
    await checkSubmissionInfo(voucher4.address).for({ hasVouched: false, registered: true });
  });

  it("Should correctly penalize vouchers that vote for a bad submission", async () => {
    // Make it so one of the vouchers is in the middle of reapplication process.
    await increaseTime(submissionDuration - renewalPeriodDuration);

    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher4).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher4.address], [], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.DoesNotExist, AddressZero, 1, "", { value: arbitrationCost });

    // Change required number of vouches to 1 because the rest 2 are used.
    await poh.connect(voucher4).reapplySubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher2).addVouch(voucher4.address);
    await poh.connect(voucher3).addVouch(voucher4.address);
    await poh.connect(governor).changeStateToPending(voucher4.address, [voucher2.address, voucher3.address], [], []);

    await arbitrator.giveRuling(1, Party.Challenger);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.Challenger);

    await poh.connect(governor).processVouches(requester.address, 0, 2);
    await checkSubmissionInfo(voucher1.address).for({ registered: false });
    await checkSubmissionInfo(voucher4.address).for({ registered: false });
    await checkSubmissionInfo(voucher1.address).onOld.for({ registered: false });
    await checkSubmissionInfo(voucher4.address).onOld.for({ registered: false });

    await checkRequestInfo(voucher4.address, 0).for({ requesterLost: true });
    await increaseTime(challengePeriodDuration + 1);
    await poh.connect(governor).executeRequest(voucher4.address);

    await checkSubmissionInfo(voucher4.address).for({ status: Status.None, registered: false });
    await checkRequestInfo(voucher4.address, 0).for({ resolved: true });
  });

  it("Ultimate challenger should take feeRewards of the first challenge", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Duplicate, voucher1.address, 1, "", { value: arbitrationCost });
    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, Reason.Duplicate, voucher2.address, 1, "", { value: arbitrationCost });

    await arbitrator.giveRuling(1, Party.Requester);
    await arbitrator.giveRuling(2, Party.Challenger);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.Requester);

    await expectRevert(
      poh.connect(governor).withdrawFeesAndRewards(challenger2.address, requester.address, 0, 0, 0),
      "Submission must be resolved"
    );
    await arbitrator.giveRuling(2, Party.Challenger);

    await expectRevert(
      poh.connect(governor).withdrawFeesAndRewards(AddressZero, requester.address, 0, 0, 0),
      "Beneficiary must not be empty"
    );
    const oldBalanceRequester = await requester.getBalance();
    await poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 0, 0);
    const newBalanceRequester = await requester.getBalance();
    // Requester's fee of the first dispute should go to the ultimate challenger.
    expect(newBalanceRequester, "The balance of the requester should stay the same").to.eql(oldBalanceRequester);

    // Only check the 2nd challenger, because the 1st challenger didn't win a dispute.
    let oldBalanceChallenger = await challenger2.getBalance();
    await poh.connect(governor).withdrawFeesAndRewards(challenger2.address, requester.address, 0, 0, 0);
    let newBalanceChallenger = await challenger2.getBalance();
    expect(newBalanceChallenger, "The challenger has incorrect balance after withdrawing from 0 challenge").to.eql(
      oldBalanceChallenger.add(requesterTotalCost)
    );
    oldBalanceChallenger = await challenger2.getBalance();
    await poh.connect(governor).withdrawFeesAndRewards(challenger2.address, requester.address, 0, 1, 0);
    newBalanceChallenger = await challenger2.getBalance();
    expect(
      newBalanceChallenger,
      "The challenger should have the same balance after withdrawing from 1 challenge"
    ).to.eql(oldBalanceChallenger);
  });

  it("Should not withdraw anything from the subsequent challenge", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost.div(5) });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);
    await poh.connect(other).fundSubmission(requester.address, { value: BigNumber.from(10).pow(18) });

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Duplicate, voucher1.address, 1, "", { value: arbitrationCost });
    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, Reason.Duplicate, voucher2.address, 1, "", { value: arbitrationCost });

    await arbitrator.giveRuling(1, Party.Requester);
    await arbitrator.giveRuling(2, Party.Requester);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.Requester);
    await arbitrator.giveRuling(2, Party.Requester);

    await increaseTime(challengePeriodDuration + 1);
    let oldBalanceRequester = await requester.getBalance();
    await poh.connect(governor).executeRequest(requester.address);
    let newBalanceRequester = await requester.getBalance();
    expect(newBalanceRequester, "The balance of the requester is incorrect after withdrawing from 0 challenge").to.eql(
      oldBalanceRequester.add(BigNumber.from(1200))
    ); // The requester only did a partial funding so he should be reimbursed according to that (0.2 * feeRewards).
    const oldBalanceCrowdfunder = await other.getBalance();
    await poh.connect(governor).withdrawFeesAndRewards(other.address, requester.address, 0, 0, 0);
    const newBalanceCrowdfunder = await other.getBalance();
    expect(newBalanceCrowdfunder, "The balance of the crowdfunder is incorrect").to.be.eql(
      oldBalanceCrowdfunder.add(BigNumber.from(4800)) // 0.8 * feeRewards.
    );

    oldBalanceRequester = await requester.getBalance();
    await poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 1, 0);
    newBalanceRequester = await requester.getBalance();
    expect(newBalanceRequester, "The balance of the requester should stay the same").to.eql(oldBalanceRequester);
  });

  it("Should withdraw fees correctly if arbitrator refused to rule", async () => {
    await poh.connect(requester).addSubmission("", "", { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address);
    await poh.connect(voucher2).addVouch(requester.address);

    await poh.connect(governor).changeStateToPending(requester.address, [voucher1.address, voucher2.address], [], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, Reason.Duplicate, voucher1.address, 1, "", { value: arbitrationCost });
    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, Reason.Duplicate, voucher2.address, 1, "", { value: arbitrationCost });

    await arbitrator.giveRuling(1, Party.None);
    await arbitrator.giveRuling(2, Party.Challenger);
    await increaseTime(appealTimeOut + 1);
    await arbitrator.giveRuling(1, Party.None);
    await arbitrator.giveRuling(2, Party.Challenger);

    let oldBalanceRequester = await requester.getBalance();
    await poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 0, 0);
    let newBalanceRequester = await requester.getBalance();
    expect(
      newBalanceRequester,
      "The balance of the requester is incorrect after withdrawing from 0 challenge"
    ).to.be.equal(oldBalanceRequester.add(BigNumber.from(5142))); // 6000/7000 * 6000 = 5142.8
    // Only check the 1st challenger, because the 2nd challenger lost a dispute.
    const oldBalanceChallenger = await challenger1.getBalance();
    await poh.connect(governor).withdrawFeesAndRewards(challenger1.address, requester.address, 0, 0, 0);
    const newBalanceChallenger = await challenger1.getBalance();
    expect(
      newBalanceChallenger,
      "The balance of the challenger is incorrect after withdrawing from 0 challenge"
    ).to.eql(oldBalanceChallenger.add(BigNumber.from(857))); // 1000/7000 * 6000 = 857.1

    oldBalanceRequester = await requester.getBalance();
    await poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 1, 0);
    newBalanceRequester = await requester.getBalance();
    expect(newBalanceRequester, "The requester should not get any reward from 1 challenge").to.eql(oldBalanceRequester);
  });

  it("Should make governance changes", async () => {
    await expectRevert(
      poh.connect(other).addSubmissionManually(other.address, await getCurrentTimestamp()),
      "Must be governor"
    );
    await expectRevert(poh.connect(other).removeSubmissionManually(voucher1.address), "Must be governor");

    // submissionBaseDeposit
    await expectRevert(poh.connect(other).changeSubmissionBaseDeposit(22), "Must be governor");
    await poh.connect(governor).changeSubmissionBaseDeposit(22);
    expect(await poh.submissionBaseDeposit(), "Incorrect submissionBaseDeposit value").to.equal(22);
    expect(await oldPoH.submissionBaseDeposit(), "Incorrect submissionBaseDeposit value").to.equal(22);

    // submissionDuration, renewalPeriodDuration, challengePeriodDuration
    await expectRevert(poh.connect(other).changeDurations(128, 94, 14), "Must be governor");
    await expectRevert(poh.connect(governor).changeDurations(28, 94, 14), "Incorrect inputs");
    await poh.connect(governor).changeDurations(128, 94, 14);
    expect(await poh.submissionDuration(), "Incorrect submissionDuration value").to.equal(128);
    expect(await poh.renewalPeriodDuration(), "Incorrect renewalPeriodDuration value").to.equal(94);
    expect(await poh.challengePeriodDuration(), "Incorrect challengePeriodDuration value").to.equal(14);
    expect(await oldPoH.submissionDuration(), "Incorrect submissionDuration value").to.equal(128);
    expect(await oldPoH.renewalPeriodDuration(), "Incorrect renewalPeriodDuration value").to.equal(94);
    expect(await oldPoH.challengePeriodDuration(), "Incorrect challengePeriodDuration value").to.equal(14);

    // requiredNumberOfVouches
    await expectRevert(poh.connect(other).changeRequiredNumberOfVouches(1223), "Must be governor");
    await poh.connect(governor).changeRequiredNumberOfVouches(1223);
    expect(await poh.requiredNumberOfVouches(), "Incorrect requiredNumberOfVouches value").to.equal(1223);
    expect(await oldPoH.requiredNumberOfVouches(), "Incorrect requiredNumberOfVouches value").to.equal(1223);

    // sharedStakeMultiplier
    await expectRevert(poh.connect(other).changeSharedStakeMultiplier(555), "Must be governor");
    await poh.connect(governor).changeSharedStakeMultiplier(555);
    expect(await poh.sharedStakeMultiplier(), "Incorrect sharedStakeMultiplier value").to.equal(555);
    expect(await oldPoH.sharedStakeMultiplier(), "Incorrect sharedStakeMultiplier value").to.equal(555);

    // winnerStakeMultiplier
    await expectRevert(poh.connect(other).changeWinnerStakeMultiplier(2001), "Must be governor");
    await poh.connect(governor).changeWinnerStakeMultiplier(2001);
    expect(await poh.winnerStakeMultiplier(), "Incorrect winnerStakeMultiplier value").to.equal(2001);
    expect(await oldPoH.winnerStakeMultiplier(), "Incorrect winnerStakeMultiplier value").to.equal(2001);

    // loserStakeMultiplier
    await expectRevert(poh.connect(other).changeLoserStakeMultiplier(9555), "Must be governor");
    await poh.connect(governor).changeLoserStakeMultiplier(9555);
    expect(await poh.loserStakeMultiplier(), "Incorrect loserStakeMultiplier value").to.equal(9555);
    expect(await oldPoH.loserStakeMultiplier(), "Incorrect loserStakeMultiplier value").to.equal(9555);

    // governor
    await expectRevert(poh.connect(other).changeGovernor(other.address), "Must be governor");
    await poh.connect(governor).changeGovernor(other.address);
    expect(await poh.governor(), "Incorrect governor value").to.equal(other.address);

    // metaEvidenceUpdates
    await expectRevert(
      poh.connect(governor).changeMetaEvidence("1", "2"),
      "Must be governor" // Check that the old governor can't change variables anymore.
    );
    await poh.connect(other).changeMetaEvidence("1", "2");
    await checkArbitratorDataList(1).for({ metaEvidenceUpdates: One });
    await checkArbitratorDataList(1).onOld.for({ metaEvidenceUpdates: One });
    expect(await poh.getArbitratorDataListCount(), "Incorrect arbitratorData length").to.equal(2);
    expect(await oldPoH.getArbitratorDataListCount(), "Incorrect arbitratorData length").to.equal(2);
    // arbitrator
    await expectRevert(poh.connect(governor).changeArbitrator(governor.address, "0xff"), "Must be governor");
    await poh.connect(other).changeArbitrator(governor.address, "0xff");

    await checkArbitratorDataList(2).for({ arbitrator: governor.address, arbitratorExtraData: "0xff" });
    await checkArbitratorDataList(2).onOld.for({ arbitrator: governor.address, arbitratorExtraData: "0xff" });
    expect(await poh.getArbitratorDataListCount(), "Incorrect arbitratorData length").to.equal(3);
    expect(await oldPoH.getArbitratorDataListCount(), "Incorrect arbitratorData length").to.equal(3);
  });

  it("Should correctly withdraw the mistakenly added submission", async () => {
    await poh.connect(requester).addSubmission("evidence1", "", { value: requesterTotalCost.mul(2).div(5) });

    await poh.connect(other).fundSubmission(requester.address, { value: BigNumber.from(10).pow(18) });

    const oldBalanceRequester = await requester.getBalance();
    const txWithdraw = await (await poh.connect(requester).withdrawSubmission({ gasPrice: gasPrice })).wait();
    const txFee = txWithdraw.gasUsed.mul(gasPrice);

    const newBalanceRequester = await requester.getBalance();
    const submission = await poh.getSubmissionInfo(requester.address);
    const request = await poh.getRequestInfo(requester.address, 0);

    expect(newBalanceRequester, "The requester has incorrect balance after withdrawal").eql(
      oldBalanceRequester.add(requesterTotalCost.mul(2).div(5)).sub(txFee)
    );

    const oldBalanceCrowdfunder = await other.getBalance();
    await poh.connect(governor).withdrawFeesAndRewards(other.address, requester.address, 0, 0, 0);
    const newBalanceCrowdfunder = await other.getBalance();
    expect(newBalanceCrowdfunder, "The crowdfunder has incorrect balance after withdrawal").eql(
      oldBalanceCrowdfunder.add(requesterTotalCost.mul(3).div(5))
    );

    expect(submission[0], "Submission should have a default status").to.be.equal(0);
    expect(request[1], "The request should be resolved").to.be.true;

    await expectRevert(poh.connect(requester).withdrawSubmission(), "Wrong status");
  });

  it("Submission should not be registered after expiration", async () => {
    await increaseTime(submissionDuration + 1);
    expect(await poh.isRegistered(voucher1.address), "The submission should not be registered").to.be.false;
  });
});

const checkRequestInfo = (...params: Parameters<ProofOfHumanityExtended["getRequestInfo"]>) =>
  checkContract(poh, "getRequestInfo")(...params);
const checkChallengeInfo = (...params: Parameters<ProofOfHumanityExtended["getChallengeInfo"]>) =>
  checkContract(poh, "getChallengeInfo")(...params);
const checkDisputeData = (...params: Parameters<ProofOfHumanityExtended["arbitratorDisputeIDToDisputeData"]>) =>
  checkContract(poh, "arbitratorDisputeIDToDisputeData")(...params);
const checkSubmissionInfo = (...params: Parameters<ProofOfHumanityExtended["getSubmissionInfo"]>) => ({
  ...checkContract(poh, "getSubmissionInfo")(...params),
  onOld: checkContract(oldPoH, "getSubmissionInfo")(...params),
});
const checkArbitratorDataList = (...params: Parameters<ProofOfHumanityExtended["arbitratorDataList"]>) => ({
  ...checkContract(poh, "arbitratorDataList")(...params),
  onOld: checkContract(oldPoH, "arbitratorDataList")(...params),
});

const checkRoundInfo = (...args: Parameters<ProofOfHumanityExtended["getRoundInfo"]>) => ({
  async for(argsToCheck: RoundInfo) {
    const round = await poh.getRoundInfo(...args);
    for (const arg in argsToCheck) {
      if (arg === "paidFeesForNone") {
        expect(round.paidFees[0], `Argument '${arg}' has not been registered correctly`).to.equal(argsToCheck[arg]);
      } else if (arg === "paidFeesForRequester") {
        expect(round.paidFees[1], `Argument '${arg}' has not been registered correctly`).to.equal(argsToCheck[arg]);
      } else if (arg === "paidFeesForChallenger") {
        expect(round.paidFees[2], `Argument '${arg}' has not been registered correctly`).to.equal(argsToCheck[arg]);
      } else {
        expect(round[arg as any], `Argument '${arg}' has not been registered correctly`).to.equal(
          (argsToCheck as any)[arg]
        );
      }
    }
  },
});
