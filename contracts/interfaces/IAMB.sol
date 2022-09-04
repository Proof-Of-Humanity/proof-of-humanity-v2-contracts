// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/**
 * @dev Arbitrary Message Bridge interface for cross-chain communication
 */
interface IAMB {
    /**
     * @notice Sets the address of the arbitration proxy on the Foreign Chain
     * @param _contract The address of the contract on the other network
     * @param _data Encoded bytes of the method selector and the parameters that will be called in the contract on the other network
     * @param _gas Gas to be provided in execution of the method call in the contract on the other chain
     */
    function requireToPassMessage(
        address _contract,
        bytes memory _data,
        uint256 _gas
    ) external returns (bytes32);

    function maxGasPerTx() external view returns (uint256);

    function messageSender() external view returns (address);

    function messageSourceChainId() external view returns (bytes32);
}
