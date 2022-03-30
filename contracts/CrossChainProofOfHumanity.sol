// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Governable} from "./utils/Governable.sol";
import {IBridgeGateway} from "./interfaces/IBridgeGateway.sol";
import {IProofOfHumanity} from "./interfaces/ProofOfHumanityInterfaces.sol";
import {ICrossChainProofOfHumanity} from "./interfaces/ICrossChainProofOfHumanity.sol";

contract CrossChainProofOfHumanity is ICrossChainProofOfHumanity, Governable, UUPSUpgradeable {
    // ========== STRUCTS ==========

    struct Transfer {
        uint64 submissionTime;
        address bridgeGateway;
        bytes32 transferHash;
    }

    // ========== STORAGE ==========

    /// @dev Instance of the ProofOfHumanity contract
    IProofOfHumanity public proofOfHumanity;

    /// @dev Mapping of the registered submissions
    mapping(address => bool) public submissions;

    /// @dev Mapping of whether the current chain is the primary chain on a submission
    mapping(address => bool) public isPrimaryChain;

    /// @dev nonce to be used as transfer hash
    bytes32 public nonce;

    /// @dev Mapping of the outgoing transfer messages
    mapping(address => Transfer) public outgoingTransfers;

    /// @dev Mapping of the received transfer hashes
    mapping(bytes32 => bool) public receivedTransferHashes;

    /// @dev Whitelist of trusted bridge gateway contracts
    mapping(address => bool) public bridgeGateways;

    // ========== EVENTS ==========

    event BridgeAdded(address indexed _bridge, address indexed _foreignProxy);

    event BridgeRemoved(address indexed _bridge);

    // ========== MODIFIERS ==========

    modifier onlyBridgeGateway(address _bridgeGateway) {
        require(bridgeGateways[_bridgeGateway], "Bridge gateway not supported");
        _;
    }

    // ========== CONSTRUCTOR ==========

    /** @notice Constructor
     *  @param _proofOfHumanity ProofOfHumanity contract address
     */
    function initialize(IProofOfHumanity _proofOfHumanity) public initializer {
        governor = msg.sender;
        proofOfHumanity = _proofOfHumanity;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}

    // ========== GOVERNANCE ==========

    event GatewaysUpdated(address indexed _bridgeGateway, bool _active);

    /** @notice Adds bridge gateway contract address to whitelist
     *  @param _bridgeGateway the address of the bridge gateway contract
     */
    function addBridgeGateway(address _bridgeGateway) external onlyGovernor {
        require(!bridgeGateways[_bridgeGateway], "Bridge gateway already supported");
        bridgeGateways[_bridgeGateway] = true;
        emit GatewaysUpdated(_bridgeGateway, true);
    }

    /** @notice Removes bridge gateway contract address from whitelist
     *  @param _bridgeGateway The address of the bridge gateway contract
     */
    function removeBridgeGateway(address _bridgeGateway) external onlyGovernor onlyBridgeGateway(_bridgeGateway) {
        delete bridgeGateways[_bridgeGateway];
    }

    // ========== REQUESTS ==========

    /** @notice Sends an update of the submission registration status to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     *  @param _submissionID ID of the submission to update
     */
    function updateSubmission(address _bridgeGateway, address _submissionID)
        external
        onlyBridgeGateway(_bridgeGateway)
    {
        bool _isRegistered = proofOfHumanity.isRegistered(_submissionID);
        if (!isPrimaryChain[_submissionID] && _isRegistered) isPrimaryChain[_submissionID] = true;
        require(isPrimaryChain[_submissionID], "Must update from primary chain");

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(this.receiveSubmissionUpdate.selector, _submissionID, _isRegistered)
        );
    }

    /** @notice Transfers the submission to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     */
    function transferSubmission(address _bridgeGateway) external onlyBridgeGateway(_bridgeGateway) {
        (, uint64 submissionTime, , bool hasVouched, ) = proofOfHumanity.getSubmissionInfo(msg.sender);
        require(!hasVouched, "Must not vouch at the moment");
        require(proofOfHumanity.isRegistered(msg.sender), "Must be registered to transfer");

        submissions[msg.sender] = true;
        isPrimaryChain[msg.sender] = false;
        proofOfHumanity.removeSubmissionManually(msg.sender);

        nonce = keccak256(abi.encodePacked(msg.sender, block.chainid, nonce));
        outgoingTransfers[msg.sender] = Transfer({
            submissionTime: submissionTime,
            bridgeGateway: _bridgeGateway,
            transferHash: nonce
        });

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(this.receiveSubmissionTransfer.selector, msg.sender, submissionTime, nonce)
        );
    }

    /** @notice Retry a failed transfer
     */
    function retryFailedTransfer() external {
        (Status status, uint64 submissionTime, bool registered, , ) = proofOfHumanity.getSubmissionInfo(msg.sender);
        require(!registered && status == Status.None, "Wrong status");

        Transfer memory transfer = outgoingTransfers[msg.sender];
        require(bridgeGateways[transfer.bridgeGateway], "Bridge gateway not supported");
        require(submissionTime == transfer.submissionTime, "Submission time mismatch");

        IBridgeGateway(transfer.bridgeGateway).sendMessage(
            abi.encodeWithSelector(
                this.receiveSubmissionTransfer.selector,
                msg.sender,
                transfer.submissionTime,
                transfer.transferHash
            )
        );
    }

    // ========== RECEIVES ==========

    /** @notice Receives the submission from the foreign proxy
     *  @param _submissionID ID of the submission to update
     *  @param _isRegistered registration status of the submission
     */
    function receiveSubmissionUpdate(address _submissionID, bool _isRegistered)
        external
        override
        onlyBridgeGateway(msg.sender)
    {
        submissions[_submissionID] = _isRegistered;
        emit SubmissionUpdated(_submissionID, _isRegistered);
    }

    /** @notice Receives the transfered submission from the foreign proxy
     *  @param _submissionID ID of the transfered submission
     *  @param _submissionTime time when the submission was accepted to the list.
     *  @param _transferHash hash of the transfer.
     */
    function receiveSubmissionTransfer(
        address _submissionID,
        uint64 _submissionTime,
        bytes32 _transferHash
    ) external override onlyBridgeGateway(msg.sender) {
        require(!receivedTransferHashes[_transferHash], "Submission already transfered");
        receivedTransferHashes[_transferHash] = true;
        delete outgoingTransfers[msg.sender];

        proofOfHumanity.addSubmissionManually(_submissionID, _submissionTime);
        isPrimaryChain[msg.sender] = true;
        emit SubmissionTransfered(_submissionID);
    }

    // ========== VIEWS ==========

    function isRegistered(address _submissionID) external view override returns (bool) {
        return
            proofOfHumanity.isRegistered(_submissionID) ||
            (!isPrimaryChain[_submissionID] && submissions[_submissionID]);
    }
}
