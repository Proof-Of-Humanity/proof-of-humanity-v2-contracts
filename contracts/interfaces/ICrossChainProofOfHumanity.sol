// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

interface ICrossChainProofOfHumanity {
    function receiveUpdate(
        address _humanID,
        uint160 _soulID,
        uint64 _expirationTime,
        bool _isActive
    ) external;

    event UpdateReceived(address _humanID, uint160 _soulID, uint64 _expirationTime);

    function receiveTransfer(
        address _humanID,
        uint160 _soulID,
        uint64 _expirationTime,
        bytes32 _transferHash
    ) external;

    event TransferReceived(address _humanID);
}
