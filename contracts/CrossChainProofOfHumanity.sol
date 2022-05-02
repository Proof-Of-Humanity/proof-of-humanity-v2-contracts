/** @authors: [@andreimvp]
 *  @reviewers: [@unknownunknown1*, @fnanni-0, @hrishibhat]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.11;

// import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IBridgeGateway} from "./interfaces/IBridgeGateway.sol";
import {IProofOfHumanity} from "./interfaces/IProofOfHumanity.sol";
import {ICrossChainProofOfHumanity} from "./interfaces/ICrossChainProofOfHumanity.sol";

// UUPSUpgradeable
contract CrossChainProofOfHumanity is ICrossChainProofOfHumanity {
    // ========== STRUCTS ==========

    struct Transfer {
        bool tried; // whether the transfer has been tried; if true, it can be retried
        uint64 blockNumber; // the block number transfer was allowed
        uint64 expiration; // when the transfer window expires
        uint64 submissionTime; // submissionTime at the moment of transfer
        uint160 qid; // the unique id correspondinf to the submission to transfer
        address bridgeGateway; // bridge gateway used for the transfer
        bytes32 transferHash; // unique hash of the transfer == keccak256(submissionID, chainID, nonce)
    }

    struct Submission {
        bool isPrimaryChain; // whether current chain is primary chain of the submission
        bool registered; // whether submission is marked as registered
        uint64 submissionTime; // submissionTime at the moment of update
        Transfer outgoing; // last outgoing transfer to a foreign chain
    }

    // ========== STORAGE ==========

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @dev The address that can make governance changes to the parameters of the contract.
    address public governor;

    /// @dev Instance of the ProofOfHumanity contract
    IProofOfHumanity public proofOfHumanity;

    /// @dev Time window in which a transfer can be initiated after allowing it.
    uint64 public transferWindowDuration = 1 hours;

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

    modifier onlyBridgeGateway(address _bridgeGateway) {
        require(bridgeGateways[_bridgeGateway]);
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

    // ========== GOVERNANCE ==========

    /** @dev Change the governor of the contract.
     *  @param _governor The address of the new governor.
     */
    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
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
    function updateSubmission(address _bridgeGateway, address _submissionID)
        external
        onlyBridgeGateway(_bridgeGateway)
    {
        (, , , uint64 submissionTime, , , ) = proofOfHumanity.getSubmissionInfo(_submissionID);
        bool _isRegistered = proofOfHumanity.isRegistered(_submissionID);
        Submission storage submission = submissions[_submissionID];
        require(submission.isPrimaryChain || _isRegistered);
        submission.isPrimaryChain = true;

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeCall(this.receiveUpdate, (_submissionID, submissionTime, _isRegistered))
        );
    }

    /** @notice Allow a transfer to be executed during the transfer window
     *  Used for frontrunning protection
     */
    function allowTransfer() external {
        Transfer storage transfer = submissions[msg.sender].outgoing;
        transfer.blockNumber = uint64(block.number);
        transfer.expiration = uint64(block.timestamp) + transferWindowDuration;
    }

    /** @notice Execute transfering the submission to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     *  @param _submissionID submission corresponding to the transfer to initiate
     */
    function executeTransfer(address _bridgeGateway, address _submissionID) external onlyBridgeGateway(_bridgeGateway) {
        Submission storage submission = submissions[_submissionID];
        Transfer storage transfer = submission.outgoing;
        require(transfer.blockNumber > uint64(block.number) && block.timestamp < transfer.expiration);

        proofOfHumanity.revokeHumanityManually(_submissionID);

        (, , , uint64 submissionTime, uint160 qid, , ) = proofOfHumanity.getSubmissionInfo(msg.sender);

        submission.registered = true;
        submission.submissionTime = submissionTime;
        submission.isPrimaryChain = false;

        nonce = keccak256(abi.encodePacked(msg.sender, block.chainid, nonce));
        transfer.transferHash = nonce;
        transfer.submissionTime = submissionTime;
        transfer.qid = qid;
        transfer.bridgeGateway = _bridgeGateway;
        transfer.tried = true;

        IBridgeGateway(transfer.bridgeGateway).sendMessage(
            abi.encodeCall(this.receiveTransfer, (qid, _submissionID, submissionTime, nonce))
        );
    }

    /** @notice Retry a failed transfer
     *  @param _submissionID ID of the submission to retry transfer for
     */
    function retryFailedTransfer(address _submissionID) external {
        (, , , uint64 submissionTime, , , ) = proofOfHumanity.getSubmissionInfo(_submissionID);

        Transfer memory transfer = submissions[msg.sender].outgoing;
        require(transfer.tried);
        require(submissionTime == transfer.submissionTime);
        require(bridgeGateways[transfer.bridgeGateway]);

        IBridgeGateway(transfer.bridgeGateway).sendMessage(
            abi.encodeCall(
                this.receiveTransfer,
                (transfer.qid, _submissionID, transfer.submissionTime, transfer.transferHash)
            )
        );
    }

    // ========== RECEIVES ==========

    /** @notice Receives the submission from the foreign proxy
     *  @param _submissionID ID of the submission to update
     *  @param _submissionTime time when the submission was last accepted to the list.
     *  @param _isRegistered registration status of the submission
     */
    function receiveUpdate(
        address _submissionID,
        uint64 _submissionTime,
        bool _isRegistered
    ) external override onlyBridgeGateway(msg.sender) {
        Submission storage submission = submissions[_submissionID];
        submission.registered = _isRegistered;
        submission.submissionTime = _submissionTime;
        submission.isPrimaryChain = false;
        emit UpdateReceived(_submissionID, _submissionTime, _isRegistered);
    }

    /** @notice Receives the transfered submission from the foreign proxy
     *  @param _qid unique ID of the submission
     *  @param _submissionID ID of the transfered submission
     *  @param _submissionTime time when the submission was last accepted to the list.
     *  @param _transferHash hash of the transfer.
     */
    function receiveTransfer(
        uint160 _qid,
        address _submissionID,
        uint64 _submissionTime,
        bytes32 _transferHash
    ) external override onlyBridgeGateway(msg.sender) {
        require(!receivedTransferHashes[_transferHash]);
        proofOfHumanity.acceptHumanityManually(_qid, _submissionID, _submissionTime);
        Submission storage submission = submissions[_submissionID];
        submission.registered = true;
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
                submission.registered &&
                (block.timestamp - submission.submissionTime <= proofOfHumanity.submissionDuration()));
    }
}
