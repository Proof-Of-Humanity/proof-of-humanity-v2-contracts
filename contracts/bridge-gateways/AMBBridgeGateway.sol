// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IAMB} from "./IAMB.sol";
import {IBridgeGateway} from "./IBridgeGateway.sol";

contract AMBBridgeGateway is IBridgeGateway {
    IAMB public immutable amb;
    address public immutable homeProxy;

    constructor(IAMB _amb, address _homeProxy) {
        amb = _amb;
        homeProxy = _homeProxy;
    }

    function sendMessage(bytes memory _data) external override {
        require(msg.sender == homeProxy, "Only home proxy allowed");
        amb.requireToPassMessage(address(this), abi.encodeCall(this.receiveMessage, (_data)), amb.maxGasPerTx());
    }

    function receiveMessage(bytes memory _data) external override {
        require(msg.sender == address(amb), "Only AMB allowed");
        require(amb.messageSender() == address(this), "AMB sender must have address as this contract");
        homeProxy.call(_data);
    }
}
