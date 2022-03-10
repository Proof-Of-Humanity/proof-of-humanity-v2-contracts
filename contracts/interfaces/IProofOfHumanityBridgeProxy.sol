// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

interface IProofOfHumanityBridgeProxy {
    function receiveSubmissionUpdate(address _submissionID, bool _isRegistered) external;

    event SubmissionUpdated(address _human, bool _isRegistered);

    function receiveSubmissionTransfer(address _submissionID, uint64 _submissionTime) external;

    event SubmissionTransfered(address _human);

    // function requestSubmissionUpdate(address _submissionID) external;
}
