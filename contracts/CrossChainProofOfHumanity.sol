/** @authors: [@andreimvp]
 *  @reviewers: [@unknownunknown1*, @fnanni-0*, @hrishibhat*]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.14;

import {IBridgeGateway} from "./interfaces/IBridgeGateway.sol";
import {IProofOfHumanity} from "./interfaces/IProofOfHumanity.sol";
import {ICrossChainProofOfHumanity} from "./interfaces/ICrossChainProofOfHumanity.sol";

contract CrossChainProofOfHumanity is ICrossChainProofOfHumanity {
    // ========== STRUCTS ==========

    struct Transfer {
        uint64 submissionTime; // submissionTime at the moment of transfer
        uint160 qid; // the unique id corresponding to the submission to transfer
        address bridgeGateway; // bridge gateway used for the transfer
        bytes32 transferHash; // unique hash of the transfer == keccak256(submissionID, chainID, nonce)
    }

    struct Submission {
        bool isPrimaryChain; // whether current chain is primary chain of the submission
        uint64 submissionTime; // submissionTime at the moment of update
        uint160 qid; // the unique id corresponding to the submission
        uint256 lastTransferTime; // time of the last received transfer
        Transfer outgoing; // last outgoing transfer to a foreign chain
    }

    // ========== STORAGE ==========

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @dev The address that can make governance changes to the parameters of the contract.
    address public governor;

    /// @dev Instance of the ProofOfHumanity contract
    IProofOfHumanity public proofOfHumanity;

    /// @dev Cooldown a submission has to wait for transferring again after a past received transfer.
    uint256 public transferCooldown;

    /// @dev nonce to be used as transfer hash
    bytes32 public nonce;

    /// @dev Mapping of the received transfer hashes
    mapping(bytes32 => bool) public receivedTransferHashes;

    /// @dev Whitelist of trusted bridge gateway contracts
    mapping(address => bool) public bridgeGateways;

    /// @dev Mapping of the registered submissions
    mapping(address => Submission) public submissions;

    // ========== EVENTS ==========

    event GatewayUpdated(address indexed _bridgeGateway, bool _active);

    // ========== MODIFIERS ==========

    modifier initializer() {
        require(!initialized);
        initialized = true;
        _;
    }

    modifier onlyGovernor() {
        require(msg.sender == governor);
        _;
    }

    modifier allowedGateway(address _bridgeGateway) {
        require(bridgeGateways[_bridgeGateway]);
        _;
    }

    // ========== CONSTRUCTOR ==========

    /** @notice Constructor
     *  @param _proofOfHumanity ProofOfHumanity contract address
     *  @param _transferCooldown Period a submission has to wait to transfer again after a past received transfer.
     */
    function initialize(IProofOfHumanity _proofOfHumanity, uint256 _transferCooldown) public initializer {
        governor = msg.sender;
        proofOfHumanity = _proofOfHumanity;
        transferCooldown = _transferCooldown;
    }

    // ========== GOVERNANCE ==========

    /** @dev Change the governor of the contract.
     *  @param _governor The address of the new governor.
     */
    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
    }

    /** @dev Change the Proof of Humanity instance.
     *  @param _proofOfHumanity The address of the new PoH instance.
     */
    function changeProofOfHumanity(IProofOfHumanity _proofOfHumanity) external onlyGovernor {
        proofOfHumanity = _proofOfHumanity;
    }

    /** @dev Change the cooldown a submission has to wait for transferring again after a past received transfer.
     *  @param _transferCooldown The new duration the submission has to wait has to wait.
     */
    function setTransferCooldown(uint256 _transferCooldown) external onlyGovernor {
        transferCooldown = _transferCooldown;
    }

    /** @notice Adds bridge gateway contract address to whitelist
     *  @param _bridgeGateway the address of the new bridge gateway contract
     *  @param _remove whether to add/remove the gateway
     */
    function setBridgeGateway(address _bridgeGateway, bool _remove) external onlyGovernor {
        if (_remove) require(bridgeGateways[_bridgeGateway]);
        else require(!bridgeGateways[_bridgeGateway]);

        bridgeGateways[_bridgeGateway] = !_remove;
        emit GatewayUpdated(_bridgeGateway, !_remove);
    }

    // ========== REQUESTS ==========

    /** @notice Sends an update of the submission registration status to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     *  @param _submissionID ID of the submission to update
     */
    function updateSubmission(address _bridgeGateway, address _submissionID) external allowedGateway(_bridgeGateway) {
        (, , uint64 submissionTime, uint160 qid, , ) = proofOfHumanity.getSubmissionInfo(_submissionID);
        bool _isRegistered = proofOfHumanity.isRegistered(_submissionID);
        Submission storage submission = submissions[_submissionID];

        require(submission.isPrimaryChain || _isRegistered, "Must update from primary chain");
        submission.isPrimaryChain = true;

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeCall(this.receiveUpdate, (_submissionID, _isRegistered ? qid : 0, submissionTime))
        );
    }

    /** @notice Execute transfering the submission to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     */
    function transferSubmission(address _bridgeGateway) external allowedGateway(_bridgeGateway) {
        (, , uint64 submissionTime, uint160 qid, , ) = proofOfHumanity.getSubmissionInfo(msg.sender);

        // This function requires submission to be registered, status None and not vouching atm
        proofOfHumanity.revokeHumanityManually(msg.sender);

        Submission storage submission = submissions[msg.sender];
        require(block.timestamp > submission.lastTransferTime + transferCooldown, "Can't transfer yet");

        submission.submissionTime = submissionTime;
        submission.qid = qid;
        submission.isPrimaryChain = false;

        Transfer storage transfer = submission.outgoing;

        nonce = keccak256(abi.encodePacked(msg.sender, block.chainid, nonce));
        transfer.transferHash = nonce;
        transfer.submissionTime = submissionTime;
        transfer.qid = qid;
        transfer.bridgeGateway = _bridgeGateway;

        IBridgeGateway(transfer.bridgeGateway).sendMessage(
            abi.encodeCall(this.receiveTransfer, (msg.sender, qid, submissionTime, nonce))
        );
    }

    /** @notice Retry a failed transfer
     *  @param _submissionID ID of the submission to retry transfer for
     */
    function retryFailedTransfer(address _submissionID) external {
        (, , uint64 submissionTime, , , ) = proofOfHumanity.getSubmissionInfo(_submissionID);

        Transfer memory transfer = submissions[_submissionID].outgoing;
        require(bridgeGateways[transfer.bridgeGateway], "Bridge gateway not supported");
        require(submissionTime == transfer.submissionTime, "Submission time mismatch");

        IBridgeGateway(transfer.bridgeGateway).sendMessage(
            abi.encodeCall(
                this.receiveTransfer,
                (_submissionID, transfer.qid, transfer.submissionTime, transfer.transferHash)
            )
        );
    }

    // ========== RECEIVES ==========

    /** @notice Receives the submission from the foreign proxy
     *  @param _submissionID ID of the submission to update
     *  @param _submissionTime time when the submission was last accepted to the list.
     *  @param _qid unique ID of the submission
     */
    function receiveUpdate(
        address _submissionID,
        uint160 _qid,
        uint64 _submissionTime
    ) external override allowedGateway(msg.sender) {
        Submission storage submission = submissions[_submissionID];
        submission.qid = _qid;
        submission.submissionTime = _submissionTime;
        submission.isPrimaryChain = false;
        emit UpdateReceived(_submissionID, _qid, _submissionTime);
    }

    /** @notice Receives the transfered submission from the foreign proxy
     *  @param _qid unique ID of the submission
     *  @param _submissionID ID of the transfered submission
     *  @param _submissionTime time when the submission was last accepted to the list.
     *  @param _transferHash hash of the transfer.
     */
    function receiveTransfer(
        address _submissionID,
        uint160 _qid,
        uint64 _submissionTime,
        bytes32 _transferHash
    ) external override allowedGateway(msg.sender) {
        require(!receivedTransferHashes[_transferHash]);
        proofOfHumanity.acceptHumanityManually(_qid, _submissionID, _submissionTime);
        Submission storage submission = submissions[_submissionID];
        submission.qid = _qid;
        submission.submissionTime = _submissionTime;
        submission.isPrimaryChain = true;
        receivedTransferHashes[_transferHash] = true;
        emit TransferReceived(_submissionID);
    }

    // ========== VIEWS ==========

    function isRegistered(address _submissionID) external view returns (bool) {
        Submission memory submission = submissions[_submissionID];
        return
            proofOfHumanity.isRegistered(_submissionID) ||
            (!submission.isPrimaryChain &&
                submission.qid != 0 &&
                (block.timestamp - submission.submissionTime <= proofOfHumanity.submissionDuration()));
    }
}
