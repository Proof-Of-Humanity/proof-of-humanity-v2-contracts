// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./Base.sol";

contract ChallengeTest is ProofOfHumanityBase {
    address internal challenger;
    address[2] internal vouchers;

    bytes20 internal humanityId;

    function setUp() external {
        skip(100 weeks);
        init();

        vm.deal(me, 1000 ether);

        challenger = makeAddr("challenger");
        vm.deal(challenger, 1000 ether);

        vouchers = [makeAddr("voucher one"), makeAddr("voucher two")];

        poh.changeRequiredNumberOfVouches(uint64(0));

        for (uint i = 0; i < 2; i++) {
            vm.deal(vouchers[i], 20 ether);
            registerVoucher(vouchers[i]);
        }

        poh.changeRequiredNumberOfVouches(2);

        humanityId = bytes20(uint160(me));

        poh.claimHumanity{value: params.totalCost}("evidence", "voucher");

        vm.prank(vouchers[0]);
        poh.addVouch(me, humanityId);
        vm.prank(vouchers[1]);
        poh.addVouch(me, humanityId);

        address[] memory onChainVouches = new address[](2);
        onChainVouches[0] = vouchers[0];
        onChainVouches[1] = vouchers[1];

        poh.advanceState(me, onChainVouches, new ProofOfHumanity.SignatureVouch[](0));
    }

    function registerVoucher(address _voucher) internal {
        vm.prank(_voucher);
        poh.claimHumanity{value: params.totalCost}("evidence", "voucher");
        poh.advanceState(_voucher, new address[](0), new ProofOfHumanity.SignatureVouch[](0));
        skip(params.challengePeriodDuration + 1 days);
        poh.executeRequest(bytes20(uint160(_voucher)), 0);
    }

    function test_NotAllowingAfterPeriodPassed() external {
        skip(params.challengePeriodDuration + 1);

        vm.prank(challenger);
        vm.expectRevert();
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.IncorrectSubmission, "evidence");
    }

    function test_NotAllowingUnpaidFee() external {
        vm.prank(challenger);
        vm.expectRevert();
        poh.challengeRequest{value: 0}(humanityId, 0, ProofOfHumanity.Reason.IncorrectSubmission, "evidence");

        vm.prank(challenger);
        vm.expectRevert();
        poh.challengeRequest{value: params.arbitrationCost - 1}(humanityId, 0, ProofOfHumanity.Reason.IncorrectSubmission, "evidence");
    }

    function test_NotAllowingReasonNone() external {
        vm.prank(challenger);
        vm.expectRevert();
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.None, "evidence");

        (, uint8 usedReasons,,,,,, ProofOfHumanity.Status status, ProofOfHumanity.Reason currentReason) = poh.getRequestInfo(humanityId, 0);
        assertEq(usedReasons, 0, "usedReasons");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Resolving), "uint8");
        assertEq(uint8(currentReason), uint8(ProofOfHumanity.Reason.None), "uint8");
    }

    function test_GrantingSoulToUnchallenged() external {
        skip(params.challengePeriodDuration + 1);

        vm.expectEmit(true, false, false, true);
        emit HumanityClaimed(humanityId, 0);

        vm.expectEmit(true, false, false, true);
        emit VouchesProcessed(humanityId, 0, 2);

        vm.expectEmit(true, false, false, true);
        emit FeesAndRewardsWithdrawn(humanityId, 0, 0, 0, me);

        (uint256 forRequester, uint256 forChallenger) = poh.getContributions(humanityId, 0, 0, 0, me);
        assertEq(forRequester, params.totalCost, "forRequester");
        assertEq(forChallenger, 0, "forChallenger");

        poh.executeRequest(humanityId, 0);

        (bool requesterLost, uint8 usedReasons,,,,,, ProofOfHumanity.Status status, ProofOfHumanity.Reason currentReason) = poh.getRequestInfo(humanityId, 0);
        assertFalse(requesterLost, "requesterLost");
        assertEq(usedReasons, 0, "usedReasons");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Resolved), "uint8");
        assertEq(uint8(currentReason), uint8(ProofOfHumanity.Reason.None), "uint8");

        (forRequester, forChallenger) = poh.getContributions(humanityId, 0, 0, 0, me);
        assertEq(forRequester, 0, "forRequester");
        assertEq(forChallenger, 0, "forChallenger");
    }

    function test_EventsAndCallingArbitrator() external {
        vm.prank(challenger);
        vm.expectCall(
            address(arbitrator),
            params.arbitrationCost,
            abi.encodeCall(arbitrator.createDispute, (2, params.arbitratorExtraData))
        );

        vm.expectEmit(true, false, false, true);
        emit Contribution(humanityId, 0, 0, 0, challenger, params.arbitrationCost, ProofOfHumanity.Party.Challenger);
        vm.expectEmit(true, false, false, true);
        emit RequestChallenged(humanityId, 0, 0, ProofOfHumanity.Reason.IncorrectSubmission, 1, "evidence");
        vm.expectEmit(true, false, false, true);
        emit Dispute(arbitrator, 1, 0, uint256(uint160(humanityId)));
        vm.expectEmit(true, false, false, true);
        emit Evidence(arbitrator, uint256(uint160(humanityId)), challenger, "evidence");

        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.IncorrectSubmission, "evidence");
    }

    function test_SubmittingEvidence() external {
        vm.expectEmit(true, false, false, true);
        emit Evidence(arbitrator, uint256(uint160(humanityId)), challenger, "test evidence");

        poh.submitEvidence(humanityId, 0, "test evidence");
    }

    modifier requesterWonFirstRound() {
        vm.prank(challenger);
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.IncorrectSubmission, "evidence");

        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Requester));
        _;
    }

    modifier challengerWonFirstRound() {
        vm.prank(challenger);
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.IncorrectSubmission, "evidence");

        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Challenger));
        _;
    }

    modifier drawFirstRound() {
        vm.prank(challenger);
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.IncorrectSubmission, "evidence");

        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.None));
        _;
    }

    function test_RequesterWon_CantExecuteDisputed() external requesterWonFirstRound {
        vm.expectRevert();
        poh.executeRequest(humanityId, 0);
    }

    function test_RequesterWon_SettingValues() external requesterWonFirstRound {
        (
            bool requesterLost,
            uint8 usedReasons,
            uint16 arbitratorDataId,
            uint16 lastChallengeId,
            uint64 challengePeriodEnd,
            address requester,
            address ultimateChallenger,
            ProofOfHumanity.Status status,
            ProofOfHumanity.Reason currentReason
        ) = poh.getRequestInfo(humanityId, 0);
        assertFalse(requesterLost, "requesterLost");
        assertEq(usedReasons, 1, "usedReasons");
        assertEq(arbitratorDataId, 0, "arbitratorDataId");
        assertEq(lastChallengeId, 1, "lastChallengeId");
        assertEq(challengePeriodEnd, uint64(block.timestamp) + params.challengePeriodDuration, "challengePeriodEnd");
        assertEq(requester, me, "requester");
        assertEq(ultimateChallenger, address(0x0), "ultimateChallenger");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Disputed), "status");
        assertEq(uint8(currentReason), uint8(ProofOfHumanity.Reason.IncorrectSubmission), "currentReason");

        (
            uint16 lastRoundId,
            address _challenger,
            uint256 disputeId,
            ProofOfHumanity.Party ruling
        ) = poh.getChallengeInfo(humanityId, 0, 0);
        assertEq(lastRoundId, 1, "lastRoundId");
        assertEq(_challenger, challenger, "challenger");
        assertEq(disputeId, 1, "disputeId");
        assertEq(uint8(ruling), uint8(ProofOfHumanity.Party.None), "ruling");

        (
            uint256 paidFeesRequester,
            uint256 paidFeesChallenger,
            ProofOfHumanity.Party sideFunded,
            uint256 feeRewards
        ) = poh.getRoundInfo(humanityId, 0, 0, 0);
        assertEq(paidFeesRequester, params.totalCost, "paidFeesRequester");
        assertEq(paidFeesChallenger, params.arbitrationCost, "paidFeesChallenger");
        assertEq(uint8(sideFunded), uint8(ProofOfHumanity.Party.None), "sideFunded");
        assertEq(feeRewards, params.totalCost, "feeRewards");
    }

    function test_RequesterWon_ResetingRequest() external requesterWonFirstRound {
        skip(params.appealTimeOut + 1);

        vm.expectCall(
            address(poh),
            abi.encodeCall(poh.rule, (1, uint(ProofOfHumanity.Party.Requester)))
        );

        vm.expectEmit(true, false, false, true);
        emit ChallengePeriodRestart(humanityId, 0, 0);

        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Requester));

        (, uint8 usedReasons,,, uint64 challengePeriodEnd,,, ProofOfHumanity.Status status, ProofOfHumanity.Reason currentReason) = poh.getRequestInfo(humanityId, 0);
        assertEq(usedReasons, 1, "usedReasons");
        assertEq(challengePeriodEnd, uint64(block.timestamp) + params.challengePeriodDuration, "challengePeriodEnd");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Resolving), "status");
        assertEq(uint8(currentReason), uint8(ProofOfHumanity.Reason.None), "currentReason");

        (,,, ProofOfHumanity.Party ruling) = poh.getChallengeInfo(humanityId, 0, 0);
        assertEq(uint8(ruling), uint8(ProofOfHumanity.Party.Requester), "ruling");
    }

    function test_RequesterWon_NotAllowingSameReason() external requesterWonFirstRound {
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Requester));

        vm.prank(challenger);
        vm.expectRevert();
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.IncorrectSubmission, "evidence");
    }

    function test_RequesterWon_ChallengedOnce() external requesterWonFirstRound {
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Requester));

        skip(params.challengePeriodDuration + 1);
        poh.executeRequest(humanityId, 0);

        (bool requesterLost, uint8 usedReasons,,,,,, ProofOfHumanity.Status status, ProofOfHumanity.Reason currentReason) = poh.getRequestInfo(humanityId, 0);
        assertFalse(requesterLost, "requesterLost");
        assertEq(usedReasons, 1, "usedReasons");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Resolved), "status");
        assertEq(uint8(currentReason), uint8(ProofOfHumanity.Reason.None), "currentReason");

        (,, uint64 nbPendingRequests, uint64 expirationTime, address owner,) = poh.getHumanityInfo(humanityId);
        assertEq(nbPendingRequests, 0, "nbPendingRequests");
        assertEq(expirationTime, uint64(block.timestamp) + params.humanityLifespan, "expirationTime");
        assertEq(owner, me, "owner");
    }

    function test_RequesterWon_ChallengedMultipleReasons() external requesterWonFirstRound {
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Requester));

        vm.prank(challenger);
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.Duplicate, "evidence");

        (bool requesterLost, uint8 usedReasons,,,,,, ProofOfHumanity.Status status, ProofOfHumanity.Reason currentReason) = poh.getRequestInfo(humanityId, 0);
        assertFalse(requesterLost, "requesterLost");
        assertEq(usedReasons, 5, "usedReasons");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Disputed), "status");
        assertEq(uint8(currentReason), uint8(ProofOfHumanity.Reason.Duplicate), "currentReason");

        (,, uint64 nbPendingRequests, uint64 expirationTime, address owner,) = poh.getHumanityInfo(humanityId);
        assertEq(nbPendingRequests, 1, "nbPendingRequests");
        assertEq(owner, address(0x0), "owner");

        (,,, ProofOfHumanity.Party ruling) = poh.getChallengeInfo(humanityId, 0, 0);
        assertEq(uint8(ruling), uint8(ProofOfHumanity.Party.Requester), "ruling");

        arbitrator.giveRuling(2, uint(ProofOfHumanity.Party.Requester));
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(2, uint(ProofOfHumanity.Party.Requester));

        (, usedReasons,,,,,, status,) = poh.getRequestInfo(humanityId, 0);
        assertEq(usedReasons, 5, "usedReasons");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Resolving), "status");

        (,,, ruling) = poh.getChallengeInfo(humanityId, 0, 1);
        assertEq(uint8(ruling), uint8(ProofOfHumanity.Party.Requester), "ruling");

        skip(params.challengePeriodDuration + 1);
        poh.executeRequest(humanityId, 0);

        (,, nbPendingRequests, expirationTime, owner,) = poh.getHumanityInfo(humanityId);
        assertEq(nbPendingRequests, 0, "nbPendingRequests");
        assertEq(expirationTime, uint64(block.timestamp) + params.humanityLifespan, "expirationTime");
        assertEq(owner, me, "owner");
    }

    function test_RequesterWon_ChallengedAllReasons() external requesterWonFirstRound {
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Requester));

        vm.prank(challenger);
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.Deceased, "evidence");

        arbitrator.giveRuling(2, uint(ProofOfHumanity.Party.Requester));
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(2, uint(ProofOfHumanity.Party.Requester));

        vm.prank(challenger);
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.Duplicate, "evidence");

        arbitrator.giveRuling(3, uint(ProofOfHumanity.Party.Requester));
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(3, uint(ProofOfHumanity.Party.Requester));

        vm.prank(challenger);
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.DoesNotExist, "evidence");

        arbitrator.giveRuling(4, uint(ProofOfHumanity.Party.Requester));
        skip(params.appealTimeOut + 1);

        vm.expectCall(
            address(poh),
            abi.encodeCall(poh.rule, (4, uint(ProofOfHumanity.Party.Requester)))
        );

        vm.expectEmit(true, false, false, true);
        emit HumanityClaimed(humanityId, 0);
        vm.expectEmit(true, false, false, true);
        emit Ruling(arbitrator, 4, uint(ProofOfHumanity.Party.Requester));

        arbitrator.giveRuling(4, uint(ProofOfHumanity.Party.Requester));

        (,,, ProofOfHumanity.Party ruling) = poh.getChallengeInfo(humanityId, 0, 3);
        assertEq(uint8(ruling), uint8(ProofOfHumanity.Party.Requester), "ruling");

        (, uint8 usedReasons,,,,,, ProofOfHumanity.Status status,) = poh.getRequestInfo(humanityId, 0);
        assertEq(usedReasons, 15, "usedReasons");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Resolved), "status");

        (,, uint64 nbPendingRequests, uint64 expirationTime, address owner,) = poh.getHumanityInfo(humanityId);
        assertEq(nbPendingRequests, 0, "nbPendingRequests");
        assertEq(expirationTime, uint64(block.timestamp) + params.humanityLifespan, "expirationTime");
        assertEq(owner, me, "owner");
    }

    function test_ChallengerWon_SettingValues() external challengerWonFirstRound {
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Challenger));

        (bool requesterLost,,,,, address requester, address ultimateChallenger, ProofOfHumanity.Status status, ProofOfHumanity.Reason currentReason) = poh.getRequestInfo(humanityId, 0);
        assertTrue(requesterLost, "requesterLost");
        assertEq(requester, me, "requester");
        assertEq(ultimateChallenger, challenger, "ultimateChallenger");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Resolved), "status");
        assertEq(uint8(currentReason), uint8(ProofOfHumanity.Reason.IncorrectSubmission), "currentReason");

        (uint16 lastRoundId,, uint256 disputeId, ProofOfHumanity.Party ruling) = poh.getChallengeInfo(humanityId, 0, 0);
        assertEq(lastRoundId, 1, "lastRoundId");
        assertEq(disputeId, 1, "disputeId");
        assertEq(uint8(ruling), uint8(ProofOfHumanity.Party.Challenger), "ruling");

        (uint256 paidFeesRequester, uint256 paidFeesChallenger, ProofOfHumanity.Party sideFunded, uint256 feeRewards) = poh.getRoundInfo(humanityId, 0, 0, 0);
        assertEq(paidFeesRequester, params.totalCost, "paidFeesRequester");
        assertEq(paidFeesChallenger, params.arbitrationCost, "paidFeesChallenger");
        assertEq(uint8(sideFunded), uint8(ProofOfHumanity.Party.None), "sideFunded");
        assertEq(feeRewards, params.totalCost, "feeRewards");
    }

    function test_Draw_SettingValues() external drawFirstRound {
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.None));

        (bool requesterLost,,,,, address requester, address ultimateChallenger, ProofOfHumanity.Status status, ProofOfHumanity.Reason currentReason) = poh.getRequestInfo(humanityId, 0);
        assertTrue(requesterLost, "requesterLost");
        assertEq(requester, me, "requester");
        assertEq(ultimateChallenger, address(0x0), "ultimateChallenger");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Resolved), "status");
        assertEq(uint8(currentReason), uint8(ProofOfHumanity.Reason.IncorrectSubmission), "currentReason");

        (uint16 lastRoundId,, uint256 disputeId, ProofOfHumanity.Party ruling) = poh.getChallengeInfo(humanityId, 0, 0);
        assertEq(lastRoundId, 1, "lastRoundId");
        assertEq(disputeId, 1, "disputeId");
        assertEq(uint8(ruling), uint8(ProofOfHumanity.Party.None), "ruling");

        (uint256 paidFeesRequester, uint256 paidFeesChallenger, ProofOfHumanity.Party sideFunded, uint256 feeRewards) = poh.getRoundInfo(humanityId, 0, 0, 0);
        assertEq(paidFeesRequester, params.totalCost, "paidFeesRequester");
        assertEq(paidFeesChallenger, params.arbitrationCost, "paidFeesChallenger");
        assertEq(uint8(sideFunded), uint8(ProofOfHumanity.Party.None), "sideFunded");
        assertEq(feeRewards, params.totalCost, "feeRewards");
    }

    function test_ChallengerWon_CantExecute() external challengerWonFirstRound {
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Challenger));

        vm.expectRevert();
        poh.executeRequest(humanityId, 0);
    }

    function test_ChallengerWon_OnNotFirstChallenge() external requesterWonFirstRound {
        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Requester));

        vm.prank(challenger);
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 0, ProofOfHumanity.Reason.Duplicate, "evidence");

        arbitrator.giveRuling(2, uint(ProofOfHumanity.Party.Challenger));
        skip(params.appealTimeOut + 1);

        vm.expectEmit(true, false, false, true);
        emit Ruling(arbitrator, 2, uint(ProofOfHumanity.Party.Challenger));

        arbitrator.giveRuling(2, uint(ProofOfHumanity.Party.Challenger));

        (bool requesterLost, uint8 usedReasons,,,,,, ProofOfHumanity.Status status, ProofOfHumanity.Reason currentReason) = poh.getRequestInfo(humanityId, 0);
        assertTrue(requesterLost, "requesterLost");
        assertEq(usedReasons, 5, "usedReasons");
        assertEq(uint8(status), uint8(ProofOfHumanity.Status.Resolved), "status");
        assertEq(uint8(currentReason), uint8(ProofOfHumanity.Reason.Duplicate), "currentReason");

        (,, uint64 nbPendingRequests, uint64 expirationTime, address owner,) = poh.getHumanityInfo(humanityId);
        assertEq(nbPendingRequests, 0, "nbPendingRequests");
        assertEq(expirationTime, 0, "expirationTime");
        assertEq(owner, address(0x0), "owner");
    }

    function test_Appeal_SettingValues() external requesterWonFirstRound {
        emit log("TODO");
    }

    function test_Appeal_CantAppealAfterPeriodPassed() external requesterWonFirstRound {
        (uint256 appealPeriodStart, uint256 appealPeriodEnd) = arbitrator.appealPeriod(1);

        poh.fundAppeal{value: 1}(humanityId, 0, 0, ProofOfHumanity.Party.Requester);
        poh.fundAppeal{value: 1}(humanityId, 0, 0, ProofOfHumanity.Party.Challenger);

        skip((appealPeriodEnd - appealPeriodStart) / 2 + 1);

        poh.fundAppeal{value: 1}(humanityId, 0, 0, ProofOfHumanity.Party.Requester);
        vm.expectRevert();
        poh.fundAppeal{value: 1}(humanityId, 0, 0, ProofOfHumanity.Party.Challenger);

        skip((appealPeriodEnd - appealPeriodStart) / 2 + 1);

        vm.expectRevert();
        poh.fundAppeal{value: 1}(humanityId, 0, 0, ProofOfHumanity.Party.Requester);
        vm.expectRevert();
        poh.fundAppeal{value: 1}(humanityId, 0, 0, ProofOfHumanity.Party.Challenger);
    }

    function test_Appeal_CallingArbitrator() external requesterWonFirstRound {
        vm.expectCall(
            address(arbitrator),
            abi.encodeCall(arbitrator.appealCost, (1, params.arbitratorExtraData))
        );
        poh.fundAppeal{value: 12}(humanityId, 0, 0, ProofOfHumanity.Party.Requester);
    }

    function test_Appeal_Contributions() external requesterWonFirstRound {
        vm.expectEmit(true, false, false, true);
        emit Contribution(humanityId, 0, 0, 1, me, 12, ProofOfHumanity.Party.Requester);

        poh.fundAppeal{value: 12}(humanityId, 0, 0, ProofOfHumanity.Party.Requester);

        uint256 totalCost = arbitrator.appealCost(1, params.arbitratorExtraData) + arbitrator.appealCost(1, params.arbitratorExtraData) * poh.loserStakeMultiplier() / _MULTIPLIER_DIVISOR;

        vm.expectEmit(true, false, false, true);
        emit Contribution(humanityId, 0, 0, 1, me, totalCost, ProofOfHumanity.Party.Challenger);

        poh.fundAppeal{value: totalCost * 2}(humanityId, 0, 0, ProofOfHumanity.Party.Challenger);
    }

    function test_RequesterWon_Appeal() external challengerWonFirstRound {
        uint256 totalCost = arbitrator.appealCost(1, params.arbitratorExtraData) + arbitrator.appealCost(1, params.arbitratorExtraData) * poh.loserStakeMultiplier() / _MULTIPLIER_DIVISOR;

        vm.expectEmit(true, false, false, true);
        emit Contribution(humanityId, 0, 0, 1, me, totalCost, ProofOfHumanity.Party.Requester);

        poh.fundAppeal{value: totalCost * 3}(humanityId, 0, 0, ProofOfHumanity.Party.Requester);

        totalCost = arbitrator.appealCost(1, params.arbitratorExtraData) + arbitrator.appealCost(1, params.arbitratorExtraData) * poh.winnerStakeMultiplier() / _MULTIPLIER_DIVISOR;

        vm.expectEmit(true, false, false, true);
        emit Contribution(humanityId, 0, 0, 1, me, totalCost, ProofOfHumanity.Party.Challenger);

        poh.fundAppeal{value: totalCost * 3}(humanityId, 0, 0, ProofOfHumanity.Party.Challenger);

        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Requester));

        assertFalse(poh.isHuman(me));

        skip(params.challengePeriodDuration + 1);

        poh.executeRequest(humanityId, 0);

        assertTrue(poh.isHuman(me));
    }

    function test_ChallengerWon_Appeal() external requesterWonFirstRound {
        uint256 totalCost = arbitrator.appealCost(1, params.arbitratorExtraData) + arbitrator.appealCost(1, params.arbitratorExtraData) * poh.loserStakeMultiplier() / _MULTIPLIER_DIVISOR;

        poh.fundAppeal{value: totalCost * 3}(humanityId, 0, 0, ProofOfHumanity.Party.Requester);

        totalCost = arbitrator.appealCost(1, params.arbitratorExtraData) + arbitrator.appealCost(1, params.arbitratorExtraData) * poh.winnerStakeMultiplier() / _MULTIPLIER_DIVISOR;

        poh.fundAppeal{value: totalCost * 3}(humanityId, 0, 0, ProofOfHumanity.Party.Challenger);

        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.Challenger));

        vm.expectRevert();
        poh.executeRequest(humanityId, 0);

        assertFalse(poh.isHuman(me));
    }

    function test_UnpaidAppeal() external requesterWonFirstRound {
        uint256 totalCost = arbitrator.appealCost(1, params.arbitratorExtraData) + arbitrator.appealCost(1, params.arbitratorExtraData) * poh.loserStakeMultiplier() / _MULTIPLIER_DIVISOR;

        poh.fundAppeal{value: totalCost}(humanityId, 0, 0, ProofOfHumanity.Party.Challenger);

        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(1, uint(ProofOfHumanity.Party.None));

        vm.expectRevert();
        poh.executeRequest(humanityId, 0);

        poh.processVouches(humanityId, 0, 10);

        assertFalse(poh.isHuman(me));

        poh.claimHumanity{value: params.totalCost}("evidence", "voucher");

        address[] memory onChainVouches = new address[](2);
        onChainVouches[0] = vouchers[0];
        onChainVouches[1] = vouchers[1];

        poh.advanceState(me, onChainVouches, new ProofOfHumanity.SignatureVouch[](0));

        vm.prank(challenger);
        poh.challengeRequest{value: params.arbitrationCost}(humanityId, 1, ProofOfHumanity.Reason.IncorrectSubmission, "evidence");

        arbitrator.giveRuling(2, uint(ProofOfHumanity.Party.Requester));

        totalCost = arbitrator.appealCost(2, params.arbitratorExtraData) + arbitrator.appealCost(2, params.arbitratorExtraData) * poh.winnerStakeMultiplier() / _MULTIPLIER_DIVISOR;

        poh.fundAppeal{value: totalCost}(humanityId, 1, 0, ProofOfHumanity.Party.Requester);

        skip(params.appealTimeOut + 1);
        arbitrator.giveRuling(2, uint(ProofOfHumanity.Party.None));

        vm.expectRevert();
        poh.executeRequest(humanityId, 1);

        skip(params.challengePeriodDuration + 1);

        assertFalse(poh.isHuman(me));

        poh.executeRequest(humanityId, 1);

        assertTrue(poh.isHuman(me));
    }

    function test_OneChallenge_MultipleAppeals() external requesterWonFirstRound {
        emit log("TODO");
    }

    function test_MultipleChallenges_MultipleAppeals() external {
        emit log("TODO");
    }
}
