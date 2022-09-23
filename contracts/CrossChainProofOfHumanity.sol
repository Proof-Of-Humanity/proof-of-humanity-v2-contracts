/** @authors: [@andreimvp]
 *  @reviewers: [@unknownunknown1*, @fnanni-0*, @hrishibhat*]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.16;

import {IBridgeGateway} from "./interfaces/IBridgeGateway.sol";
import {IProofOfHumanity} from "./interfaces/IProofOfHumanity.sol";
import {ICrossChainProofOfHumanity} from "./interfaces/ICrossChainProofOfHumanity.sol";

contract CrossChainProofOfHumanity is ICrossChainProofOfHumanity {
    // ========== STRUCTS ==========

    struct Transfer {
        bytes20 humanityId; // the unique id corresponding to the humanity to transfer
        uint64 humanityExpirationTime; // expirationTime at the moment of transfer
        bytes32 transferHash; // unique hash of the transfer == keccak256(humanityId, chainID, nonce)
        address foreignProxy; // address of the foreign proxy
        uint64 initiationTime; // time the transfer was initiated
    }

    struct CrossChainHumanity {
        bool isHomeChain; // whether current chain is home chain of the humanity
        uint40 expirationTime; // expirationTime at the moment of update
        address owner; // the owner address
        uint40 lastTransferTime; // time of the last received transfer
    }

    struct GatewayInfo {
        address foreignProxy; // address of the foreign proxy
        bool approved; // whether the gateway is approved
    }

    // ========== STORAGE ==========

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @dev The address that can make governance changes to the parameters of the contract.
    address public governor;

    /// @dev Instance of the ProofOfHumanity contract
    IProofOfHumanity public proofOfHumanity;

    /// @dev Cooldown a humanity has to wait for transferring again after a past received transfer.
    uint256 public transferCooldown;

    /// @dev Mapping of the received transfer hashes
    mapping(bytes32 => bool) public receivedTransferHashes;

    /// @dev Whitelist of trusted bridge gateway contracts
    mapping(address => GatewayInfo) public bridgeGateways;

    /// @dev Mapping of the humanity IDs to corresponding humanity struct
    mapping(bytes20 => CrossChainHumanity) public humanityMapping;

    /// @dev Mapping of addresses to corresponding humanity IDs
    mapping(address => bytes20) public humans;

    /// @dev Mapping of the humanity IDs to last corresponding outgoing transfer
    mapping(bytes20 => Transfer) public transfers;

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
     *  @param _transferCooldown Period a humanity has to wait to transfer again after a past received transfer.
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

    /** @dev Change the cooldown a humanity has to wait for transferring again after a past received transfer.
     *  @param _transferCooldown The new duration the humanity has to wait has to wait.
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

    /** @notice Sends an update of the humanity status to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     *  @param _humanityId Id of the humanity to update
     */
    function updateHumanity(address _bridgeGateway, bytes20 _humanityId) external allowedGateway(_bridgeGateway) {
        (, , , uint64 expirationTime, address owner, ) = proofOfHumanity.getHumanityInfo(_humanityId);
        bool humanityClaimed = proofOfHumanity.isClaimed(_humanityId);

        CrossChainHumanity storage humanity = humanityMapping[_humanityId];
        require(humanity.isHomeChain || humanityClaimed, "Must update from home chain");
        humanity.isHomeChain = true;

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(
                ICrossChainProofOfHumanity.receiveUpdate.selector,
                owner,
                _humanityId,
                expirationTime,
                humanityClaimed
            )
        );
    }

    /** @notice Execute transfering the humanity to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     */
    function transferHumanity(address _bridgeGateway) external allowedGateway(_bridgeGateway) {
        // This function requires humanity to be active, status None and human not vouching at the moment
        (uint64 expirationTime, bytes20 humanityId) = proofOfHumanity.revokeManually(msg.sender);

        CrossChainHumanity storage humanity = humanityMapping[humanityId];
        require(block.timestamp > humanity.lastTransferTime + transferCooldown, "Can't transfer yet");

        humanity.expirationTime = uint40(expirationTime);
        humanity.owner = msg.sender;
        humanity.isHomeChain = false;

        humans[msg.sender] = humanityId;

        Transfer storage transfer = transfers[humanityId];
        transfer.transferHash = keccak256(
            abi.encodePacked(humanityId, block.timestamp, address(this), bridgeGateways[_bridgeGateway].foreignProxy)
        );
        transfer.humanityId = humanityId;
        transfer.humanityExpirationTime = expirationTime;
        transfer.initiationTime = uint64(block.timestamp);
        transfer.foreignProxy = bridgeGateways[_bridgeGateway].foreignProxy;

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(
                ICrossChainProofOfHumanity.receiveTransfer.selector,
                msg.sender,
                humanityId,
                expirationTime,
                transfer.transferHash
            )
        );
    }

    /** @notice Retry a failed transfer
     *  @param _humanityId ID of the humanity to retry transfer for
     *  @param _bridgeGateway address of the bridge gateway to use
     */
    function retryFailedTransfer(bytes20 _humanityId, address _bridgeGateway) external allowedGateway(_bridgeGateway) {
        (, , , uint64 expirationTime, , ) = proofOfHumanity.getHumanityInfo(_humanityId);

        CrossChainHumanity memory humanity = humanityMapping[_humanityId];
        Transfer memory transfer = transfers[_humanityId];
        require(bridgeGateways[_bridgeGateway].approved, "Bridge gateway not supported");
        require(expirationTime == transfer.humanityExpirationTime, "Humanity time mismatch");

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(
                ICrossChainProofOfHumanity.receiveTransfer.selector,
                humanity.owner,
                transfer.humanityId,
                transfer.humanityExpirationTime,
                transfer.transferHash
            )
        );
    }

    // /** @notice Revert a (supposedly) failed transfer
    //  *  @param _humanityId ID of the humanity to revert transfer of
    //  *  @param _initiationTime Timestamp when the transfer was initiatiated
    //  *  @param _bridgeGateway address of the bridge gateway to use
    //  */
    // function revertTransfer(
    //     bytes20 _humanityId,
    //     uint64 _initiationTime,
    //     address _bridgeGateway
    // ) external allowedGateway(_bridgeGateway) {
    //     bytes32 revertedTransferHash = keccak256(
    //         abi.encodePacked(_humanityId, _initiationTime, bridgeGateways[_bridgeGateway].foreignProxy, address(this))
    //     );

    //     require(!receivedTransferHashes[revertedTransferHash]);

    //     receivedTransferHashes[revertedTransferHash] = true;

    //     IBridgeGateway(_bridgeGateway).sendMessage(
    //         abi.encodeWithSelector(
    //             ICrossChainProofOfHumanity.receiveTransferReversion.selector,
    //             _humanityId,
    //             _initiationTime,
    //             msg.sender
    //         )
    //     );
    // }

    // ========== RECEIVES ==========

    /** @notice Receives the humanity from the foreign proxy
     *  @param _owner ID of the human corresponding to the humanity
     *  @param _humanityId ID of the humanity to update
     *  @param _expirationTime time when the humanity was last claimed
     *  @param _humanityId unique ID of the humanity
     */
    function receiveUpdate(
        address _owner,
        bytes20 _humanityId,
        uint64 _expirationTime,
        bool _isActive
    ) external override allowedGateway(msg.sender) {
        CrossChainHumanity storage humanity = humanityMapping[_humanityId];

        // Clean human humanityId for past owner
        delete humans[humanity.owner];

        if (_isActive) {
            humans[_owner] = _humanityId;
            humanity.owner = _owner;
        } else delete humanity.owner;

        humanity.expirationTime = uint40(_expirationTime);
        humanity.isHomeChain = false;

        emit UpdateReceived(_owner, _humanityId, _expirationTime);
    }

    /** @notice Receives the transfered humanity from the foreign proxy
     *  @param _owner ID of the human corresponding to the humanity
     *  @param _humanityId ID of the humanity
     *  @param _expirationTime time when the humanity was last claimed
     *  @param _transferHash hash of the transfer.
     */
    function receiveTransfer(
        address _owner,
        bytes20 _humanityId,
        uint64 _expirationTime,
        bytes32 _transferHash
    ) external override allowedGateway(msg.sender) {
        require(!receivedTransferHashes[_transferHash]);
        // Requires no status or phase for the humanity and human respectively
        bool success = proofOfHumanity.grantManually(_humanityId, _owner, _expirationTime);

        CrossChainHumanity storage humanity = humanityMapping[_humanityId];

        // Clean human humanityId for past owner
        delete humans[humanity.owner];

        if (success) {
            humans[_owner] = _humanityId;

            humanity.owner = _owner;
            humanity.expirationTime = uint40(_expirationTime);
            humanity.isHomeChain = true;
            humanity.lastTransferTime = uint40(block.timestamp);
        }

        receivedTransferHashes[_transferHash] = true;

        emit TransferReceived(_owner);
    }

    // /** @notice Receives a transfer reversion from the foreign proxy
    //  *  @param _humanityId ID of the humanity to revert transfer of
    //  *  @param _initiationTime Timestamp when the transfer was initiatiated
    //  *  @param _initiator Initiator of the reversion (should be owner of humanity)
    //  */
    // function receiveTransferReversion(
    //     bytes20 _humanityId,
    //     uint64 _initiationTime,
    //     address _initiator
    // ) external override allowedGateway(msg.sender) {
    //     Transfer memory transfer = transfers[_humanityId];
    //     bytes32 revertedTransferHash = keccak256(
    //         abi.encodePacked(_humanityId, _initiationTime, address(this), bridgeGateways[msg.sender].foreignProxy)
    //     );

    //     require(transfer.transferHash == revertedTransferHash);
    //     require(transfer.humanityExpirationTime > block.timestamp);
    //     require(humanityMapping[_humanityId].owner == _initiator);

    //     proofOfHumanity.grantManually(_humanityId, humanityMapping[_humanityId].owner, transfer.humanityExpirationTime);
    // }

    // ========== VIEWS ==========

    function isClaimed(bytes20 _humanityId) external view returns (bool) {
        if (proofOfHumanity.isClaimed(_humanityId)) return true;

        CrossChainHumanity memory humanity = humanityMapping[_humanityId];
        return humanity.owner != address(0) && humanity.expirationTime >= block.timestamp;
    }

    function isHuman(address _owner) external view returns (bool) {
        bytes20 humanityId = humans[_owner];
        CrossChainHumanity memory humanity = humanityMapping[humanityId];

        return
            proofOfHumanity.isHuman(_owner) ||
            (!humanity.isHomeChain &&
                humanityId != 0 &&
                humanity.owner == _owner &&
                humanity.expirationTime > block.timestamp);
    }
}
