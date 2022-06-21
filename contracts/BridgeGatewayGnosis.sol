// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import {IAMB} from "./interfaces/IAMB.sol";
import {IBridgeGateway} from "./interfaces/IBridgeGateway.sol";

contract BridgeGatewayGnosis is IBridgeGateway {
    address public governor;
    IAMB public amb;
    address public homeProxy;
    address public foreignProxy;
    bytes32 public foreignChainID;

    modifier onlyGovernor() {
        require(msg.sender == governor, "Only governor");
        _;
    }

    constructor(IAMB _amb, address _homeProxy) {
        governor = msg.sender;
        amb = _amb;
        homeProxy = _homeProxy;
    }

    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
    }

    function changeAmb(IAMB _amb) external onlyGovernor {
        amb = _amb;
    }

    function setForeignProxy(address _foreignProxy, uint256 _foreignChainID) external onlyGovernor {
        require(foreignProxy == address(0), "Foreign proxy already set");
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
