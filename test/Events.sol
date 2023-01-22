// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "src/interfaces/IArbitrator.sol";
import "src/interfaces/IEvidence.sol";
import "src/ProofOfHumanity.sol";

interface ProofOfHumanityEvents is IEvidence {
    event Ruling(IArbitrator indexed _arbitrator, uint256 indexed _disputeID, uint256 _ruling);

    event Initialized();
    event GovernorChanged(address governor);
    event RequestBaseDepositChanged(uint256 requestBaseDeposit);
    event DurationsChanged(uint64 humanityLifespan, uint64 renewalPeriodDuration, uint64 challengePeriodDuration);
    event RequiredNumberOfVouchesChanged(uint64 requiredNumberOfVouches);
    event StakeMultipliersChanged(uint256 sharedMultiplier, uint256 winnerMultiplier, uint256 loserMultiplier);
    event CrossChainProxyChanged(address crossChainProofOfHumanity);
    event ArbitratorChanged(IArbitrator arbitrator, bytes arbitratorExtraData);
    event HumanityGrantedManually(bytes20 indexed humanityId, address indexed owner, uint64 expirationTime);
    event HumanityRevokedManually(bytes20 indexed humanityId);
    event ClaimRequest(
        address indexed requester,
        bytes20 indexed humanityId,
        uint256 requestId,
        string evidence,
        string name
    );
    event RenewalRequest(address indexed requester, bytes20 indexed humanityId, uint256 requestId, string evidence);
    event RevocationRequest(address indexed requester, bytes20 indexed humanityId, uint256 requestId, string evidence);
    event VouchAdded(address indexed voucherAccount, address indexed claimer, bytes20 humanityId);
    event VouchRemoved(address indexed voucherAccount, address indexed claimer, bytes20 humanityId);
    event VouchRegistered(bytes20 indexed voucherHumanityId, bytes20 indexed vouchedHumanityId, uint256 requestId);
    event RequestWithdrawn(bytes20 humanityId, uint256 requestId);
    event StateAdvanced(address claimer);
    event RequestChallenged(
        bytes20 humanityId,
        uint256 requestId,
        uint256 challengeId,
        ProofOfHumanity.Reason reason,
        uint256 disputeId,
        string evidence
    );
    event HumanityClaimed(bytes20 humanityId, uint256 requestId);
    event HumanityRevoked(bytes20 humanityId, uint256 requestId);
    event VouchesProcessed(bytes20 humanityId, uint256 requestId, uint256 endIndex);
    event ChallengePeriodRestart(bytes20 humanityId, uint256 requestId, uint256 challengeId);
    event AppealCreated(IArbitrator arbitrator, uint256 disputeId);
    event Contribution(
        bytes20 humanityId,
        uint256 requestId,
        uint256 challengeId,
        uint256 round,
        address contributor,
        uint256 contribution,
        ProofOfHumanity.Party side
    );
    event FeesAndRewardsWithdrawn(
        bytes20 humanityId,
        uint256 requestId,
        uint256 challengeId,
        uint256 round,
        address beneficiary
    );
}

interface CrossChainProofOfHumanityEvents {
    event GatewayAdded(address indexed bridgeGateway, address foreignProxy);
    event GatewayRemoved(address indexed bridgeGateway);
    event UpdateInitiated(
        bytes20 indexed humanityId,
        address indexed owner,
        uint160 expirationTime,
        address gateway,
        bool claimed
    );
    event UpdateReceived(bytes20 indexed humanityId, address indexed owner, uint160 expirationTime, bool claimed);
    event TransferInitiated(
        bytes20 indexed humanityId,
        address indexed owner,
        uint160 expirationTime,
        address gateway,
        bytes32 transferHash
    );
    event TransferRetry(bytes32 transferHash);
    event TransferReceived(
        bytes20 indexed humanityId,
        address indexed owner,
        uint160 expirationTime,
        bytes32 transferHash
    );

}
