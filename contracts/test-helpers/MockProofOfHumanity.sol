// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "../interfaces/ProofOfHumanityInterfaces.sol";

contract MockProofOfHumanity is IProofOfHumanity {
    struct Submission {
        bool registered;
        uint64 submissionTime;
    }

    mapping(address => Submission) public submissions;
    uint256 public override submissionCounter;

    function addSubmissionManually(address _submissionID, uint64 _submissionTime) external override {
        Submission storage submission = submissions[_submissionID];
        if (submission.submissionTime == 0) submissionCounter++;
        submission.registered = true;
        submission.submissionTime = _submissionTime;
    }

    function removeSubmissionManually(address _submissionID) external override {
        Submission storage submission = submissions[_submissionID];
        require(submission.registered, "Wrong status");
        submission.registered = false;
    }

    function isRegistered(address _submissionID) external view override returns (bool) {
        return submissions[_submissionID].registered;
    }

    function getSubmissionInfo(address _submissionID)
        external
        view
        override
        returns (
            Status status,
            uint64 submissionTime,
            bool registered,
            bool hasVouched,
            uint256 numberOfRequests
        )
    {
        return (
            Status.None,
            submissions[_submissionID].submissionTime,
            submissions[_submissionID].registered,
            false,
            0
        );
    }
}
