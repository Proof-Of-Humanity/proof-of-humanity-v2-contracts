// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

interface ICrossChainProofOfHumanity {
    function receiveUpdate(
        address _submissionID,
        uint160 _qid,
        uint64 _submissionTime
    ) external;

    event UpdateReceived(address _submissionID, uint160 _qid, uint64 _submissionTime);

    function receiveTransfer(
        address _submissionID,
        uint160 _qid,
        uint64 _submissionTime,
        bytes32 _transferHash
    ) external;

    event TransferReceived(address _submissionID);
}
