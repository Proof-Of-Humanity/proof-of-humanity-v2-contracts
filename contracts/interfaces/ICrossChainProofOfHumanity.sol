// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface ICrossChainProofOfHumanity {
    function receiveUpdate(
        address _owner,
        bytes20 _humanityId,
        uint64 _expirationTime,
        bool _isActive
    ) external;

    function receiveTransfer(
        address _owner,
        bytes20 _humanityId,
        uint64 _expirationTime,
        bytes32 _transferHash
    ) external;
}
