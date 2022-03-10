// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

/** @title Governable
 *  @dev The Governable contract has an governor address, and provides basic authorization control
 *  functions, this simplifies the implementation of "user permissions".
 */
contract Governable {
    /// @dev The address that can make governance changes to the parameters of the contract.
    address public governor = msg.sender;

    modifier onlyGovernor() {
        require(msg.sender == governor, "Must be governor");
        _;
    }

    /** @dev Change the governor of the contract.
     *  @param _governor The address of the new governor.
     */
    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
    }
}
