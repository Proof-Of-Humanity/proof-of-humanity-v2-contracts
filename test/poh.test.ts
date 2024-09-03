import { ethers, network } from "hardhat";
import { expect } from "chai";
import { AddressZero } from "@ethersproject/constants";
import { MockArbitrator, MockArbitrator__factory, ProofOfHumanity, ProofOfHumanity__factory } from "../typechain-types";
import { solidityPackedKeccak256 } from "ethers";
import { Party, Reason, Status } from "../utils/enums";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

const MULTIPLIER_DIVISOR = 10000;
const arbitratorExtraData = "0x85";
const arbitrationCost = 1000;
const submissionBaseDeposit = 5000;
const submissionDuration = 86400;
const challengePeriodDuration = 600;
const renewalPeriodDuration = 6000;
const failedRevocationCooldown = 2400;
const nbVouches = 2;
const requesterTotalCost = arbitrationCost + submissionBaseDeposit;
const appealTimeOut = 180;

const sharedStakeMultiplier = 5000;
const winnerStakeMultiplier = 2000;
const loserStakeMultiplier = 8000;

const gasPrice = BigInt(875000000);

const registrationMetaEvidence = "registrationMetaEvidence.json";
const clearingMetaEvidence = "clearingMetaEvidence.json";
const evidence = "I'm human";
const name = "123";

let arbitrator: MockArbitrator;
let poh: ProofOfHumanity;

let [
  governor,
  requester,
  requester2,
  challenger1,
  challenger2,
  voucher1,
  voucher2,
  voucher3,
  other,
  wNativeMock,
  crosschainMock,
]: SignerWithAddress[] = [];

