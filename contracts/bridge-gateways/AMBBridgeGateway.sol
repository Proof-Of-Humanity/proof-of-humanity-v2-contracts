// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IBridgeGateway} from "./IBridgeGateway.sol";

interface IAMB {
    /**
     * @param _contract The address of the contract on the other network
     * @param _data Encoded bytes of the method selector and the parameters that will be called in the contract on the other network
     * @param _gas Gas to be provided in execution of the method call in the contract on the other chain
     */
    function requireToPassMessage(address _contract, bytes memory _data, uint256 _gas) external returns (bytes32);

    function maxGasPerTx() external view returns (uint256);

    function messageSender() external view returns (address);
}

interface IAMBReceiver {
    function receiveMessage(bytes memory _data) external;
}

contract AMBBridgeGateway is IBridgeGateway, IAMBReceiver {
    IAMB public immutable amb;
    address public immutable homeProxy;
    address public foreignGateway;

    constructor(IAMB _amb, address _homeProxy) {
        amb = _amb;
        homeProxy = _homeProxy;
    }

    function setForeignGateway(address _foreignGateway) public {
        require(foreignGateway == address(0x0), "set!");
        foreignGateway = _foreignGateway;
    }

    function sendMessage(bytes memory _data) external override {
        require(msg.sender == homeProxy, "!homeProxy");
        amb.requireToPassMessage(foreignGateway, abi.encodeCall(this.receiveMessage, (_data)), amb.maxGasPerTx());
    }

    function receiveMessage(bytes memory _data) external override {
        require(msg.sender == address(amb), "!amb");
        require(amb.messageSender() == foreignGateway, "!foreignGateway");
        homeProxy.call(_data);
    }
}
