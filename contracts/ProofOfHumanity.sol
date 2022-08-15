/** @authors: [@unknownunknown1, @nix1g]
 *  @reviewers: [@fnanni-0, @mtsalenc*, @nix1g, @clesaege*, @hbarcelos*, @ferittuncer*, @shalzz, @MerlinEgalite]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.14;

import "@kleros/erc-792/contracts/IArbitrable.sol";
import "@kleros/erc-792/contracts/erc-1497/IEvidence.sol";
import "@kleros/erc-792/contracts/IArbitrator.sol";

import {IProofOfHumanity} from "./interfaces/IProofOfHumanity.sol";

/** @title ProofOfHumanity
 *  This contract is a curated registry for people. The users are identified by their address and can be added or removed through the request-challenge protocol.
 *  In order to challenge a registration request the challenger must provide one of the four reasons.
 *  New registration requests firstly should gain sufficient amount of vouches from other registered users and only after that they can be accepted or challenged.
 *  The users who vouched for a human that lost the challenge with the reason Duplicate or DoesNotExist would be penalized with optional fine or ban period.
 *  @notice This contract trusts that the Arbitrator is honest and will not reenter or modify its costs during a call.
 *  The arbitrator must support appeal period.
 */
contract ProofOfHumanity is IProofOfHumanity, IArbitrable, IEvidence {
    /// ====== CONSTANTS ====== ///

    /// @notice The amount of non 0 choices the arbitrator can give.
    uint256 private constant _RULING_OPTIONS = 2;

    /// @notice The number of vouches that will be automatically processed when executing a request.
    uint256 private constant _AUTO_PROCESSED_VOUCH = 10;

    /// @notice Indicates that reasons' bitmap is full. 0b1111.
    uint256 private constant _FULL_REASONS_SET = 15;

    /// @notice Divisor parameter for multipliers.
    uint256 private constant _MULTIPLIER_DIVISOR = 10000;

    /// @notice The EIP-712 domainSeparator specific to this deployed instance. It is used to verify the IsHumanVoucher's signature.
    bytes32 private _DOMAIN_SEPARATOR;

    /// @notice The EIP-712 typeHash of IsHumanVoucher. keccak256("IsHumanVoucher(address vouchedHuman, uint160 soulId,uint256 voucherExpirationTimestamp)").
    bytes32 private constant _IS_HUMAN_VOUCHER_TYPEHASH =
        0x18faecde3c110f2038178ff999914b696caf80bf6f9e9600c8383e913a997dff;

    /// ====== ENUMS ====== ///

    enum Party {
        None, // Party per default when there is no challenger or requester. Also used for unconclusive ruling.
        Requester, // Party that made the request to change a status.
        Challenger // Party that challenged the request to change a status.
    }

    enum Reason {
        None, // No reason specified. This option should be used to challenge removal requests.
        IncorrectSubmission, // Request does not comply with the rules.
        Deceased, // Human has existed but does not exist anymore.
        Duplicate, // Human is already registered.
        DoesNotExist // Human is not real. For example, this can be used for videos showing computer generated persons.
    }

    enum Status {
        Vouching, // Request requires vouches / funding to advance to the next state. Should not be in this state for revokal requests.
        Resolving, // Request is resolving and can be challenged within the time limit.
        Disputed, // Request has been challenged.
        Resolved // Request has been resolved.
    }

    /// ====== STRUCTS ====== ///

    /** @dev A human makes requests to become the owner of the soul.
     *  @dev Multiple claimers can be in the claiming process at the same time. Only one request can be pending at a time.
     *  @dev Owner must be in this struct in order to know the real owner during renewal process.
     */
    struct Soul {
        address owner; // Address corresponding to the soul.
        uint64 expirationTime; // Time when the soul expires.
        bool vouching; // True if the human used its vouch for another human. This is set back to false once the vouch is processed.
        bool pendingRevokal; // True if the human is in the process of revokal.
        uint64 nbPendingRequests; // Number of pending requests in challenging phase.
        uint64 nbRequests; // Number of requests made for the soul.
        mapping(address => uint256) claimers; // Mapping of the claimer address to the id of the current claim request.
        mapping(uint256 => Request) requests; // Mapping of the ids to corresponding requests.
    }

    struct Request {
        bool typeRevokal; // True if the request is a revokal request. False if it is a renewal request.
        Status status; // Current status of the request.
        Reason currentReason; // Current reason a claim request was challenged with. Is left empty for removal requests.
        uint8 usedReasons; // Bitmap of the reasons used by challengers of this request.
        uint16 arbitratorDataId; // Index of the relevant arbitratorData struct. All the arbitrator info is stored in a separate struct to reduce gas cost.
        uint16 lastChallengeId; // Id of the last challenge, which is equal to the total number of challenges for the request.
        uint32 lastProcessedVouch; // Stores the index of the last processed vouch in the array of vouches. It is used for partial processing of the vouches in resolved requests.
        address payable requester; // Address that made the request.
        address payable ultimateChallenger; // Address of the challenger who won a dispute. Users who vouched for the challenged human must pay the fines to this address.
        uint64 challengePeriodEnd; // Time until the request can be challenged.
        bool requesterLost; // True if the requester has already had a dispute that wasn't ruled in his favor.
        uint160[] vouches; // Stores the unique Ids of humans that vouched for this request and whose vouches were used in this request.
        mapping(uint256 => Challenge) challenges; // Stores all the challenges of this request. challengeId -> Challenge.
    }

    struct ContributionsSet {
        uint256 forRequester;
        uint256 forChallenger;
    }

    // Some arrays below have 3 elements to map with the Party enums for better readability:
    // - 0: is unused, matches `Party.None`.
    // - 1: for `Party.Requester`.
    // - 2: for `Party.Challenger`.
    struct Round {
        Party sideFunded; // Stores the side that successfully paid the appeal fees in the latest round. Note that if both sides have paid a new round is created.
        uint256 feeRewards; // Sum of reimbursable fees and stake rewards available to the parties that made contributions to the side that ultimately wins a dispute.
        ContributionsSet paidFees; // Tracks the fees paid by each side in this round.
        mapping(address => ContributionsSet) contributions; // Maps contributors to their contributions for each side.
    }

    struct Challenge {
        uint16 lastRoundId; // Id of the last round.
        Party ruling; // Ruling given by the arbitrator of the dispute.
        address payable challenger; // Address that challenged the request.
        uint256 disputeId; // Id of the dispute related to the challenge.
        mapping(uint256 => Round) rounds; // Tracks the info of each funding round of the challenge.
    }

    // The data tied to the arbitrator that will be needed to recover the info for arbitrator's call.
    struct DisputeData {
        uint96 requestId; // The Id of the request.
        uint96 challengeId; // The Id of the challenge of the request.
        uint160 soulId; // The Id of the soul involving the disputed request.
    }

    struct ArbitratorData {
        uint96 metaEvidenceUpdates; // The meta evidence to be used in disputes.
        IArbitrator arbitrator; // Address of the trusted arbitrator to solve disputes.
        bytes arbitratorExtraData; // Extra data for the arbitrator.
    }

    struct SignatureVouch {
        uint64 expirationTime;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// ====== STORAGE ====== ///

    /// @notice Indicates that the contract has been initialized.
    bool public initialized;

    /// @notice The address that can make governance changes to the parameters of the contract.
    address public governor;

    /// @notice The address of the CrossChainProofOfHumanity instance.
    address public crossChainProofOfHumanity;

    /// @notice The base deposit to make a new request for a soul.
    uint256 public requestBaseDeposit;

    /// @notice Time after which the soul will no longer be considered claimed. The human has to renew the soul to refresh it.
    uint64 public soulLifespan;
    /// @notice  The duration of the period when the registered soul can be renewd.
    uint64 public renewalPeriodDuration;
    /// @notice The time after which a request becomes executable if not challenged.
    uint64 public challengePeriodDuration;

    /// @notice The number of registered users that have to vouch for a new claim request in order for it to advance beyond Vouching state.
    uint64 public requiredNumberOfVouches;

    /// @notice Multiplier for calculating the fee stake that must be paid in the case where arbitrator refused to arbitrate.
    uint256 public sharedStakeMultiplier;
    /// @notice Multiplier for calculating the fee stake paid by the party that won the previous round.
    uint256 public winnerStakeMultiplier;
    /// @notice Multiplier for calculating the fee stake paid by the party that lost the previous round.
    uint256 public loserStakeMultiplier;

    /// @notice Stores the arbitrator data of the contract. Updated each time the data is changed.
    ArbitratorData[] public arbitratorDataList;

    /// @notice Maps the soul id to the Soul data. souls[soulId].
    mapping(uint160 => Soul) private souls;

    /// @notice Maps the address to human's soulId. humans[humanAddress].
    mapping(address => uint160) public humans;

    /// @notice Indicates whether or not the voucher has vouched for a certain human. vouches[voucherId][vouchedHumanId][soulId].
    mapping(address => mapping(address => mapping(uint160 => bool))) public vouches;
    /// @notice Maps a dispute Id with its data. arbitratorDisputeIdToDisputeData[arbitrator][disputeId].
    mapping(address => mapping(uint256 => DisputeData)) public arbitratorDisputeIdToDisputeData;

    /* Modifiers */

    modifier initializer() {
        require(!initialized);
        initialized = true;
        _;
    }

    modifier onlyGovernor() {
        require(msg.sender == governor);
        _;
    }

    modifier onlyCrossChain() {
        require(msg.sender == crossChainProofOfHumanity || msg.sender == governor);
        _;
    }

    /// ====== EVENTS ====== ///

    event Initialized();
    event GovernorChanged(address governor);
    event RequestBaseDepositChanged(uint256 requestBaseDeposit);
    event DurationsChanged(uint64 soulLifespan, uint64 renewalPeriodDuration, uint64 challengePeriodDuration);
    event RequiredNumberOfVouchesChanged(uint64 requiredNumberOfVouches);
    event StakeMultipliersChanged(
        uint256 sharedStakeMultiplier,
        uint256 winnerStakeMultiplier,
        uint256 loserStakeMultiplier
    );
    event CrossChainProxyChanged(address crossChainProofOfHumanity);
    event ArbitratorChanged(IArbitrator arbitrator, bytes arbitratorExtraData);
    event SoulGrantedManually(uint160 indexed soulId, address indexed owner, uint64 expirationTime);
    event SoulRevokedManually(address indexed human);
    event SoulClaim(address indexed requester, uint160 indexed soulId, uint256 requestId, string evidence, string name);
    event SoulRenewal(address indexed requester, uint160 indexed soulId, uint256 requestId, string evidence);
    event SoulRevokal(address indexed requester, uint160 indexed soulId, uint256 requestId, string evidence);
    event VouchAdded(address indexed voucher, address indexed vouched, uint160 soulId);
    event VouchRemoved(address indexed voucher, address indexed vouched, uint160 soulId);
    event RequestWithdrawn(uint160 soulId, uint256 requestId);
    event RequestContribution(address claimer, uint256 amount);
    event StateAdvanced(address claimer);
    event RequestChallenged(uint160 soulId, uint256 requestId, uint256 challengeId, Reason reason, string evidence);
    event RequestExecuted(uint160 soulId, uint256 requestId);
    event VouchesProcessed(uint160 soulId, uint256 requestId, uint256 endIndex);
    event ChallengePeriodRestart(uint160 soulId, uint256 requestId, uint256 challengeId);
    event EvidenceAppended(uint160 soulId, uint256 requestId, string evidence);
    event AppealCreated(IArbitrator arbitrator, uint256 disputeId);
    event AppealContribution(IArbitrator arbitrator, uint256 disputeId, Party side, uint256 amount);
    event FeesAndRewardsWithdrawn(
        address beneficiary,
        uint160 soulId,
        uint256 requestId,
        uint256 challengeId,
        uint256 round
    );

    /// ====== INITIALIZATION ====== ///

    /** @notice Initializes the ProofOfHumanity contract.
     *
     *  @dev Emits {MetaEvidence} event for the registration meta evidence.
     *  @dev Emits {MetaEvidence} event for the clearing meta evidence.
     *
     *  @param _arbitrator The trusted arbitrator to resolve potential disputes.
     *  @param _arbitratorExtraData Extra data for the trusted arbitrator contract.
     *  @param _registrationMetaEvidence The URI of the meta evidence object for registration requests.
     *  @param _clearingMetaEvidence The URI of the meta evidence object for clearing requests.
     *  @param _requestBaseDeposit The base deposit to make a request for a soul.
     *  @param _soulLifespan Time in seconds during which the claimed soul won't automatically lose its status.
     *  @param _renewalPeriodDuration Value that defines the duration of soul's renewal period.
     *  @param _challengePeriodDuration The time in seconds during which the request can be challenged.
     *  @param _multipliers The array that contains fee stake multipliers to avoid 'stack too deep' error.
     *  @param _requiredNumberOfVouches The number of vouches the human has to have to pass from Vouching to Resolving phase.
     */
    function initialize(
        IArbitrator _arbitrator,
        bytes memory _arbitratorExtraData,
        string memory _registrationMetaEvidence,
        string memory _clearingMetaEvidence,
        uint256 _requestBaseDeposit,
        uint64 _soulLifespan,
        uint64 _renewalPeriodDuration,
        uint64 _challengePeriodDuration,
        uint256[3] memory _multipliers,
        uint64 _requiredNumberOfVouches
    ) public initializer {
        governor = msg.sender;
        requestBaseDeposit = _requestBaseDeposit;
        soulLifespan = _soulLifespan;
        renewalPeriodDuration = _renewalPeriodDuration;
        challengePeriodDuration = _challengePeriodDuration;
        sharedStakeMultiplier = _multipliers[0];
        winnerStakeMultiplier = _multipliers[1];
        loserStakeMultiplier = _multipliers[2];
        requiredNumberOfVouches = _requiredNumberOfVouches;

        ArbitratorData storage arbitratorData = arbitratorDataList.push();
        arbitratorData.arbitrator = _arbitrator;
        arbitratorData.arbitratorExtraData = _arbitratorExtraData;

        // EIP-712.
        bytes32 DOMAIN_TYPEHASH = 0x8cad95687ba82c2ce50e74f7b754645e5117c3a5bec8151c0726d5857980a866; // keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)").
        _DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("Proof of Humanity"), block.chainid, address(this))
        );

        emit Initialized();
        emit MetaEvidence(0, _registrationMetaEvidence);
        emit MetaEvidence(1, _clearingMetaEvidence);
    }

    /// ====== GOVERNANCE ====== ///

    /** @notice Manually grant soul via cross-chain instance / governor.
     *
     *  @dev Requirements:
     *  - Human must not be in the process of claiming a soul.
     *  - Soul must not be claimed.
     *
     *  @param _soulId Unique id to be added.
     *  @param _owner Address owner corresponding to the soul.
     *  @param _expirationTime Expiration time of the newly added soul.
     */
    function grantSoulManually(
        uint160 _soulId,
        address _owner,
        uint64 _expirationTime
    ) external override onlyCrossChain returns (bool success) {
        Soul storage soul = souls[_soulId];

        if (_soulClaimed(soul)) return false;

        require(_noOngoingClaim(_owner));

        soul.owner = _owner;
        soul.expirationTime = _expirationTime;
        humans[_owner] = _soulId;

        emit SoulGrantedManually(_soulId, _owner, _expirationTime);

        return true;
    }

    /** @notice Directly revoke a soul via cross-chain instance/governor.
     *
     *  @dev Requirements:
     *  - Sould must be claimed by someone.
     *  - Owner of the soul must be _humanId.
     *  - Soul must have no pending requests.
     *  - Soul must not be vouching at the moment.
     *
     *  @param _humanId Human corresponding to the soul to be revoked.
     *  @return expirationTime Expiration time of the revoked soul.
     *  @return soulId Unique id corresponding to the revoked soul.
     */
    function revokeSoulManually(address _humanId)
        external
        override
        onlyCrossChain
        returns (uint64 expirationTime, uint160 soulId)
    {
        soulId = humans[_humanId];
        Soul storage soul = souls[soulId];

        require(_soulClaimed(soul));
        require(soul.owner == _humanId);
        require(soul.nbPendingRequests == 0);
        require(!soul.vouching);

        expirationTime = soul.expirationTime;

        delete soul.owner;
        delete humans[_humanId];

        emit SoulRevokedManually(_humanId);
    }

    /** @notice Change the governor of the contract.
     *  @param _governor The address of the new governor.
     */
    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
        emit GovernorChanged(_governor);
    }

    /** @notice Change the base amount required as a deposit to make a request for a soul.
     *  @param _requestBaseDeposit The new base amount of wei required to make a new request.
     */
    function changeRequestBaseDeposit(uint256 _requestBaseDeposit) external onlyGovernor {
        requestBaseDeposit = _requestBaseDeposit;
        emit RequestBaseDepositChanged(_requestBaseDeposit);
    }

    /** @notice Change the duration of the soul lifespan, renewal and challenge periods.
     *
     *  @dev Requirements:
     *  - To ensure correct contract behaviour, the sum of challengePeriodDuration and renewalPeriodDuration should be less than soulLifespan.
     *
     *  @param _soulLifespan The new lifespan of the time the soul is considered registered.
     *  @param _renewalPeriodDuration The new value that defines the duration of the soul's renewal period.
     *  @param _challengePeriodDuration The new duration of the challenge period. It should be lower than the time for a dispute.
     */
    function changeDurations(
        uint64 _soulLifespan,
        uint64 _renewalPeriodDuration,
        uint64 _challengePeriodDuration
    ) external onlyGovernor {
        require(_challengePeriodDuration + _renewalPeriodDuration < _soulLifespan);
        soulLifespan = _soulLifespan;
        renewalPeriodDuration = _renewalPeriodDuration;
        challengePeriodDuration = _challengePeriodDuration;
        emit DurationsChanged(_soulLifespan, _renewalPeriodDuration, _challengePeriodDuration);
    }

    /** @notice Change the number of vouches required for the request to pass beyond Vouching state.
     *  @param _requiredNumberOfVouches The new required number of vouches.
     */
    function changeRequiredNumberOfVouches(uint64 _requiredNumberOfVouches) external onlyGovernor {
        requiredNumberOfVouches = _requiredNumberOfVouches;
        emit RequiredNumberOfVouchesChanged(_requiredNumberOfVouches);
    }

    /** @notice Change the proportion of arbitration fees that must be paid as fee stake by parties depending on the result of the dispute (e.g. when the arbitrator refused to rule).
     *  @param _sharedStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake by parties when there is no winner or loser. In basis points.
     *  @param _winnerStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake by the winner of the previous round. In basis points.
     *  @param _loserStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake by the loser of the previous round. In basis points.
     */
    function changeStakeMultipliers(
        uint256 _sharedStakeMultiplier,
        uint256 _winnerStakeMultiplier,
        uint256 _loserStakeMultiplier
    ) external onlyGovernor {
        sharedStakeMultiplier = _sharedStakeMultiplier;
        winnerStakeMultiplier = _winnerStakeMultiplier;
        loserStakeMultiplier = _loserStakeMultiplier;
        emit StakeMultipliersChanged(_sharedStakeMultiplier, _winnerStakeMultiplier, _loserStakeMultiplier);
    }

    /** @notice Update the meta evidence used for disputes.
     *
     *  @dev Emits {MetaEvidence} event for the registration meta evidence.
     *  @dev Emits {MetaEvidence} event for the clearing meta evidence.
     *
     *  @param _registrationMetaEvidence The meta evidence to be used for future registration request disputes.
     *  @param _clearingMetaEvidence The meta evidence to be used for future clearing request disputes.
     */
    function changeMetaEvidence(string calldata _registrationMetaEvidence, string calldata _clearingMetaEvidence)
        external
        onlyGovernor
    {
        ArbitratorData storage arbitratorData = arbitratorDataList[arbitratorDataList.length - 1];
        uint96 newMetaEvidenceUpdates = arbitratorData.metaEvidenceUpdates + 1;
        arbitratorDataList.push(
            ArbitratorData({
                arbitrator: arbitratorData.arbitrator,
                metaEvidenceUpdates: newMetaEvidenceUpdates,
                arbitratorExtraData: arbitratorData.arbitratorExtraData
            })
        );
        emit MetaEvidence(2 * newMetaEvidenceUpdates, _registrationMetaEvidence);
        emit MetaEvidence(2 * newMetaEvidenceUpdates + 1, _clearingMetaEvidence);
    }

    /** @notice Change the arbitrator to be used for disputes that may be raised in the next requests. The arbitrator is trusted to support appeal period and not reenter.
     *  @param _arbitrator The new trusted arbitrator to be used in the next requests.
     *  @param _arbitratorExtraData The extra data used by the new arbitrator.
     */
    function changeArbitrator(IArbitrator _arbitrator, bytes calldata _arbitratorExtraData) external onlyGovernor {
        ArbitratorData storage arbitratorData = arbitratorDataList[arbitratorDataList.length - 1];
        arbitratorDataList.push(
            ArbitratorData({
                arbitrator: _arbitrator,
                metaEvidenceUpdates: arbitratorData.metaEvidenceUpdates,
                arbitratorExtraData: _arbitratorExtraData
            })
        );
        emit ArbitratorChanged(_arbitrator, _arbitratorExtraData);
    }

    /** @notice Change the cross-chain instance.
     *  @param _crossChainProofOfHumanity The new cross-chain instance to be used.
     */
    function changeCrossChainProofOfHumanity(address _crossChainProofOfHumanity) external onlyGovernor {
        crossChainProofOfHumanity = _crossChainProofOfHumanity;
        emit CrossChainProxyChanged(_crossChainProofOfHumanity);
    }

    /// ====== REQUESTS ====== ///

    function claimSoul(string calldata _evidence, string calldata _name) external payable {
        _claimSoul(uint160(msg.sender), _evidence, _name);
    }

    function claimSoul(
        uint160 _soulId,
        string calldata _evidence,
        string calldata _name
    ) external payable {
        _claimSoul(_soulId, _evidence, _name);
    }

    /** @notice Make a request to enter the registry. Paying the full deposit right away is not required as it can be crowdfunded later.
     *
     *  @dev Emits {ClaimSoul} event.
     *
     *  @dev Requirements:
     *  - Sender must not own a soul.
     *  - Soul corresponding to _soulId must not be claimed (can be expired).
     *  - Sender must not be in the process of claiming a soul (covered by _requestSoul).
     *
     *  @param _soulId The soul id the human applies for. 0 can be used as default.
     *  @param _evidence Link to evidence using its URI.
     *  @param _name Name of the human (for Subgraph only and it won't be used in this function).
     */
    function _claimSoul(
        uint160 _soulId,
        string calldata _evidence,
        string calldata _name
    ) internal {
        Soul storage soul = souls[_soulId];

        require(!isRegistered(msg.sender));
        require(!_soulClaimed(soul));

        uint256 requestId = _requestSoul(_soulId, _evidence);

        emit SoulClaim(msg.sender, _soulId, requestId, _evidence, _name);
    }

    /** @notice Make a request to renew soul's lifespan. Paying the full deposit right away is not required as it can be crowdfunded later.
     *  @notice The user can reapply even when current lifespan has not expired, but only after the start of renewal period.
     *
     *  @dev Emits {RenewSoul} event.
     *
     *  @dev Requirements:
     *  - Sender must be current owner of the soul.
     *  - Current time passed the start of the renewal period for soul.
     *  - Sender must not be in the process of claiming a soul (covered by _requestSoul).
     *
     *  @param _evidence Link to evidence using its URI.
     */
    function renewSoul(string calldata _evidence) external payable {
        uint160 soulId = humans[msg.sender];

        Soul storage soul = souls[soulId];

        require(soul.owner == msg.sender);
        require(soul.expirationTime - renewalPeriodDuration <= block.timestamp);

        uint256 requestId = _requestSoul(soulId, _evidence);

        emit SoulRenewal(msg.sender, soulId, requestId, _evidence);
    }

    /** @notice Make a request to revoke a soul.
     *  @notice Accepts enough ETH to cover the deposit, reimburses the rest.
     *  @notice Status of the soul can be anything to avoid blocking revokals.
     *
     *  @dev Emits {RevokeSoul} event.
     *  @dev Emits {Evidence} event.
     *
     *  @dev Requirements:
     *  - Soul must be claimed by someone and not expired.
     *  - Soul must not be pending revokal.
     *  - Deposit must be fully paid.
     *
     *  @param _soulId The id of the soul to revoke.
     *  @param _evidence Link to evidence using its URI.
     */
    function revokeSoul(uint160 _soulId, string calldata _evidence) external payable {
        Soul storage soul = souls[_soulId];

        require(_soulClaimed(soul));
        require(!soul.pendingRevokal);

        uint256 requestId = ++soul.nbRequests;
        soul.pendingRevokal = true;
        soul.nbPendingRequests++;

        Request storage request = soul.requests[requestId];
        request.status = Status.Resolving;
        request.typeRevokal = true;
        request.requester = payable(msg.sender);
        uint256 arbitratorDataId = arbitratorDataList.length - 1;
        request.arbitratorDataId = uint16(arbitratorDataId);
        request.challengePeriodEnd = uint64(block.timestamp) + challengePeriodDuration;

        Round storage round = request.challenges[0].rounds[0];
        ArbitratorData storage arbitratorData = arbitratorDataList[arbitratorDataId];
        uint256 totalCost = _arbitrationCost(arbitratorData) + requestBaseDeposit;

        require(_contribute(round, Party.Requester, totalCost));

        emit SoulRevokal(msg.sender, _soulId, requestId, _evidence);

        if (bytes(_evidence).length > 0)
            emit Evidence(arbitratorData.arbitrator, requestId + uint256(_soulId), msg.sender, _evidence);
    }

    /** @notice Fund the requester's deposit. Accepts enough ETH to cover the deposit, reimburses the rest.
     *
     *  @dev Requirements:
     *  - Human must be in the process of claiming a soul and the request is in Vouching state.
     *
     *  @param _claimer The address of the human whose request to fund.
     */
    function fundRequest(address _claimer) external payable {
        Soul storage soul = souls[humans[_claimer]];
        uint256 requestId = soul.claimers[_claimer];
        Request storage request = soul.requests[requestId];
        require(request.status == Status.Vouching);
        Round storage round = request.challenges[0].rounds[0];

        ArbitratorData storage arbitratorData = arbitratorDataList[request.arbitratorDataId];
        uint256 totalCost = _arbitrationCost(arbitratorData) + requestBaseDeposit;

        emit RequestContribution(_claimer, msg.value);

        _contribute(round, Party.Requester, totalCost);
    }

    /** @notice Vouch that the human corresponds to the soul id.
     *
     *  @dev Emits {VouchAdded} event.
     *
     *  @param _human The address of the human.
     *  @param _soulId The soul id the vouch specifies human corresponds to.
     */
    function addVouch(address _human, uint160 _soulId) external {
        vouches[msg.sender][_human][_soulId] = true;
        emit VouchAdded(msg.sender, _human, _soulId);
    }

    /** @notice Remove a previously added vouch. Note that the event spam is not an issue as it will be handled by the UI.
     *
     *  @dev Emits {VouchRemoved} event.
     *
     *  @param _human The address of the human.
     *  @param _soulId The soul id the vouch specifies human corresponds to.
     */
    function removeVouch(address _human, uint160 _soulId) external {
        vouches[msg.sender][_human][_soulId] = false;
        emit VouchRemoved(msg.sender, _human, _soulId);
    }

    /** @notice Allow to withdraw a mistakenly added request while it's still in a vouching state.
     *
     *  @dev Requirements:
     *  - Sender must be in the process of claiming a soul and the request is in Vouching state.
     */
    function withdrawRequest() external {
        uint160 soulId = humans[msg.sender];
        Soul storage soul = souls[soulId];
        uint256 requestId = soul.claimers[msg.sender];
        Request storage request = soul.requests[requestId];
        require(request.status == Status.Vouching);

        delete soul.claimers[msg.sender];
        request.status = Status.Resolved;

        // Automatically withdraw for the requester.
        withdrawFeesAndRewards(payable(msg.sender), soulId, requestId, 0, 0);

        emit RequestWithdrawn(soulId, requestId);
    }

    /** @notice Change human's phase from Vouching to Claiming if all conditions are met.
     *
     *  @dev Emits {VouchAdded} event.
     *
     *  @dev Requirements:
     *  - Request must be in Vouching state.
     *  - Soul must not be claimed.
     *  - Requester must have the deposit covered.
     *  - Provided signatures must be valid.
     *  - Number of aggregated vouches must be at least required number of vouches.
     *
     *  @dev EIP-712:
     *  struct IsHumanVoucher {
     *      address vouchedHuman;
     *      uint160 vouchedForSoul;
     *      uint256 voucherExpirationTimestamp;
     *  }
     *
     *  @param _claimer The address of the human whose request status to advance.
     *  @param _vouches Array of users whose vouches to count (optional).
     *  @param _signatureVouches Array of EIP-712 signatures of struct IsHumanVoucher (optional).
     */
    function advanceState(
        address _claimer,
        address[] calldata _vouches,
        SignatureVouch[] calldata _signatureVouches
    ) external {
        uint160 soulId = humans[_claimer];
        Soul storage soul = souls[soulId];
        uint256 requestId = soul.claimers[_claimer];
        Request storage request = soul.requests[requestId];
        require(request.status == Status.Vouching);
        require(!_soulClaimed(soul));
        require(request.challenges[0].rounds[0].sideFunded == Party.Requester);

        uint256 i;
        while (request.vouches.length < requiredNumberOfVouches) {
            if (i < _signatureVouches.length) {
                SignatureVouch memory signature = _signatureVouches[i];
                address voucherAddress = ecrecover(
                    keccak256(
                        abi.encodePacked(
                            "\x19\x01",
                            _DOMAIN_SEPARATOR,
                            keccak256(
                                abi.encode(_IS_HUMAN_VOUCHER_TYPEHASH, _claimer, soulId, signature.expirationTime)
                            )
                        )
                    ),
                    signature.v,
                    signature.r,
                    signature.s
                );

                if (block.timestamp < signature.expirationTime && _vouchValid(voucherAddress, _claimer)) {
                    uint160 voucherSoulId = humans[voucherAddress];
                    request.vouches.push(voucherSoulId);
                    souls[voucherSoulId].vouching = true;

                    emit VouchAdded(voucherAddress, _claimer, soulId);
                }
            } else {
                // Overflows if the end of _vouches has been reached and not enough valid vouches were gathered.
                address voucherAddress = _vouches[i - _signatureVouches.length];
                uint160 voucherSoulId = humans[voucherAddress];
                if (vouches[voucherAddress][_claimer][soulId] && _vouchValid(voucherAddress, _claimer)) {
                    request.vouches.push(voucherSoulId);
                    souls[voucherSoulId].vouching = true;
                }
            }

            unchecked {
                i++;
            }
        }

        soul.nbPendingRequests++;
        request.status = Status.Resolving;
        request.challengePeriodEnd = uint64(block.timestamp) + challengePeriodDuration;

        emit StateAdvanced(_claimer);
    }

    /** @notice Challenge the human's request. Accept enough ETH to cover the deposit, reimburse the rest.
     *
     *  @dev Emits {RequestChallenged} event.
     *  @dev Emits {Dispute} event.
     *  @dev Emits {Evidence} event.
     *
     *  @dev Requirements:
     *  - Soul must be in claiming/revoking phase.
     *  - If there is a revokal request, reason must be None.
     *  - If there is a claim request, reason must not be None.
     *  - Request must be in resolving state.
     *  - Must be challenge period for the request.
     *  - Reason must not have been used for this request.
     *  - Challenger side must be fully paid.
     *
     *  @param _soulId Id of the soul the request to challenge corresponds to.
     *  @param _requestId Id of the request to challenge.
     *  @param _reason Reason to challenge the request.
     *  @param _evidence Link to evidence using its URI. Ignored if not provided.
     */
    function challengeRequest(
        uint160 _soulId,
        uint64 _requestId,
        Reason _reason,
        string calldata _evidence
    ) external payable {
        Soul storage soul = souls[_soulId];
        require(soul.pendingRevokal == (_reason == Reason.None));

        Request storage request = souls[_soulId].requests[_requestId];
        require(request.status == Status.Resolving);
        require(request.challengePeriodEnd >= uint64(block.timestamp));

        if (request.currentReason != _reason) {
            // Get the bit that corresponds with reason's index.
            uint8 reasonBit;
            unchecked {
                reasonBit = uint8(1 << (uint256(_reason) - 1));
            }

            require((reasonBit & ~request.usedReasons) == reasonBit);

            // Mark the bit corresponding with reason's index as 'true', to indicate that the reason was used.
            request.usedReasons ^= reasonBit;

            request.currentReason = _reason;
        }

        Challenge storage challenge = request.challenges[request.lastChallengeId];
        Round storage round = challenge.rounds[0];

        ArbitratorData storage arbitratorData = arbitratorDataList[request.arbitratorDataId];
        uint256 arbitrationCost = _arbitrationCost(arbitratorData);
        require(_contribute(round, Party.Challenger, arbitrationCost));
        round.feeRewards = round.feeRewards - arbitrationCost;

        challenge.disputeId = arbitratorData.arbitrator.createDispute{value: arbitrationCost}(
            _RULING_OPTIONS,
            arbitratorData.arbitratorExtraData
        );
        challenge.challenger = payable(msg.sender);

        DisputeData storage disputeData = arbitratorDisputeIdToDisputeData[address(arbitratorData.arbitrator)][
            challenge.disputeId
        ];
        disputeData.soulId = _soulId;
        disputeData.requestId = uint96(_requestId);
        disputeData.challengeId = uint96(request.lastChallengeId);

        request.status = Status.Disputed;
        request.lastChallengeId++;
        challenge.lastRoundId++;

        emit RequestChallenged(_soulId, _requestId, request.lastChallengeId, _reason, _evidence);

        uint256 evidenceGroupId = _requestId + uint256(_soulId);

        emit Dispute(
            arbitratorData.arbitrator,
            challenge.disputeId,
            2 * arbitratorData.metaEvidenceUpdates + (soul.pendingRevokal ? 1 : 0),
            evidenceGroupId
        );

        if (bytes(_evidence).length > 0)
            emit Evidence(arbitratorData.arbitrator, evidenceGroupId, msg.sender, _evidence);
    }

    /** @notice Take up to the total amount required to fund a side of an appeal. Reimburse the rest. Create an appeal if both sides are fully funded.
     *
     *  @dev Emits {AppealContribution} event.
     *  @dev Emits {HasPaidAppealFee} event.
     *
     *  @dev Requirements:
     *  - Side funded must be either requester or challenger.
     *  - Request must be disputed.
     *  - Challenge id must be valid.
     *  - Must be appeal period.
     *  - Appeal period must not be over for loser.
     *  - Must fund an non-funded side.
     *
     *  @param _soulId Id corresponding to soul of which request to fund.
     *  @param _requestId Id of the request.
     *  @param _challengeId Index of a dispute, created for the request.
     *  @param _side Recipient of the contribution.
     */
    function fundAppeal(
        uint160 _soulId,
        uint256 _requestId,
        uint256 _challengeId,
        Party _side
    ) external payable {
        require(_side != Party.None);
        Request storage request = souls[_soulId].requests[_requestId];
        require(request.status == Status.Disputed);
        require(_challengeId < request.lastChallengeId);

        Challenge storage challenge = request.challenges[_challengeId];
        ArbitratorData storage arbitratorData = arbitratorDataList[request.arbitratorDataId];

        (uint256 appealPeriodStart, uint256 appealPeriodEnd) = arbitratorData.arbitrator.appealPeriod(
            challenge.disputeId
        );
        require(block.timestamp >= appealPeriodStart && block.timestamp < appealPeriodEnd);

        uint256 multiplier;
        Party winner = Party(arbitratorData.arbitrator.currentRuling(challenge.disputeId));
        if (winner == _side) multiplier = winnerStakeMultiplier;
        else if (winner == Party.None) multiplier = sharedStakeMultiplier;
        else if (block.timestamp - appealPeriodStart < (appealPeriodEnd - appealPeriodStart) / 2)
            multiplier = loserStakeMultiplier;
        else revert();

        Round storage round = challenge.rounds[challenge.lastRoundId];
        Party firstFunded = round.sideFunded;
        require(_side != firstFunded);

        emit AppealContribution(arbitratorData.arbitrator, challenge.disputeId, _side, msg.value);

        uint256 appealCost = arbitratorData.arbitrator.appealCost(
            challenge.disputeId,
            arbitratorData.arbitratorExtraData
        );
        uint256 totalCost = appealCost + (appealCost * multiplier) / _MULTIPLIER_DIVISOR;

        if (_contribute(round, _side, totalCost)) {
            if (firstFunded != Party.None) {
                // Both sides are fully funded. Create an appeal.
                arbitratorData.arbitrator.appeal{value: appealCost}(
                    challenge.disputeId,
                    arbitratorData.arbitratorExtraData
                );
                challenge.lastRoundId++;
                round.feeRewards = round.feeRewards - appealCost;

                emit AppealCreated(arbitratorData.arbitrator, challenge.disputeId);
            }
        }
    }

    /** @notice Execute a request if the challenge period passed and no one challenged the request.
     *
     *  @dev Requirements:
     *  - Request must be in resolving state.
     *  - Challenge period must have ended.
     *
     *  @param _soulId Id of the soul the request to execute corresponds to.
     *  @param _requestId Id of the request to execute.
     */
    function executeRequest(uint160 _soulId, uint256 _requestId) external {
        Soul storage soul = souls[_soulId];
        Request storage request = soul.requests[_requestId];
        require(request.status == Status.Resolving);
        require(request.challengePeriodEnd < uint64(block.timestamp));

        if (request.typeRevokal) {
            delete soul.owner;
            delete humans[soul.owner];
            soul.pendingRevokal = false;
        } else if (!request.requesterLost) {
            soul.owner = request.requester;
            soul.expirationTime = uint64(block.timestamp) + soulLifespan;
        }

        soul.nbPendingRequests--;
        request.status = Status.Resolved;
        delete soul.claimers[request.requester];

        emit RequestExecuted(_soulId, _requestId);

        if (request.vouches.length != 0) processVouches(_soulId, _requestId, _AUTO_PROCESSED_VOUCH);

        withdrawFeesAndRewards(request.requester, _soulId, _requestId, 0, 0); // Automatically withdraw for the requester.
    }

    /** @notice Process vouches of the resolved request, so vouchings of users who vouched for it can be used for other humans.
     *  @notice Users who vouched for bad soul requests are penalized.
     *
     *  @dev Requirements:
     *  - Request must be resolved.
     *
     *  @param _soulId Id of the soul for which the request was made.
     *  @param _requestId Id of request for which vouches to iterate.
     *  @param _iterations Number of iterations to go through.
     */
    function processVouches(
        uint160 _soulId,
        uint256 _requestId,
        uint256 _iterations
    ) public {
        Request storage request = souls[_soulId].requests[_requestId];
        require(request.status == Status.Resolved, "Not resolved");

        uint256 lastProcessed = request.lastProcessedVouch;
        uint256 endIndex = _iterations + lastProcessed;
        uint256 vouchCount = request.vouches.length;

        if (endIndex > vouchCount) endIndex = vouchCount;

        Reason currentReason = request.currentReason;
        bool applyPenalty = request.ultimateChallenger != address(0x0) &&
            (currentReason == Reason.Duplicate || currentReason == Reason.DoesNotExist);

        while (lastProcessed < endIndex) {
            Soul storage voucherSoul = souls[request.vouches[lastProcessed]];
            voucherSoul.vouching = false;
            if (applyPenalty) {
                // Check the situation when vouching address is in the middle of renewal process.
                uint256 voucherRequestId = voucherSoul.claimers[voucherSoul.owner];
                if (voucherRequestId != 0) voucherSoul.requests[voucherRequestId].requesterLost = true;

                delete voucherSoul.owner;
            }

            unchecked {
                lastProcessed++;
            }
        }
        request.lastProcessedVouch = uint32(endIndex);

        emit VouchesProcessed(_soulId, _requestId, endIndex);
    }

    /** @notice Reimburse contributions if no disputes were raised. If a dispute was raised, send the fee stake rewards and reimbursements proportionally to the contributions made to the winner of a dispute.
     *
     *  @dev Requirements:
     *  - Request must be resolved.
     *  - Beneficiary must not be null address.
     *
     *  @param _beneficiary The address that made contributions to a request.
     *  @param _soulId Id of soul the request was for.
     *  @param _requestId The request from which to withdraw.
     *  @param _challengeId The Id of the challenge from which to withdraw.
     *  @param _round The round from which to withdraw.
     */
    function withdrawFeesAndRewards(
        address payable _beneficiary,
        uint160 _soulId,
        uint256 _requestId,
        uint256 _challengeId,
        uint256 _round
    ) public {
        Request storage request = souls[_soulId].requests[_requestId];
        Challenge storage challenge = request.challenges[_challengeId];
        Round storage round = challenge.rounds[_round];
        require(request.status == Status.Resolved);
        require(_beneficiary != address(0x0));

        Party ruling = challenge.ruling;
        uint256 reward;
        ContributionsSet storage beneficiaryContributions = round.contributions[_beneficiary];
        if (_round != 0 && _round == challenge.lastRoundId) {
            // Reimburse the payment if the last round wasn't fully funded.
            // Note that the 0 round is always considered funded if there is a challenge. If there was no challenge the requester will be reimbursed with the subsequent condition, since the ruling will be Party.None.
            reward = beneficiaryContributions.forRequester + beneficiaryContributions.forChallenger;
        } else if (ruling == Party.None) {
            uint256 totalFeesInRound = round.paidFees.forChallenger + round.paidFees.forRequester;
            uint256 claimableFees = beneficiaryContributions.forChallenger + beneficiaryContributions.forRequester;
            if (totalFeesInRound > 0) reward = (claimableFees * round.feeRewards) / totalFeesInRound;
        } else if (_beneficiary == request.ultimateChallenger && _challengeId == 0 && _round == 0) {
            // Challenger, who ultimately wins, will be able to get the deposit of the requester, even if he didn't participate in the initial dispute.
            reward = round.feeRewards;
            round.feeRewards = 0;
        } else if (request.ultimateChallenger == address(0x0) || _challengeId != 0 || _round != 0) {
            // This condition will prevent claiming a reward, intended for the ultimate challenger.
            uint256 paidFeesForWinner;
            uint256 contributionForWinner;
            if (ruling == Party.Requester) {
                paidFeesForWinner = round.paidFees.forRequester;
                contributionForWinner = beneficiaryContributions.forRequester;
            } else {
                paidFeesForWinner = round.paidFees.forChallenger;
                contributionForWinner = beneficiaryContributions.forChallenger;
            }
            if (paidFeesForWinner > 0) reward = (contributionForWinner * round.feeRewards) / paidFeesForWinner;
        }

        beneficiaryContributions.forRequester = 0;
        beneficiaryContributions.forChallenger = 0;
        _beneficiary.send(reward);

        emit FeesAndRewardsWithdrawn(_beneficiary, _soulId, _requestId, _challengeId, _round);
    }

    /** @notice Give a ruling for a dispute. Can only be called by the arbitrator. TRUSTED.
     *
     *  @dev Account for the situation where the winner loses a case due to paying less appeal fees than expected.
     *  @dev Ruling 0 is reserved for "Refused to arbitrate".
     *
     *  @dev Emits {ChallengePeriodRestart} event.
     *  @dev Emits {Ruling} event.
     *
     *  @dev Requirements:
     *  - Must be called by the arbitrator of the request.
     *  - Request must be resolved.
     *
     *  @param _disputeId Id of the dispute in the arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator.
     */
    function rule(uint256 _disputeId, uint256 _ruling) public override {
        Party resultRuling = Party(_ruling);
        DisputeData storage disputeData = arbitratorDisputeIdToDisputeData[msg.sender][_disputeId];
        Soul storage soul = souls[disputeData.soulId];
        Request storage request = soul.requests[disputeData.requestId];
        Challenge storage challenge = request.challenges[disputeData.challengeId];
        Round storage round = challenge.rounds[challenge.lastRoundId];

        require(address(arbitratorDataList[request.arbitratorDataId].arbitrator) == msg.sender);
        require(request.status != Status.Resolved);

        // The ruling is inverted if the loser paid its fees.
        if (round.sideFunded == Party.Requester)
            // If one side paid its fees, the ruling is in its favor. Note that if the other side had also paid, an appeal would have been created.
            resultRuling = Party.Requester;
        else if (round.sideFunded == Party.Challenger) resultRuling = Party.Challenger;

        // Store the rulings of each dispute for correct distribution of rewards.
        challenge.ruling = resultRuling;

        if (request.typeRevokal) {
            soul.pendingRevokal = false;
            if (resultRuling == Party.Requester) {
                delete soul.owner;
                delete humans[soul.owner];
            }
        } else {
            // For a claim request there can be more than one dispute.
            if (resultRuling == Party.Requester) {
                // Check whether or not the requester won all of his previous disputes for current reason.
                if (!request.requesterLost) {
                    // All reasons being used means the request can't be challenged again, so we can update its status.
                    if (request.usedReasons == _FULL_REASONS_SET) {
                        soul.owner = request.requester;
                        soul.expirationTime = uint64(block.timestamp) + soulLifespan;
                    } else {
                        // Refresh the state of the request so it can be challenged again.
                        request.status = Status.Resolving;
                        request.challengePeriodEnd = uint64(block.timestamp) + challengePeriodDuration;
                        request.currentReason = Reason.None;

                        emit ChallengePeriodRestart(disputeData.soulId, disputeData.requestId, disputeData.challengeId);

                        return;
                    }
                }
                // Challenger won or it’s a tie.
            } else {
                if (resultRuling == Party.Challenger) request.ultimateChallenger = challenge.challenger;
                request.requesterLost = true;
            }
        }

        soul.nbPendingRequests--;
        request.status = Status.Resolved;
        delete soul.claimers[request.requester];

        emit Ruling(IArbitrator(msg.sender), _disputeId, uint256(resultRuling));
    }

    /** @notice Submit a reference to evidence.
     *
     *  @dev Emits {Evidence} event.
     *
     *  @dev Requirements:
     *  - Must be valid request.
     *
     *  @param _soulId Id of soul the request is for.
     *  @param _requestId Id of request the evidence is related to.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(
        uint160 _soulId,
        uint256 _requestId,
        string calldata _evidence
    ) external {
        emit EvidenceAppended(_soulId, _requestId, _evidence);
        emit Evidence(
            arbitratorDataList[souls[_soulId].requests[_requestId].arbitratorDataId].arbitrator,
            _requestId + uint256(_soulId),
            msg.sender,
            _evidence
        );
    }

    /// ====== INTERNAL ====== ///

    /** @notice Make a request to claim/renew the humanity.
     *
     *  @dev Emits {Evidence} event.
     *
     *  @dev Requirements:
     *  - Sender has no ongoing claim.
     *
     *  @param _soulId Id of the soul the request is for.
     *  @param _evidence A link to evidence using its URI.
     *  @return requestId Id of the created request.
     */
    function _requestSoul(uint160 _soulId, string calldata _evidence) internal returns (uint256 requestId) {
        // Human must not be in the process of claiming a soul.
        require(_noOngoingClaim(msg.sender));

        Soul storage soul = souls[_soulId];

        requestId = ++soul.nbRequests;
        soul.claimers[msg.sender] = requestId;
        humans[msg.sender] = _soulId;

        Request storage request = soul.requests[requestId];
        request.requester = payable(msg.sender);
        uint256 arbitratorDataId = arbitratorDataList.length - 1;
        request.arbitratorDataId = uint16(arbitratorDataId);

        Round storage round = request.challenges[0].rounds[0];
        uint256 totalCost = _arbitrationCost(arbitratorDataList[arbitratorDataId]) + requestBaseDeposit;
        _contribute(round, Party.Requester, totalCost);

        if (bytes(_evidence).length > 0)
            emit Evidence(
                arbitratorDataList[arbitratorDataId].arbitrator,
                requestId + uint256(_soulId),
                msg.sender,
                _evidence
            );
    }

    /** @notice Make a fee contribution.
     *  @param _round Round to contribute to.
     *  @param _side Side to contribute to.
     *  @param _totalRequired Total amount required for this side.
     *  @return paidInFull Whether the contribution was paid in full.
     */
    function _contribute(
        Round storage _round,
        Party _side,
        uint256 _totalRequired
    ) internal returns (bool paidInFull) {
        uint256 remainingETH;
        uint256 contribution = msg.value;
        uint256 requiredAmount = _totalRequired -
            (_side == Party.Requester ? _round.paidFees.forRequester : _round.paidFees.forChallenger);
        if (requiredAmount <= msg.value) {
            contribution = requiredAmount;
            remainingETH = msg.value - requiredAmount;

            paidInFull = true;
            _round.sideFunded = _round.sideFunded == Party.None ? _side : Party.None;
        }

        if (_side == Party.Requester) {
            _round.contributions[msg.sender].forRequester += contribution;
            _round.paidFees.forRequester += contribution;
        } else {
            _round.contributions[msg.sender].forChallenger += contribution;
            _round.paidFees.forChallenger += contribution;
        }
        _round.feeRewards += contribution;

        if (remainingETH != 0) payable(msg.sender).send(remainingETH);
    }

    /// ====== GETTERS ====== ///

    /** @notice Check if vouch is valid:
     *  - Voucher must own a soul.
     *  - Must not be vouching at the moment.
     *  - Must not be the same with vouched.
     *
     *  @param _voucher Address of the voucher.
     *  @param _vouched Address of the vouched human.
     *  @return Whether vouch is valid or not.
     */
    function _vouchValid(address _voucher, address _vouched) internal view returns (bool) {
        Soul storage voucherSoul = souls[humans[_voucher]];
        return _soulClaimed(voucherSoul) && !voucherSoul.vouching && _vouched != _voucher;
    }

    /** @notice Return the arbitration cost for the arbitratorData.
     *  @param _arbitratorData ArbitratorData from storage to get the arbitration cost for.
     *  @return cost of arbitration.
     */
    function _arbitrationCost(ArbitratorData storage _arbitratorData) internal view returns (uint256) {
        return _arbitratorData.arbitrator.arbitrationCost(_arbitratorData.arbitratorExtraData);
    }

    /** @notice Check whether human has ongoing claim for soul.
     *  @param _human Address of human to check.
     *  @return Whether human has ongoing claim.
     */
    function _noOngoingClaim(address _human) internal view returns (bool) {
        return souls[humans[_human]].claimers[_human] == 0;
    }

    /** @notice Check whether soul is claimed:
     *  - Owner must not be null address.
     *  - Soul must not have expired.
     *
     *  @param _soul Soul struct from storage to check.
     *  @return Whether soul is claimed.
     */
    function _soulClaimed(Soul storage _soul) internal view returns (bool) {
        return _soul.owner != address(0) && _soul.expirationTime >= block.timestamp;
    }

    /** @notice Check whether id corresponds to a claimed soul.
     *  @param _soulId The id of the soul to check.
     *  @return Whether soul is claimed.
     */
    function isSoulClaimed(uint160 _soulId) public view returns (bool) {
        return _soulClaimed(souls[_soulId]);
    }

    /** @notice Return true if the human has a non expired soul.
     *  @param _humanId The address of the human.
     *  @return Whether the human has a valid soul.
     */
    function isRegistered(address _humanId) public view override returns (bool) {
        Soul storage soul = souls[humans[_humanId]];
        return soul.owner == _humanId && soul.expirationTime >= block.timestamp;
    }

    /** @notice Get the number of times the arbitrator data was updated.
     *  @return The number of arbitrator data updates.
     */
    function getArbitratorDataListCount() external view returns (uint256) {
        return arbitratorDataList.length;
    }

    function getSoulInfo(uint160 _soulId)
        external
        view
        override
        returns (
            bool vouching,
            bool pendingRevokal,
            uint64 nbPendingRequests,
            uint64 expirationTime,
            address owner,
            uint256 nbRequests
        )
    {
        Soul storage soul = souls[_soulId];
        return (
            soul.vouching,
            soul.pendingRevokal,
            soul.nbPendingRequests,
            soul.expirationTime,
            soul.owner,
            soul.nbRequests
        );
    }

    function getClaimerRequestId(address _claimer) external view returns (uint256) {
        return souls[humans[_claimer]].claimers[_claimer];
    }

    /** @notice Get information of a request of a soul.
     *  @param _soulId The address of the soul.
     *  @param _requestId The request
     */
    function getRequestInfo(uint160 _soulId, uint256 _requestId)
        external
        view
        returns (
            bool requesterLost,
            uint8 usedReasons,
            uint16 arbitratorDataId,
            uint16 lastChallengeId,
            uint64 challengePeriodEnd,
            address payable requester,
            address payable ultimateChallenger,
            Status status,
            Reason currentReason
        )
    {
        Request storage request = souls[_soulId].requests[_requestId];
        return (
            request.requesterLost,
            request.usedReasons,
            request.arbitratorDataId,
            request.lastChallengeId,
            request.challengePeriodEnd,
            request.requester,
            request.ultimateChallenger,
            request.status,
            request.currentReason
        );
    }

    /** @notice Get the information of a particular challenge of the request.
     *  @param _soulId The queried soul Id.
     *  @param _requestId The request to query.
     *  @param _challengeId The challenge to query.
     *  @return lastRoundId Id of last round.
     *  @return challenger Address that challenged the request.
     *  @return disputeId Id of the dispute related to the challenge.
     *  @return ruling Ruling given by the arbitrator of the dispute.
     */
    function getChallengeInfo(
        uint160 _soulId,
        uint256 _requestId,
        uint256 _challengeId
    )
        external
        view
        returns (
            uint16 lastRoundId,
            address challenger,
            uint256 disputeId,
            Party ruling
        )
    {
        Challenge storage challenge = souls[_soulId].requests[_requestId].challenges[_challengeId];
        return (challenge.lastRoundId, challenge.challenger, challenge.disputeId, challenge.ruling);
    }

    /** @notice Get the information of a round of a request.
     *  @param _soulId The queried soul Id.
     *  @param _requestId The request to query.
     *  @param _challengeId The challenge to query.
     *  @param _round The round to query.
     */
    function getRoundInfo(
        uint160 _soulId,
        uint256 _requestId,
        uint256 _challengeId,
        uint256 _round
    )
        external
        view
        returns (
            bool appealed,
            uint256 feesPaidForRequester,
            uint256 feesPaidForChallenger,
            Party sideFunded,
            uint256 feeRewards
        )
    {
        Challenge storage challenge = souls[_soulId].requests[_requestId].challenges[_challengeId];
        Round storage round = challenge.rounds[_round];
        return (
            _round < (challenge.lastRoundId),
            round.paidFees.forRequester,
            round.paidFees.forChallenger,
            round.sideFunded,
            round.feeRewards
        );
    }

    /** @notice Get the contributions made by a party for a given round of a given challenge of a request.
     *  @param _soulId The soul id.
     *  @param _requestId The request to query.
     *  @param _challengeId the challenge to query.
     *  @param _round The round to query.
     *  @param _contributor The address of the contributor.
     */
    function getContributions(
        uint160 _soulId,
        uint256 _requestId,
        uint256 _challengeId,
        uint256 _round,
        address _contributor
    ) external view returns (uint256 forRequester, uint256 forChallenger) {
        ContributionsSet memory contributions = souls[_soulId]
            .requests[_requestId]
            .challenges[_challengeId]
            .rounds[_round]
            .contributions[_contributor];
        return (contributions.forRequester, contributions.forChallenger);
    }

    /** @notice Get the number of vouches of a particular request.
     *  @param _soulId The Id of the queried human.
     *  @param _requestId The request to query.
     */
    function getNumberOfVouches(uint160 _soulId, uint256 _requestId) external view returns (uint256) {
        return souls[_soulId].requests[_requestId].vouches.length;
    }
}
