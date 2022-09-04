// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IAMB} from "./interfaces/IAMB.sol";
import {IBridgeGateway} from "./interfaces/IBridgeGateway.sol";

contract BridgeGatewayGnosis is IBridgeGateway {
    IAMB public immutable amb;
    address public immutable homeProxy;
    address public immutable foreignProxy;
    bytes32 public immutable foreignChainID;

    constructor(
        IAMB _amb,
        address _homeProxy,
        address _foreignProxy,
        uint256 _foreignChainID
    ) {
        amb = _amb;
        homeProxy = _homeProxy;
        foreignProxy = _foreignProxy;
        foreignChainID = bytes32(_foreignChainID);
    }

    function sendMessage(bytes memory _data) external override {
        require(msg.sender == homeProxy, "Only home proxy allowed");
        amb.requireToPassMessage(foreignProxy, abi.encodeCall(this.receiveMessage, (_data)), amb.maxGasPerTx());
    }

    function receiveMessage(bytes memory _data) external override {
        require(msg.sender == address(amb), "Only AMB allowed");
        require(amb.messageSender() == foreignProxy, "Message sender must be foreign proxy");
        require(amb.messageSourceChainId() == foreignChainID, "Source chain must be foreign chain");
        homeProxy.call(_data);
    }
}
