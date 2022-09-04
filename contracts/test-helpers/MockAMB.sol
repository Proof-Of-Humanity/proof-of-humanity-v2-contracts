// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../interfaces/IAMB.sol";

contract MockAMB is IAMB {
    uint256 private currentMessageId;
    address private currentMessageSender;

    event MessagePassed(address _contract, bytes _data, uint256 _gas);

    function requireToPassMessage(
        address _contract,
        bytes memory _data,
        uint256 _gas
    ) external override returns (bytes32) {
        currentMessageSender = msg.sender;

        (bool success, ) = _contract.call(_data);
        require(success, "Failed to call contract");

        emit MessagePassed(_contract, _data, _gas);

        return bytes32(++currentMessageId);
    }

    function maxGasPerTx() external pure override returns (uint256) {
        return 8000000;
    }

    function messageSender() external view override returns (address) {
        return currentMessageSender;
    }

    function messageSourceChainId() external view override returns (bytes32) {
        return bytes32(block.chainid);
    }
}
