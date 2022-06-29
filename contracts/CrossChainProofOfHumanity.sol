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
        uint64 expirationTime; // expirationTime at the moment of transfer
        uint160 soulID; // the unique id corresponding to the soul to transfer
        address bridgeGateway; // bridge gateway used for the transfer
        bytes32 transferHash; // unique hash of the transfer == keccak256(soulID, chainID, nonce)
    }

    struct Soul {
        bool isHomeChain; // whether current chain is home chain of the soul
        uint64 expirationTime; // expirationTime at the moment of update
        address owner; // the owner address
        uint256 lastTransferTime; // time of the last received transfer
    }

    // ========== STORAGE ==========

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @dev The address that can make governance changes to the parameters of the contract.
    address public governor;

    /// @dev Instance of the ProofOfHumanity contract
    IProofOfHumanity public proofOfHumanity;

    /// @dev Cooldown a soul has to wait for transferring again after a past received transfer.
    uint256 public transferCooldown;

    /// @dev nonce to be used as transfer hash
    bytes32 public nonce;

    /// @dev Mapping of the received transfer hashes
    mapping(bytes32 => bool) public receivedTransferHashes;

    /// @dev Whitelist of trusted bridge gateway contracts
    mapping(address => bool) public bridgeGateways;

    /// @dev Mapping of the soul IDs to corresponding soul struct
    mapping(uint160 => Soul) public souls;

    /// @dev Mapping of the humanIDs to corresponding soul IDs
    mapping(address => uint160) public humans;

    /// @dev Mapping of the soul IDs to last corresponding outgoing transfer
    mapping(uint160 => Transfer) public transfers;

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
     *  @param _transferCooldown Period a soul has to wait to transfer again after a past received transfer.
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

    /** @dev Change the cooldown a soul has to wait for transferring again after a past received transfer.
     *  @param _transferCooldown The new duration the soul has to wait has to wait.
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

    /** @notice Sends an update of the soul status to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     *  @param _soulId Id of the soul to update
     */
    function updateSoul(address _bridgeGateway, uint160 _soulId) external allowedGateway(_bridgeGateway) {
        (, , , uint64 expirationTime, address owner, ) = proofOfHumanity.getSoulInfo(_soulId);
        bool soulClaimed = proofOfHumanity.isSoulClaimed(_soulId);

        Soul storage soul = souls[_soulId];
        require(soul.isHomeChain || soulClaimed, "Must update from home chain");
        soul.isHomeChain = true;

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeCall(this.receiveUpdate, (owner, _soulId, expirationTime, soulClaimed))
        );
    }

    /** @notice Execute transfering the soul to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     */
    function transferSoul(address _bridgeGateway) external allowedGateway(_bridgeGateway) {
        // This function requires soul to be active, status None and human not vouching at the moment
        (uint64 expirationTime, uint160 soulID) = proofOfHumanity.revokeSoulManually(msg.sender);

        Soul storage soul = souls[soulID];
        require(block.timestamp > soul.lastTransferTime + transferCooldown, "Can't transfer yet");

        soul.expirationTime = expirationTime;
        soul.owner = msg.sender;
        soul.isHomeChain = false;

        humans[msg.sender] = soulID;

        Transfer storage transfer = transfers[soulID];
        nonce = keccak256(abi.encodePacked(soulID, block.chainid, nonce));
        transfer.transferHash = nonce;
        transfer.expirationTime = expirationTime;
        transfer.soulID = soulID;
        transfer.bridgeGateway = _bridgeGateway;

        IBridgeGateway(transfer.bridgeGateway).sendMessage(
            abi.encodeCall(this.receiveTransfer, (msg.sender, soulID, expirationTime, nonce))
        );
    }

    /** @notice Retry a failed transfer
     *  @param _soulId ID of the soul to retry transfer for
     */
    function retryFailedTransfer(uint160 _soulId) external {
        (, , , uint64 expirationTime, , ) = proofOfHumanity.getSoulInfo(_soulId);

        Soul memory soul = souls[_soulId];
        Transfer memory transfer = transfers[_soulId];
        require(bridgeGateways[transfer.bridgeGateway], "Bridge gateway not supported");
        require(expirationTime == transfer.expirationTime, "Soul time mismatch");

        IBridgeGateway(transfer.bridgeGateway).sendMessage(
            abi.encodeCall(
                this.receiveTransfer,
                (soul.owner, transfer.soulID, transfer.expirationTime, transfer.transferHash)
            )
        );
    }

    // ========== RECEIVES ==========

    /** @notice Receives the soul from the foreign proxy
     *  @param _humanID ID of the human corresponding to the soul
     *  @param _soulId ID of the soul to update
     *  @param _expirationTime time when the soul was last claimed
     *  @param _soulId unique ID of the soul
     */
    function receiveUpdate(
        address _humanID,
        uint160 _soulId,
        uint64 _expirationTime,
        bool _isActive
    ) external override allowedGateway(msg.sender) {
        Soul storage soul = souls[_soulId];

        // Clean human soulID for past owner
        delete humans[soul.owner];

        if (_isActive) {
            humans[_humanID] = _soulId;
            soul.owner = _humanID;
        } else delete soul.owner;

        soul.expirationTime = _expirationTime;
        soul.isHomeChain = false;

        emit UpdateReceived(_humanID, _soulId, _expirationTime);
    }

    /** @notice Receives the transfered soul from the foreign proxy
     *  @param _humanID ID of the human corresponding to the soul
     *  @param _soulId ID of the soul
     *  @param _expirationTime time when the soul was last claimed
     *  @param _transferHash hash of the transfer.
     */
    function receiveTransfer(
        address _humanID,
        uint160 _soulId,
        uint64 _expirationTime,
        bytes32 _transferHash
    ) external override allowedGateway(msg.sender) {
        require(!receivedTransferHashes[_transferHash]);
        // Requires no status or phase for the soul and human respectively
        bool success = proofOfHumanity.grantSoulManually(_soulId, _humanID, _expirationTime);

        Soul storage soul = souls[_soulId];

        // Clean human soulID for past owner
        delete humans[soul.owner];

        if (success) {
            humans[_humanID] = _soulId;

            soul.owner = _humanID;
            soul.expirationTime = _expirationTime;
            soul.isHomeChain = true;
            soul.lastTransferTime = block.timestamp;
        }

        receivedTransferHashes[_transferHash] = true;

        emit TransferReceived(_humanID);
    }

    // ========== VIEWS ==========

    function isRegistered(address _humanID) external view returns (bool) {
        uint160 soulID = humans[_humanID];
        Soul memory soul = souls[soulID];

        return
            proofOfHumanity.isRegistered(_humanID) ||
            (!soul.isHomeChain && soulID != 0 && soul.owner == _humanID && soul.expirationTime > block.timestamp);
    }
}