describe("ProofOfHumanity", function () {
  beforeEach("Initializing the contracts", async () => {
    [
      governor,
      requester,
      requester2,
      challenger1,
      challenger2,
      voucher1,
      voucher2,
      voucher3,
      other,
      wNativeMock,
      crosschainMock,
    ] = await ethers.getSigners();
    arbitrator = await new MockArbitrator__factory(governor).deploy(arbitrationCost);

    await arbitrator.connect(other).createDispute(3, arbitratorExtraData, { value: arbitrationCost }); // Create a dispute so the index in tests will not be a default value.

    poh = await new ProofOfHumanity__factory(governor).deploy();
    await poh
      .connect(governor)
      .initialize(
        wNativeMock.address,
        arbitrator.target,
        arbitratorExtraData,
        registrationMetaEvidence,
        clearingMetaEvidence,
        submissionBaseDeposit,
        submissionDuration,
        renewalPeriodDuration,
        challengePeriodDuration,
        failedRevocationCooldown,
        [sharedStakeMultiplier, winnerStakeMultiplier, loserStakeMultiplier],
        nbVouches
      );
    await poh.connect(governor).changeCrossChainProofOfHumanity(crosschainMock);
  });

  it("Should return the correct initial value", async function () {
    expect(await poh.governor()).to.equal(governor.address);
    expect(await poh.wNative()).to.equal(wNativeMock.address);
    expect(await poh.requestBaseDeposit()).to.equal(submissionBaseDeposit);
    expect(await poh.humanityLifespan()).to.equal(submissionDuration);
    expect(await poh.renewalPeriodDuration()).to.equal(renewalPeriodDuration);
    expect(await poh.challengePeriodDuration()).to.equal(challengePeriodDuration);
    expect(await poh.challengePeriodDuration()).to.equal(challengePeriodDuration);
    expect(await poh.failedRevocationCooldown()).to.equal(failedRevocationCooldown);
    expect(await poh.winnerStakeMultiplier()).to.equal(winnerStakeMultiplier);
    expect(await poh.loserStakeMultiplier()).to.equal(loserStakeMultiplier);
    expect(await poh.requiredNumberOfVouches()).to.equal(nbVouches);
    expect(await poh.crossChainProofOfHumanity()).to.equal(crosschainMock.address);

    const arbitratorData = await poh.arbitratorDataHistory(0);
    expect(arbitratorData[0]).to.equal(0, "Incorrect metaevidenceUpdates");
    expect(arbitratorData[1]).to.equal(arbitrator.target, "Incorrect arbitrator set");
    expect(arbitratorData[2]).to.equal(arbitratorExtraData, "Incorrect arbitrator extra data");
    expect(await poh.getArbitratorDataHistoryCount()).to.equal(1, "Incorrect arbitrator history count");

    // Check initialize modifier
    await expect(
      poh
        .connect(governor)
        .initialize(
          other.address,
          arbitrator.target,
          arbitratorExtraData,
          registrationMetaEvidence,
          clearingMetaEvidence,
          submissionBaseDeposit,
          submissionDuration,
          renewalPeriodDuration,
          challengePeriodDuration,
          failedRevocationCooldown,
          [sharedStakeMultiplier, winnerStakeMultiplier, loserStakeMultiplier],
          nbVouches
        )
    ).to.be.revertedWithoutReason();
  });

  it("Check cross-chain functions", async function () {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration

    await expect(
      poh.connect(other).ccGrantHumanity(requester.address, requester.address, expirationTime)
    ).to.be.revertedWithoutReason();

    await expect(poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime))
      .to.emit(poh, "HumanityGrantedDirectly")
      // Convert to lower case to match bytes20
      .withArgs(requester.address.toLowerCase(), requester.address, expirationTime);

    const humanityInfo = await poh.getHumanityInfo(requester.address);
    expect(humanityInfo[3]).to.equal(expirationTime, "Incorrect expiration time after direct submission");
    expect(humanityInfo[4]).to.equal(requester.address, "Incorrect owner after direct submission");

    expect(await poh.isHuman(requester.address)).to.equal(true, "Profile should be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(true, "Profile should be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(requester.address, "Incorrect bound address");
    expect(await poh.humanityOf(requester.address)).to.equal(
      requester.address.toLowerCase(),
      "Incorrect humanity Id to address"
    );

    // Check that it'll return false 2nd time
    await expect(
      poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime)
    ).to.not.emit(poh, "HumanityGrantedDirectly");

    // Check that can't grant humanity when request is active
    await poh.connect(requester2).claimHumanity(requester2.address, evidence, name);
    await expect(
      poh.connect(crosschainMock).ccGrantHumanity(requester2.address, requester2.address, expirationTime)
    ).to.be.revertedWithoutReason();

    // Check discharge function

    // Check permission
    await expect(poh.connect(other).ccDischargeHumanity(requester.address)).to.be.revertedWithoutReason();

    // Should revert when supplied address doesn't match owner (0 in this case as requester2 profile isn't claimed)
    await expect(poh.connect(crosschainMock).ccDischargeHumanity(requester2.address)).to.be.revertedWithoutReason();

    // Shouldn't allow discharge while request is active
    await poh.connect(requester).revokeHumanity(requester.address, evidence, { value: requesterTotalCost });
    await expect(poh.connect(crosschainMock).ccDischargeHumanity(requester.address)).to.be.revertedWithoutReason();
  });

  it("Check expiration time require for crosschain discharge", async function () {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    await network.provider.send("evm_increaseTime", [submissionDuration + 1]);

    await expect(poh.connect(crosschainMock).ccDischargeHumanity(requester.address)).to.be.revertedWithoutReason();
  });

  it("Check vouching require for crosschain discharge", async function () {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration
    await poh.connect(governor).changeRequiredNumberOfVouches(1);
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    await poh.connect(requester2).claimHumanity(requester2.address, evidence, name, { value: requesterTotalCost });

    await poh.connect(requester).addVouch(requester2.address, requester2.address);
    await poh.connect(governor).advanceState(requester2.address, [requester.address], []);

    await expect(poh.connect(crosschainMock).ccDischargeHumanity(requester.address)).to.be.revertedWithoutReason();
  });

  it("Should set correct values after discharge", async function () {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    await expect(poh.connect(crosschainMock).ccDischargeHumanity(requester.address))
      .to.emit(poh, "HumanityDischargedDirectly")
      // Convert to lower case to match bytes20
      .withArgs(requester.address.toLowerCase());

    expect(await poh.isHuman(requester.address)).to.equal(false, "Profile should not be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(false, "Profile should not be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(AddressZero, "Should be bound to 0");
    expect(await poh.humanityOf(requester.address)).to.equal(AddressZero, "Incorrect humanity Id to address");

    // Should revert 2nd time

    await expect(poh.connect(crosschainMock).ccDischargeHumanity(requester.address)).to.be.revertedWithoutReason();
  });

  it("Should set correct values after creating a request to add new submission", async () => {
    // Change metaevidence so arbitrator data ID is not 0
    await poh.connect(governor).changeMetaEvidence("1", "2");
    const oldBalance = await ethers.provider.getBalance(requester.address);

    const addSubmissionTX = await (
      await poh.connect(requester).claimHumanity(requester.address, evidence, name, {
        gasPrice: gasPrice,
        // Overpay to check reimbursement
        value: BigInt(1e18),
      })
    ).wait();
    if (!addSubmissionTX) return;
    const txFee = addSubmissionTX.gasUsed * gasPrice;

    const newBalance = await ethers.provider.getBalance(requester.address);
    expect(newBalance).to.equal(oldBalance - txFee - BigInt(requesterTotalCost), "Incorrect balance after submission");

    const hash = solidityPackedKeccak256(["bytes20", "uint256"], [requester.address, 0]); // Request id is 0
    const evidenceGroupId = BigInt(hash);

    await expect(addSubmissionTX)
      .to.emit(poh, "ClaimRequest")
      .withArgs(requester.address, requester.address.toLowerCase(), 0, name)
      .to.emit(poh, "Evidence")
      .withArgs(arbitrator.target, evidenceGroupId, requester.address, evidence)
      .to.emit(poh, "Contribution")
      .withArgs(requester.address.toLowerCase(), 0, 0, 0, requester.address, 6000, Party.Requester); // humanity id, request, challenge, round, contributor, contribution, side

    const requestInfo = await poh.getRequestInfo(requester.address, 0);
    expect(requestInfo[2]).to.equal(1, "Incorrect arbitrator data id");
    expect(requestInfo[5]).to.equal(requester.address, "Incorrect requester stored");
    expect(requestInfo[7]).to.equal(Status.Vouching, "Status should not change");

    const roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(requesterTotalCost, "Requester should be fully funded");
    expect(roundInfo[2]).to.equal(0, "Challenger should not be funded");
    expect(roundInfo[3]).to.equal(Party.Requester, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(requesterTotalCost, "Incorrect fee rewards value");

    const contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(contribution[0]).to.equal(6000, "Requester contribution has not been registered correctly"); // total cost = 6000

    expect(await poh.isHuman(requester.address)).to.equal(false, "Profile should not be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(false, "Profile should not be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(AddressZero, "Should be bound to 0");
    expect(await poh.humanityOf(requester.address)).to.equal(AddressZero, "Incorrect humanity Id to address");

    expect((await poh.getHumanityInfo(requester.address))[5]).to.equal(1, "Incorrect number of requests for profile");
    expect((await poh.getHumanityInfo(requester.address))[3]).to.equal(0, "Expiration time should not be set");

    // Should revert 2nd time
    await expect(poh.connect(requester).claimHumanity(requester.address, evidence, name)).to.be.revertedWithoutReason();
  });

  it("Check requires for claim humanity", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    let expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration

    await expect(poh.connect(requester).claimHumanity(AddressZero, evidence, name)).to.be.revertedWithoutReason();

    // Can't claim someone else's registered profile

    await poh.connect(crosschainMock).ccGrantHumanity(requester2.address, requester2.address, expirationTime);

    await expect(
      poh.connect(requester).claimHumanity(requester2.address, evidence, name)
    ).to.be.revertedWithoutReason();

    // Can't claim once claimed already

    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    await expect(poh.connect(requester).claimHumanity(requester.address, evidence, name)).to.be.revertedWithoutReason();

    // Check that can make a claim once the profiles expired.
    await network.provider.send("evm_increaseTime", [submissionDuration + 1]);

    await expect(poh.connect(requester).claimHumanity(requester.address, evidence, name))
      .to.emit(poh, "ClaimRequest")
      .withArgs(requester.address, requester.address.toLowerCase(), 0, name);

    await expect(poh.connect(requester2).claimHumanity(requester2.address, evidence, name))
      .to.emit(poh, "ClaimRequest")
      .withArgs(requester2.address, requester2.address.toLowerCase(), 0, name);
  });

  it("Should correctly fund a new submission", async () => {
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: 200 });

    let roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(200, "Funded value registered incorrectly");
    expect(roundInfo[2]).to.equal(0, "Challenger should not be funded");
    expect(roundInfo[3]).to.equal(Party.None, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(200, "Incorrect fee rewards value");

    let contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(contribution[0]).to.equal(200, "Requester contribution has not been registered correctly");

    await poh.connect(other).fundRequest(requester.address, 0, { value: 500 });

    roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0);
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(700, "Funded value registered incorrectly");
    expect(roundInfo[2]).to.equal(0, "Challenger should not be funded");
    expect(roundInfo[3]).to.equal(Party.None, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(700, "Incorrect fee rewards value");

    contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(contribution[0]).to.equal(200, "Requester contribution has not been registered correctly");
    contribution = await poh.getContributions(requester.address, 0, 0, 0, other.address);
    expect(contribution[0]).to.equal(500, "Crowdfunder contribution has not been registered correctly");

    const oldBalance = await ethers.provider.getBalance(other.address);

    const fundSubmissionTX = await (
      await poh.connect(other).fundRequest(requester.address, 0, {
        gasPrice: gasPrice,
        // Overpay to check reimbursement
        value: BigInt(1e18),
      })
    ).wait();
    if (!fundSubmissionTX) return;
    const txFee = fundSubmissionTX.gasUsed * gasPrice;
    const newBalance = await ethers.provider.getBalance(other.address);

    expect(newBalance).to.equal(oldBalance - txFee - BigInt(5300), "Incorrect balance after revocation request"); // 700 out of 600 was already paid

    roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0);
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(requesterTotalCost, "Funded value registered incorrectly");
    expect(roundInfo[2]).to.equal(0, "Challenger should not be funded");
    expect(roundInfo[3]).to.equal(Party.Requester, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(requesterTotalCost, "Incorrect fee rewards value");

    contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(contribution[0]).to.equal(200, "Requester contribution has not been registered correctly");
    contribution = await poh.getContributions(requester.address, 0, 0, 0, other.address);
    expect(contribution[0]).to.equal(5800, "Crowdfunder contribution has not been registered correctly");

    // Check the require. For that advance the state of the profile

    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration
    await poh.connect(governor).changeRequiredNumberOfVouches(1);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);

    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address], []);

    await expect(poh.connect(other).fundRequest(requester.address, 0, { value: 500 })).to.be.revertedWithoutReason();

    // Manually registered profile can't be funded also as he has empty requests array. And if it had finished requests their status wouldn't allow funding either
    await expect(poh.connect(other).fundRequest(voucher1.address, 0, { value: 500 })).to.be.revertedWithPanic("0x32");
  });

  it("Check the funding bug status. Remove this test when it's fixed", async () => {
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });

    let roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(6000, "Funded value registered incorrectly");
    expect(roundInfo[2]).to.equal(0, "Challenger should not be funded");
    expect(roundInfo[3]).to.equal(Party.Requester, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(6000, "Incorrect fee rewards value");

    await poh.connect(other).fundRequest(requester.address, 0);

    roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0);
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(6000, "Funded value registered incorrectly");
    expect(roundInfo[2]).to.equal(0, "Challenger should not be funded");
    expect(roundInfo[3]).to.equal(Party.None, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(6000, "Incorrect fee rewards value");

    await poh.connect(requester).fundRequest(requester.address, 0);

    roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0);
    expect(roundInfo[3]).to.equal(Party.Requester, "Incorrect party funding status");
  });

  it("Should set correct values after creating a request to remove a submission", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration
    // Register the profile first
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    // Change metaevidence so arbitrator data ID is not 0
    await poh.connect(governor).changeMetaEvidence("1", "2");

    const hash = solidityPackedKeccak256(["bytes20", "uint256"], [requester.address, 0]); // Request id is 0
    const evidenceGroupId = BigInt(hash);

    // We'll fund a request with other account
    const oldBalance = await ethers.provider.getBalance(other.address);

    const removeSubmissionTX = await (
      await poh.connect(other).revokeHumanity(requester.address, "Bad human", {
        gasPrice: gasPrice,
        // Overpay to check reimbursement
        value: BigInt(1e18),
      })
    ).wait();
    if (!removeSubmissionTX) return;
    const txFee = removeSubmissionTX.gasUsed * gasPrice;
    const newBalance = await ethers.provider.getBalance(other.address);

    expect(newBalance).to.equal(
      oldBalance - txFee - BigInt(requesterTotalCost),
      "Incorrect balance after revocation request"
    );

    await expect(removeSubmissionTX)
      .to.emit(poh, "RevocationRequest")
      .withArgs(other.address, requester.address.toLowerCase(), 0) // Request id is 0
      .to.emit(poh, "Evidence")
      .withArgs(arbitrator.target, evidenceGroupId, other.address, "Bad human")
      .to.emit(poh, "Contribution")
      .withArgs(requester.address.toLowerCase(), 0, 0, 0, other.address, 6000, Party.Requester); // humanity id, request, challenge, round, contributor, contribution, side

    const requestInfo = await poh.getRequestInfo(requester.address, 0);
    expect(requestInfo[2]).to.equal(1, "Incorrect arbitrator data id");
    expect(requestInfo[4]).to.not.equal(0, "Challenge start time should be updated");
    expect(requestInfo[5]).to.equal(other.address, "Incorrect requester stored");
    expect(requestInfo[7]).to.equal(Status.Resolving, "Status should be Resolving");

    const roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(requesterTotalCost, "Requester should be fully funded");
    expect(roundInfo[2]).to.equal(0, "Challenger should not be funded");
    expect(roundInfo[3]).to.equal(Party.Requester, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(requesterTotalCost, "Incorrect fee rewards value");

    const contribution = await poh.getContributions(requester.address, 0, 0, 0, other.address);
    expect(contribution[0]).to.equal(6000, "Other contribution has not been registered correctly"); // total cost = 6000

    expect(await poh.isHuman(requester.address)).to.equal(true, "Profile should still be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(true, "Profile should still be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(requester.address, "Should still be bound");
    expect(await poh.humanityOf(requester.address)).to.equal(
      requester.address.toLowerCase(),
      "Incorrect humanity Id to address"
    );

    const humanityInfo = await poh.getHumanityInfo(requester.address);
    expect(humanityInfo[1]).to.equal(true, "Should be pending revocation");
    expect(humanityInfo[2]).to.equal(1, "Number of pending requests incorrect");
    expect(humanityInfo[5]).to.equal(1, "Incorrect number of requests for profile");
  });

  it("Check requires for revocation requests", async () => {
    // Can't revoke not registered profile
    await expect(
      poh.connect(other).revokeHumanity(requester.address, "Bad human", { value: requesterTotalCost })
    ).to.be.revertedWithoutReason();

    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration
    // Register the profile first
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    // Check the underpay revert
    await expect(
      poh.connect(other).revokeHumanity(requester.address, "Bad human", { value: requesterTotalCost - 1 })
    ).to.be.revertedWithoutReason();

    // Check that can't make request 2nd time

    await poh.connect(other).revokeHumanity(requester.address, "Bad human", { value: requesterTotalCost });

    await expect(
      poh.connect(other).revokeHumanity(requester.address, "Bad human", { value: requesterTotalCost })
    ).to.be.revertedWithoutReason();

    // Check revocation timeout

    await poh.connect(challenger1).challengeRequest(requester.address, 0, Reason.None, "", { value: arbitrationCost });
    // Rule the dispute in favor of challenger so the profile isn't deleted
    await arbitrator.connect(governor).giveRuling(1, Party.Challenger);

    await expect(
      poh.connect(other).revokeHumanity(requester.address, "Bad human", { value: requesterTotalCost })
    ).to.be.revertedWithoutReason();

    await network.provider.send("evm_increaseTime", [failedRevocationCooldown + 1]);

    await expect(
      poh.connect(other).revokeHumanity(requester.address, "Bad human", { value: requesterTotalCost })
    ).to.emit(poh, "RevocationRequest");
  });

  it("Check that can't revoke an expired profile", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration
    // Register the profile first
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    await network.provider.send("evm_increaseTime", [submissionDuration + 1]);
    await expect(
      poh.connect(other).revokeHumanity(requester.address, "Bad human", { value: requesterTotalCost })
    ).to.be.revertedWithoutReason();
  });

  it("Should correctly make a renewal request", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration
    // Register the profile first
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    // Check that can't renew until renewal phase
    await expect(
      poh.connect(requester).renewHumanity("Still human", { value: requesterTotalCost })
    ).to.be.revertedWithoutReason();

    await network.provider.send("evm_increaseTime", [submissionDuration + 1 - renewalPeriodDuration]);

    // Check that can only be renewed by the owner
    await expect(
      poh.connect(other).renewHumanity("Still human", { value: requesterTotalCost })
    ).to.be.revertedWithoutReason();

    const oldBalance = await ethers.provider.getBalance(requester.address);

    const renewSubmissionTX = await (
      await poh.connect(requester).renewHumanity("Still human", {
        gasPrice: gasPrice,
        // Overpay to check reimbursement
        value: BigInt(1e18),
      })
    ).wait();
    if (!renewSubmissionTX) return;
    const txFee = renewSubmissionTX.gasUsed * gasPrice;

    const newBalance = await ethers.provider.getBalance(requester.address);
    expect(newBalance).to.equal(oldBalance - txFee - BigInt(requesterTotalCost), "Incorrect balance after submission");

    const hash = solidityPackedKeccak256(["bytes20", "uint256"], [requester.address, 0]); // Request id is 0
    const evidenceGroupId = BigInt(hash);

    await expect(renewSubmissionTX)
      .to.emit(poh, "RenewalRequest")
      .withArgs(requester.address, requester.address.toLowerCase(), 0)
      .to.emit(poh, "Evidence")
      .withArgs(arbitrator.target, evidenceGroupId, requester.address, "Still human")
      .to.emit(poh, "Contribution")
      .withArgs(requester.address.toLowerCase(), 0, 0, 0, requester.address, 6000, Party.Requester); // humanity id, request, challenge, round, contributor, contribution, side

    const requestInfo = await poh.getRequestInfo(requester.address, 0);
    expect(requestInfo[2]).to.equal(0, "Incorrect arbitrator data id"); // It's default in this case
    expect(requestInfo[5]).to.equal(requester.address, "Incorrect requester stored");
    expect(requestInfo[7]).to.equal(Status.Vouching, "Status should not change");

    const roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(requesterTotalCost, "Requester should be fully funded");
    expect(roundInfo[2]).to.equal(0, "Challenger should not be funded");
    expect(roundInfo[3]).to.equal(Party.Requester, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(requesterTotalCost, "Incorrect fee rewards value");

    const contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(contribution[0]).to.equal(6000, "Requester contribution has not been registered correctly"); // total cost = 6000

    expect(await poh.isHuman(requester.address)).to.equal(true, "Profile should still be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(true, "Profile should still be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(requester.address, "Should be bound to requester");
    expect(await poh.humanityOf(requester.address)).to.equal(
      requester.address.toLowerCase(),
      "Incorrect humanity Id to address"
    );

    expect((await poh.getHumanityInfo(requester.address))[4]).to.equal(requester.address, "Should still be the owner");
    expect((await poh.getHumanityInfo(requester.address))[5]).to.equal(1, "Incorrect number of requests for profile");
  });

  it("Should correctly change status after expiration", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration; // Increase for submission duration
    // Register the profile first
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);
    await network.provider.send("evm_increaseTime", [submissionDuration + 1]);
    // Send a random tx to trigger new time increase for view functions
    await poh.connect(governor).changeMetaEvidence("1", "2");

    expect(await poh.isHuman(requester.address)).to.equal(false, "Profile expired");
    expect(await poh.isClaimed(requester.address)).to.equal(false, "Claim status expired");
    expect(await poh.boundTo(requester.address)).to.equal(AddressZero, "Should be bound to 0");
    expect(await poh.humanityOf(requester.address)).to.equal(
      AddressZero,
      "Incorrect humanity Id to address. Should be 0"
    );
  });

  it("Should correctly store vouches and change vouching state", async () => {
    // Pre-emptively register 2 vouching profiles.
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);

    // Should revert if no request was made.
    await expect(
      poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], [])
    ).to.be.revertedWithPanic("0x11");

    await poh.connect(requester).claimHumanity(requester.address, evidence, name);

    await expect(poh.connect(voucher1).addVouch(requester.address, requester.address))
      .to.emit(poh, "VouchAdded")
      .withArgs(voucher1.address, requester.address, requester.address.toLowerCase());

    expect(await poh.vouches(voucher1.address, requester.address, requester.address)).to.equal(
      true,
      "Vouch not registered"
    );

    // Check vouch removal and then add it back again
    await expect(poh.connect(voucher1).removeVouch(requester.address, requester.address))
      .to.emit(poh, "VouchRemoved")
      .withArgs(voucher1.address, requester.address, requester.address.toLowerCase());

    expect(await poh.vouches(voucher1.address, requester.address, requester.address)).to.equal(
      false,
      "Vouch should not be registered"
    );

    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    // Deilberated add a fake voucher to check
    await poh.connect(other).addVouch(requester.address, requester.address);

    // Should revert since submission isn't funded
    await expect(
      poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], [])
    ).to.be.revertedWithoutReason();

    await poh.connect(other).fundRequest(requester.address, 0, { value: requesterTotalCost });

    // Check that can't advance if not enough legit vouches

    await expect(
      poh.connect(governor).advanceState(requester.address, [voucher1.address, other.address, governor.address], [])
    ).to.be.revertedWithPanic("0x32");

    await poh.connect(voucher1).removeVouch(requester.address, requester.address);

    await expect(
      poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], [])
    ).to.be.revertedWithPanic("0x32");

    await poh.connect(voucher1).addVouch(requester.address, requester.address);

    await expect(poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []))
      .to.emit(poh, "StateAdvanced")
      .withArgs(requester.address)
      .to.emit(poh, "VouchRegistered")
      .withArgs(voucher1.address.toLowerCase(), requester.address.toLowerCase(), 0)
      .to.emit(poh, "VouchRegistered")
      .withArgs(voucher2.address.toLowerCase(), requester.address.toLowerCase(), 0);

    expect((await poh.getHumanityInfo(requester.address))[2]).to.equal(1, "Incorrect number of requests for profile");
    expect((await poh.getHumanityInfo(voucher1.address))[0]).to.equal(true, "Profile should be marked as vouching");
    expect((await poh.getHumanityInfo(voucher2.address))[0]).to.equal(true, "Profile should be marked as vouching");

    expect(await poh.getNumberOfVouches(requester.address, 0)).to.equal(2, "Incorrect number of registered vouches");

    const requestInfo = await poh.getRequestInfo(requester.address, 0);
    expect(requestInfo[4]).to.not.equal(0, "Challenge start time should be updated");
    expect(requestInfo[7]).to.equal(Status.Resolving, "Status should change");

    // Should revert 2nd time
    await expect(
      poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], [])
    ).to.be.revertedWithoutReason();
  });

  it("Check that invalid vouches are not counted", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);

    // Change required number of vouches to 1 to make checks more transparent
    await poh.connect(governor).changeRequiredNumberOfVouches(1);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });

    // Empty array of vouchers.
    await expect(poh.connect(governor).advanceState(requester.address, [], [])).to.be.revertedWithPanic("0x32");

    // Array with voucher who didn't vouch.
    await expect(poh.connect(governor).advanceState(requester.address, [voucher1.address], [])).to.be.revertedWithPanic(
      "0x32"
    );

    // Voucher who already vouched for a different submission.
    await poh.connect(requester2).claimHumanity(requester2.address, evidence, name, { value: requesterTotalCost });

    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester2.address, requester2.address);
    await poh.connect(governor).advanceState(requester2.address, [voucher2.address], []);

    await expect(poh.connect(governor).advanceState(requester.address, [voucher2.address], [])).to.be.revertedWithPanic(
      "0x32"
    );

    // Change the nbVouches back to do another check.
    await poh.connect(governor).changeRequiredNumberOfVouches(2);
    await poh.connect(voucher1).addVouch(requester.address, requester.address);

    // Check that the voucher can't be duplicated.
    await expect(
      poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher1.address], [])
    ).to.be.revertedWithPanic("0x32");

    // Voucher whose submission time has expired.
    await poh.connect(governor).changeRequiredNumberOfVouches(1);
    await network.provider.send("evm_increaseTime", [submissionDuration + 1]);

    await expect(poh.connect(governor).advanceState(requester.address, [voucher1.address], [])).to.be.revertedWithPanic(
      "0x32"
    );
  });

  it("Should not use more vouches than needed", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher3.address, voucher3.address, expirationTime);

    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });

    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(voucher3).addVouch(requester.address, requester.address);

    await poh
      .connect(governor)
      .advanceState(requester.address, [voucher1.address, voucher2.address, voucher3.address], []);
    expect((await poh.getHumanityInfo(voucher1.address))[0]).to.equal(true, "Profile should be marked as vouching");
    expect((await poh.getHumanityInfo(voucher2.address))[0]).to.equal(true, "Profile should be marked as vouching");
    expect((await poh.getHumanityInfo(voucher3.address))[0]).to.equal(
      false,
      "Profile should not be marked as vouching"
    );
  });

  it("Should set correct values and create a dispute after the submission is challenged", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);

    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });

    // Check that the submission with the wrong status can't be challenged.
    await expect(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Bad human", { value: arbitrationCost })
    ).to.be.revertedWithoutReason();

    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);

    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    // Should revert if reason not specified
    await expect(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, 0, Reason.None, "Bad human", { value: arbitrationCost })
    ).to.be.revertedWithoutReason();

    // Check the funding
    await expect(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Bad human", { value: arbitrationCost - 1 })
    ).to.be.revertedWithoutReason();

    const oldBalance = await ethers.provider.getBalance(challenger1.address);
    const challengeSubmissionTX = await (
      await poh.connect(challenger1).challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Bad human", {
        gasPrice: gasPrice,
        // Overpay to check reimbursement
        value: BigInt(1e18),
      })
    ).wait();
    if (!challengeSubmissionTX) return;
    const txFee = challengeSubmissionTX.gasUsed * gasPrice;

    const newBalance = await ethers.provider.getBalance(challenger1.address);
    expect(newBalance).to.equal(oldBalance - txFee - BigInt(arbitrationCost), "Incorrect balance after challenge");

    // Shouldn't allow to challenge 2nd time
    await expect(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Bad human", { value: BigInt(1e18) })
    ).to.be.revertedWithoutReason();

    const hash = solidityPackedKeccak256(["bytes20", "uint256"], [requester.address, 0]); // Request id is 0
    const evidenceGroupId = BigInt(hash);

    await expect(challengeSubmissionTX)
      .to.emit(poh, "RequestChallenged")
      .withArgs(requester.address.toLowerCase(), 0, 0, Reason.IncorrectSubmission, 1) // HumanityId, request, challenge, reason, dispute id
      .to.emit(poh, "Dispute")
      .withArgs(arbitrator.target, 1, 0, evidenceGroupId) // arbitrator, dispute, metaevidence id, evidence grou
      .to.emit(poh, "Evidence")
      .withArgs(arbitrator.target, evidenceGroupId, challenger1.address, "Bad human")
      .to.emit(poh, "Contribution")
      .withArgs(requester.address.toLowerCase(), 0, 0, 0, challenger1.address, 1000, Party.Challenger);

    const requestInfo = await poh.getRequestInfo(requester.address, 0);
    expect(requestInfo[1]).to.equal(1, "Incorrect reason bitmap");
    expect(requestInfo[3]).to.equal(1, "Incorrect last challenge id");
    expect(requestInfo[7]).to.equal(Status.Disputed, "Status should be disputed");
    expect(requestInfo[8]).to.equal(Reason.IncorrectSubmission, "Incorrect current reason");

    const roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 0); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(true, "Should increment round id for appeals");
    expect(roundInfo[1]).to.equal(requesterTotalCost, "Requester should be fully funded");
    expect(roundInfo[2]).to.equal(arbitrationCost, "Challenger should be fullyfunded");
    expect(roundInfo[3]).to.equal(Party.None, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(requesterTotalCost, "Incorrect fee rewards value"); // This value won't change since challenger's deposit will cover arbitration fees

    const challengeInfo = await poh.getChallengeInfo(requester.address, 0, 0);
    expect(challengeInfo[0]).to.equal(1, "Round should be incremented");
    expect(challengeInfo[1]).to.equal(challenger1.address, "Incorrect challenger stored");
    expect(challengeInfo[2]).to.equal(1, "Incorrect dispute id");
    expect(challengeInfo[3]).to.equal(0, "Ruling should be 0");

    const disputeData = await poh.disputeIdToData(arbitrator.target, 1);
    expect(disputeData[0]).to.equal(0, "Wrong request id");
    expect(disputeData[1]).to.equal(0, "Wrong challenge id");
    expect(disputeData[2]).to.equal(requester.address.toLowerCase(), "Incorrect humanity id");

    const dispute = await arbitrator.disputes(1);
    expect(dispute[0]).to.equal(poh.target, "Incorrect arbitrable address");
    expect(dispute[1]).to.equal(2, "Incorrect number of choices");
    expect(dispute[2]).to.equal(1000, "Incorrect fees value stored");
  });

  it("Should not be possible to challenge after timeout", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    await network.provider.send("evm_increaseTime", [challengePeriodDuration + 1]);
    await expect(
      poh
        .connect(challenger1)
        .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Bad human", { value: BigInt(1e18) })
    ).to.be.revertedWithoutReason();
  });

  it("Should set correct values when challenging a removal request", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);

    // All checks for correct values have already been done in previous tests. Here just check conditions that are unique for this type of challenge.
    await poh.connect(requester).revokeHumanity(voucher1.address, "", { value: requesterTotalCost });
    // Reason must be left empty
    await expect(
      poh
        .connect(challenger1)
        .challengeRequest(voucher1.address, 0, Reason.IncorrectSubmission, "Bad human", { value: arbitrationCost })
    ).to.be.revertedWithoutReason();

    await poh
      .connect(challenger1)
      .challengeRequest(voucher1.address, 0, Reason.None, "Bad human", { value: arbitrationCost });

    const requestInfo = await poh.getRequestInfo(voucher1.address, 0);
    expect(requestInfo[1]).to.equal(0, "Incorrect reason bitmap");
    expect(requestInfo[3]).to.equal(1, "Incorrect last challenge id");
    expect(requestInfo[7]).to.equal(Status.Disputed, "Status should be disputed");
    expect(requestInfo[8]).to.equal(Reason.None, "Reason should be empty");
  });

  it("Should successfully execute a request if it has not been challenged", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);

    // Check status
    await expect(poh.connect(governor).executeRequest(requester.address, 0)).to.be.revertedWithoutReason();
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    // Check timeout
    await expect(poh.connect(governor).executeRequest(requester.address, 0)).to.be.revertedWithoutReason();

    await network.provider.send("evm_increaseTime", [challengePeriodDuration + 1]);

    expect(await poh.getClaimerRequestId(requester.address)).to.equal(0, "Request id should be 0");

    const oldBalance = await ethers.provider.getBalance(requester.address);
    await expect(poh.connect(governor).executeRequest(requester.address, 0))
      .to.emit(poh, "HumanityClaimed")
      // Convert to lower case to match bytes20
      .withArgs(requester.address.toLowerCase(), 0);
    const newBalance = await ethers.provider.getBalance(requester.address);
    expect(newBalance).to.equal(oldBalance + BigInt(requesterTotalCost), "Incorrect balance after reimbursement");

    // Request count was nullified thus it should underflow.
    await expect(poh.getClaimerRequestId(requester.address)).to.be.revertedWithPanic("0x11");

    expect((await poh.getRequestInfo(requester.address, 0))[7]).to.equal(Status.Resolved, "Incorrect status");

    expect((await poh.getHumanityInfo(requester.address))[2]).to.equal(
      0,
      "Incorrect number of active requests for profile"
    );
    let humanityInfo = await poh.getHumanityInfo(requester.address);
    expect(humanityInfo[2]).to.equal(0, "Incorrect number of active requests for profile");
    expect(humanityInfo[3]).to.not.equal(0, "Expiration time should be set");
    expect(humanityInfo[4]).to.equal(requester.address, "Incorrect owner after executing request");

    const contribution = await poh.getContributions(requester.address, 0, 0, 0, requester.address);
    expect(contribution[0]).to.equal(0, "Requester contribution should be 0");

    expect((await poh.getHumanityInfo(voucher1.address))[0]).to.equal(
      false,
      "Profile should not be marked as vouching"
    );
    expect((await poh.getHumanityInfo(voucher2.address))[0]).to.equal(
      false,
      "Profile should not be marked as vouching"
    );

    expect(await poh.isHuman(requester.address)).to.equal(true, "Profile should be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(true, "Profile should be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(requester.address, "Incorrect bound address");
    expect(await poh.humanityOf(requester.address)).to.equal(
      requester.address.toLowerCase(),
      "Incorrect humanity Id to address"
    );

    // Also check removal request.
    await poh.connect(other).revokeHumanity(requester.address, "123", { value: requesterTotalCost });
    await network.provider.send("evm_increaseTime", [challengePeriodDuration + 1]);

    await expect(poh.connect(governor).executeRequest(requester.address, 1))
      .to.emit(poh, "HumanityRevoked")
      // Convert to lower case to match bytes20
      .withArgs(requester.address.toLowerCase(), 1);

    humanityInfo = await poh.getHumanityInfo(requester.address);
    expect(humanityInfo[1]).to.equal(false, "Pending revocation should be false");
    expect(humanityInfo[2]).to.equal(0, "Incorrect number of active requests for profile");
    expect(humanityInfo[4]).to.equal(AddressZero, "Owner should be 0");

    expect(await poh.isHuman(requester.address)).to.equal(false, "Profile should not be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(false, "Profile should not be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(AddressZero, "Should be bound to 0");
    expect(await poh.humanityOf(requester.address)).to.equal(AddressZero, "Incorrect humanity Id to address");
  });

  it("Should not discharge a profile that is actively vouching", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher3.address, voucher3.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    await expect(poh.connect(crosschainMock).ccDischargeHumanity(voucher1.address)).to.be.revertedWithoutReason();
    await expect(poh.connect(crosschainMock).ccDischargeHumanity(voucher2.address)).to.be.revertedWithoutReason();

    // Check that it works on a profile that isn't vouching
    await expect(poh.connect(crosschainMock).ccDischargeHumanity(voucher3.address))
      .to.emit(poh, "HumanityDischargedDirectly")
      // Convert to lower case to match bytes20
      .withArgs(voucher3.address.toLowerCase());
  });

  it("Should demand correct appeal fees and register that appeal fee has been paid", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    // Check status. Should revert because there was no challenge yet and disputeData wasn't set up.
    await expect(
      poh.connect(challenger1).fundAppeal(arbitrator.target, 1, Party.Challenger, { value: BigInt(1e18) })
    ).to.be.revertedWithPanic("0x32");

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Suspicious human", {
        value: arbitrationCost,
      });

    await arbitrator.connect(governor).giveAppealableRuling(1, Party.Challenger, arbitrationCost, appealTimeOut); // Arbitration cost is the same as appeal cost

    // Appeal fee is the same as arbitration fee for this arbitrator.
    const loserAppealFee = arbitrationCost + (arbitrationCost * loserStakeMultiplier) / MULTIPLIER_DIVISOR; // 1000 + 1000 * 0.8 = 1800

    // Check that can't fund 0 side
    await expect(
      poh.connect(challenger1).fundAppeal(arbitrator.target, 1, Party.None, { value: loserAppealFee })
    ).to.be.revertedWithoutReason();

    // Other sanity checks
    await expect(
      poh.connect(challenger1).fundAppeal(poh.target, 1, Party.Challenger, { value: loserAppealFee }) // Incorrect arbitrator
    ).to.be.revertedWithoutReason();
    await expect(
      poh.connect(challenger1).fundAppeal(arbitrator.target, 2, Party.Challenger, { value: loserAppealFee }) // Dispute out of bounds
    ).to.be.revertedWithPanic("0x32");

    // Deliberately overpay to check that only required fee amount will be registered.
    await expect(poh.connect(requester).fundAppeal(arbitrator.target, 1, Party.Requester, { value: BigInt(1e18) }))
      .to.emit(poh, "Contribution")
      .withArgs(requester.address.toLowerCase(), 0, 0, 1, requester.address, loserAppealFee, Party.Requester);

    // Side already funded
    await expect(
      poh.connect(requester).fundAppeal(arbitrator.target, 1, Party.Requester, { value: BigInt(1e18) })
    ).to.be.revertedWithoutReason();

    let roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 1); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(loserAppealFee, "Requester should be fully funded");
    expect(roundInfo[2]).to.equal(0, "Challenger should not be funded");
    expect(roundInfo[3]).to.equal(Party.Requester, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(loserAppealFee, "Incorrect fee rewards value");

    const winnerAppealFee = arbitrationCost + (arbitrationCost * winnerStakeMultiplier) / MULTIPLIER_DIVISOR; // 1200
    // Increase time to make sure winner can pay in 2nd half.
    await network.provider.send("evm_increaseTime", [appealTimeOut / 2 + 1]);

    await expect(
      poh.connect(challenger1).fundAppeal(arbitrator.target, 1, Party.Challenger, { value: winnerAppealFee })
    )
      .to.emit(poh, "Contribution")
      .withArgs(requester.address.toLowerCase(), 0, 0, 1, challenger1.address, winnerAppealFee, Party.Challenger)
      .to.emit(poh, "AppealCreated")
      .withArgs(arbitrator.target, 1);

    // Check that can't fund right after successful appeal
    await expect(
      poh.connect(requester).fundAppeal(arbitrator.target, 1, Party.Challenger, { value: BigInt(1e18) })
    ).to.be.revertedWithoutReason();

    roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 1); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(true, "Should be appealed");
    expect(roundInfo[1]).to.equal(loserAppealFee, "Requester should be fully funded");
    expect(roundInfo[2]).to.equal(winnerAppealFee, "Challenger should be funded");
    expect(roundInfo[3]).to.equal(Party.None, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(loserAppealFee + winnerAppealFee - arbitrationCost, "Incorrect fee rewards value");

    expect((await poh.getChallengeInfo(requester.address, 0, 0))[0]).to.equal(2, "Round should be incremented");

    // If both sides pay their fees it starts new appeal round. Check that both sides have their values set to default.
    roundInfo = await poh.getRoundInfo(requester.address, 0, 0, 2); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(0, "Requester should have 0 funding in new round");
    expect(roundInfo[2]).to.equal(0, "Challenger should have 0 funding in new round");
    expect(roundInfo[3]).to.equal(Party.None, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(0, "Incorrect fee rewards value");

    // Resolve the first challenge to see if the new challenge will set correct values as well.
    await arbitrator.connect(governor).giveRuling(1, Party.Requester);

    // Should revert if reason is the same
    await expect(
      poh
        .connect(challenger2)
        .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Bad human", { value: arbitrationCost })
    ).to.be.revertedWithoutReason();

    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, 0, Reason.Deceased, "Suspicious human", { value: arbitrationCost });

    // Give 0 ruling to check shared multiplier this time
    const sharedAppealFee = arbitrationCost + (arbitrationCost * sharedStakeMultiplier) / MULTIPLIER_DIVISOR; // 1500
    await arbitrator.connect(governor).giveAppealableRuling(2, Party.None, arbitrationCost, appealTimeOut); // Arbitration cost is the same as appeal cost

    // Try to fund appeal of the previous dispute to see if it fails
    await expect(
      poh.connect(requester).fundAppeal(arbitrator.target, 1, Party.Requester, { value: BigInt(1e18) })
    ).to.be.revertedWithoutReason();

    await poh.connect(requester).fundAppeal(arbitrator.target, 2, Party.Requester, { value: BigInt(1e18) }); // Note that dispute ID incremented

    roundInfo = await poh.getRoundInfo(requester.address, 0, 1, 1); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(false, "Should not be appealed");
    expect(roundInfo[1]).to.equal(sharedAppealFee, "Requester should have sharedAppealFee funded");
    expect(roundInfo[2]).to.equal(0, "Challenger should have 0 funding");
    expect(roundInfo[3]).to.equal(Party.Requester, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(sharedAppealFee, "Incorrect fee rewards value");

    await poh.connect(challenger1).fundAppeal(arbitrator.target, 2, Party.Challenger, { value: sharedAppealFee });
    roundInfo = await poh.getRoundInfo(requester.address, 0, 1, 1); // id, request, challenge, round
    expect(roundInfo[0]).to.equal(true, "Should be appealed");
    expect(roundInfo[1]).to.equal(sharedAppealFee, "Requester should have sharedAppealFee funded");
    expect(roundInfo[2]).to.equal(sharedAppealFee, "Challenger should have sharedAppealFee funded");
    expect(roundInfo[3]).to.equal(Party.None, "Incorrect party funding status");
    expect(roundInfo[4]).to.equal(sharedAppealFee * 2 - arbitrationCost, "Incorrect fee rewards value");

    expect((await poh.getRoundInfo(requester.address, 0, 1, 2))[3]).to.equal(
      Party.None,
      "Party should be default in a new round"
    );
  });

  it("Should not be possible to fund appeal if the timeout has passed", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Suspicious human", {
        value: arbitrationCost,
      });

    await arbitrator.connect(governor).giveAppealableRuling(1, Party.Requester, arbitrationCost, appealTimeOut); // Arbitration cost is the same as appeal cost

    const loserAppealFee = arbitrationCost + (arbitrationCost * winnerStakeMultiplier) / MULTIPLIER_DIVISOR;
    await network.provider.send("evm_increaseTime", [appealTimeOut / 2 + 1]);
    // Appeal period over for loser
    await expect(
      poh.connect(requester).fundAppeal(arbitrator.target, 1, Party.Challenger, { value: loserAppealFee })
    ).to.be.revertedWithoutReason();

    // Appeal period over for winner
    await network.provider.send("evm_increaseTime", [appealTimeOut / 2 + 1]);
    const winnerAppealFee = arbitrationCost + (arbitrationCost * winnerStakeMultiplier) / MULTIPLIER_DIVISOR;
    await expect(
      poh.connect(requester).fundAppeal(arbitrator.target, 1, Party.Requester, { value: winnerAppealFee })
    ).to.be.revertedWithoutReason();
  });

  it("Should correctly reset the challenge period if the requester wins", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Suspicious human", {
        value: arbitrationCost,
      });
    await expect(arbitrator.connect(governor).giveRuling(1, Party.Requester))
      .to.emit(poh, "ChallengePeriodRestart")
      .withArgs(requester.address.toLowerCase(), 0, 0) // Humanity id, request, challenge
      .to.emit(poh, "Ruling")
      .withArgs(arbitrator.target, 1, Party.Requester);

    const requestInfo = await poh.getRequestInfo(requester.address, 0);
    expect(requestInfo[7]).to.equal(Status.Resolving, "Status should be Resolving");
    expect(requestInfo[8]).to.equal(Reason.None, "Current reason should be nullified");

    // Check that it's not possible to challenge with the same reason.
    await expect(
      poh
        .connect(challenger2)
        .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Bad human", { value: arbitrationCost })
    ).to.be.revertedWithoutReason();

    // Check that can't execute before timeout after the 1st challenge
    await expect(poh.connect(governor).executeRequest(requester.address, 0)).to.be.revertedWithoutReason();

    // Also check that the execution of the request is still possible if there is no dispute.
    await network.provider.send("evm_increaseTime", [challengePeriodDuration + 1]);

    await expect(poh.connect(governor).executeRequest(requester.address, 0))
      .to.emit(poh, "HumanityClaimed")
      // Convert to lower case to match bytes20
      .withArgs(requester.address.toLowerCase(), 0);
  });

  it("Should register the submission if the requester won in all 4 reasons", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Suspicious human", {
        value: arbitrationCost,
      });
    await arbitrator.connect(governor).giveRuling(1, Party.Requester);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IdentityTheft, "Suspicious human", { value: arbitrationCost });
    await arbitrator.connect(governor).giveRuling(2, Party.Requester);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.SybilAttack, "Suspicious human", { value: arbitrationCost });
    await arbitrator.connect(governor).giveRuling(3, Party.Requester);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.Deceased, "Suspicious human", { value: arbitrationCost });

    await expect(arbitrator.connect(governor).giveRuling(4, Party.Requester))
      .to.emit(poh, "HumanityClaimed")
      .withArgs(requester.address.toLowerCase(), 0);

    const humanityInfo = await poh.getHumanityInfo(requester.address);
    expect(humanityInfo[2]).to.equal(0, "Incorrect number of active requests for profile");
    expect(humanityInfo[3]).to.not.equal(0, "Expiration time should be set");
    expect(humanityInfo[4]).to.equal(requester.address, "Incorrect owner after fulfilling request");

    expect(await poh.isHuman(requester.address)).to.equal(true, "Profile should be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(true, "Profile should be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(requester.address, "Incorrect bound address");
    expect(await poh.humanityOf(requester.address)).to.equal(
      requester.address.toLowerCase(),
      "Incorrect humanity Id to address"
    );

    expect((await poh.getRequestInfo(requester.address, 0))[7]).to.equal(Status.Resolved, "Request should be resolved");
    // Check the ruling stored for each dispute
    expect((await poh.getChallengeInfo(requester.address, 0, 0))[3]).to.equal(
      Party.Requester,
      "Incorrect ruling stored"
    );
    expect((await poh.getChallengeInfo(requester.address, 0, 1))[3]).to.equal(
      Party.Requester,
      "Incorrect ruling stored"
    );
    expect((await poh.getChallengeInfo(requester.address, 0, 2))[3]).to.equal(
      Party.Requester,
      "Incorrect ruling stored"
    );
    expect((await poh.getChallengeInfo(requester.address, 0, 3))[3]).to.equal(
      Party.Requester,
      "Incorrect ruling stored"
    );
    // And check the default ruling of unprocced challenge ID
    expect((await poh.getChallengeInfo(requester.address, 0, 4))[3]).to.equal(Party.None, "Ruling should be default");

    // Request count was nullified thus it should underflow.
    await expect(poh.getClaimerRequestId(requester.address)).to.be.revertedWithPanic("0x11");
  });

  it("Should set correct values if arbitrator refuses to rule", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Suspicious human", {
        value: arbitrationCost,
      });

    await expect(arbitrator.connect(governor).giveRuling(1, Party.None))
      .to.emit(poh, "Ruling")
      .withArgs(arbitrator.target, 1, Party.None)
      .to.not.emit(poh, "HumanityClaimed");

    const humanityInfo = await poh.getHumanityInfo(requester.address);
    expect(humanityInfo[2]).to.equal(0, "Incorrect number of active requests for profile");
    expect(humanityInfo[3]).to.equal(0, "Expiration time should not be set");
    expect(humanityInfo[4]).to.equal(AddressZero, "Owner should be 0");

    expect((await poh.getRequestInfo(requester.address, 0))[6]).to.equal(
      AddressZero,
      "Ultimate challenger should be 0"
    );
    expect((await poh.getRequestInfo(requester.address, 0))[7]).to.equal(Status.Resolved, "Request should be resolved");

    expect((await poh.getChallengeInfo(requester.address, 0, 0))[3]).to.equal(Party.None, "Incorrect ruling stored");

    expect(await poh.isHuman(requester.address)).to.equal(false, "Profile should not be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(false, "Profile should not be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(AddressZero, "Should be bound to 0");
    expect(await poh.humanityOf(requester.address)).to.equal(AddressZero, "Incorrect humanity Id to address");
  });

  it("Should set correct values if challenger wins", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Suspicious human", {
        value: arbitrationCost,
      });

    await expect(arbitrator.connect(governor).giveRuling(1, Party.Challenger))
      .to.emit(poh, "Ruling")
      .withArgs(arbitrator.target, 1, Party.Challenger)
      .to.not.emit(poh, "HumanityClaimed");

    const humanityInfo = await poh.getHumanityInfo(requester.address);
    expect(humanityInfo[2]).to.equal(0, "Incorrect number of active requests for profile");
    expect(humanityInfo[3]).to.equal(0, "Expiration time should not be set");
    expect(humanityInfo[4]).to.equal(AddressZero, "Owner should be 0");

    expect((await poh.getRequestInfo(requester.address, 0))[6]).to.equal(
      challenger1.address,
      "Ultimate challenger should be set"
    );
    expect((await poh.getRequestInfo(requester.address, 0))[7]).to.equal(Status.Resolved, "Request should be resolved");

    expect((await poh.getChallengeInfo(requester.address, 0, 0))[3]).to.equal(
      Party.Challenger,
      "Incorrect ruling stored"
    );

    expect(await poh.isHuman(requester.address)).to.equal(false, "Profile should not be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(false, "Profile should not be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(AddressZero, "Should be bound to 0");
    expect(await poh.humanityOf(requester.address)).to.equal(AddressZero, "Incorrect humanity Id to address");
  });

  it("Should set correct values if requester wins removal request", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    expect(await poh.isHuman(requester.address)).to.equal(true, "Profile should be registered");

    await poh.connect(other).revokeHumanity(requester.address, "No", { value: requesterTotalCost });
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.None, "Yes", { value: arbitrationCost });

    await expect(arbitrator.connect(governor).giveRuling(1, Party.Requester))
      .to.emit(poh, "HumanityRevoked")
      .withArgs(requester.address.toLowerCase(), 0);

    const humanityInfo = await poh.getHumanityInfo(requester.address);
    expect(humanityInfo[1]).to.equal(false, "Pending revocation should be false");
    expect(humanityInfo[2]).to.equal(0, "Incorrect number of active requests for profile");
    expect(humanityInfo[4]).to.equal(AddressZero, "Owner should be 0");

    expect((await poh.getRequestInfo(requester.address, 0))[7]).to.equal(Status.Resolved, "Request should be resolved");

    expect((await poh.getChallengeInfo(requester.address, 0, 0))[3]).to.equal(
      Party.Requester,
      "Incorrect ruling stored"
    );

    expect(await poh.isHuman(requester.address)).to.equal(false, "Profile should not be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(false, "Profile should not be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(AddressZero, "Should be bound to 0");
    expect(await poh.humanityOf(requester.address)).to.equal(AddressZero, "Incorrect humanity Id to address");
  });

  it("Should set correct values if challenger wins removal request", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(requester.address, requester.address, expirationTime);

    await poh.connect(other).revokeHumanity(requester.address, "No", { value: requesterTotalCost });
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.None, "Yes", { value: arbitrationCost });

    await expect(arbitrator.connect(governor).giveRuling(1, Party.Challenger))
      .to.emit(poh, "Ruling")
      .withArgs(arbitrator.target, 1, Party.Challenger)
      .to.not.emit(poh, "HumanityRevoked");

    expect(await poh.isHuman(requester.address)).to.equal(true, "Profile should be registered");
    expect(await poh.isClaimed(requester.address)).to.equal(true, "Profile should be considered claimed");
    expect(await poh.boundTo(requester.address)).to.equal(requester.address, "Incorrect bound address");
    expect(await poh.humanityOf(requester.address)).to.equal(
      requester.address.toLowerCase(),
      "Incorrect humanity Id to address"
    );

    const humanityInfo = await poh.getHumanityInfo(requester.address);
    expect(humanityInfo[1]).to.equal(false, "Pending revocation should be false");
    expect(humanityInfo[2]).to.equal(0, "Incorrect number of active requests for profile");
    expect(humanityInfo[4]).to.equal(requester.address, "Owner should be set");

    expect((await poh.getRequestInfo(requester.address, 0))[6]).to.equal(
      AddressZero,
      "Ultimate challenger should not be set"
    ); // It's needed only for regular requests which can have multiple challenges
    expect((await poh.getRequestInfo(requester.address, 0))[7]).to.equal(Status.Resolved, "Request should be resolved");

    expect((await poh.getChallengeInfo(requester.address, 0, 0))[3]).to.equal(
      Party.Challenger,
      "Incorrect ruling stored"
    );
  });

  it("Should change the ruling if the loser paid appeal fee while winner did not", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.Deceased, "Suspicious human", { value: arbitrationCost });

    await arbitrator.connect(governor).giveAppealableRuling(1, Party.Requester, arbitrationCost, appealTimeOut); // Arbitration cost is the same as appeal cost
    const loserAppealFee = arbitrationCost + (arbitrationCost * loserStakeMultiplier) / MULTIPLIER_DIVISOR; // 1000 + 1000 * 0.8 = 1800
    await poh.connect(challenger1).fundAppeal(arbitrator.target, 1, Party.Challenger, { value: loserAppealFee }); // loser appeal fee

    await network.provider.send("evm_increaseTime", [appealTimeOut + 1]);
    await expect(arbitrator.connect(governor).executeRuling(1)) // dispute id
      .to.emit(poh, "Ruling")
      .withArgs(arbitrator.target, 1, Party.Challenger);

    expect((await poh.getRequestInfo(requester.address, 0))[6]).to.equal(
      challenger1.address,
      "Ultimate challenger should be set after ruling switch"
    );

    expect((await poh.getChallengeInfo(requester.address, 0, 0))[3]).to.equal(
      Party.Challenger,
      "Ruling should be switched"
    );
  });

  it("Should process vouches correctly", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);
    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IncorrectSubmission, "Suspicious human", {
        value: arbitrationCost,
      });

    // Check revert if request is not resolved
    await expect(poh.connect(governor).processVouches(requester.address, 0, 1)).to.be.revertedWithoutReason();

    await arbitrator.connect(governor).giveRuling(1, Party.Challenger);

    await expect(poh.connect(governor).processVouches(requester.address, 0, 1))
      .to.emit(poh, "VouchesProcessed")
      .withArgs(requester.address.toLowerCase(), 0, 1); // humanity id, request id, end index

    expect((await poh.getHumanityInfo(voucher1.address))[0]).to.equal(false, "Voucher1 should be processed");
    expect((await poh.getHumanityInfo(voucher1.address))[4]).to.equal(
      voucher1.address,
      "Voucher1 should still be registered"
    );
    expect((await poh.getHumanityInfo(voucher2.address))[0]).to.equal(true, "Voucher2 should not be processed");

    await expect(poh.connect(governor).processVouches(requester.address, 0, 1))
      .to.emit(poh, "VouchesProcessed")
      .withArgs(requester.address.toLowerCase(), 0, 2) // humanity id, request id, end index
      .to.not.emit(poh, "HumanityDischargedDirectly");

    expect((await poh.getHumanityInfo(voucher2.address))[0]).to.equal(false, "Voucher2 should be processed");
    expect((await poh.getHumanityInfo(voucher2.address))[4]).to.equal(
      voucher2.address,
      "Voucher2 should still be registered"
    );
  });

  it("Should correctly penalize vouchers that vote for a bad submission", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher3.address, voucher3.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IdentityTheft, "Suspicious human", { value: arbitrationCost });

    // Make it so one of the vouchers is in the middle of reapplication process.
    await network.provider.send("evm_increaseTime", [submissionDuration + 1 - renewalPeriodDuration]);
    // Change required number of vouches to 1 for convenience.
    await poh.connect(governor).changeRequiredNumberOfVouches(1);
    await poh.connect(voucher1).renewHumanity("Still human", { value: requesterTotalCost });

    await poh.connect(voucher3).addVouch(voucher1.address, voucher1.address);
    await poh.connect(governor).advanceState(voucher1.address, [voucher3.address], []);

    await arbitrator.connect(governor).giveRuling(1, Party.Challenger);

    await expect(poh.connect(governor).processVouches(requester.address, 0, 2))
      .to.emit(poh, "HumanityDischargedDirectly")
      .withArgs(voucher1.address.toLowerCase())
      .to.emit(poh, "HumanityDischargedDirectly")
      .withArgs(voucher2.address.toLowerCase());

    expect((await poh.getHumanityInfo(voucher1.address))[4]).to.equal(AddressZero, "Voucher1 should be revoked");
    expect((await poh.getHumanityInfo(voucher2.address))[4]).to.equal(AddressZero, "Voucher2 should be revoked");

    // Execute request to see if it didn't register the voucher back.
    await network.provider.send("evm_increaseTime", [challengePeriodDuration + 1]);
    await poh.connect(governor).executeRequest(voucher1.address, 0);

    expect((await poh.getRequestInfo(voucher1.address, 0))[7]).to.equal(Status.Resolved, "Request should be resolved");
    expect((await poh.getHumanityInfo(voucher1.address))[4]).to.equal(AddressZero, "Voucher1 should still be revoked");
    expect(await poh.isHuman(voucher1.address)).to.equal(false, "Profile should not be registered");

    // Check that voucher3 is still registered
    expect((await poh.getHumanityInfo(voucher3.address))[4]).to.equal(
      voucher3.address,
      "Voucher3 should be registered"
    );
    expect((await poh.getHumanityInfo(voucher3.address))[0]).to.equal(false, "Voucher3 should not be vouching");
  });

  it("Ultimate challenger should take feeRewards of the first challenge", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IdentityTheft, "Suspicious human", { value: arbitrationCost });

    // Check status before ruling
    await expect(
      poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 0, 0) // beneficiary, humanity id, request, challenge, round
    ).to.be.revertedWithoutReason();

    // First challenger will lose, so we check that the 2nd challenger takes the reward from 0 round and 0 challenge
    await arbitrator.connect(governor).giveRuling(1, Party.Requester);

    // Check status after the 1st ruling but before request resolution
    await expect(
      poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 0, 0) // beneficiary, humanity id, request, challenge, round
    ).to.be.revertedWithoutReason();

    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, 0, Reason.Deceased, "Suspicious human", { value: arbitrationCost });
    await arbitrator.connect(governor).giveRuling(2, Party.Challenger);

    //////// Request is resolved now

    // Check 0 beneficiary
    await expect(
      poh.connect(governor).withdrawFeesAndRewards(AddressZero, requester.address, 0, 0, 0) // beneficiary, humanity id, request, challenge, round
    ).to.be.revertedWithoutReason();

    //////// 1st challenge won by Requester. No fees should be taken since the winning fees are reserved for ultimate challenger

    let oldBalanceRequester = await ethers.provider.getBalance(requester.address);
    await poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 0, 0);
    let newBalanceRequester = await ethers.provider.getBalance(requester.address);
    // Requester won the 1st challenge but he'll take the reward only
    expect(newBalanceRequester).to.equal(oldBalanceRequester, "Requester balance should stay the same");

    let oldBalanceChallenger = await ethers.provider.getBalance(challenger1.address);
    await poh.connect(governor).withdrawFeesAndRewards(challenger1.address, requester.address, 0, 0, 0);
    let newBalanceChallenger = await ethers.provider.getBalance(challenger1.address);
    // 1st challenger didn't win his dispute
    expect(newBalanceChallenger).to.equal(oldBalanceChallenger, "1st challenger should have the same balance");

    //////// 2nd challenge. Ultimate challenger should win requester deposit

    oldBalanceRequester = await ethers.provider.getBalance(requester.address);
    await poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 1, 0);
    newBalanceRequester = await ethers.provider.getBalance(requester.address);
    // Requester won the 1st challenge but he'll take the reward only
    expect(newBalanceRequester).to.equal(oldBalanceRequester, "Requester balance should stay the same");

    // 1st challenger

    oldBalanceChallenger = await ethers.provider.getBalance(challenger1.address);
    await poh.connect(governor).withdrawFeesAndRewards(challenger1.address, requester.address, 0, 1, 0);
    newBalanceChallenger = await ethers.provider.getBalance(challenger1.address);
    // 1st challenger didn't shouldn't get ultimate challenger's reward
    expect(newBalanceChallenger).to.equal(oldBalanceChallenger, "1st challenger should have the same balance");

    // ultimate challenger
    // Withdrawing from 2nd challenge shouldn't give anything

    expect((await poh.getRoundInfo(requester.address, 0, 0, 0))[4]).to.equal(
      requesterTotalCost,
      "Incorrect fee rewards value"
    );
    oldBalanceChallenger = await ethers.provider.getBalance(challenger2.address);
    await poh.connect(governor).withdrawFeesAndRewards(challenger2.address, requester.address, 0, 1, 0);

    newBalanceChallenger = await ethers.provider.getBalance(challenger2.address);
    expect(newBalanceChallenger).to.equal(oldBalanceChallenger, "Ultimate challenger should have the same balance");

    // Withdrawing from the 1st challenge should give requester's deposit
    oldBalanceChallenger = await ethers.provider.getBalance(challenger2.address);
    await expect(poh.connect(governor).withdrawFeesAndRewards(challenger2.address, requester.address, 0, 0, 0))
      .to.emit(poh, "FeesAndRewardsWithdrawn")
      .withArgs(requester.address.toLowerCase(), 0, 0, 0, challenger2.address);

    newBalanceChallenger = await ethers.provider.getBalance(challenger2.address);
    expect(newBalanceChallenger).to.equal(
      oldBalanceChallenger + BigInt(requesterTotalCost),
      "Incorrect fees received for ultimate challenger"
    );
    expect((await poh.getRoundInfo(requester.address, 0, 0, 0))[4]).to.equal(
      0,
      "Incorrect fee rewards value after withdrawal"
    );

    // Check 2nd time
    oldBalanceChallenger = await ethers.provider.getBalance(challenger2.address);
    await poh.connect(governor).withdrawFeesAndRewards(challenger2.address, requester.address, 0, 0, 0);
    newBalanceChallenger = await ethers.provider.getBalance(challenger2.address);
    expect(newBalanceChallenger).to.equal(oldBalanceChallenger, "Balance should stay the same");
  });

  it("Should not withdraw anything from the subsequent challenge", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost / 5 }); // 1200
    // Check how partial funding works too
    await poh.connect(other).fundRequest(requester.address, 0, { value: BigInt(1e18) });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IdentityTheft, "Suspicious human", { value: arbitrationCost });
    await arbitrator.connect(governor).giveRuling(1, Party.Requester);

    await poh
      .connect(challenger2)
      .challengeRequest(requester.address, 0, Reason.Deceased, "Suspicious human", { value: arbitrationCost });
    await arbitrator.connect(governor).giveRuling(2, Party.Requester);

    await network.provider.send("evm_increaseTime", [challengePeriodDuration + 1]);

    // Check that executing requests after 2nd challenge still correctly withdraws the initial deposit
    let oldBalanceRequester = await ethers.provider.getBalance(requester.address);
    await poh.connect(governor).executeRequest(requester.address, 0);
    let newBalanceRequester = await ethers.provider.getBalance(requester.address);
    expect(newBalanceRequester).to.equal(
      oldBalanceRequester + BigInt(requesterTotalCost / 5),
      "Requester balance is incorrect"
    );

    let oldBalanceCrowdfunder = await ethers.provider.getBalance(other.address);
    await poh.connect(governor).withdrawFeesAndRewards(other.address, requester.address, 0, 0, 0);
    let newBalanceCrowdfunder = await ethers.provider.getBalance(other.address);
    expect(newBalanceCrowdfunder).to.equal(
      oldBalanceCrowdfunder + BigInt(requesterTotalCost * 0.8),
      "Crowdfunder balance is incorrect"
    );

    // Check 2nd time
    oldBalanceCrowdfunder = await ethers.provider.getBalance(other.address);
    await poh.connect(governor).withdrawFeesAndRewards(other.address, requester.address, 0, 0, 0);
    newBalanceCrowdfunder = await ethers.provider.getBalance(other.address);
    expect(newBalanceCrowdfunder).to.equal(oldBalanceCrowdfunder, "Crowdfunder balance should stay the same");

    // Check subsequent challenge

    oldBalanceRequester = await ethers.provider.getBalance(requester.address);
    await poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 1, 0);
    newBalanceRequester = await ethers.provider.getBalance(requester.address);
    expect(newBalanceRequester).to.equal(oldBalanceRequester, "Requester should have the same balance");
  });

  it("Should withdraw fees correctly if arbitrator refused to rule", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IdentityTheft, "Suspicious human", { value: arbitrationCost });
    await arbitrator.connect(governor).giveRuling(1, Party.None);

    const oldBalanceRequester = await ethers.provider.getBalance(requester.address);
    await poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 0, 0);
    const newBalanceRequester = await ethers.provider.getBalance(requester.address);
    expect(newBalanceRequester).to.equal(oldBalanceRequester + BigInt(5142), "Requester has incorrect balance"); // 6000/7000 * 6000 = 5142.8

    const oldBalanceChallenger = await ethers.provider.getBalance(challenger1.address);
    await poh.connect(governor).withdrawFeesAndRewards(challenger1.address, requester.address, 0, 0, 0);
    const newBalanceChallenger = await ethers.provider.getBalance(challenger1.address);
    expect(newBalanceChallenger).to.equal(oldBalanceChallenger + BigInt(857), "Challenger has incorrect balance"); // 1000/7000 * 6000 = 857.1
  });

  it("Should correctly withdraw fees of unsuccessful appeal", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    await poh
      .connect(challenger1)
      .challengeRequest(requester.address, 0, Reason.IdentityTheft, "Suspicious human", { value: arbitrationCost });
    await arbitrator.connect(governor).giveAppealableRuling(1, Party.Challenger, arbitrationCost, appealTimeOut);
    // Not enough value to cover the appeal fee (1800)
    await poh.connect(requester).fundAppeal(arbitrator.target, 1, Party.Requester, { value: 100 });

    await network.provider.send("evm_increaseTime", [appealTimeOut + 1]);
    await arbitrator.connect(governor).executeRuling(1);

    const oldBalanceRequester = await ethers.provider.getBalance(requester.address);
    // Withdraw from 2nd round
    await poh.connect(governor).withdrawFeesAndRewards(requester.address, requester.address, 0, 0, 1);
    const newBalanceRequester = await ethers.provider.getBalance(requester.address);
    expect(newBalanceRequester).to.equal(oldBalanceRequester + BigInt(100), "Requester has incorrect balance");

    const oldBalanceChallenger = await ethers.provider.getBalance(challenger1.address);
    await poh.connect(governor).withdrawFeesAndRewards(challenger1.address, requester.address, 0, 0, 0);
    const newBalanceChallenger = await ethers.provider.getBalance(challenger1.address);
    expect(newBalanceChallenger).to.equal(
      oldBalanceChallenger + BigInt(requesterTotalCost),
      "Challenger has incorrect balance"
    );
  });

  it("Should correctly withdraw the mistakenly added submission", async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await poh.connect(crosschainMock).ccGrantHumanity(voucher1.address, voucher1.address, expirationTime);
    await poh.connect(crosschainMock).ccGrantHumanity(voucher2.address, voucher2.address, expirationTime);
    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost * 0.4 });
    await poh.connect(other).fundRequest(requester.address, 0, { value: BigInt(1e18) });

    // Should revert if there is no request
    await expect(poh.connect(voucher1).withdrawRequest()).to.be.revertedWithPanic("0x11");

    expect(await poh.getClaimerRequestId(requester.address)).to.equal(0, "Request id should be 0");
    const oldBalance = await ethers.provider.getBalance(requester.address);
    const withdrawSubmissionTX = await (await poh.connect(requester).withdrawRequest({ gasPrice: gasPrice })).wait();
    if (!withdrawSubmissionTX) return;
    const txFee = withdrawSubmissionTX.gasUsed * gasPrice;

    await expect(withdrawSubmissionTX)
      .to.emit(poh, "RequestWithdrawn")
      .withArgs(requester.address.toLowerCase(), 0)
      .to.emit(poh, "FeesAndRewardsWithdrawn")
      .withArgs(requester.address.toLowerCase(), 0, 0, 0, requester.address);

    const newBalance = await ethers.provider.getBalance(requester.address);
    expect(newBalance).to.equal(
      oldBalance - txFee + BigInt(requesterTotalCost * 0.4),
      "Incorrect balance after withdrawal"
    );

    const oldBalanceCrowdfunder = await ethers.provider.getBalance(other.address);
    await poh.connect(governor).withdrawFeesAndRewards(other.address, requester.address, 0, 0, 0);
    const newBalanceCrowdfunder = await ethers.provider.getBalance(other.address);
    expect(newBalanceCrowdfunder).to.equal(
      oldBalanceCrowdfunder + BigInt(requesterTotalCost * 0.6),
      "Incorrect balance of the crowdfunder"
    );

    expect((await poh.getRequestInfo(requester.address, 0))[7]).to.equal(Status.Resolved, "Incorrect status");

    // Request count was nullified thus it should underflow.
    await expect(poh.getClaimerRequestId(requester.address)).to.be.revertedWithPanic("0x11");

    // Should revert if withdrawing 2nd time
    await expect(poh.connect(requester).withdrawRequest()).to.be.revertedWithPanic("0x11");

    // Check that can't withdraw after advancing

    await poh.connect(requester).claimHumanity(requester.address, evidence, name, { value: requesterTotalCost });
    await poh.connect(voucher1).addVouch(requester.address, requester.address);
    await poh.connect(voucher2).addVouch(requester.address, requester.address);
    await poh.connect(governor).advanceState(requester.address, [voucher1.address, voucher2.address], []);

    await expect(poh.connect(requester).withdrawRequest()).to.be.revertedWithoutReason();
  });

  it("Should submit evidence and emit an event", async () => {
    await poh.connect(requester).claimHumanity(requester.address, evidence, name);
    const hash = solidityPackedKeccak256(["bytes20", "uint256"], [requester.address, 0]); // Request id is 0
    const evidenceGroupId = BigInt(hash);
    await expect(poh.connect(requester).submitEvidence(requester.address, 0, "Evidence2"))
      .to.emit(poh, "Evidence")
      .withArgs(arbitrator.target, evidenceGroupId, requester.address, "Evidence2");
  });

  it("Should make governance changes", async () => {
    await expect(poh.connect(other).changeGovernor(other.address)).to.be.revertedWithoutReason();
    await expect(poh.connect(governor).changeGovernor(other.address))
      .to.emit(poh, "GovernorChanged")
      .withArgs(other.address);
    // Change governor back for convenience
    await poh.connect(other).changeGovernor(governor.address);

    await expect(poh.connect(other).changeRequestBaseDeposit(1)).to.be.revertedWithoutReason();
    await expect(poh.connect(governor).changeRequestBaseDeposit(1))
      .to.emit(poh, "RequestBaseDepositChanged")
      .withArgs(1);

    await expect(poh.connect(other).changeDurations(100, 10, 5, 10)).to.be.revertedWithoutReason();
    await expect(poh.connect(governor).changeDurations(100, 10, 5, 10))
      .to.emit(poh, "DurationsChanged")
      .withArgs(100, 10, 5, 10);

    await expect(poh.connect(other).changeRequiredNumberOfVouches(100)).to.be.revertedWithoutReason();
    await expect(poh.connect(governor).changeRequiredNumberOfVouches(100))
      .to.emit(poh, "RequiredNumberOfVouchesChanged")
      .withArgs(100);

    await expect(poh.connect(other).changeStakeMultipliers(10000, 20000, 30000)).to.be.revertedWithoutReason();
    await expect(poh.connect(governor).changeStakeMultipliers(10000, 20000, 30000))
      .to.emit(poh, "StakeMultipliersChanged")
      .withArgs(10000, 20000, 30000);

    await expect(poh.connect(other).changeMetaEvidence("reg", "clear")).to.be.revertedWithoutReason();
    await expect(poh.connect(governor).changeMetaEvidence("reg", "clear"))
      .to.emit(poh, "MetaEvidence")
      .withArgs(2, "reg")
      .to.emit(poh, "MetaEvidence")
      .withArgs(3, "clear");
    let arbitratorData = await poh.arbitratorDataHistory(1);
    expect(arbitratorData[0]).to.equal(1, "Incorrect metaevidenceUpdates");

    await expect(poh.connect(other).changeArbitrator(other, "0xfa")).to.be.revertedWithoutReason();
    await expect(poh.connect(governor).changeArbitrator(other, "0xfa"))
      .to.emit(poh, "ArbitratorChanged")
      .withArgs(other.address, "0xfa");
    arbitratorData = await poh.arbitratorDataHistory(2);
    expect(arbitratorData[0]).to.equal(1, "Incorrect metaevidenceUpdates");
    expect(arbitratorData[1]).to.equal(other.address, "Incorrect arbitrator set");
    expect(arbitratorData[2]).to.equal("0xfa", "Incorrect arbitrator extra data");
    expect(await poh.getArbitratorDataHistoryCount()).to.equal(3, "Incorrect arbitrator history count");

    await expect(poh.connect(other).changeCrossChainProofOfHumanity(other.address)).to.be.revertedWithoutReason();
    await expect(poh.connect(governor).changeCrossChainProofOfHumanity(other.address))
      .to.emit(poh, "CrossChainProxyChanged")
      .withArgs(other.address);
  });
});
