// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

enum OldStatus {
    None, // The submission doesn't have a pending status.
    Vouching, // The submission is in the state where it can be vouched for and crowdfunded.
    PendingRegistration, // The submission is in the state where it can be challenged. Or accepted to the list, if there are no challenges within the time limit.
    PendingRemoval // The submission is in the state where it can be challenged. Or removed from the list, if there are no challenges within the time limit.
}

interface IProofOfHumanityOld {
    /* Governance */

    function removeSubmissionManually(address _submissionID) external;

    /* Views */

    function submissionDuration() external view returns (uint64);

    function isRegistered(address _submissionID) external view returns (bool);

    function getSubmissionInfo(address _submissionID)
        external
        view
        returns (
            OldStatus status,
            uint64 submissionTime,
            uint64 index,
            bool registered,
            bool hasVouched,
            uint256 numberOfRequests
        );
}
