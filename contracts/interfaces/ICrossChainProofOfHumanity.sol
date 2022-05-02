// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface ICrossChainProofOfHumanity {
    function receiveUpdate(
        address _submissionID,
        uint64 _submissionTime,
        bool _isRegistered
    ) external;

    event UpdateReceived(address _submissionID, uint64 _submissionTime, bool _isRegistered);

    function receiveTransfer(
        uint160 _qid,
        address _submissionID,
        uint64 _submissionTime,
        bytes32 _transferHash
    ) external;

    event TransferReceived(address _submissionID);
}
