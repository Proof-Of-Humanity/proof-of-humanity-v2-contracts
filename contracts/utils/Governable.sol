// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

abstract contract Governable {
    /// @dev The address that can make governance changes to the parameters of the contract.
    address public governor;

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
