// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IBridgeGateway} from "./IBridgeGateway.sol";

interface IVeaReceiver {
    function receiveMessage(address _sender, bytes memory _data) external;
}

contract VeaReceiverGateway is IVeaReceiver {
    address public immutable veaOutbox;
    address public immutable homeProxy;
    address public homeGateway;

    // === Setting variables ===

    constructor(address _veaOutbox, address _homeProxy) {
        veaOutbox = _veaOutbox;
        homeProxy = _homeProxy;
    }

    function setHomeGateway(address _homeGateway) public {
        require(homeGateway == address(0x0), "set!");
        homeGateway = _homeGateway;
    }

    // === Sending / receiving messages ===

    function receiveMessage(address _messageSender, bytes memory _data) external override {
        require(veaOutbox == msg.sender, "!vea");
        require(_messageSender == homeGateway, "!homeGateway");
        homeProxy.call(_data);
    }
}
