// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBridgeGateway {
    function sendMessage(bytes memory _data) external;

    function receiveMessage(bytes memory _data) external;
}
