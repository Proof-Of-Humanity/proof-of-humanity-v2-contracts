// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IProofOfHumanityOld {
    enum OldStatus {
        None,
        Vouching,
        PendingRegistration,
        PendingRemoval
    }

    /* Views */

    function submissionDuration() external view returns (uint64);

    function isRegistered(address _submissionID) external view returns (bool);

    function getSubmissionInfo(
        address _submissionID
    ) external view returns (OldStatus, uint64 submissionTime, uint64, bool registered, bool, uint256);
}
