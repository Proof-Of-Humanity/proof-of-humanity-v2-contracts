// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {IAMB} from "./interfaces/IAMB.sol";
import {Governable} from "./utils/Governable.sol";
import {IProofOfHumanityBridgeProxy} from "./interfaces/IProofOfHumanityBridgeProxy.sol";
import {IProofOfHumanity, IProofOfHumanityBase} from "./interfaces/ProofOfHumanityInterfaces.sol";

contract ProofOfHumanityBridgeProxy is IProofOfHumanityBase, IProofOfHumanityBridgeProxy, Governable {
    // ========== STORAGE ==========

    /// @dev ArbitraryMessageBridge contract address
    IAMB public amb;

    /// @dev Instance of the ProofOfHumanity contract
    IProofOfHumanity public proofOfHumanity;

    /// @dev ID of foreign chain
    bytes32 public foreignChainID;

    /// @dev Address of the proxy on Ethereum mainnet
    address public foreignProxy;

    /// @dev Mapping of the registered submissions
    mapping(address => bool) private submissions;

    /// @dev Mapping of whether the current chain is the primary chain on a submission
    mapping(address => bool) public isPrimaryChain;

    /// @dev Counter of submission bridged to current chain
    uint256 public bridgedCounter;

    // ========== MODIFIERS ==========

    modifier onlyForeignProxy() {
        require(msg.sender == address(amb), "Only the AMB allowed");
        require(amb.messageSender() == foreignProxy, "Only foreign proxy allowed");
        require(amb.messageSourceChainId() == foreignChainID, "Only foreign chain allowed");
        _;
    }

    // ========== CONSTRUCTOR ==========

    /**@notice Creates an arbitration proxy on the foreign chain
     * @param _amb Contract address of the ArbitraryMessageBridge
     * @param _proofOfHumanity ProofOfHumanity contract address
     */
    constructor(IAMB _amb, IProofOfHumanity _proofOfHumanity) {
        amb = _amb;
        proofOfHumanity = _proofOfHumanity;
    }

    // ========== GOVERNANCE ==========

    /**@notice Sets a new ArbitraryMessageBridge
     * @param _amb The address of the new ArbitraryMessageBridge
     */
    function changeAmb(IAMB _amb) external onlyGovernor {
        amb = _amb;
    }

    /**@notice Sets the address of the arbitration proxy on the Mainnet
     * @param _foreignProxy Address of the proxy
     * @param _foreignChainID ID of the foreign chain
     */
    function setForeignProxy(address _foreignProxy, uint256 _foreignChainID) external onlyGovernor {
        require(foreignProxy == address(0), "Foreign proxy already set");
        foreignProxy = _foreignProxy;
        foreignChainID = bytes32(_foreignChainID);
    }

    // ========== REQUESTS ==========

    /**@notice Sends an update of the submission registration status to the foreign chain
     * @param _submissionID ID of the submission to update
     */
    function updateSubmission(address _submissionID) external {
        bool _isRegistered = proofOfHumanity.isRegistered(_submissionID);
        if (!isPrimaryChain[_submissionID] && _isRegistered) isPrimaryChain[_submissionID] = true;
        require(isPrimaryChain[_submissionID], "Must update from primary chain");

        bytes4 functionSelector = IProofOfHumanityBridgeProxy(payable(0)).receiveSubmissionUpdate.selector;
        bytes memory data = abi.encodeWithSelector(functionSelector, _submissionID, _isRegistered);
        amb.requireToPassMessage(foreignProxy, data, amb.maxGasPerTx());
    }

    /**@notice Transfers the submission to the foreign chain
     */
    function transferSubmission() external {
        (, uint64 _submissionTime, , bool _hasVouched, ) = proofOfHumanity.getSubmissionInfo(msg.sender);
        require(!_hasVouched, "Must not vouch at the moment");

        submissions[msg.sender] = proofOfHumanity.isRegistered(msg.sender);
        isPrimaryChain[msg.sender] = false;
        proofOfHumanity.removeSubmissionManually(msg.sender);

        bytes4 functionSelector = IProofOfHumanityBridgeProxy(payable(0)).receiveSubmissionTransfer.selector;
        bytes memory data = abi.encodeWithSelector(functionSelector, msg.sender, _submissionTime);
        amb.requireToPassMessage(foreignProxy, data, amb.maxGasPerTx());
    }

    // ========== RECEIVES ==========

    /**@notice Receives the submission from the foreign proxy
     * @param _submissionID ID of the submission to update
     * @param _isRegistered registration status of the submission
     */
    function receiveSubmissionUpdate(address _submissionID, bool _isRegistered) external override onlyForeignProxy {
        submissions[_submissionID] = _isRegistered;
    }

    /**@notice Receives the transfered submission from the foreign proxy
     * @param _submissionID ID of the transfered submission
     * @param _submissionTime time when the submission was accepted to the list.
     */
    function receiveSubmissionTransfer(address _submissionID, uint64 _submissionTime)
        external
        override
        onlyForeignProxy
    {
        proofOfHumanity.addSubmissionManually(_submissionID, _submissionTime);
        isPrimaryChain[msg.sender] = true;
    }

    // ========== VIEWS ==========

    function isRegistered(address _submissionID) external view override returns (bool) {
        return
            proofOfHumanity.isRegistered(_submissionID) ||
            (!isPrimaryChain[_submissionID] && submissions[_submissionID]);
        // return submissions[_submissionID] || proofOfHumanity.isRegistered(_submissionID);
    }

    function submissionCounter() external view override returns (uint256) {
        return bridgedCounter + proofOfHumanity.submissionCounter();
    }
}
