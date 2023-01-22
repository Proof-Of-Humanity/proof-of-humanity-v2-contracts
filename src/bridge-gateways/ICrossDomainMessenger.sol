// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);

    /**
     * @param _target The address of the contract on the other network
     * @param _message Encoded bytes of the method selector and the parameters that will be called in the contract on the other network
     * @param _gasLimit Gas to be provided in execution of the method call in the contract on the other chain
     */
    function sendMessage(
        address _target,
        bytes memory _message,
        uint32 _gasLimit
    ) external;
}
