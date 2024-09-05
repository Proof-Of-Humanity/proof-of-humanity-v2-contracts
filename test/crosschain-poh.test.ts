import { ethers, network } from "hardhat";
import { expect } from "chai";
import { AddressZero } from "@ethersproject/constants";
import {
  MockArbitrator,
  MockArbitrator__factory,
  ProofOfHumanity,
  ProofOfHumanity__factory,
  MockAMB,
  MockAMB__factory,
  CrossChainProofOfHumanity,
  CrossChainProofOfHumanity__factory,
  AMBBridgeGateway,
  AMBBridgeGateway__factory,
} from "../typechain-types";
import { solidityPackedKeccak256 } from "ethers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

const arbitratorExtraData = "0x85";
const arbitrationCost = 1000;
const submissionBaseDeposit = 5000;
const submissionDuration = 86400;
const challengePeriodDuration = 600;
const renewalPeriodDuration = 6000;
const failedRevocationCooldown = 2400;
const nbVouches = 2;
const requesterTotalCost = arbitrationCost + submissionBaseDeposit;
const transferCooldown = 500;

const sharedStakeMultiplier = 5000;
const winnerStakeMultiplier = 2000;
const loserStakeMultiplier = 8000;

const registrationMetaEvidence = "registrationMetaEvidence.json";
const clearingMetaEvidence = "clearingMetaEvidence.json";

let arbitrator: MockArbitrator;
let homePoh: ProofOfHumanity;
let foreignPoh: ProofOfHumanity;
// AMB will be the same for both contracts
let amb: MockAMB;
let homeCrosschainPoh: CrossChainProofOfHumanity;
let foreignCrosschainPoh: CrossChainProofOfHumanity;
let homeGateway: AMBBridgeGateway;
let foreignGateway: AMBBridgeGateway;

let [governor, homeProfile1, homeProfile2, foreignProfile1, other]: SignerWithAddress[] = [];

