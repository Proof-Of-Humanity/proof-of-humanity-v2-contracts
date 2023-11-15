// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ICrossChainProofOfHumanity {
    function receiveUpdate(address _owner, bytes20 _humanityId, uint40 _expirationTime, bool _isActive) external;

    function receiveTransfer(
        address _owner,
        bytes20 _humanityId,
        uint40 _expirationTime,
        bytes32 _transferHash
    ) external;
}
