// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

interface ICrossChainProofOfHumanity {
    function receiveUpdate(
        address _humanID,
        uint160 _soulID,
        uint64 _claimTime,
        bool _isActive
    ) external;

    event UpdateReceived(address _humanID, uint160 _soulID, uint64 _claimTime);

    function receiveTransfer(
        address _humanID,
        uint160 _soulID,
        uint64 _claimTime,
        bytes32 _transferHash
    ) external;

    event TransferReceived(address _humanID);
}