describe("Crosschain Proof of Humanity", function () {
  beforeEach("Initializing the contracts", async () => {
    [governor, homeProfile1, homeProfile2, foreignProfile1, other] = await ethers.getSigners();
    arbitrator = await new MockArbitrator__factory(governor).deploy(arbitrationCost);
    await arbitrator.connect(other).createDispute(3, arbitratorExtraData, { value: arbitrationCost }); // Create a dispute so the index in tests will not be a default value.

    amb = await new MockAMB__factory(governor).deploy();

    // Deploy 2 instances to simulate different chains. Arbitrator address can be shared as it doesn't matter as much.
    homePoh = await new ProofOfHumanity__factory(governor).deploy();
    await homePoh.connect(governor).initialize(
      AddressZero, // wNative
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

    foreignPoh = await new ProofOfHumanity__factory(governor).deploy();
    await foreignPoh.connect(governor).initialize(
      AddressZero, // wNative
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

    // Set governor as a crosschain to manually create profiles.
    await homePoh.connect(governor).changeCrossChainProofOfHumanity(governor);
    await foreignPoh.connect(governor).changeCrossChainProofOfHumanity(governor);

    homeCrosschainPoh = await new CrossChainProofOfHumanity__factory(governor).deploy();
    await homeCrosschainPoh.connect(governor).initialize(homePoh.target, transferCooldown);

    foreignCrosschainPoh = await new CrossChainProofOfHumanity__factory(governor).deploy();
    await foreignCrosschainPoh.connect(governor).initialize(foreignPoh.target, transferCooldown);

    homeGateway = await new AMBBridgeGateway__factory(governor).deploy(amb.target, homeCrosschainPoh.target);
    foreignGateway = await new AMBBridgeGateway__factory(governor).deploy(amb.target, foreignCrosschainPoh.target);

    // Create a couple of profiles to transfer.
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    const currentTimestamp = latestBlock.timestamp;
    const expirationTime = currentTimestamp + submissionDuration;
    await homePoh.connect(governor).ccGrantHumanity(homeProfile1.address, homeProfile1.address, expirationTime);
    await homePoh.connect(governor).ccGrantHumanity(homeProfile2.address, homeProfile2.address, expirationTime);

    await foreignPoh
      .connect(governor)
      .ccGrantHumanity(foreignProfile1.address, foreignProfile1.address, expirationTime);

    await homeCrosschainPoh.connect(governor).addBridgeGateway(homeGateway.target, foreignCrosschainPoh.target);
    await foreignCrosschainPoh.connect(governor).addBridgeGateway(foreignGateway.target, homeCrosschainPoh.target);

    // Setup is done. Change it back
    await homePoh.connect(governor).changeCrossChainProofOfHumanity(homeCrosschainPoh.target);
    await foreignPoh.connect(governor).changeCrossChainProofOfHumanity(foreignCrosschainPoh.target);
  });

  it("Should return correct initial value", async function () {
    await homeGateway.connect(governor).setForeignGateway(foreignGateway.target);
    await foreignGateway.connect(governor).setForeignGateway(homeGateway.target);

    expect(await homeCrosschainPoh.governor()).to.equal(governor.address);
    expect(await homeCrosschainPoh.proofOfHumanity()).to.equal(homePoh.target);
    expect(await homeCrosschainPoh.transferCooldown()).to.equal(transferCooldown);

    expect(await foreignCrosschainPoh.governor()).to.equal(governor.address);
    expect(await foreignCrosschainPoh.proofOfHumanity()).to.equal(foreignPoh.target);
    expect(await foreignCrosschainPoh.transferCooldown()).to.equal(transferCooldown);

    expect(await homeGateway.governor()).to.equal(governor.address);
    expect(await homeGateway.amb()).to.equal(amb.target);
    expect(await homeGateway.homeProxy()).to.equal(homeCrosschainPoh.target);
    expect(await homeGateway.foreignGateway()).to.equal(foreignGateway.target);

    expect(await foreignGateway.governor()).to.equal(governor.address);
    expect(await foreignGateway.amb()).to.equal(amb.target);
    expect(await foreignGateway.homeProxy()).to.equal(foreignCrosschainPoh.target);
    expect(await foreignGateway.foreignGateway()).to.equal(homeGateway.target);

    expect((await homePoh.getHumanityInfo(homeProfile1.address))[3]).to.not.equal(
      0,
      "Expiration time not set in HomePoh profile"
    );
    expect((await homePoh.getHumanityInfo(homeProfile1.address))[4]).to.equal(
      homeProfile1.address,
      "Incorrect owner after direct submission"
    );
    expect(await homePoh.isHuman(homeProfile1.address)).to.equal(true, "Profile should be registered");
    expect(await homePoh.isClaimed(homeProfile1.address)).to.equal(true, "Profile should be considered claimed");

    expect((await homePoh.getHumanityInfo(homeProfile2.address))[3]).to.not.equal(
      0,
      "Expiration time not set in HomePoh profile"
    );
    expect((await homePoh.getHumanityInfo(homeProfile2.address))[4]).to.equal(
      homeProfile2.address,
      "Incorrect owner after direct submission"
    );
    expect(await homePoh.isHuman(homeProfile2.address)).to.equal(true, "Profile should be registered");
    expect(await homePoh.isClaimed(homeProfile2.address)).to.equal(true, "Profile should be considered claimed");

    expect((await foreignPoh.getHumanityInfo(foreignProfile1.address))[3]).to.not.equal(
      0,
      "Expiration time not set in ForeignPoh profile"
    );
    expect((await foreignPoh.getHumanityInfo(foreignProfile1.address))[4]).to.equal(
      foreignProfile1.address,
      "Incorrect owner after direct submission"
    );
    expect(await foreignPoh.isHuman(foreignProfile1.address)).to.equal(true, "Profile should be registered");
    expect(await foreignPoh.isClaimed(foreignProfile1.address)).to.equal(true, "Profile should be considered claimed");

    expect((await homeCrosschainPoh.bridgeGateways(homeGateway.target))[0]).to.equal(
      foreignCrosschainPoh.target,
      "Incorrect foreign proxy returned"
    );
    expect((await homeCrosschainPoh.bridgeGateways(homeGateway.target))[1]).to.equal(
      true,
      "Gateway should be approved"
    );

    expect((await foreignCrosschainPoh.bridgeGateways(foreignGateway.target))[0]).to.equal(
      homeCrosschainPoh.target,
      "Incorrect home proxy returned"
    );
    expect((await foreignCrosschainPoh.bridgeGateways(foreignGateway.target))[1]).to.equal(
      true,
      "Gateway should be approved"
    );

    // Check initialize modifier
    await expect(
      homeCrosschainPoh.connect(governor).initialize(homePoh, transferCooldown)
    ).to.be.revertedWithoutReason();
  });

  it("Should correctly update humanity", async function () {
    await homeGateway.connect(governor).setForeignGateway(foreignGateway.target);
    await foreignGateway.connect(governor).setForeignGateway(homeGateway.target);

    // Check bad gateway first
    await expect(
      homeCrosschainPoh.connect(homeProfile1).updateHumanity(amb.target, homeProfile1.address)
    ).to.be.revertedWithoutReason();

    // Check bad profile
    await expect(
      homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, foreignProfile1.address)
    ).to.be.revertedWith("Must update from home chain");

    // Check the state of the profile in crosschain contract
    expect(await homeCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      true,
      "Profile should be registered at home proxy"
    );
    expect(await homeCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      true,
      "Profile should be considered claimed at home proxy"
    );
    expect(await homeCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      homeProfile1.address,
      "Profile is bound to incorrect address at home proxy"
    );
    expect(await homeCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      homeProfile1.address.toLowerCase(),
      "Incorrect humanity Id to address at home proxy"
    );

    expect(await foreignCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      false,
      "Profile should not be registered at foreign proxy"
    );
    expect(await foreignCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      false,
      "Profile should not be considered claimed at foreign proxy"
    );
    expect(await foreignCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      AddressZero,
      "Profile should be bound to 0 at foreign proxy"
    );
    expect(await foreignCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      AddressZero,
      "Humanity id should be at 0 foreign proxy"
    );

    const expirationTime = (await homePoh.getHumanityInfo(homeProfile1.address))[3];
    await expect(homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address))
      .to.emit(homeCrosschainPoh, "UpdateInitiated")
      // Convert to lower case to match bytes20
      .withArgs(homeProfile1.address.toLowerCase(), homeProfile1.address, expirationTime, true, homeGateway.target)
      .to.emit(foreignCrosschainPoh, "UpdateReceived")
      .withArgs(homeProfile1.address.toLowerCase(), homeProfile1.address, expirationTime, true);

    let humanityInfo = await homeCrosschainPoh.humanityData(homeProfile1.address);
    expect(humanityInfo[3]).to.equal(true, "IsHomeChain should be true");

    // Check the info of the received profile
    humanityInfo = await foreignCrosschainPoh.humanityData(homeProfile1.address);
    expect(humanityInfo[0]).to.equal(homeProfile1.address, "Incorrect owner of the received profile");
    expect(humanityInfo[1]).to.equal(expirationTime, "Incorrect expiration time received");
    expect(humanityInfo[3]).to.equal(false, "IsHomeChain should be false");

    expect(await foreignCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      true,
      "Profile should be registered at foreign proxy"
    );
    expect(await foreignCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      true,
      "Profile should be considered claimed at foreign proxy"
    );
    expect(await foreignCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      homeProfile1.address,
      "Profile is bound to incorrect address at foreign proxy"
    );
    expect(await foreignCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      homeProfile1.address.toLowerCase(),
      "Incorrect humanity Id to address at foreign proxy"
    );

    // Check that it's still registered at home chain too
    expect(await homeCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      true,
      "Profile should be registered at home proxy"
    );
    expect(await homeCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      true,
      "Profile should be considered claimed at home proxy"
    );
    expect(await homeCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      homeProfile1.address,
      "Profile is bound to incorrect address at home proxy"
    );
    expect(await homeCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      homeProfile1.address.toLowerCase(),
      "Incorrect humanity Id to address at home proxy"
    );

    // Check that can't update the received profile from foreign chain
    await expect(
      foreignCrosschainPoh.connect(homeProfile1).updateHumanity(foreignGateway.target, homeProfile1.address)
    ).to.be.revertedWith("Must update from home chain");

    // Check that can update 2nd time

    await expect(
      homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address)
    ).to.emit(homeCrosschainPoh, "UpdateInitiated");
  });

  it("Should correctly update the profile if it was unregistered", async function () {
    await homeGateway.connect(governor).setForeignGateway(foreignGateway.target);
    await foreignGateway.connect(governor).setForeignGateway(homeGateway.target);

    const expirationTime = (await homePoh.getHumanityInfo(homeProfile1.address))[3];
    await homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address);
    expect(await foreignCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      true,
      "Profile should be registered at foreign proxy"
    );
    expect(await homeCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      true,
      "Profile should be registered at home proxy"
    );

    await homePoh.connect(other).revokeHumanity(homeProfile1.address, "123", { value: requesterTotalCost });
    await network.provider.send("evm_increaseTime", [challengePeriodDuration + 1]);

    await homePoh.connect(governor).executeRequest(homeProfile1.address, 0);

    expect(await homeCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      false,
      "Profile should not be registered at home proxy"
    );
    expect(await homeCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      false,
      "Profile should not be considered claimed at home proxy"
    );
    expect(await homeCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      AddressZero,
      "Profile should be bound to 0 at home proxy"
    );
    expect(await homeCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      AddressZero,
      "Humanity id should be at 0 home proxy"
    );

    expect(await foreignCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      true,
      "Profile should still be registered at foreign proxy"
    );
    expect(await foreignCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      true,
      "Profile should still be considered claimed at foreign proxy"
    );
    expect(await foreignCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      homeProfile1.address,
      "Profile is bound to incorrect address at foreign proxy"
    );
    expect(await foreignCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      homeProfile1.address.toLowerCase(),
      "Incorrect humanity Id to address at foreign proxy"
    );

    // Inform foreign proxy that profile is revoked
    await homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address);

    expect(await foreignCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      false,
      "Profile should not be registered at foreign proxy"
    );
    expect(await foreignCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      false,
      "Profile should not be considered claimed at foreign proxy"
    );
    expect(await foreignCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      AddressZero,
      "Profile should be bound to 0 at foreign proxy"
    );
    expect(await foreignCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      AddressZero,
      "Humanity id should be at 0 foreign proxy"
    );

    const humanityInfo = await foreignCrosschainPoh.humanityData(homeProfile1.address);
    expect(humanityInfo[0]).to.equal(AddressZero, "Owner should be nullified");
    expect(humanityInfo[1]).to.equal(expirationTime, "Incorrect expiration time received");
    expect(humanityInfo[3]).to.equal(false, "IsHomeChain should be false");
  });

  it("Should correctly update expired profile", async function () {
    await homeGateway.connect(governor).setForeignGateway(foreignGateway.target);
    await foreignGateway.connect(governor).setForeignGateway(homeGateway.target);

    await homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address);

    await network.provider.send("evm_increaseTime", [submissionDuration + 1]);
    // Send a random tx to trigger time increase.
    await homeCrosschainPoh.connect(governor).setTransferCooldown(transferCooldown);

    expect(await homeCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      false,
      "Profile should not be registered at home proxy"
    );
    expect(await homeCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      false,
      "Profile should not be considered claimed at home proxy"
    );
    expect(await homeCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      AddressZero,
      "Profile should be bound to 0 at home proxy"
    );
    expect(await homeCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      AddressZero,
      "Humanity id should be at 0 home proxy"
    );

    expect(await foreignCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      false,
      "Profile should not be registered at foreign proxy"
    );
    expect(await foreignCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      false,
      "Profile should not be considered claimed at foreign proxy"
    );
    expect(await foreignCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      AddressZero,
      "Profile should be bound to 0 at foreign proxy"
    );
    expect(await foreignCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      AddressZero,
      "Humanity id should be at 0 foreign proxy"
    );

    expect((await foreignCrosschainPoh.humanityData(homeProfile1.address))[0]).to.equal(
      homeProfile1.address,
      "Owner should still be stored on foreign proxy"
    );
    await homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address);

    expect((await foreignCrosschainPoh.humanityData(homeProfile1.address))[0]).to.equal(
      AddressZero,
      "Owner should be nullified on foreign proxy"
    );
  });

  it("Check cross-chain requires", async function () {
    // Check gateway first because it can't be reset. We check with empty gateway to see if require works
    await homeGateway.connect(governor).setForeignGateway(foreignGateway.target);

    // The revert is picked up by AMB because foreignGateway couldn't receive the message.
    await expect(
      homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address)
    ).to.be.revertedWith("Failed to call contract");

    await foreignGateway.connect(governor).setForeignGateway(homeGateway.target);

    // Check gateway require
    await homeCrosschainPoh.connect(governor).removeBridgeGateway(homeGateway.target);

    await expect(
      homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address)
    ).to.be.revertedWithoutReason();

    // Set the gateway back
    await homeCrosschainPoh.connect(governor).addBridgeGateway(homeGateway.target, foreignCrosschainPoh.target);

    // Check home proxy require. Sent data is irrelevant so just use arbitratorExtraData as a placeholder
    await expect(homeGateway.connect(governor).sendMessage(arbitratorExtraData)).to.be.revertedWith("!homeProxy");

    await expect(foreignGateway.connect(governor).receiveMessage(arbitratorExtraData)).to.be.revertedWith("!amb");

    // Check gateway require on a receiving end.
    await foreignCrosschainPoh.connect(governor).removeBridgeGateway(foreignGateway.target);
    await expect(
      homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address)
    ).to.be.revertedWith("Failed to call contract");

    await foreignCrosschainPoh.connect(governor).addBridgeGateway(foreignGateway.target, homeCrosschainPoh.target);

    // Check that it still works
    await expect(
      homeCrosschainPoh.connect(homeProfile1).updateHumanity(homeGateway.target, homeProfile1.address)
    ).to.emit(homeCrosschainPoh, "UpdateInitiated");
  });

  it("Should correctly transfer profile", async function () {
    await homeGateway.connect(governor).setForeignGateway(foreignGateway.target);
    await foreignGateway.connect(governor).setForeignGateway(homeGateway.target);

    const expirationTime = (await homePoh.getHumanityInfo(homeProfile1.address))[3];

    const transferProfileTx = (
      await homeCrosschainPoh.connect(homeProfile1).transferHumanity(homeGateway.target)
    ).wait();
    if (!transferProfileTx) return;

    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock === null) {
      throw new Error("Failed to retrieve the latest block");
    }
    // Get the current timestamp from the latest block to calculate hash
    const currentTimestamp = latestBlock.timestamp;
    const txHash = solidityPackedKeccak256(
      ["bytes20", "uint256", "address", "address"],
      [homeProfile1.address, currentTimestamp, homeCrosschainPoh.target, foreignCrosschainPoh.target]
    );

    await expect(transferProfileTx)
      .to.emit(homeCrosschainPoh, "TransferInitiated")
      // Convert to lower case to match bytes20
      .withArgs(homeProfile1.address.toLowerCase(), homeProfile1.address, expirationTime, homeGateway.target, txHash)
      .to.emit(foreignCrosschainPoh, "TransferReceived")
      .withArgs(homeProfile1.address.toLowerCase(), homeProfile1.address, expirationTime, txHash)
      .to.emit(homePoh, "HumanityDischargedDirectly")
      .withArgs(homeProfile1.address.toLowerCase())
      .to.emit(foreignPoh, "HumanityGrantedDirectly")
      .withArgs(homeProfile1.address.toLowerCase(), homeProfile1.address, expirationTime);

    let humanityInfo = await homeCrosschainPoh.humanityData(homeProfile1.address);
    expect(humanityInfo[0]).to.equal(homeProfile1.address, "Owner should be stored");
    expect(humanityInfo[1]).to.equal(expirationTime, "Incorrect expiration time");
    expect(humanityInfo[3]).to.equal(false, "IsHomeChain should be false");

    // Check that the profile was removed from the registry but still stored in the cross-chain contract
    expect(await homeCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      true,
      "Profile should be registered at home proxy"
    );
    expect(await homeCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      true,
      "Profile should be considered claimed at home proxy"
    );
    expect(await homeCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      homeProfile1.address,
      "Profile is bound to incorrect address at home proxy"
    );
    expect(await homeCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      homeProfile1.address.toLowerCase(),
      "Incorrect humanity Id to address at home proxy"
    );

    expect((await homePoh.getHumanityInfo(homeProfile1.address))[4]).to.equal(
      AddressZero,
      "Owner should be nullified in Poh"
    );
    expect(await homePoh.isHuman(homeProfile1.address)).to.equal(false, "Profile should not be registered");
    expect(await homePoh.isClaimed(homeProfile1.address)).to.equal(false, "Profile should not be considered claimed");
    expect(await homePoh.boundTo(homeProfile1.address)).to.equal(AddressZero, "Should be bound to 0");
    expect(await homePoh.humanityOf(homeProfile1.address)).to.equal(AddressZero, "Incorrect humanity Id to address");

    const transfer = await homeCrosschainPoh.transfers(homeProfile1.address);
    expect(transfer[0]).to.equal(homeProfile1.address.toLowerCase(), "Incorrect humanity ID stored in transfer");
    expect(transfer[1]).to.equal(expirationTime, "Incorrect expiration time");
    expect(transfer[2]).to.equal(txHash, "Incorrect txHash stored");
    expect(transfer[3]).to.equal(foreignCrosschainPoh.target, "Incorrect foreign proxy stored");

    // Check the state of the receiving chain

    expect((await foreignPoh.getHumanityInfo(homeProfile1.address))[3]).to.equal(
      expirationTime,
      "Expiration time is incorrect in ForeignPoh profile"
    );
    expect((await foreignPoh.getHumanityInfo(homeProfile1.address))[4]).to.equal(
      homeProfile1.address,
      "Incorrect owner after direct transfer"
    );
    expect(await foreignPoh.isHuman(homeProfile1.address)).to.equal(true, "Profile should be registered");
    expect(await foreignPoh.isClaimed(homeProfile1.address)).to.equal(true, "Profile should be considered claimed");
    expect(await foreignPoh.boundTo(homeProfile1.address)).to.equal(homeProfile1.address, "Incorrect bound address");
    expect(await foreignPoh.humanityOf(homeProfile1.address)).to.equal(
      homeProfile1.address.toLowerCase(),
      "Incorrect humanity Id to address"
    );

    expect(await foreignCrosschainPoh.isHuman(homeProfile1.address)).to.equal(
      true,
      "Profile should be registered at foreign proxy"
    );
    expect(await foreignCrosschainPoh.isClaimed(homeProfile1.address)).to.equal(
      true,
      "Profile should be considered claimed at foreign proxy"
    );
    expect(await foreignCrosschainPoh.boundTo(homeProfile1.address)).to.equal(
      homeProfile1.address,
      "Profile is bound to incorrect address at foreign proxy"
    );
    expect(await foreignCrosschainPoh.humanityOf(homeProfile1.address)).to.equal(
      homeProfile1.address.toLowerCase(),
      "Incorrect humanity Id to address at foreign proxy"
    );

    humanityInfo = await foreignCrosschainPoh.humanityData(homeProfile1.address);
    expect(humanityInfo[0]).to.equal(homeProfile1.address, "Owner should be stored");
    expect(humanityInfo[1]).to.equal(expirationTime, "Incorrect expiration time");
    expect(humanityInfo[2]).to.equal(currentTimestamp, "Incorrect transfer timestamp");
    expect(humanityInfo[3]).to.equal(true, "IsHomeChain should be true");

    expect(await foreignCrosschainPoh.receivedTransferHashes(txHash)).to.equal(true, "Hash should be stored");
  });

  it("Check requires for profile transfer", async function () {
    await homeGateway.connect(governor).setForeignGateway(foreignGateway.target);
    await foreignGateway.connect(governor).setForeignGateway(homeGateway.target);

    // Check gateway require
    await homeCrosschainPoh.connect(governor).removeBridgeGateway(homeGateway.target);

    await expect(
      homeCrosschainPoh.connect(homeProfile1).transferHumanity(homeGateway.target)
    ).to.be.revertedWithoutReason();

    // Set the gateway back
    await homeCrosschainPoh.connect(governor).addBridgeGateway(homeGateway.target, foreignCrosschainPoh.target);

    // Make a transfer, and then attempt another transfer to check cooldown
    await homeCrosschainPoh.connect(homeProfile1).transferHumanity(homeGateway.target);
    await expect(foreignCrosschainPoh.connect(homeProfile1).transferHumanity(foreignGateway.target)).to.be.revertedWith(
      "Can't transfer yet"
    );

    await network.provider.send("evm_increaseTime", [transferCooldown + 1]);

    await expect(foreignCrosschainPoh.connect(homeProfile1).transferHumanity(foreignGateway.target)).to.emit(
      foreignCrosschainPoh,
      "TransferInitiated"
    );

    // Check gateway require on a receiving end.
    await foreignCrosschainPoh.connect(governor).removeBridgeGateway(foreignGateway.target);
    await expect(homeCrosschainPoh.connect(homeProfile2).transferHumanity(homeGateway.target)).to.be.revertedWith(
      "Failed to call contract"
    );

    await foreignCrosschainPoh.connect(governor).addBridgeGateway(foreignGateway.target, homeCrosschainPoh.target);

    // Check that it still works
    await expect(homeCrosschainPoh.connect(homeProfile2).transferHumanity(homeGateway.target)).to.emit(
      homeCrosschainPoh,
      "TransferInitiated"
    );
  });

  it("Check governance in crosschain and gateway contracts", async function () {
    await expect(homeCrosschainPoh.connect(other).changeGovernor(other.address)).to.be.revertedWithoutReason();
    await homeCrosschainPoh.connect(governor).changeGovernor(other.address);
    expect(await homeCrosschainPoh.governor()).to.equal(other.address, "Incorrect governor");
    // Change governor back for convenience
    await homeCrosschainPoh.connect(other).changeGovernor(governor.address);

    await expect(
      homeCrosschainPoh.connect(other).changeProofOfHumanity(homeGateway.target)
    ).to.be.revertedWithoutReason();
    await homeCrosschainPoh.connect(governor).changeProofOfHumanity(homeGateway.target);
    expect(await homeCrosschainPoh.proofOfHumanity()).to.equal(homeGateway.target, "Incorrect PoH address");

    await expect(homeCrosschainPoh.connect(other).setTransferCooldown(11)).to.be.revertedWithoutReason();
    await homeCrosschainPoh.connect(governor).setTransferCooldown(11);
    expect(await homeCrosschainPoh.transferCooldown()).to.equal(11, "Incorrect transfer cooldown");

    await expect(
      homeCrosschainPoh.connect(other).removeBridgeGateway(homeGateway.target)
    ).to.be.revertedWithoutReason();
    await expect(homeCrosschainPoh.connect(governor).removeBridgeGateway(homeGateway.target))
      .to.emit(homeCrosschainPoh, "GatewayRemoved")
      .withArgs(homeGateway.target);

    expect((await homeCrosschainPoh.bridgeGateways(homeGateway.target))[0]).to.equal(
      AddressZero,
      "Incorrect foreign proxy returned"
    );
    expect((await homeCrosschainPoh.bridgeGateways(homeGateway.target))[1]).to.equal(
      false,
      "Gateway should not be approved"
    );

    // Check that can't remove 2nd time
    await expect(
      homeCrosschainPoh.connect(governor).removeBridgeGateway(homeGateway.target)
    ).to.be.revertedWithoutReason();

    await expect(
      homeCrosschainPoh.connect(other).addBridgeGateway(homeGateway.target, foreignCrosschainPoh.target)
    ).to.be.revertedWithoutReason();
    await expect(homeCrosschainPoh.connect(governor).addBridgeGateway(homeGateway.target, foreignCrosschainPoh.target))
      .to.emit(homeCrosschainPoh, "GatewayAdded")
      .withArgs(homeGateway.target, foreignCrosschainPoh.target);

    // Check requires for addGateway
    // Empty address
    await expect(
      homeCrosschainPoh.connect(governor).addBridgeGateway(AddressZero, foreignCrosschainPoh.target)
    ).to.be.revertedWithoutReason();
    // Already approved
    await expect(
      homeCrosschainPoh.connect(governor).addBridgeGateway(homeGateway.target, foreignCrosschainPoh.target)
    ).to.be.revertedWithoutReason();

    // Gateway contract
    await expect(homeGateway.connect(other).changeGovernor(other.address)).to.be.revertedWithoutReason();
    await homeGateway.connect(governor).changeGovernor(other.address);
    expect(await homeGateway.governor()).to.equal(other.address, "Incorrect governor");
    // Change governor back for convenience
    await homeGateway.connect(other).changeGovernor(governor.address);

    await expect(homeGateway.connect(other).setForeignGateway(foreignGateway.target)).to.be.revertedWithoutReason();
    await homeGateway.connect(governor).setForeignGateway(foreignGateway.target);
    expect(await homeGateway.foreignGateway()).to.equal(foreignGateway.target, "Incorrect gateway address");

    // Check that can't set 2nd time
    await expect(homeGateway.connect(governor).setForeignGateway(foreignGateway.target)).to.be.revertedWith("set!");
  });
});
