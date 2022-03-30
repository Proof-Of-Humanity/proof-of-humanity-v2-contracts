// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Governable} from "./utils/Governable.sol";
import {IAMB} from "./interfaces/IAMB.sol";
import {IBridgeGateway} from "./interfaces/IBridgeGateway.sol";

contract BridgeGatewayGnosis is IBridgeGateway, Governable {
    IAMB public amb;
    address public homeProxy;
    address public foreignProxy;
    bytes32 public foreignChainID;

    constructor(IAMB _amb, address _homeProxy) {
        amb = _amb;
        homeProxy = _homeProxy;
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
        require(msg.sender == homeProxy, "Only the home proxy allowed");
        abi.encodeWithSelector(this.receiveMessage.selector, _data);
        amb.requireToPassMessage(foreignProxy, _data, amb.maxGasPerTx());
    }

    function receiveMessage(bytes memory _data) external override {
        require(msg.sender == address(amb), "Only the AMB allowed");
        require(amb.messageSender() == foreignProxy, "Only foreign proxy allowed");
        require(amb.messageSourceChainId() == foreignChainID, "Only foreign chain allowed");
        homeProxy.call(_data);
    }
}
