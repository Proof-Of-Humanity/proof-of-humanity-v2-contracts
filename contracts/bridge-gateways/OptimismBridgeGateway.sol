// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IBridgeGateway} from "./IBridgeGateway.sol";

interface ICrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);

    /**
     * @param _target The address of the contract on the other network
     * @param _message Encoded bytes of the method selector and the parameters that will be called in the contract on the other network
     * @param _gasLimit Gas to be provided in execution of the method call in the contract on the other chain
     */
    function sendMessage(address _target, bytes memory _message, uint32 _gasLimit) external;
}

interface IAMBReceiver {
    function receiveMessage(bytes memory _data) external;
}

contract OptimismBridgeGateway is IBridgeGateway, IAMBReceiver {
    uint32 internal constant GAS_LIMIT = 5_000_000;

    ICrossDomainMessenger public immutable messenger;
    address public immutable homeProxy;
    address public foreignGateway;

    constructor(address _messenger, address _homeProxy) {
        messenger = ICrossDomainMessenger(_messenger);
        homeProxy = _homeProxy;
    }

    function setForeignGateway(address _foreignGateway) public {
        require(foreignGateway == address(0x0), "set!");
        foreignGateway = _foreignGateway;
    }

    function sendMessage(bytes memory _data) external override {
        require(msg.sender == homeProxy, "!homeProxy");
        messenger.sendMessage(foreignGateway, abi.encodeCall(this.receiveMessage, (_data)), GAS_LIMIT);
    }

    function receiveMessage(bytes memory _data) external override {
        require(msg.sender == address(messenger), "!messenger");
        require(messenger.xDomainMessageSender() == foreignGateway, "!foreignGateway");
        homeProxy.call(_data);
    }
}
