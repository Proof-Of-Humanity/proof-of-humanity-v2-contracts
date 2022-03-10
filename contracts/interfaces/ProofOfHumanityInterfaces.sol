// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@kleros/erc-792/contracts/IArbitrator.sol";

interface IProofOfHumanityBase {
    enum Status {
        None, // The submission doesn't have a pending status.
        Vouching, // The submission is in the state where it can be vouched for and crowdfunded.
        PendingRegistration, // The submission is in the state where it can be challenged. Or accepted to the list, if there are no challenges within the time limit.
        PendingRemoval // The submission is in the state where it can be challenged. Or removed from the list, if there are no challenges within the time limit.
    }

    function isRegistered(address _submissionID) external view returns (bool);

    function submissionCounter() external view returns (uint256);
}

interface IProofOfHumanityOld is IProofOfHumanityBase {
    /* Governance */

    function removeSubmissionManually(address _submissionID) external;

    function changeSubmissionBaseDeposit(uint256 _submissionBaseDeposit) external;

    function changeDurations(
        uint64 _submissionDuration,
        uint64 _renewalPeriodDuration,
        uint64 _challengePeriodDuration
    ) external;

    function changeRequiredNumberOfVouches(uint64 _requiredNumberOfVouches) external;

    function changeSharedStakeMultiplier(uint256 _sharedStakeMultiplier) external;

    function changeWinnerStakeMultiplier(uint256 _winnerStakeMultiplier) external;

    function changeLoserStakeMultiplier(uint256 _loserStakeMultiplier) external;

    function changeMetaEvidence(string calldata _registrationMetaEvidence, string calldata _clearingMetaEvidence)
        external;

    function changeArbitrator(IArbitrator _arbitrator, bytes calldata _arbitratorExtraData) external;

    /* Views */

    function getSubmissionInfo(address _submissionID)
        external
        view
        returns (
            Status status,
            uint64 submissionTime,
            uint64 index,
            bool registered,
            bool hasVouched,
            uint256 numberOfRequests
        );
}

interface IProofOfHumanity is IProofOfHumanityBase {
    /* Manual adding/removing */

    function addSubmissionManually(address _submissionID, uint64 _submissionTime) external;

    function removeSubmissionManually(address _submissionID) external;

    /* Views */

    function getSubmissionInfo(address _submissionID)
        external
        view
        returns (
            Status status,
            uint64 submissionTime,
            bool registered,
            bool hasVouched,
            uint256 numberOfRequests
        );
}
