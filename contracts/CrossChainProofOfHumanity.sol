/** @authors: [@andreimvp]
 *  @reviewers: [@unknownunknown1*, @fnanni-0*, @hrishibhat*, @divyangchauhan, @Harman-singh-waraich, @wadader]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.20;

import {IBridgeGateway} from "./bridge-gateways/IBridgeGateway.sol";
import {IProofOfHumanity} from "./interfaces/IProofOfHumanity.sol";
import {ICrossChainProofOfHumanity} from "./interfaces/ICrossChainProofOfHumanity.sol";

contract CrossChainProofOfHumanity is ICrossChainProofOfHumanity {
    // ========== STRUCTS ==========

    struct Transfer {
        bytes20 humanityId; // the unique id corresponding to the humanity to transfer
        uint40 humanityExpirationTime; // expirationTime at the moment of transfer
        bytes32 transferHash; // unique hash of the transfer == keccak256(humanityId, block.timestamp, address(this), address(foreignProxy))
        address foreignProxy; // address of the foreign proxy transfer was sent to
    }

    struct CrossChainHumanity {
        address owner; // the owner address
        uint40 expirationTime; // expirationTime at the moment of update
        uint40 lastTransferTime; // time of the last received transfer
        bool isHomeChain; // whether current chain is considered as home chain by this contract; note: actual home chain of humanity is dependent on the state of it on all blockchains
    }

    struct GatewayInfo {
        address foreignProxy; // address of the foreign proxy; used in hash in case of multiple gateways for same proxy
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
    /// @dev Used to avoid exploiting transfer functionality to evade revocation requests.
    uint256 public transferCooldown;

    /// @dev Gap for possible future versions storage layout changes.
    uint256[50] internal __gap;

    /// @dev Mapping of the received transfer hashes
    mapping(bytes32 => bool) public receivedTransferHashes;

    /// @dev Whitelist of trusted bridge gateway contracts
    mapping(address => GatewayInfo) public bridgeGateways;

    /// @dev Mapping of the humanity IDs to corresponding humanity struct
    mapping(bytes20 => CrossChainHumanity) public humanityData;

    /// @dev Mapping of addresses to corresponding humanity IDs
    mapping(address => bytes20) private accountHumanity;

    /// @dev Mapping of the humanity IDs to last corresponding outgoing transfer
    mapping(bytes20 => Transfer) public transfers;

    // ========== EVENTS ==========

    /** @dev Emitted when a bridge gateway is added via governance.
     *  @param bridgeGateway The address of the bridge gateway.
     *  @param foreignProxy The address of the foreign proxy.
     */
    event GatewayAdded(address indexed bridgeGateway, address foreignProxy);

    /** @dev Emitted when a bridge gateway is removed via governance.
     *  @param bridgeGateway The address of the bridge gateway.
     */
    event GatewayRemoved(address indexed bridgeGateway);

    /** @dev Emitted when an update is initiated for a humanity ID.
     *  @param humanityId The humanity ID.
     *  @param owner The address of the owner.
     *  @param expirationTime The expiration time of the humanity.
     *  @param claimed Indicates whether the humanity is claimed.
     *  @param gateway The address of the bridge gateway to use to relay the data.
     */
    event UpdateInitiated(
        bytes20 indexed humanityId,
        address indexed owner,
        uint40 expirationTime,
        bool claimed,
        address gateway
    );

    /** @dev Emitted when a state update is received for a humanity ID.
     *  @param humanityId The humanity ID.
     *  @param owner The address of the owner.
     *  @param expirationTime The new expiration time of the humanity.
     *  @param claimed Indicates if the humanity is claimed.
     */
    event UpdateReceived(bytes20 indexed humanityId, address indexed owner, uint40 expirationTime, bool claimed);

    /** @dev Emitted when a transfer is initiated for a humanity ID.
     *  @param humanityId The humanity ID.
     *  @param owner The address of the owner.
     *  @param expirationTime The expiration time of the humanity.
     *  @param gateway The address of the bridge gateway to use to relay the data.
     *  @param transferHash The computed hash of the transfer.
     */
    event TransferInitiated(
        bytes20 indexed humanityId,
        address indexed owner,
        uint40 expirationTime,
        address gateway,
        bytes32 transferHash
    );

    /** @dev Emitted when a transfer is received for a humanity ID.
     *  @param humanityId The humanity ID.
     *  @param owner The address of the owner.
     *  @param expirationTime The expiration time of the humanity.
     *  @param transferHash The hash of the transfer.
     */
    event TransferReceived(
        bytes20 indexed humanityId,
        address indexed owner,
        uint40 expirationTime,
        bytes32 transferHash
    );

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
     *  @param _transferCooldown The new duration the humanity has to wait for transferring again.
     */
    function setTransferCooldown(uint256 _transferCooldown) external onlyGovernor {
        transferCooldown = _transferCooldown;
    }

    /** @dev Add a bridge gateway as trusted.
     *  @param _bridgeGateway address of the gateway on current chain.
     *  @param _foreignProxy proxy messages sent through this gateway will be sent to.
     */
    function addBridgeGateway(address _bridgeGateway, address _foreignProxy) external onlyGovernor {
        require(_bridgeGateway != address(0));
        require(!bridgeGateways[_bridgeGateway].approved);

        bridgeGateways[_bridgeGateway] = GatewayInfo(_foreignProxy, true);

        emit GatewayAdded(_bridgeGateway, _foreignProxy);
    }

    /** @dev Remove a bridge gateway as trusted.
     *  @param _bridgeGateway address of the trusted gateway whose trust will be removed.
     */
    function removeBridgeGateway(address _bridgeGateway) external onlyGovernor {
        require(bridgeGateways[_bridgeGateway].approved);

        delete bridgeGateways[_bridgeGateway];

        emit GatewayRemoved(_bridgeGateway);
    }

    // ========== REQUESTS ==========

    /** @notice Sends an update of the humanity status to the foreign chain. No need to specify the receiving chain as it'd be know by the gateway
     *  @notice Communicates with receiveUpdate function of this contract's instance on the receiving chain
     *
     *  @param _bridgeGateway address of the bridge gateway to use
     *  @param _humanityId Id of the humanity to update
     */
    function updateHumanity(address _bridgeGateway, bytes20 _humanityId) external allowedGateway(_bridgeGateway) {
        (, , , uint40 expirationTime, address owner, ) = proofOfHumanity.getHumanityInfo(_humanityId);
        bool humanityClaimed = proofOfHumanity.isClaimed(_humanityId);

        CrossChainHumanity storage humanity = humanityData[_humanityId];

        require(humanity.isHomeChain || humanityClaimed, "Must update from home chain");

        // isHomeChain is set to true when humanity is claimed
        // It also keeps true value (unless overwritten) if it was set before and humanity is now expired,
        //      thus making it possible to update state of expired / unregistered humanity
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

        emit UpdateInitiated(_humanityId, owner, expirationTime, humanityClaimed, _bridgeGateway);
    }

    /** @notice Execute transfering the humanity to the foreign chain
     *  @param _bridgeGateway address of the bridge gateway to use
     */
    function transferHumanity(address _bridgeGateway) external allowedGateway(_bridgeGateway) {
        // Function will require humanity to be claimed by sender, have no pending requests and human not vouching at the time
        (bytes20 humanityId, uint40 expirationTime) = proofOfHumanity.ccDischargeHumanity(msg.sender);

        CrossChainHumanity storage humanity = humanityData[humanityId];

        require(block.timestamp > humanity.lastTransferTime + transferCooldown, "Can't transfer yet");

        // Save state to not require extra updates from receiving chain
        humanity.expirationTime = expirationTime;
        humanity.owner = msg.sender;
        humanity.isHomeChain = false;

        accountHumanity[msg.sender] = humanityId;

        Transfer storage transfer = transfers[humanityId];

        // Transfer hash must be unique, hence using timestamp in the packing among the other parameters
        bytes32 tHash = keccak256(
            abi.encodePacked(humanityId, block.timestamp, address(this), bridgeGateways[_bridgeGateway].foreignProxy)
        );

        // Store the transfer details in the struct to use in case future implementations that support transfer retrials / recoveries
        transfer.transferHash = tHash;
        transfer.humanityId = humanityId;
        transfer.humanityExpirationTime = expirationTime;
        transfer.foreignProxy = bridgeGateways[_bridgeGateway].foreignProxy;

        IBridgeGateway(_bridgeGateway).sendMessage(
            abi.encodeWithSelector(
                ICrossChainProofOfHumanity.receiveTransfer.selector,
                msg.sender,
                humanityId,
                expirationTime,
                tHash
            )
        );

        emit TransferInitiated(humanityId, msg.sender, expirationTime, _bridgeGateway, tHash);
    }

    // ========== RECEIVES ==========

    /** @notice Receives the humanity from the foreign proxy
     *  @dev Can only be called by a trusted gateway
     *  @param _owner Wallet address corresponding to the humanity
     *  @param _humanityId ID of the humanity to update
     *  @param _expirationTime Time when the humanity expires
     *  @param _isActive Whether the humanity is claimed
     */
    function receiveUpdate(
        address _owner,
        bytes20 _humanityId,
        uint40 _expirationTime,
        bool _isActive
    ) external override allowedGateway(msg.sender) {
        CrossChainHumanity storage humanity = humanityData[_humanityId];

        // Clear humanityId for past owner
        delete accountHumanity[humanity.owner];

        if (_isActive) {
            accountHumanity[_owner] = _humanityId;
            humanity.owner = _owner;
        } else delete humanity.owner;

        humanity.expirationTime = _expirationTime;

        // If it received update from another chain `isHomeChain` flag is marked as false
        //         in order to avoid bridging state update of an removed / expired humanity
        humanity.isHomeChain = false;

        emit UpdateReceived(_humanityId, _owner, _expirationTime, _isActive);
    }

    /** @notice Receives the transfered humanity from the foreign proxy
     *  @dev Can only be called by a trusted gateway
     *  @param _owner Address of the human corresponding to the humanity
     *  @param _humanityId ID of the humanity
     *  @param _expirationTime time when the humanity was last claimed
     *  @param _transferHash hash of the transfer.
     */
    function receiveTransfer(
        address _owner,
        bytes20 _humanityId,
        uint40 _expirationTime,
        bytes32 _transferHash
    ) external override allowedGateway(msg.sender) {
        // Once transfer hash is flagged as received it is not possible to receive the transfer again
        require(!receivedTransferHashes[_transferHash]);

        // If humanity is claimed on the main contract it will return false and not override the state
        // Otherwise requires _owner to not be in process of claiming a humanity
        bool success = proofOfHumanity.ccGrantHumanity(_humanityId, _owner, _expirationTime);

        CrossChainHumanity storage humanity = humanityData[_humanityId];

        // Clear human humanityId for past owner
        delete accountHumanity[humanity.owner];

        // Overriding this data in case it is outdated
        if (success) {
            accountHumanity[_owner] = _humanityId;

            humanity.owner = _owner;
            humanity.expirationTime = _expirationTime;
            humanity.isHomeChain = true;
            humanity.lastTransferTime = uint40(block.timestamp);
        }

        receivedTransferHashes[_transferHash] = true;

        emit TransferReceived(_humanityId, _owner, _expirationTime, _transferHash);
    }

    // ========== VIEWS ==========

    /** @notice Check whether humanity is claimed or not
     *  @notice First check state to return from main contract and, if not claimed there, derive from state from this contract
     *  @param _humanityId The id of the humanity to check
     *  @return Whether humanity is claimed
     */
    function isClaimed(bytes20 _humanityId) external view returns (bool) {
        if (proofOfHumanity.isClaimed(_humanityId)) return true;

        CrossChainHumanity memory humanity = humanityData[_humanityId];
        return humanity.owner != address(0) && humanity.expirationTime >= block.timestamp;
    }

    /** @notice Check whether the account corresponds to a claimed humanity
     *  @notice First check isHuman state in main contract and, if false there, derive from state of this contract
     *  @param _account The account address
     *  @return Whether the account has a valid humanity
     */
    function isHuman(address _account) external view returns (bool) {
        if (proofOfHumanity.isHuman(_account)) return true;

        bytes20 humanityId = accountHumanity[_account];
        CrossChainHumanity memory humanity = humanityData[humanityId];

        return
            !humanity.isHomeChain &&
            humanityId != bytes20(0x0) &&
            humanity.owner == _account &&
            humanity.expirationTime > block.timestamp;
    }

    /** @notice Get the owner of a humanity. Returns null address if not claimed
     *  @notice First check state in main contract and, if no owner returned, derive from state of this contract
     *  @param _humanityId The id of the humanity
     *  @return owner The owner of the humanity
     */
    function boundTo(bytes20 _humanityId) external view returns (address owner) {
        owner = proofOfHumanity.boundTo(_humanityId);

        if (owner == address(0x0)) {
            CrossChainHumanity memory humanity = humanityData[_humanityId];

            if (humanity.expirationTime >= block.timestamp) owner = humanity.owner;
        }
    }

    /** @notice Get the humanity corresponding to an address. Returns null humanity if it does not correspond to a humanity
     *  @notice First check state in main contract and, if no humanity returned, derive from state of this contract
     *  @param _account The address of the account to get the correspding humanity of
     *  @return humanityId The humanity corresponding to the account
     */
    function humanityOf(address _account) external view returns (bytes20 humanityId) {
        humanityId = proofOfHumanity.humanityOf(_account);

        if (humanityId == bytes20(0x0)) {
            humanityId = accountHumanity[_account];
            CrossChainHumanity memory humanity = humanityData[humanityId];

            if (humanity.owner != _account || block.timestamp > humanity.expirationTime) humanityId = bytes20(0x0);
        }
    }
}
