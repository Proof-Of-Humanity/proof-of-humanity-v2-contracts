// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IBridgeGateway} from "./IBridgeGateway.sol";
import {ICrossDomainMessenger} from "./ICrossDomainMessenger.sol";

contract OptimismBridgeGateway is IBridgeGateway {
    uint32 internal constant GAS_LIMIT = 5_000_000;

    ICrossDomainMessenger public immutable messenger;
    address public immutable homeProxy;
    address public foreignGateway;

    constructor(address _messenger, address _homeProxy) {
        messenger = ICrossDomainMessenger(_messenger);
        homeProxy = _homeProxy;
    }

    function setForeignGateway(address _foreignGateway) public {
        require(foreignGateway == address(0x0), "Foreign proxy already set");
        foreignGateway = _foreignGateway;
    }

    function sendMessage(bytes memory _data) external override {
        require(msg.sender == homeProxy, "Only home proxy allowed");
        messenger.sendMessage(foreignGateway, abi.encodeCall(this.receiveMessage, (_data)), GAS_LIMIT);
    }

    function receiveMessage(bytes memory _data) external override {
        require(msg.sender == address(messenger), "Only home messenger allowed");
        require(messenger.xDomainMessageSender() == foreignGateway, "Message sender must be foreign proxy");
        homeProxy.call(_data);
    }
}
