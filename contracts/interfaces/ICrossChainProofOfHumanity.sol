// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {IProofOfHumanityBase} from "./ProofOfHumanityInterfaces.sol";

interface ICrossChainProofOfHumanity is IProofOfHumanityBase {
    function receiveSubmissionUpdate(
        address _submissionID,
        uint64 _submissionTime,
        bool _isRegistered
    ) external;

    event SubmissionUpdated(address _submissionID, uint64 _submissionTime, bool _isRegistered);

    function receiveSubmissionTransfer(
        address _submissionID,
        uint64 _submissionTime,
        bytes32 _transferHash
    ) external;

    event SubmissionTransfered(address _submissionID);
}
