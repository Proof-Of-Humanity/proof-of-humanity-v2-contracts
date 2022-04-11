// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {Governable} from "./utils/Governable.sol";
import {IAMB} from "./interfaces/IAMB.sol";
import {IBridgeGateway} from "./interfaces/IBridgeGateway.sol";

error ForeignProxyAlreadySet();
error OnlyAMBAllowed();
error OnlyHomeProxyAllowed();
error SenderNotForeignProxy();
error SourceChainNotForeignChain();

contract BridgeGatewayGnosis is IBridgeGateway, Governable {
    IAMB public amb;
    address public homeProxy;
    address public foreignProxy;
    bytes32 public foreignChainID;

    constructor(IAMB _amb, address _homeProxy) {
        governor = msg.sender;
        amb = _amb;
        homeProxy = _homeProxy;
    }

    function changeAmb(IAMB _amb) external onlyGovernor {
        amb = _amb;
    }

    function setForeignProxy(address _foreignProxy, uint256 _foreignChainID) external onlyGovernor {
        if (foreignProxy != address(0)) revert ForeignProxyAlreadySet();
        foreignProxy = _foreignProxy;
        foreignChainID = bytes32(_foreignChainID);
    }

    function sendMessage(bytes memory _data) external override {
        if (msg.sender != homeProxy) revert OnlyHomeProxyAllowed();
        amb.requireToPassMessage(foreignProxy, abi.encodeCall(this.receiveMessage, (_data)), amb.maxGasPerTx());
    }

    function receiveMessage(bytes memory _data) external override {
        if (msg.sender != address(amb)) revert OnlyAMBAllowed();
        if (amb.messageSender() != foreignProxy) revert SenderNotForeignProxy();
        if (amb.messageSourceChainId() != foreignChainID) revert SourceChainNotForeignChain();
        homeProxy.call(_data);
    }
}
