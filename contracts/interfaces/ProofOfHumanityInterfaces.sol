// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@kleros/erc-792/contracts/IArbitrator.sol";

interface IProofOfHumanityBase {
    enum Status {
        None, // The submission doesn't have a pending status.
        Vouching, // The submission is in the state where it can be vouched for and crowdfunded.
        PendingRegistration, // The submission is in the state where it can be challenged. Or accepted to the list, if there are no challenges within the time limit.
        PendingRemoval // The submission is in the state where it can be challenged. Or removed from the list, if there are no challenges within the time limit.
    }

    function isRegistered(address _submissionID) external view returns (bool);
}

interface IProofOfHumanityOld is IProofOfHumanityBase {
    /* Governance */

    function removeSubmissionManually(address _submissionID) external;

    /* Views */

    function vouches(address voucherID, address submissionID) external view returns (bool);

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
    function submissionDuration() external view returns (uint64);

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
