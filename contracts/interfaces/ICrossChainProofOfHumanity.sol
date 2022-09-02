// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

interface ICrossChainProofOfHumanity {
    function receiveUpdate(
        address _owner,
        bytes20 _humanityId,
        uint64 _expirationTime,
        bool _isActive
    ) external;

    event UpdateReceived(address _owner, bytes20 _humanityId, uint64 _expirationTime);

    function receiveTransfer(
        address _owner,
        bytes20 _humanityId,
        uint64 _expirationTime,
        bytes32 _transferHash
    ) external;

    event TransferReceived(address _owner);

    function receiveTransferReversion(
        bytes20 _humanityId,
        uint64 _initiationTime,
        address _initiator
    ) external;
}
