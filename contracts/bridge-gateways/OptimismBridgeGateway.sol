// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IBridgeGateway} from "./IBridgeGateway.sol";
import {ICrossDomainMessenger} from "./ICrossDomainMessenger.sol";

contract OptimismBridgeGateway is IBridgeGateway {
    uint32 internal constant GAS_LIMIT = 5_000_000;

    ICrossDomainMessenger public immutable homeMessenger;
    address public immutable homeProxy;
    address public foreignProxy;

    constructor(address _messenger, address _homeProxy) {
        homeMessenger = ICrossDomainMessenger(_messenger);
        homeProxy = _homeProxy;
    }

    function setForeignProxy(address _foreignProxy) public {
        require(foreignProxy == address(0x0), "Foreign proxy already set");
        foreignProxy = _foreignProxy;
    }

    function sendMessage(bytes memory _data) external override {
        require(msg.sender == homeProxy, "Only home proxy allowed");
        homeMessenger.sendMessage(foreignProxy, abi.encodeCall(this.receiveMessage, (_data)), GAS_LIMIT);
    }

    function receiveMessage(bytes memory _data) external override {
        require(msg.sender == address(homeMessenger), "Only home messenger allowed");
        require(homeMessenger.xDomainMessageSender() == foreignProxy, "Message sender must be foreign proxy");
        homeProxy.call(_data);
    }
}
