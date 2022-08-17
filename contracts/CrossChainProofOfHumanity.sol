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
        uint160 soulID; // the unique id corresponding to the soul to transfer
        uint64 soulExpirationTime; // expirationTime at the moment of transfer
        address foreignProxy;
        uint64 initiationTime;
        bytes32 transferHash; // unique hash of the transfer == keccak256(soulID, chainID, nonce)
    }

    struct CrossChainSoul {
        bool isHomeChain; // whether current chain is home chain of the soul
        uint40 expirationTime; // expirationTime at the moment of update
        address owner; // the owner address
        uint40 lastTransferTime; // time of the last received transfer
    }

    struct GatewayInfo {
        address foreignProxy;
        bool approved;
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

    /// @dev Mapping of the received transfer hashes
    mapping(bytes32 => bool) public receivedTransferHashes;

    /// @dev Whitelist of trusted bridge gateway contracts
    mapping(address => GatewayInfo) public bridgeGateways;

    /// @dev Mapping of the soul IDs to corresponding soul struct
    mapping(uint160 => CrossChainSoul) public souls;

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
        require(bridgeGateways[_bridgeGateway].approved);
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

    function addBridgeGateway(address _bridgeGateway, address foreignProxy) external onlyGovernor {
        require(_bridgeGateway != address(0));
        require(!bridgeGateways[_bridgeGateway].approved);
        bridgeGateways[_bridgeGateway] = GatewayInfo(foreignProxy, true);
        emit GatewayUpdated(_bridgeGateway, true);
    }

    function removeBridgeGateway(address _bridgeGateway) external onlyGovernor {
        require(bridgeGateways[_bridgeGateway].approved);
        delete bridgeGateways[_bridgeGateway];
        emit GatewayUpdated(_bridgeGateway, false);
    }

    // ========== REQUESTS ==========

    /** @notice Sends an update of the soul status to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     *  @param _soulId Id of the soul to update
     */
    function updateSoul(address _bridgeGateway, uint160 _soulId) external allowedGateway(_bridgeGateway) {
        (, , , uint64 expirationTime, address owner, ) = proofOfHumanity.getSoulInfo(_soulId);
        bool soulClaimed = proofOfHumanity.isSoulClaimed(_soulId);

        CrossChainSoul storage soul = souls[_soulId];
        require(soul.isHomeChain || soulClaimed, "Must update from home chain");
        soul.isHomeChain = true;

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(
                ICrossChainProofOfHumanity.receiveUpdate.selector,
                owner,
                _soulId,
                expirationTime,
                soulClaimed
            )
        );
    }

    /** @notice Execute transfering the soul to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     */
    function transferSoul(address _bridgeGateway) external allowedGateway(_bridgeGateway) {
        // This function requires soul to be active, status None and human not vouching at the moment
        (uint64 expirationTime, uint160 soulID) = proofOfHumanity.revokeSoulManually(msg.sender);

        CrossChainSoul storage soul = souls[soulID];
        require(block.timestamp > soul.lastTransferTime + transferCooldown, "Can't transfer yet");

        soul.expirationTime = uint40(expirationTime);
        soul.owner = msg.sender;
        soul.isHomeChain = false;

        humans[msg.sender] = soulID;

        Transfer storage transfer = transfers[soulID];
        transfer.transferHash = keccak256(
            abi.encodePacked(soulID, block.timestamp, address(this), bridgeGateways[_bridgeGateway].foreignProxy)
        );
        transfer.soulID = soulID;
        transfer.soulExpirationTime = expirationTime;
        transfer.initiationTime = uint64(block.timestamp);
        transfer.foreignProxy = bridgeGateways[_bridgeGateway].foreignProxy;

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(
                ICrossChainProofOfHumanity.receiveTransfer.selector,
                msg.sender,
                soulID,
                expirationTime,
                transfer.transferHash
            )
        );
    }

    /** @notice Retry a failed transfer
     *  @param _soulId ID of the soul to retry transfer for
     */
    function retryFailedTransfer(uint160 _soulId, address _bridgeGateway) external allowedGateway(_bridgeGateway) {
        (, , , uint64 expirationTime, , ) = proofOfHumanity.getSoulInfo(_soulId);

        CrossChainSoul memory soul = souls[_soulId];
        Transfer memory transfer = transfers[_soulId];
        require(bridgeGateways[_bridgeGateway].approved, "Bridge gateway not supported");
        require(expirationTime == transfer.soulExpirationTime, "Soul time mismatch");

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(
                ICrossChainProofOfHumanity.receiveTransfer.selector,
                soul.owner,
                transfer.soulID,
                transfer.soulExpirationTime,
                transfer.transferHash
            )
        );
    }

    function revertTransfer(
        uint160 _soulID,
        uint64 _initiationTime,
        address _bridgeGateway
    ) external allowedGateway(_bridgeGateway) {
        bytes32 revertedTransferHash = keccak256(
            abi.encodePacked(_soulID, _initiationTime, bridgeGateways[_bridgeGateway].foreignProxy, address(this))
        );

        require(!receivedTransferHashes[revertedTransferHash]);

        receivedTransferHashes[revertedTransferHash] = true;

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(
                ICrossChainProofOfHumanity.receiveTransferReversion.selector,
                _soulID,
                _initiationTime
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
        CrossChainSoul storage soul = souls[_soulId];

        // Clean human soulID for past owner
        delete humans[soul.owner];

        if (_isActive) {
            humans[_humanID] = _soulId;
            soul.owner = _humanID;
        } else delete soul.owner;

        soul.expirationTime = uint40(_expirationTime);
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

        CrossChainSoul storage soul = souls[_soulId];

        // Clean human soulID for past owner
        delete humans[soul.owner];

        if (success) {
            humans[_humanID] = _soulId;

            soul.owner = _humanID;
            soul.expirationTime = uint40(_expirationTime);
            soul.isHomeChain = true;
            soul.lastTransferTime = uint40(block.timestamp);
        }

        receivedTransferHashes[_transferHash] = true;

        emit TransferReceived(_humanID);
    }

    function receiveTransferReversion(uint160 _soulID, uint64 _initiationTime)
        external
        override
        allowedGateway(msg.sender)
    {
        Transfer memory transfer = transfers[_soulID];
        bytes32 revertedTransferHash = keccak256(
            abi.encodePacked(_soulID, _initiationTime, address(this), bridgeGateways[msg.sender].foreignProxy)
        );

        require(transfer.transferHash == revertedTransferHash);
        require(transfer.soulExpirationTime > block.timestamp);

        proofOfHumanity.grantSoulManually(_soulID, souls[_soulID].owner, transfer.soulExpirationTime);
    }

    // ========== VIEWS ==========

    function isRegistered(address _humanID) external view returns (bool) {
        uint160 soulID = humans[_humanID];
        CrossChainSoul memory soul = souls[soulID];

        return
            proofOfHumanity.isRegistered(_humanID) ||
            (!soul.isHomeChain && soulID != 0 && soul.owner == _humanID && soul.expirationTime > block.timestamp);
    }
}
