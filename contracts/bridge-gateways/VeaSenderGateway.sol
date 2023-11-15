// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IVeaReceiver} from "./VeaReceiverGateway.sol";
import {IBridgeGateway} from "./IBridgeGateway.sol";

interface IVeaInbox {
    function sendMessage(address to, bytes4 fnSelection, bytes memory data) external returns (uint64 msgId);
}

contract VeaSenderGateway is IBridgeGateway {
    IVeaInbox public immutable veaInbox;
    address public immutable homeProxy;
    address public foreignGateway;

    // === Setting variables ===

    constructor(address _veaInbox, address _homeProxy) {
        veaInbox = IVeaInbox(_veaInbox);
        homeProxy = _homeProxy;
    }

    function setForeignGateway(address _foreignGateway) public {
        require(foreignGateway == address(0x0), "set!");
        foreignGateway = _foreignGateway;
    }

    // === Sending / receiving messages ===

    function sendMessage(bytes memory _data) external override {
        require(msg.sender == homeProxy, "!homeProxy");
        veaInbox.sendMessage(foreignGateway, IVeaReceiver.receiveMessage.selector, _data);
    }
}
