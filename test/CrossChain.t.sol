// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "./Events.sol";
import "src/interfaces/IArbitrator.sol";
import {IAMB} from "src/bridge-gateways/IAMB.sol";
import {IBridgeGateway} from "src/bridge-gateways/IBridgeGateway.sol";

import {ProofOfHumanity} from "src/ProofOfHumanity.sol";
import {CrossChainProofOfHumanity} from "src/CrossChainProofOfHumanity.sol";

import {ProofOfHumanityExtended} from "src/extending-old/ProofOfHumanityExtended.sol";
import {ProofOfHumanityOld} from "src/extending-old/ProofOfHumanityOld.sol";
import {ForkModule} from "src/extending-old/ForkModule.sol";

import {AMBBridgeGateway} from "src/bridge-gateways/AMBBridgeGateway.sol";
import {MockAMB} from "src/test-helpers/MockAMB.sol";
import {MockArbitrator} from "src/test-helpers/MockArbitrator.sol";

contract CrossChainTest is Test, CrossChainProofOfHumanityEvents {
    struct Parameters {
        IArbitrator arbitrator;
        string registrationMetaEvidence;
        string clearingMetaEvidence;
        bytes arbitratorExtraData;
        uint64 humanityLifespan;
        uint64 renewalPeriodDuration;
        uint64 challengePeriodDuration;
        uint64 requiredNumberOfVouches;
        uint[3] multipliers;
        uint arbitrationCost;
        uint requestBaseDeposit;
        uint appealTimeOut;
        uint totalCost;
    }

    Parameters internal params;
    MockArbitrator internal arbitrator;
    IAMB internal amb;

    address internal gatewayETHGNO;
    address internal gatewayGNOETH;
    address internal gatewayARBETH;
    address internal gatewayETHARB;
    address internal gatewayARBGNO;
    address internal gatewayGNOARB;

    ProofOfHumanityOld internal pohOld;
    ProofOfHumanityExtended internal pohETH;
    ProofOfHumanity internal pohGNO;
    ProofOfHumanity internal pohARB;
    CrossChainProofOfHumanity internal ccpohETH;
    CrossChainProofOfHumanity internal ccpohGNO;
    CrossChainProofOfHumanity internal ccpohARB;

    struct Human {
        address wallet;
        bytes20 humanityId;
    }

    Human internal alice;
    Human internal bob;
    Human internal carol;
    Human internal dave;
    Human internal eve;

    fallback() external payable {}
    receive() external payable {}

    function setUp() external {
        skip(100 weeks);

        params.arbitratorExtraData = bytes.concat(bytes32(uint(0x85)));
        params.registrationMetaEvidence = "registration_meta";
        params.clearingMetaEvidence = "clearing_meta";

        params.humanityLifespan = 8 weeks;
        params.renewalPeriodDuration = 2 weeks;
        params.challengePeriodDuration = 3 days;
        params.appealTimeOut = 1 days;

        params.requiredNumberOfVouches = 0;

        params.arbitrationCost = 1 ether;
        params.requestBaseDeposit = 10 ether;
        params.totalCost = params.arbitrationCost + params.requestBaseDeposit;

        params.multipliers = [uint(5000), uint(2000), uint(8000)];

        arbitrator = new MockArbitrator(params.arbitrationCost, params.appealTimeOut);
        params.arbitrator = IArbitrator(address(arbitrator));

        amb = new MockAMB();

        pohOld = new ProofOfHumanityOld(
            params.arbitrator,
            params.arbitratorExtraData,
            params.registrationMetaEvidence,
            params.clearingMetaEvidence,
            params.requestBaseDeposit,
            params.humanityLifespan,
            params.renewalPeriodDuration,
            params.challengePeriodDuration,
            params.multipliers,
            params.requiredNumberOfVouches
        );
        pohETH = new ProofOfHumanityExtended();
        pohETH.initialize(
            params.arbitrator,
            params.arbitratorExtraData,
            params.registrationMetaEvidence,
            params.clearingMetaEvidence,
            params.requestBaseDeposit,
            params.humanityLifespan,
            params.renewalPeriodDuration,
            params.challengePeriodDuration,
            params.multipliers,
            params.requiredNumberOfVouches
        );

        ForkModule forkModule = new ForkModule(address(pohETH), address(pohOld));
        pohETH.changeForkModule(forkModule);

        ccpohETH = new CrossChainProofOfHumanity();
        ccpohETH.initialize(pohETH, 1 days);
        pohETH.changeCrossChainProofOfHumanity(address(ccpohETH));

        pohGNO = new ProofOfHumanity();
        pohGNO.initialize(
            params.arbitrator,
            params.arbitratorExtraData,
            params.registrationMetaEvidence,
            params.clearingMetaEvidence,
            params.requestBaseDeposit,
            params.humanityLifespan,
            params.renewalPeriodDuration,
            params.challengePeriodDuration,
            params.multipliers,
            params.requiredNumberOfVouches
        );
        ccpohGNO = new CrossChainProofOfHumanity();
        ccpohGNO.initialize(pohGNO, 1 days);
        pohGNO.changeCrossChainProofOfHumanity(address(ccpohGNO));

        pohARB = new ProofOfHumanity();
        pohARB.initialize(
            params.arbitrator,
            params.arbitratorExtraData,
            params.registrationMetaEvidence,
            params.clearingMetaEvidence,
            params.requestBaseDeposit,
            params.humanityLifespan,
            params.renewalPeriodDuration,
            params.challengePeriodDuration,
            params.multipliers,
            params.requiredNumberOfVouches
        );
        ccpohARB = new CrossChainProofOfHumanity();
        ccpohARB.initialize(pohARB, 1 days);
        pohARB.changeCrossChainProofOfHumanity(address(ccpohARB));

        gatewayETHGNO = address(new AMBBridgeGateway(amb, address(ccpohETH)));
        gatewayGNOETH = address(new AMBBridgeGateway(amb, address(ccpohGNO)));
        AMBBridgeGateway(gatewayETHGNO).setForeignMessenger(gatewayGNOETH);
        AMBBridgeGateway(gatewayGNOETH).setForeignMessenger(gatewayETHGNO);
        ccpohETH.addBridgeGateway(gatewayETHGNO, address(ccpohGNO));
        ccpohGNO.addBridgeGateway(gatewayGNOETH, address(ccpohETH));

        gatewayARBETH = address(new AMBBridgeGateway(amb, address(ccpohARB)));
        gatewayETHARB = address(new AMBBridgeGateway(amb, address(ccpohETH)));
        AMBBridgeGateway(gatewayARBETH).setForeignMessenger(gatewayETHARB);
        AMBBridgeGateway(gatewayETHARB).setForeignMessenger(gatewayARBETH);
        ccpohETH.addBridgeGateway(gatewayETHARB, address(ccpohARB));
        ccpohARB.addBridgeGateway(gatewayARBETH, address(ccpohETH));

        gatewayARBGNO = address(new AMBBridgeGateway(amb, address(ccpohARB)));
        gatewayGNOARB = address(new AMBBridgeGateway(amb, address(ccpohGNO)));
        AMBBridgeGateway(gatewayARBGNO).setForeignMessenger(gatewayGNOARB);
        AMBBridgeGateway(gatewayGNOARB).setForeignMessenger(gatewayARBGNO);
        ccpohARB.addBridgeGateway(gatewayARBGNO, address(ccpohGNO));
        ccpohGNO.addBridgeGateway(gatewayGNOARB, address(ccpohARB));

        alice = Human({wallet: makeAddr("alice"), humanityId: bytes20(makeAddr("alice"))});
        bob = Human({wallet: makeAddr("bob"), humanityId: bytes20(makeAddr("bob"))});
        carol = Human({wallet: makeAddr("carol"), humanityId: bytes20(uint160(0x3))});
        dave = Human({wallet: makeAddr("dave"), humanityId: bytes20(makeAddr("dave"))});
        eve = Human({wallet: makeAddr("eve"), humanityId: bytes20(uint160(0x5))});

        vm.deal(alice.wallet, 20 ether);
        vm.deal(bob.wallet, 20 ether);
        vm.deal(carol.wallet, 20 ether);
        vm.deal(dave.wallet, 20 ether);
        vm.deal(eve.wallet, 20 ether);

        vm.prank(alice.wallet);
        pohOld.addSubmission{value: params.totalCost}("evidence", "voucher");
        vm.prank(bob.wallet);
        pohOld.addSubmission{value: params.totalCost}("evidence", "voucher");
        vm.prank(carol.wallet);
        pohETH.claimHumanity{value: params.totalCost}(carol.humanityId, "evidence", "voucher");

        pohOld.changeStateToPending(alice.wallet, new address[](0), new bytes[](0), new uint[](0));
        pohOld.changeStateToPending(bob.wallet, new address[](0), new bytes[](0), new uint[](0));
        pohETH.advanceState(carol.wallet, new address[](0), new ProofOfHumanityExtended.SignatureVouch[](0));

        skip(params.challengePeriodDuration + 1);

        pohOld.executeRequest(alice.wallet);
        pohOld.executeRequest(bob.wallet);
        pohETH.executeRequest(carol.humanityId, 0);
    }

    function test_CorrectlyInitialized() external {
        assertTrue(ccpohETH.initialized());
        assertTrue(pohETH.initialized());
        assertTrue(pohGNO.initialized());

        assertEq(address(pohETH.crossChainProofOfHumanity()), address(ccpohETH), "ETH - crossChainProofOfHumanity");
        assertEq(address(pohGNO.crossChainProofOfHumanity()), address(ccpohGNO), "GNO - crossChainProofOfHumanity");

        assertEq(address(ccpohETH.proofOfHumanity()), address(pohETH), "ETH - proofOfHumanity");
        assertEq(address(ccpohGNO.proofOfHumanity()), address(pohGNO), "GNO - proofOfHumanity");

        assertEq(ccpohETH.transferCooldown(), 1 days, "ETH - transferCooldown");
        assertEq(ccpohGNO.transferCooldown(), 1 days, "GNO - transferCooldown");

        (address foreignProxy, bool approved) = ccpohETH.bridgeGateways(gatewayETHGNO);
        assertEq(foreignProxy, address(ccpohGNO), "ETHGNO - foreignProxy");
        assertTrue(approved, "ETHGNO - approved");
        (foreignProxy, approved) = ccpohETH.bridgeGateways(gatewayETHARB);
        assertEq(foreignProxy, address(ccpohARB), "ETHARB - foreignProxy");
        assertTrue(approved, "ETHARB - approved");
        (foreignProxy, approved) = ccpohGNO.bridgeGateways(gatewayGNOETH);
        assertEq(foreignProxy, address(ccpohETH), "GNOETH - foreignProxy");
        assertTrue(approved, "GNOETH - approved");
        (foreignProxy, approved) = ccpohGNO.bridgeGateways(gatewayGNOARB);
        assertEq(foreignProxy, address(ccpohARB), "GNOARB - foreignProxy");
        assertTrue(approved, "GNOARB - approved");

        assertTrue(ccpohETH.isClaimed(alice.humanityId), "alice - isClaimed");
        assertTrue(ccpohETH.isClaimed(bob.humanityId), "bob - isClaimed");
        assertTrue(ccpohETH.isClaimed(carol.humanityId), "carol - isClaimed");
        assertFalse(ccpohETH.isClaimed(dave.humanityId), "dave - isClaimed");
        assertFalse(ccpohETH.isClaimed(eve.humanityId), "eve - isClaimed");

        assertTrue(ccpohETH.isHuman(alice.wallet), "alice - isHuman");
        assertTrue(ccpohETH.isHuman(bob.wallet), "bob - isHuman");
        assertTrue(ccpohETH.isHuman(carol.wallet), "carol - isHuman");
        assertFalse(ccpohETH.isHuman(dave.wallet), "dave - isHuman");
        assertFalse(ccpohETH.isHuman(eve.wallet), "eve - isHuman");

        assertEq(pohETH.boundTo(alice.humanityId), alice.wallet, "alice - boundTo");
        assertEq(pohETH.boundTo(bob.humanityId), bob.wallet, "bob - boundTo");
        assertEq(pohETH.boundTo(carol.humanityId), carol.wallet, "carol - boundTo");
        assertEq(pohETH.boundTo(dave.humanityId), address(0x0), "dave - boundTo");
        assertEq(pohETH.boundTo(eve.humanityId), address(0x0), "eve - boundTo");
    }

    function test_ClaimedHumanity_Update() external {
        assertTrue(ccpohETH.isHuman(alice.wallet), "alice - isHuman ETH");
        assertFalse(ccpohGNO.isHuman(alice.wallet), "alice - isHuman GNO");

        (,,,uint64 expirationTime,,) = pohETH.getHumanityInfo(alice.humanityId);

        vm.expectEmit(true, false, false, true);
        emit UpdateInitiated(alice.humanityId, alice.wallet, expirationTime, gatewayETHGNO, true);

        ccpohETH.updateHumanity(gatewayETHGNO, alice.humanityId);

        assertTrue(ccpohETH.isHuman(alice.wallet), "alice - isHuman ETH");
        assertTrue(ccpohGNO.isHuman(alice.wallet), "alice - isHuman GNO");

        vm.expectEmit(true, false, false, true);
        emit UpdateInitiated(alice.humanityId, alice.wallet, expirationTime, gatewayETHARB, true);

        ccpohETH.updateHumanity(gatewayETHARB, alice.humanityId);

        assertTrue(ccpohETH.isHuman(alice.wallet), "alice - isHuman ETH");
        assertTrue(ccpohGNO.isHuman(alice.wallet), "alice - isHuman GNO");
        assertTrue(ccpohARB.isHuman(alice.wallet), "alice - isHuman ARB");

        (bool isHomeChain,,, uint40 lastTransferTime)= ccpohETH.humanityMapping(alice.humanityId);
        assertTrue(isHomeChain, "alice - isHomeChain ETH");

        (isHomeChain,,,)= ccpohGNO.humanityMapping(alice.humanityId);
        assertFalse(isHomeChain, "alice - isHomeChain GNO");
    }

    function test_ClaimedHumanity_Update_OnlyFromHomeChain() external {
        vm.expectRevert();
        ccpohGNO.updateHumanity(gatewayGNOARB, alice.humanityId);

        assertTrue(ccpohETH.isHuman(alice.wallet), "alice ETH");
        assertFalse(ccpohGNO.isHuman(alice.wallet), "alice GNO");

        ccpohETH.updateHumanity(gatewayETHGNO, alice.humanityId);

        assertTrue(ccpohETH.isHuman(alice.wallet), "alice ETH");
        assertTrue(ccpohGNO.isHuman(alice.wallet), "alice GNO");

        vm.expectRevert();
        ccpohGNO.updateHumanity(gatewayGNOARB, alice.humanityId);

        assertFalse(ccpohARB.isHuman(alice.wallet), "alice ARB");

        vm.prank(alice.wallet);
        ccpohETH.transferHumanity(gatewayETHGNO);

        assertTrue(ccpohETH.isHuman(alice.wallet), "alice ETH");
        assertTrue(ccpohGNO.isHuman(alice.wallet), "alice GNO");

        vm.expectRevert();
        ccpohETH.updateHumanity(gatewayETHARB, alice.humanityId);

        assertFalse(ccpohARB.isHuman(alice.wallet), "alice ARB");

        ccpohGNO.updateHumanity(gatewayGNOARB, alice.humanityId);

        assertTrue(ccpohARB.isHuman(alice.wallet), "alice ARB");
    }

    function test_RevokedHumanity_Update() external {
        assertFalse(ccpohETH.isHuman(dave.wallet), "dave ETH");

        vm.prank(dave.wallet);
        pohETH.claimHumanity{value: params.totalCost}(dave.humanityId, "evidence", "voucher");
        pohETH.advanceState(dave.wallet, new address[](0), new ProofOfHumanityExtended.SignatureVouch[](0));
        skip(params.challengePeriodDuration + 1);
        pohETH.executeRequest(dave.humanityId, 0);

        vm.prank(dave.wallet);
        pohOld.addSubmission{value: params.totalCost}("evidence", "voucher");
        pohOld.changeStateToPending(dave.wallet, new address[](0), new bytes[](0), new uint[](0));
        skip(params.challengePeriodDuration + 1);
        pohOld.executeRequest(dave.wallet);

        assertTrue(ccpohETH.isHuman(dave.wallet), "dave ETH");

        ccpohETH.updateHumanity(gatewayETHARB, dave.humanityId);

        assertTrue(ccpohARB.isHuman(dave.wallet), "dave ARB");

        pohETH.revokeHumanity{value: params.totalCost}(dave.humanityId, "evidence");
        skip(params.challengePeriodDuration + 1);
        pohETH.executeRequest(dave.humanityId, 1);

        assertFalse(ccpohETH.isHuman(dave.wallet), "dave ETH");
        assertTrue(ccpohARB.isHuman(dave.wallet), "dave ARB");

        ccpohETH.updateHumanity(gatewayETHARB, dave.humanityId);

        assertFalse(ccpohETH.isHuman(dave.wallet), "dave ETH");
        assertTrue(ccpohARB.isHuman(dave.wallet), "dave ARB");
    }

    function test_Transfer_CantTransferUnclaimed() external {
        vm.expectRevert();
        ccpohETH.transferHumanity(gatewayETHGNO);

        vm.prank(dave.wallet);
        vm.expectRevert();
        ccpohETH.transferHumanity(gatewayETHGNO);
    }
}
