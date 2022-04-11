/** @authors: [@andreimvp]
 *  @reviewers: [@unknownunknown1*, @fnanni-0, @hrishibhat]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Governable} from "./utils/Governable.sol";
import {IBridgeGateway} from "./interfaces/IBridgeGateway.sol";
import {IProofOfHumanity} from "./interfaces/ProofOfHumanityInterfaces.sol";
import {ICrossChainProofOfHumanity} from "./interfaces/ICrossChainProofOfHumanity.sol";

error CCPOH_UnsupportedGateway();
error CCPOH_AlreadyUnsupported();
error CCPOH_AlreadySupported();
error CCPOH_OnlyFromPrimaryChain();
error CCPOH_MustNotVouchAtTheMoment();
error CCPOH_WrongStatus();
error CCPOH_SubmissionTimeMismatch();
error CCPOH_AlreadyTransferred();

contract CrossChainProofOfHumanity is ICrossChainProofOfHumanity, Governable, UUPSUpgradeable {
    // ========== STRUCTS ==========

    struct Transfer {
        uint64 submissionTime; // submissionTime at the moment of transfer
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

    /// @dev Instance of the ProofOfHumanity contract
    IProofOfHumanity public proofOfHumanity;

    /// @dev Mapping of the registered submissions
    mapping(address => Submission) public submissions;

    /// @dev nonce to be used as transfer hash
    bytes32 public nonce;

    /// @dev Mapping of the received transfer hashes
    mapping(bytes32 => bool) public receivedTransferHashes;

    /// @dev Whitelist of trusted bridge gateway contracts
    mapping(address => bool) public bridgeGateways;

    // ========== EVENTS ==========

    event GatewayUpdated(address indexed _bridgeGateway, bool _active);

    // ========== MODIFIERS ==========

    modifier onlyBridgeGateway(address _bridgeGateway) {
        if (!bridgeGateways[_bridgeGateway]) revert CCPOH_UnsupportedGateway();
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

    /** @notice Adds bridge gateway contract address to whitelist
     *  @param _bridgeGateway the address of the new bridge gateway contract
     *  @param _remove whether to add/remove the gateway
     */
    function setBridgeGateway(address _bridgeGateway, bool _remove) external onlyGovernor {
        if (_remove) {
            if (!bridgeGateways[_bridgeGateway]) revert CCPOH_AlreadyUnsupported();
        } else if (bridgeGateways[_bridgeGateway]) revert CCPOH_AlreadySupported();

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
        (, uint64 submissionTime, , , ) = proofOfHumanity.getSubmissionInfo(_submissionID);
        bool _isRegistered = proofOfHumanity.isRegistered(_submissionID);
        Submission storage submission = submissions[_submissionID];
        if (!submission.isPrimaryChain) {
            if (_isRegistered) submission.isPrimaryChain = true;
            else revert CCPOH_OnlyFromPrimaryChain();
        }

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeCall(this.receiveSubmissionUpdate, (_submissionID, submissionTime, _isRegistered))
        );
    }

    /** @notice Transfers the submission to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     */
    function transferSubmission(address _bridgeGateway) external onlyBridgeGateway(_bridgeGateway) {
        (, uint64 submissionTime, , bool hasVouched, ) = proofOfHumanity.getSubmissionInfo(msg.sender);
        if (hasVouched) revert CCPOH_MustNotVouchAtTheMoment();
        if (!proofOfHumanity.isRegistered(msg.sender)) revert CCPOH_WrongStatus();

        proofOfHumanity.removeSubmissionManually(msg.sender);

        Submission storage submission = submissions[msg.sender];
        _updateSubmission(submission, true, submissionTime, false);

        nonce = keccak256(abi.encodePacked(msg.sender, block.chainid, nonce));
        submission.outgoing = Transfer({
            submissionTime: submissionTime,
            bridgeGateway: _bridgeGateway,
            transferHash: nonce
        });

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeCall(this.receiveSubmissionTransfer, (msg.sender, submissionTime, nonce))
        );
    }

    /** @notice Retry a failed transfer
     *  @param _submissionID ID of the submission to retry transfer for
     */
    function retryFailedTransfer(address _submissionID) external {
        (Status status, uint64 submissionTime, bool registered, , ) = proofOfHumanity.getSubmissionInfo(_submissionID);
        if (registered || status != Status.None) revert CCPOH_WrongStatus();

        Transfer memory transfer = submissions[msg.sender].outgoing;
        if (!bridgeGateways[transfer.bridgeGateway]) revert CCPOH_UnsupportedGateway();
        if (submissionTime != transfer.submissionTime) revert CCPOH_SubmissionTimeMismatch();

        IBridgeGateway(transfer.bridgeGateway).sendMessage(
            abi.encodeCall(
                this.receiveSubmissionTransfer,
                (_submissionID, transfer.submissionTime, transfer.transferHash)
            )
        );
    }

    // ========== RECEIVES ==========

    /** @notice Receives the submission from the foreign proxy
     *  @param _submissionID ID of the submission to update
     *  @param _submissionTime time when the submission was last accepted to the list.
     *  @param _isRegistered registration status of the submission
     */
    function receiveSubmissionUpdate(
        address _submissionID,
        uint64 _submissionTime,
        bool _isRegistered
    ) external override onlyBridgeGateway(msg.sender) {
        _updateSubmission(submissions[_submissionID], _isRegistered, _submissionTime, false);
        emit SubmissionUpdated(_submissionID, _submissionTime, _isRegistered);
    }

    /** @notice Receives the transfered submission from the foreign proxy
     *  @param _submissionID ID of the transfered submission
     *  @param _submissionTime time when the submission was last accepted to the list.
     *  @param _transferHash hash of the transfer.
     */
    function receiveSubmissionTransfer(
        address _submissionID,
        uint64 _submissionTime,
        bytes32 _transferHash
    ) external override onlyBridgeGateway(msg.sender) {
        if (receivedTransferHashes[_transferHash]) revert CCPOH_AlreadyTransferred();
        receivedTransferHashes[_transferHash] = true;

        proofOfHumanity.addSubmissionManually(_submissionID, _submissionTime);
        _updateSubmission(submissions[_submissionID], true, _submissionTime, true);
        emit SubmissionTransfered(_submissionID);
    }

    // ========== INTERNAL ==========

    /** @notice Updates the submission attributes
     *  @param _submission the submission to update
     *  @param _isRegistered registration status of the submission
     *  @param _submissionTime time when the submission was last accepted to the list
     *  @param _isPrimaryChain whether current chain is primary chain of the submission
     */
    function _updateSubmission(
        Submission storage _submission,
        bool _isRegistered,
        uint64 _submissionTime,
        bool _isPrimaryChain
    ) internal {
        _submission.registered = _isRegistered;
        _submission.submissionTime = _submissionTime;
        _submission.isPrimaryChain = _isPrimaryChain;
    }

    // ========== VIEWS ==========

    function isRegistered(address _submissionID) external view override returns (bool) {
        Submission memory submission = submissions[_submissionID];
        return
            proofOfHumanity.isRegistered(_submissionID) ||
            (!submission.isPrimaryChain &&
                submission.registered &&
                (block.timestamp - submission.submissionTime <= proofOfHumanity.submissionDuration()));
    }
}
