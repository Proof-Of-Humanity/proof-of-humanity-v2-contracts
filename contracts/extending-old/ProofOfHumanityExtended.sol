/** @authors: [@andreimvp]
 *  @reviewers: [@unknownunknown1, @shotaronowhere*, @gratestas, Param, @fnanni-0*]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.18;

import "@kleros/erc-792/contracts/IArbitrable.sol";
import "@kleros/erc-792/contracts/erc-1497/IEvidence.sol";
import "@kleros/erc-792/contracts/IArbitrator.sol";

import {IProofOfHumanity} from "../interfaces/IProofOfHumanity.sol";
import {SafeSend} from "../libraries/SafeSend.sol";
import {CappedMath} from "../libraries/CappedMath.sol";

import {IForkModule} from "./ForkModule.sol";

/** @title ProofOfHumanity
 *  This contract is a curated registry for people. The users are identified by their address and can be added or removed through the request-challenge protocol.
 *  In order to challenge a registration request the challenger must provide one of the four reasons.
 *  New registration requests firstly should gain sufficient amount of vouches from other registered users and only after that they can be accepted or challenged.
 *  The users who vouched for a human that lost the challenge with the reason Duplicate or DoesNotExist would be penalized with optional fine or ban period.
 *  @notice This contract trusts that the Arbitrator is honest and will not reenter or modify its costs during a call.
 *  The arbitrator must support appeal period.
 */
contract ProofOfHumanityExtended is IProofOfHumanity, IArbitrable, IEvidence {
    using SafeSend for address payable;
    using CappedMath for uint256;
    using CappedMath for uint40;

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

    /// @notice The EIP-712 typeHash of IsHumanVoucher. keccak256("IsHumanVoucher(address vouched,bytes20 humanityId,uint256 expirationTimestamp)").
    bytes32 private constant _IS_HUMAN_VOUCHER_TYPEHASH =
        0x396b8143cb24d01c85cbad0682e0e83f2ea427a5b3cd56872e8e1b2a55d4c2ab;

    // keccak256("old-proof-of-humanity")
    bytes32 private constant _FORK_MODULE_SLOT = 0x526164fb4adeea0c7815d0240c63ebf772859d7cea21e1bb488e78a2c7deab5b;

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
        Vouching, // Request requires vouches / funding to advance to the next state. Should not be in this state for revocation requests.
        Resolving, // Request is resolving and can be challenged within the time limit.
        Disputed, // Request has been challenged.
        Resolved // Request has been resolved.
    }

    /// ====== STRUCTS ====== ///

    /** @dev A human makes requests to become the owner of the humanity.
     *  @dev Multiple claimers can be in the claiming process at the same time. Only one request can be pending at a time.
     *  @dev Owner must be in this struct in order to know the real owner during renewal process.
     */
    struct Humanity {
        address owner; // Address corresponding to the humanity.
        uint40 expirationTime; // Time when the humanity expires.
        uint40 lastFailedRevocationTime; // Resolution time for last failed revocation request.
        uint16 nbPendingRequests; // Number of pending requests in challenging phase.
        bool vouching; // True if the human used its vouch for another human. This is set back to false once the vouch is processed.
        bool pendingRevocation; // True if the human is in the process of revocation.
        mapping(address => uint256) requestCount; // Mapping of the claimer address to the number of requests at the moment of the claim.
        Request[] requests; // Array of the ids to corresponding requests.
    }

    struct Request {
        bool revocation; // True if the request is a revocation request. False if it is a renewal request.
        Status status; // Current status of the request.
        Reason currentReason; // Current reason a claim request was challenged with. Is left empty for removal requests.
        uint8 usedReasons; // Bitmap of the reasons used by challengers of this request.
        uint16 arbitratorDataId; // Index of the relevant arbitratorData struct. All the arbitrator info is stored in a separate struct to reduce gas cost.
        uint16 lastChallengeId; // Id of the last challenge, which is equal to the total number of challenges for the request.
        uint32 lastProcessedVouch; // Stores the index of the last processed vouch in the array of vouches. It is used for partial processing of the vouches in resolved requests.
        address payable requester; // Address that made the request.
        address payable ultimateChallenger; // Address of the challenger who won a dispute. Users who vouched for the challenged human must pay the fines to this address.
        uint40 challengePeriodStart; // Time when the request can be challenged.
        bool punishedVouch; // True if the requester was punished for bad vouching during a claim request.
        bytes20[] vouches; // Stores the unique Ids of humans that vouched for this request and whose vouches were used in this request.
        mapping(uint256 => Challenge) challenges; // Stores all the challenges of this request. challengeId -> Challenge.
    }

    struct ContributionsSet {
        uint256 forRequester; // Amount of contributions made for the requester.
        uint256 forChallenger; // Amount of contributions made for the challenger.
    }

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
        bytes20 humanityId; // The Id of the humanity involving the disputed request.
    }

    struct ArbitratorData {
        uint96 metaEvidenceUpdates; // The meta evidence to be used in disputes.
        IArbitrator arbitrator; // Address of the trusted arbitrator to solve disputes.
        bytes arbitratorExtraData; // Extra data for the arbitrator.
    }

    struct SignatureVouch {
        uint40 expirationTime; // Time when the signature expires.
        uint8 v; // `v` value of the signature.
        bytes32 r; // `r` value of the signature.
        bytes32 s; // `s` value of the signature.
    }

    /// ====== STORAGE ====== ///

    /// @notice Address of wrapped version of the chain's native currency. WETH-like.
    address public wNative;

    /// @notice Indicates that the contract has been initialized.
    bool public initialized;

    /// @notice The address that can make governance changes to the parameters of the contract.
    address public governor;

    /// @notice The address of the CrossChainProofOfHumanity instance.
    address public crossChainProofOfHumanity;

    /// @notice The base deposit to make a new request for a humanity.
    uint256 public requestBaseDeposit;

    /// @notice Time after which the humanity will no longer be considered claimed. The human has to renew the humanity to refresh it.
    uint40 public humanityLifespan;
    /// @notice  The duration of the period when the registered humanity can be renewed.
    uint40 public renewalPeriodDuration;
    /// @notice The time after which a request becomes executable if not challenged.
    uint40 public challengePeriodDuration;

    /// @notice The time after which a request becomes executable if not challenged.
    uint40 public failedRevocationCooldown;

    /// @notice The number of registered users that have to vouch for a new claim request in order for it to advance beyond Vouching state.
    uint32 public requiredNumberOfVouches;

    /// @notice Multiplier for calculating the fee stake that must be paid in the case where arbitrator refused to arbitrate.
    uint256 public sharedStakeMultiplier;
    /// @notice Multiplier for calculating the fee stake paid by the party that won the previous round.
    uint256 public winnerStakeMultiplier;
    /// @notice Multiplier for calculating the fee stake paid by the party that lost the previous round.
    uint256 public loserStakeMultiplier;

    /// @notice Stores the arbitrator data of the contract. Updated each time the data is changed.
    ArbitratorData[] public arbitratorDataList;

    /// @notice Maps the humanity id to the Humanity data. humanityMapping[humanityId].
    mapping(bytes20 => Humanity) private humanityMapping;

    /// @notice Maps the address to human's humanityId. humans[address].
    mapping(address => bytes20) private humans;

    /// @notice Indicates whether or not the voucher has vouched for a certain human. vouches[voucherAccount][vouchedHumanId][humanityId].
    mapping(address => mapping(address => mapping(bytes20 => bool))) public vouches;
    /// @notice Maps a dispute Id with its data. disputeIdToData[arbitrator][disputeId].
    mapping(address => mapping(uint256 => DisputeData)) public disputeIdToData;

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
        require(msg.sender == crossChainProofOfHumanity);
        _;
    }

    /// ====== EVENTS ====== ///

    event Initialized();
    event GovernorChanged(address governor);
    event RequestBaseDepositChanged(uint256 requestBaseDeposit);
    event DurationsChanged(uint40 humanityLifespan, uint40 renewalPeriodDuration, uint40 challengePeriodDuration);
    event RequiredNumberOfVouchesChanged(uint32 requiredNumberOfVouches);
    event StakeMultipliersChanged(uint256 sharedMultiplier, uint256 winnerMultiplier, uint256 loserMultiplier);
    event CrossChainProxyChanged(address crossChainProofOfHumanity);
    event ArbitratorChanged(IArbitrator arbitrator, bytes arbitratorExtraData);
    event HumanityGrantedManually(bytes20 indexed humanityId, address indexed owner, uint40 expirationTime);
    event HumanityRevokedManually(bytes20 indexed humanityId);
    event ClaimRequest(
        address indexed requester,
        bytes20 indexed humanityId,
        uint256 requestId,
        string evidence,
        string name
    );
    event RenewalRequest(address indexed requester, bytes20 indexed humanityId, uint256 requestId, string evidence);
    event RevocationRequest(address indexed requester, bytes20 indexed humanityId, uint256 requestId, string evidence);
    event VouchAdded(address indexed voucherAccount, address indexed claimer, bytes20 humanityId);
    event VouchRemoved(address indexed voucherAccount, address indexed claimer, bytes20 humanityId);
    event VouchRegistered(bytes20 indexed voucherHumanityId, bytes20 indexed vouchedHumanityId, uint256 requestId);
    event RequestWithdrawn(bytes20 humanityId, uint256 requestId);
    event StateAdvanced(address claimer);
    event RequestChallenged(
        bytes20 humanityId,
        uint256 requestId,
        uint256 challengeId,
        Reason reason,
        uint256 disputeId,
        string evidence
    );
    event HumanityClaimed(bytes20 humanityId, uint256 requestId);
    event HumanityRevoked(bytes20 humanityId, uint256 requestId);
    event VouchesProcessed(bytes20 humanityId, uint256 requestId, uint256 endIndex);
    event ChallengePeriodRestart(bytes20 humanityId, uint256 requestId, uint256 challengeId);
    event AppealCreated(IArbitrator arbitrator, uint256 disputeId);
    event Contribution(
        bytes20 humanityId,
        uint256 requestId,
        uint256 challengeId,
        uint256 round,
        address contributor,
        uint256 contribution,
        Party side
    );
    event FeesAndRewardsWithdrawn(
        bytes20 humanityId,
        uint256 requestId,
        uint256 challengeId,
        uint256 round,
        address beneficiary
    );

    /// ====== INITIALIZATION ====== ///

    /** @notice Initializes the ProofOfHumanity contract.
     *
     *  @dev Emits {MetaEvidence} event for the registration meta evidence.
     *  @dev Emits {MetaEvidence} event for the clearing meta evidence.
     *
     *  @param _wNative The address of the wrapped version of the native currency.
     *  @param _arbitrator The trusted arbitrator to resolve potential disputes.
     *  @param _arbitratorExtraData Extra data for the trusted arbitrator contract.
     *  @param _registrationMetaEvidence The URI of the meta evidence object for registration requests.
     *  @param _clearingMetaEvidence The URI of the meta evidence object for clearing requests.
     *  @param _requestBaseDeposit The base deposit to make a request for a humanity.
     *  @param _humanityLifespan Time in seconds during which the claimed humanity won't automatically lose its status.
     *  @param _renewalPeriodDuration Value that defines the duration of humanity's renewal period.
     *  @param _challengePeriodDuration The time in seconds during which the request can be challenged.
     *  @param _failedRevocationCooldown The time in seconds after which a revocation request can be made after a previously failed one.
     *  @param _multipliers The array that contains fee stake multipliers to avoid 'stack too deep' error.
     *  @param _requiredNumberOfVouches The number of vouches the human has to have to pass from Vouching to Resolving phase.
     */
    function initialize(
        address _wNative,
        IArbitrator _arbitrator,
        bytes memory _arbitratorExtraData,
        string memory _registrationMetaEvidence,
        string memory _clearingMetaEvidence,
        uint256 _requestBaseDeposit,
        uint40 _humanityLifespan,
        uint40 _renewalPeriodDuration,
        uint40 _challengePeriodDuration,
        uint40 _failedRevocationCooldown,
        uint256[3] memory _multipliers,
        uint32 _requiredNumberOfVouches
    ) public initializer {
        wNative = _wNative;
        governor = msg.sender;
        requestBaseDeposit = _requestBaseDeposit;
        humanityLifespan = _humanityLifespan;
        renewalPeriodDuration = _renewalPeriodDuration;
        challengePeriodDuration = _challengePeriodDuration;
        failedRevocationCooldown = _failedRevocationCooldown;
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

    /** @notice Manually grant humanity via cross-chain instance.
     *
     *  @dev Emits {HumanityGrantedManually} event.
     *
     *  @dev Requirements:
     *  - Human must not be in the process of claiming a humanity.
     *  - Humanity must not be claimed.
     *
     *  @param _humanityId Unique id to be added.
     *  @param _account Address owner corresponding to the humanity.
     *  @param _expirationTime Expiration time of the newly added humanity.
     *  @return success Whether the humanity was successfully granted.
     */
    function grantManually(
        bytes20 _humanityId,
        address _account,
        uint40 _expirationTime
    ) external override onlyCrossChain returns (bool success) {
        Humanity storage humanity = humanityMapping[_humanityId];

        if (
            (humanity.owner != address(0x0) && humanity.expirationTime >= block.timestamp) ||
            _getForkModule().isRegistered(_account)
        ) return false;

        // Must not be in the process of claiming a humanity.
        require(humanityMapping[humans[_account]].requestCount[_account] == 0);

        humanity.owner = _account;
        humanity.expirationTime = _expirationTime;
        humans[_account] = _humanityId;

        emit HumanityGrantedManually(_humanityId, _account, _expirationTime);

        return true;
    }

    /** @notice Directly revoke a humanity via cross-chain instance.
     *
     *  @dev Emits {HumanityRevokedManually} event.
     *
     *  @dev Requirements:
     *  - HumanityId must be claimed by someone.
     *  - Owner of the humanity must be _account.
     *  - Humanity must have no pending requests.
     *  - Humanity must not be vouching at the moment.
     *
     *  @param _account Human corresponding to the humanity to be revoked.
     *  @return expirationTime Expiration time of the revoked humanity.
     *  @return humanityId Unique id corresponding to the revoked humanity.
     */
    function revokeManually(
        address _account
    ) external override onlyCrossChain returns (uint40 expirationTime, bytes20 humanityId) {
        humanityId = humans[_account];
        Humanity storage humanity = humanityMapping[humanityId];
        require(humanity.nbPendingRequests == 0);

        if (humanity.owner == _account && humanity.expirationTime >= block.timestamp) {
            require(humanity.expirationTime >= block.timestamp);
            require(humanity.owner == _account);
            require(!humanity.vouching);

            expirationTime = humanity.expirationTime;

            delete humanity.owner;
            delete humans[_account];
        } else {
            humanityId = bytes20(_account);
            expirationTime = _getForkModule().removeForTransfer(_account);
        }

        emit HumanityRevokedManually(humanityId);
    }

    /** @notice Change the governor of the contract.
     *
     *  @dev Emits {GovernorChanged} event.
     *
     *  @param _governor The address of the new governor.
     */
    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
        emit GovernorChanged(_governor);
    }

    /** @notice Change the base amount required as a deposit to make a request for a humanity.
     *
     *  @dev Emits {RequestBaseDepositChanged} event.
     *
     *  @param _requestBaseDeposit The new base amount of wei required to make a new request.
     */
    function changeRequestBaseDeposit(uint256 _requestBaseDeposit) external onlyGovernor {
        requestBaseDeposit = _requestBaseDeposit;
        emit RequestBaseDepositChanged(_requestBaseDeposit);
    }

    /** @notice Change the duration of the humanity lifespan, renewal and challenge periods.
     *
     *  @dev Emits {DurationsChanged} event.
     *
     *  @dev Requirements:
     *  - To ensure correct contract behaviour, the sum of challengePeriodDuration and renewalPeriodDuration should be less than humanityLifespan.
     *
     *  @param _humanityLifespan The new lifespan of the time the humanity is considered registered.
     *  @param _renewalPeriodDuration The new value that defines the duration of the humanity's renewal period.
     *  @param _challengePeriodDuration The new duration of the challenge period. It should be lower than the time for a dispute.
     */
    function changeDurations(
        uint40 _humanityLifespan,
        uint40 _renewalPeriodDuration,
        uint40 _challengePeriodDuration,
        uint40 _failedRevocationCooldown
    ) external onlyGovernor {
        humanityLifespan = _humanityLifespan;
        renewalPeriodDuration = _renewalPeriodDuration;
        challengePeriodDuration = _challengePeriodDuration;
        failedRevocationCooldown = _failedRevocationCooldown;
        emit DurationsChanged(_humanityLifespan, _renewalPeriodDuration, _challengePeriodDuration);
    }

    /** @notice Change the number of vouches required for the request to pass beyond Vouching state.
     *
     *  @dev Emits {RequiredNumberOfVouchesChanged} event.
     *
     *  @param _requiredNumberOfVouches The new required number of vouches.
     */
    function changeRequiredNumberOfVouches(uint32 _requiredNumberOfVouches) external onlyGovernor {
        requiredNumberOfVouches = _requiredNumberOfVouches;
        emit RequiredNumberOfVouchesChanged(_requiredNumberOfVouches);
    }

    /** @notice Change the proportion of arbitration fees that must be paid as fee stake by parties depending on the result of the dispute (e.g. when the arbitrator refused to rule).
     *
     *  @dev Emits {StakeMultipliersChanged} event.
     *
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
    function changeMetaEvidence(
        string calldata _registrationMetaEvidence,
        string calldata _clearingMetaEvidence
    ) external onlyGovernor {
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
     *
     *  @dev Emits {ArbitratorChanged} event.
     *
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
     *
     *  @dev Emits {CrossChainProxyChanged} event.
     *
     *  @param _crossChainProofOfHumanity The new cross-chain instance to be used.
     */
    function changeCrossChainProofOfHumanity(address _crossChainProofOfHumanity) external onlyGovernor {
        crossChainProofOfHumanity = _crossChainProofOfHumanity;
        emit CrossChainProxyChanged(_crossChainProofOfHumanity);
    }

    /** @notice Change old ProofOfHumanity instance.
     *  @param _forkModule Address of old ProofOfHumanity contract.
     */
    function changeForkModule(IForkModule _forkModule) external onlyGovernor {
        assembly {
            sstore(_FORK_MODULE_SLOT, _forkModule)
        }
    }

    /// ====== REQUESTS ====== ///

    /** @notice Making a request to enter the registry. Paying the full deposit right away is not required as it can be crowdfunded later.
     *
     *  @dev Emits {ClaimRequest} event.
     *
     *  @dev Requirements:
     *  - Sender must not own a humanity.
     *  - Humanity corresponding to _humanityId must not be claimed (can be expired).
     *  - Sender must not be in the process of claiming a humanity (covered by _requestHumanity).
     *
     *  @param _humanityId The humanity id the human applies for.
     *  @param _evidence Link to evidence using its URI.
     *  @param _name Name of the human.
     */
    function _claimHumanity(bytes20 _humanityId, string calldata _evidence, string calldata _name) internal {
        Humanity storage humanity = humanityMapping[_humanityId];

        require(!isHuman(msg.sender));
        require(humanity.owner == address(0x0) || block.timestamp > humanity.expirationTime);

        require(_getForkModule().hasLockedState(msg.sender));

        uint256 requestId = _requestHumanity(_humanityId, _evidence);

        emit ClaimRequest(msg.sender, _humanityId, requestId, _evidence, _name);
    }

    /** @notice Make a request to enter the registry. Use default humanity id derived from sender address.
     *
     *  @param _evidence Link to evidence using its URI.
     *  @param _name Name of the human.
     */
    function claimHumanityDefault(string calldata _evidence, string calldata _name) external payable {
        _claimHumanity(bytes20(msg.sender), _evidence, _name);
    }

    /** @notice Make a request to enter the registry. Humanity id to be specified.
     *
     *  @param _humanityId The humanity id the human applies for.
     *  @param _evidence Link to evidence using its URI.
     *  @param _name Name of the human.
     */
    function claimHumanity(bytes20 _humanityId, string calldata _evidence, string calldata _name) external payable {
        require(_humanityId != 0);
        _claimHumanity(_humanityId, _evidence, _name);
    }

    /** @notice Make a request to renew humanity's lifespan. Paying the full deposit right away is not required as it can be crowdfunded later.
     *  @notice The user can reapply even when current lifespan has not expired, but only after the start of renewal period.
     *
     *  @dev Emits {RenewalRequest} event.
     *
     *  @dev Requirements:
     *  - Sender must be current owner of the humanity.
     *  - Current time passed the start of the renewal period for humanity.
     *  - Sender must not be in the process of claiming a humanity (covered by _requestHumanity).
     *
     *  @param _evidence Link to evidence using its URI.
     */
    function renewHumanity(string calldata _evidence) external payable {
        bytes20 humanityId = humans[msg.sender];

        Humanity storage humanity = humanityMapping[humanityId];

        require(humanity.owner == msg.sender);
        require(block.timestamp > humanity.expirationTime.subCap40(renewalPeriodDuration));

        uint256 requestId = _requestHumanity(humanityId, _evidence);

        emit RenewalRequest(msg.sender, humanityId, requestId, _evidence);
    }

    /** @notice Make a request to revoke a humanity.
     *  @notice Accepts enough ETH to cover the deposit, reimburses the rest.
     *  @notice Status of the humanity can be anything to avoid blocking revocations.
     *
     *  @dev Emits {RevocationRequest} event.
     *  @dev Emits {Evidence} event.
     *
     *  @dev Requirements:
     *  - Humanity must be claimed by someone and not expired.
     *  - Humanity must not be pending revocation.
     *  - Deposit must be fully paid.
     *
     *  @param _humanityId The id of the humanity to revoke.
     *  @param _evidence Link to evidence using its URI.
     */
    function revokeHumanity(bytes20 _humanityId, string calldata _evidence) external payable {
        Humanity storage humanity = humanityMapping[_humanityId];

        require(
            (humanity.owner != address(0x0) && humanity.expirationTime >= block.timestamp) ||
                _getForkModule().removalReady(address(_humanityId))
        );
        require(!humanity.pendingRevocation);
        require(block.timestamp > humanity.lastFailedRevocationTime.addCap40(failedRevocationCooldown));

        uint256 requestId = humanity.requests.length;

        Request storage request = humanity.requests.push();
        request.status = Status.Resolving;
        request.revocation = true;
        request.requester = payable(msg.sender);
        request.challengePeriodStart = uint40(block.timestamp);

        uint256 arbitratorDataId = arbitratorDataList.length - 1;
        request.arbitratorDataId = uint16(arbitratorDataId);

        humanity.pendingRevocation = true;
        humanity.nbPendingRequests++;

        ArbitratorData memory arbitratorData = arbitratorDataList[arbitratorDataId];
        uint256 totalCost = arbitratorData.arbitrator.arbitrationCost(arbitratorData.arbitratorExtraData).addCap(
            requestBaseDeposit
        );

        require(_contribute(_humanityId, requestId, 0, 0, Party.Requester, totalCost));

        emit RevocationRequest(msg.sender, _humanityId, requestId, _evidence);

        if (bytes(_evidence).length > 0)
            emit Evidence(arbitratorData.arbitrator, requestId + uint256(uint160(_humanityId)), msg.sender, _evidence);
    }

    /** @notice Fund the requester's deposit. Accepts enough ETH to cover the deposit, reimburses the rest.
     *
     *  @dev Requirements:
     *  - Human must be in the process of claiming a humanity and the request is in Vouching state.
     *
     *  @param _humanityId The humanityId corresponding to the request to fund.
     *  @param _requestId The id of the request to fund.
     */
    function fundRequest(bytes20 _humanityId, uint256 _requestId) external payable {
        Request storage request = humanityMapping[_humanityId].requests[_requestId];
        require(request.status == Status.Vouching);

        ArbitratorData memory arbitratorData = arbitratorDataList[request.arbitratorDataId];
        uint256 totalCost = arbitratorData.arbitrator.arbitrationCost(arbitratorData.arbitratorExtraData).addCap(
            requestBaseDeposit
        );

        _contribute(_humanityId, _requestId, 0, 0, Party.Requester, totalCost);
    }

    /** @notice Vouch that the human corresponds to the humanity id.
     *
     *  @dev Emits {VouchAdded} event.
     *
     *  @param _account The address of the human.
     *  @param _humanityId The humanity id the vouch specifies human corresponds to.
     */
    function addVouch(address _account, bytes20 _humanityId) external {
        vouches[msg.sender][_account][_humanityId] = true;
        emit VouchAdded(msg.sender, _account, _humanityId);
    }

    /** @notice Remove a previously added vouch. Note that the event spam is not an issue as it will be handled by the UI.
     *
     *  @dev Emits {VouchRemoved} event.
     *
     *  @param _account The address of the human.
     *  @param _humanityId The humanity id the vouch specifies human corresponds to.
     */
    function removeVouch(address _account, bytes20 _humanityId) external {
        vouches[msg.sender][_account][_humanityId] = false;
        emit VouchRemoved(msg.sender, _account, _humanityId);
    }

    /** @notice Allow to withdraw a mistakenly added request while it's still in a vouching state.
     *
     *  @dev Emits {RequestWithdrawn} event.
     *
     *  @dev Requirements:
     *  - Sender must be in the process of claiming a humanity and the request is in Vouching state.
     */
    function withdrawRequest() external {
        bytes20 humanityId = humans[msg.sender];
        Humanity storage humanity = humanityMapping[humanityId];
        uint256 requestId = humanity.requestCount[msg.sender] - 1;
        Request storage request = humanity.requests[requestId];
        require(request.status == Status.Vouching);

        delete humanity.requestCount[msg.sender];
        delete humans[msg.sender];
        request.status = Status.Resolved;

        // Automatically withdraw for the requester.
        withdrawFeesAndRewards(payable(msg.sender), humanityId, requestId, 0, 0);

        emit RequestWithdrawn(humanityId, requestId);
    }

    /** @notice Change human's phase from Vouching to Resolving if all conditions are met.
     *
     *  @dev Emits {VouchRegistered} event.
     *  @dev Emits {StateAdvanced} event.
     *
     *  @dev Requirements:
     *  - Request must be in Vouching state.
     *  - Humanity must not be claimed.
     *  - Requester must have the deposit covered.
     *  - Provided signatures must be valid.
     *  - Number of aggregated vouches must be at least required number of vouches.
     *
     *  @dev EIP-712:
     *  struct IsHumanVoucher {
     *      address vouchedHuman;
     *      bytes20 vouchedForHumanity;
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
        bytes20 humanityId = humans[_claimer];
        Humanity storage humanity = humanityMapping[humanityId];
        uint256 requestId = humanity.requestCount[_claimer] - 1;
        Request storage request = humanity.requests[requestId];
        require(request.status == Status.Vouching);
        require(
            humanity.owner == address(0x0) || block.timestamp > humanity.expirationTime.subCap40(renewalPeriodDuration)
        );
        require(request.challenges[0].rounds[0].sideFunded == Party.Requester);

        address voucherAccount;
        Humanity storage voucherHumanity;
        uint256 i = 0;
        uint256 requiredVouches = requiredNumberOfVouches;
        while (request.vouches.length < requiredVouches) {
            bool isValid;
            if (i < _signatureVouches.length) {
                SignatureVouch memory signature = _signatureVouches[i];
                require(signature.s <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0);

                voucherAccount = ecrecover(
                    keccak256(
                        abi.encodePacked(
                            "\x19\x01",
                            _DOMAIN_SEPARATOR,
                            keccak256(
                                abi.encode(_IS_HUMAN_VOUCHER_TYPEHASH, _claimer, humanityId, signature.expirationTime)
                            )
                        )
                    ),
                    signature.v,
                    signature.r,
                    signature.s
                );

                isValid = block.timestamp < signature.expirationTime;
            } else {
                // Overflows if the end of _vouches has been reached and not enough valid vouches were gathered.
                voucherAccount = _vouches[i - _signatureVouches.length];

                isValid = vouches[voucherAccount][_claimer][humanityId];
            }

            if (isValid) {
                bytes20 voucherHumanityId = humanityOf(voucherAccount);
                voucherHumanity = humanityMapping[voucherHumanityId];
                if (
                    ((voucherHumanity.owner == voucherAccount &&
                        voucherHumanity.expirationTime >= block.timestamp &&
                        !voucherHumanity.vouching) || _getForkModule().vouchReady(voucherAccount)) &&
                    voucherAccount != _claimer
                ) {
                    request.vouches.push(voucherHumanityId);
                    voucherHumanity.vouching = true;

                    emit VouchRegistered(voucherHumanityId, humanityId, requestId);
                }
            }

            unchecked {
                i++;
            }
        }

        humanity.nbPendingRequests++;
        request.status = Status.Resolving;
        request.challengePeriodStart = uint40(block.timestamp);

        emit StateAdvanced(_claimer);
    }

    /** @notice Challenge the human's request. Accept enough ETH to cover the deposit, reimburse the rest.
     *
     *  @dev Emits {RequestChallenged} event.
     *  @dev Emits {Dispute} event.
     *  @dev Emits {Evidence} event.
     *
     *  @dev Requirements:
     *  - Humanity must be in claiming/revoking phase.
     *  - If there is a revocation request, reason must be None.
     *  - If there is a claim request, reason must not be None.
     *  - Request must be in resolving state.
     *  - Must be challenge period for the request.
     *  - Reason must not have been used for this request.
     *  - Challenger side must be fully paid.
     *
     *  @param _humanityId Id of the humanity the request to challenge corresponds to.
     *  @param _requestId Id of the request to challenge.
     *  @param _reason Reason to challenge the request.
     *  @param _evidence Link to evidence using its URI. Ignored if not provided.
     */
    function challengeRequest(
        bytes20 _humanityId,
        uint256 _requestId,
        Reason _reason,
        string calldata _evidence
    ) external payable {
        Request storage request = humanityMapping[_humanityId].requests[_requestId];
        require(request.revocation == (_reason == Reason.None));
        require(request.status == Status.Resolving);
        require(request.challengePeriodStart + challengePeriodDuration >= uint40(block.timestamp));

        if (!request.revocation) {
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

        uint256 challengeId = request.lastChallengeId++;
        Challenge storage challenge = request.challenges[challengeId];
        Round storage round = challenge.rounds[0];

        ArbitratorData memory arbitratorData = arbitratorDataList[request.arbitratorDataId];
        uint256 arbitrationCost = arbitratorData.arbitrator.arbitrationCost(arbitratorData.arbitratorExtraData);
        require(_contribute(_humanityId, _requestId, challengeId, 0, Party.Challenger, arbitrationCost));
        round.feeRewards = round.feeRewards.subCap(arbitrationCost);

        uint256 disputeId = arbitratorData.arbitrator.createDispute{value: arbitrationCost}(
            _RULING_OPTIONS,
            arbitratorData.arbitratorExtraData
        );
        challenge.disputeId = disputeId;
        challenge.challenger = payable(msg.sender);
        challenge.lastRoundId++;

        DisputeData storage disputeData = disputeIdToData[address(arbitratorData.arbitrator)][disputeId];
        disputeData.humanityId = _humanityId;
        disputeData.requestId = uint96(_requestId);
        disputeData.challengeId = uint96(challengeId);

        request.status = Status.Disputed;

        emit RequestChallenged(_humanityId, _requestId, challengeId, _reason, disputeId, _evidence);

        uint256 evidenceGroupId = _requestId + uint256(uint160(_humanityId));

        emit Dispute(
            arbitratorData.arbitrator,
            challenge.disputeId,
            2 * arbitratorData.metaEvidenceUpdates + (request.revocation ? 1 : 0),
            evidenceGroupId
        );

        if (bytes(_evidence).length > 0)
            emit Evidence(arbitratorData.arbitrator, evidenceGroupId, msg.sender, _evidence);
    }

    /** @notice Take up to the total amount required to fund a side of an appeal. Reimburse the rest. Create an appeal if both sides are fully funded.
     *
     *  @dev Emits {AppealCreated} event.
     *
     *  @dev Requirements:
     *  - Side funded must be either requester or challenger.
     *  - Request must be disputed.
     *  - Challenge id must be valid.
     *  - Must be appeal period.
     *  - Appeal period must not be over for loser.
     *  - Must fund a non-funded side.
     *
     *  @param _humanityId Id corresponding to humanity of which request to fund.
     *  @param _requestId Id of the request.
     *  @param _challengeId Index of a dispute, created for the request.
     *  @param _side Recipient of the contribution.
     */
    function fundAppeal(bytes20 _humanityId, uint256 _requestId, uint256 _challengeId, Party _side) external payable {
        require(_side != Party.None);
        Request storage request = humanityMapping[_humanityId].requests[_requestId];
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

        uint256 appealCost = arbitratorData.arbitrator.appealCost(
            challenge.disputeId,
            arbitratorData.arbitratorExtraData
        );
        uint256 totalCost = appealCost.addCap(appealCost.mulCap(multiplier) / _MULTIPLIER_DIVISOR);

        if (_contribute(_humanityId, _requestId, _challengeId, challenge.lastRoundId, _side, totalCost)) {
            if (firstFunded != Party.None) {
                // Both sides are fully funded. Create an appeal.
                arbitratorData.arbitrator.appeal{value: appealCost}(
                    challenge.disputeId,
                    arbitratorData.arbitratorExtraData
                );
                challenge.lastRoundId++;
                round.feeRewards = round.feeRewards.subCap(appealCost);

                emit AppealCreated(arbitratorData.arbitrator, challenge.disputeId);
            }
        }
    }

    /** @notice Execute a request if the challenge period passed and no one challenged the request.
     *
     *  @dev Emits {HumanityClaimed} event.
     *  @dev Emits {HumanityRevoked} event.
     *
     *  @dev Requirements:
     *  - Request must be in resolving state.
     *  - Challenge period must have ended.
     *
     *  @param _humanityId Id of the humanity the request to execute corresponds to.
     *  @param _requestId Id of the request to execute.
     */
    function executeRequest(bytes20 _humanityId, uint256 _requestId) external {
        Humanity storage humanity = humanityMapping[_humanityId];
        Request storage request = humanity.requests[_requestId];
        require(request.status == Status.Resolving);
        require(request.challengePeriodStart + challengePeriodDuration < uint40(block.timestamp));

        if (request.revocation) {
            if (humanity.owner != address(0x0) && humanity.expirationTime >= block.timestamp) {
                delete humanity.owner;
                delete humans[humanity.owner];
                humanity.pendingRevocation = false;
            } else _getForkModule().removeFromRequest(address(_humanityId));

            emit HumanityRevoked(_humanityId, _requestId);
        } else if (!request.punishedVouch) {
            humanity.owner = request.requester;
            humanity.expirationTime = uint40(block.timestamp).addCap40(humanityLifespan);

            emit HumanityClaimed(_humanityId, _requestId);
        }

        humanity.nbPendingRequests--;
        request.status = Status.Resolved;
        delete humanity.requestCount[request.requester];

        if (request.vouches.length != 0) processVouches(_humanityId, _requestId, _AUTO_PROCESSED_VOUCH);

        withdrawFeesAndRewards(request.requester, _humanityId, _requestId, 0, 0); // Automatically withdraw for the requester.
    }

    /** @notice Process vouches of the resolved request, so vouchings of users who vouched for it can be used for other humans.
     *  @notice Users who vouched for bad humanity requests are penalized.
     *
     *  @dev Emits {VouchesProcessed} event.
     *  @dev Emits {HumanityRevokedManually} event.
     *
     *  @dev Requirements:
     *  - Request must be resolved.
     *
     *  @param _humanityId Id of the humanity for which the request was made.
     *  @param _requestId Id of request for which vouches to iterate.
     *  @param _iterations Number of iterations to go through.
     */
    function processVouches(bytes20 _humanityId, uint256 _requestId, uint256 _iterations) public {
        Request storage request = humanityMapping[_humanityId].requests[_requestId];
        require(request.status == Status.Resolved);

        uint256 lastProcessed = request.lastProcessedVouch;
        uint256 endIndex = _iterations.addCap(lastProcessed);
        uint256 vouchCount = request.vouches.length;

        if (endIndex > vouchCount) endIndex = vouchCount;

        Reason currentReason = request.currentReason;
        bool applyPenalty = request.ultimateChallenger != address(0x0) &&
            (currentReason == Reason.Duplicate || currentReason == Reason.DoesNotExist);

        while (lastProcessed < endIndex) {
            bytes20 voucherHumanityId = request.vouches[lastProcessed];
            Humanity storage voucherHumanity = humanityMapping[voucherHumanityId];
            voucherHumanity.vouching = false;
            if (applyPenalty) {
                if (voucherHumanity.owner != address(0x0) && voucherHumanity.expirationTime >= block.timestamp) {
                    // Check the situation when vouching address is in the middle of renewal process.
                    uint256 voucherRequestId = voucherHumanity.requestCount[voucherHumanity.owner] - 1;
                    if (voucherRequestId != 0) voucherHumanity.requests[voucherRequestId].punishedVouch = true;

                    delete voucherHumanity.owner;
                } else _getForkModule().removeFromRequest(address(voucherHumanityId));

                emit HumanityRevokedManually(voucherHumanityId);
            }

            unchecked {
                lastProcessed++;
            }
        }

        request.lastProcessedVouch = uint32(endIndex);

        emit VouchesProcessed(_humanityId, _requestId, endIndex);
    }

    /** @notice Reimburse contributions if no disputes were raised. If a dispute was raised, send the fee stake rewards and reimbursements proportionally to the contributions made to the winner of a dispute.
     *
     *  @dev Emits {FeesAndRewardsWithdrawn} event.
     *
     *  @dev Requirements:
     *  - Request must be resolved.
     *  - Beneficiary must not be null address.
     *
     *  @param _beneficiary The address that made contributions to a request.
     *  @param _humanityId Id of humanity the request was for.
     *  @param _requestId The request from which to withdraw.
     *  @param _challengeId The Id of the challenge from which to withdraw.
     *  @param _round The round from which to withdraw.
     */
    function withdrawFeesAndRewards(
        address payable _beneficiary,
        bytes20 _humanityId,
        uint256 _requestId,
        uint256 _challengeId,
        uint256 _round
    ) public {
        Request storage request = humanityMapping[_humanityId].requests[_requestId];
        Challenge storage challenge = request.challenges[_challengeId];
        Round storage round = challenge.rounds[_round];
        require(request.status == Status.Resolved);
        require(_beneficiary != address(0x0));

        Party ruling = challenge.ruling;
        uint256 reward = 0;
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
            uint256 paidFees = ruling == Party.Requester ? round.paidFees.forRequester : round.paidFees.forChallenger;
            if (paidFees > 0)
                reward =
                    ((
                        ruling == Party.Requester
                            ? beneficiaryContributions.forRequester
                            : beneficiaryContributions.forChallenger
                    ) * round.feeRewards) /
                    paidFees;
        }

        beneficiaryContributions.forRequester = 0;
        beneficiaryContributions.forChallenger = 0;
        _beneficiary.safeSend(reward, wNative);

        emit FeesAndRewardsWithdrawn(_humanityId, _requestId, _challengeId, _round, _beneficiary);
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
     *  - Request must be disputed.
     *
     *  @param _disputeId Id of the dispute in the arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator.
     */
    function rule(uint256 _disputeId, uint256 _ruling) external override {
        Party resultRuling = Party(_ruling);
        DisputeData storage disputeData = disputeIdToData[msg.sender][_disputeId];
        Humanity storage humanity = humanityMapping[disputeData.humanityId];
        Request storage request = humanity.requests[disputeData.requestId];
        Challenge storage challenge = request.challenges[disputeData.challengeId];
        Round storage round = challenge.rounds[challenge.lastRoundId];

        require(address(arbitratorDataList[request.arbitratorDataId].arbitrator) == msg.sender);
        require(request.status == Status.Disputed);

        // The ruling is inverted if the loser paid its fees.
        if (round.sideFunded == Party.Requester)
            // If one side paid its fees, the ruling is in its favor. Note that if the other side had also paid, an appeal would have been created.
            resultRuling = Party.Requester;
        else if (round.sideFunded == Party.Challenger) resultRuling = Party.Challenger;

        // Store the rulings of each dispute for correct distribution of rewards.
        challenge.ruling = resultRuling;

        emit Ruling(IArbitrator(msg.sender), _disputeId, uint256(resultRuling));

        if (request.revocation) {
            humanity.pendingRevocation = false;

            if (resultRuling == Party.Requester) {
                if (humanity.owner != address(0x0) && humanity.expirationTime >= block.timestamp) {
                    delete humanity.owner;
                    delete humans[humanity.owner];
                } else _getForkModule().removeFromRequest(address(disputeData.humanityId));

                emit HumanityRevoked(disputeData.humanityId, disputeData.requestId);
            } else humanity.lastFailedRevocationTime = uint40(block.timestamp);
        } else {
            // For a claim request there can be more than one dispute.
            if (resultRuling == Party.Requester) {
                if (!request.punishedVouch) {
                    // All reasons being used means the request can't be challenged again, so we can update its status.
                    if (request.usedReasons == _FULL_REASONS_SET) {
                        humanity.owner = request.requester;
                        humanity.expirationTime = uint40(block.timestamp).addCap40(humanityLifespan);

                        emit HumanityClaimed(disputeData.humanityId, disputeData.requestId);
                    } else {
                        // Refresh the state of the request so it can be challenged again.
                        request.status = Status.Resolving;
                        request.challengePeriodStart = uint40(block.timestamp);
                        request.currentReason = Reason.None;

                        emit ChallengePeriodRestart(
                            disputeData.humanityId,
                            disputeData.requestId,
                            disputeData.challengeId
                        );

                        return;
                    }
                }
                // Challenger won or it’s a tie.
            } else if (resultRuling == Party.Challenger) request.ultimateChallenger = challenge.challenger;
        }

        humanity.nbPendingRequests--;
        request.status = Status.Resolved;
        delete humanity.requestCount[request.requester];
    }

    /** @notice Submit a reference to evidence.
     *
     *  @dev Emits {Evidence} event.
     *
     *  @dev Requirements:
     *  - Must be valid request.
     *
     *  @param _humanityId Id of humanity the request is for.
     *  @param _requestId Id of request the evidence is related to.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(bytes20 _humanityId, uint256 _requestId, string calldata _evidence) external {
        emit Evidence(
            arbitratorDataList[humanityMapping[_humanityId].requests[_requestId].arbitratorDataId].arbitrator,
            _requestId + uint256(uint160(_humanityId)),
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
     *  @param _humanityId Id of the humanity the request is for.
     *  @param _evidence A link to evidence using its URI.
     *  @return requestId Id of the created request.
     */
    function _requestHumanity(bytes20 _humanityId, string calldata _evidence) internal returns (uint256 requestId) {
        // Human must not be in the process of claiming a humanity.
        require(humanityMapping[humans[msg.sender]].requestCount[msg.sender] == 0);

        Humanity storage humanity = humanityMapping[_humanityId];

        requestId = humanity.requests.length;

        Request storage request = humanity.requests.push();
        request.requester = payable(msg.sender);

        uint256 arbitratorDataId = arbitratorDataList.length - 1;
        request.arbitratorDataId = uint16(arbitratorDataId);

        humanity.requestCount[msg.sender] = requestId + 1;
        humans[msg.sender] = _humanityId;

        ArbitratorData memory arbitratorData = arbitratorDataList[arbitratorDataId];
        uint256 totalCost = arbitratorData.arbitrator.arbitrationCost(arbitratorData.arbitratorExtraData).addCap(
            requestBaseDeposit
        );
        _contribute(_humanityId, requestId, 0, 0, Party.Requester, totalCost);

        if (bytes(_evidence).length > 0)
            emit Evidence(arbitratorData.arbitrator, requestId + uint256(uint160(_humanityId)), msg.sender, _evidence);
    }

    /** @notice Make a fee contribution.
     *  @param _humanityId .
     *  @param _requestId .
     *  @param _challengeId .
     *  @param _roundId Round to contribute to.
     *  @param _side Side to contribute to.
     *  @param _totalRequired Total amount required for this side.
     *  @return paidInFull Whether the contribution was paid in full.
     */
    function _contribute(
        bytes20 _humanityId,
        uint256 _requestId,
        uint256 _challengeId,
        uint256 _roundId,
        Party _side,
        uint256 _totalRequired
    ) internal returns (bool paidInFull) {
        Round storage round = humanityMapping[_humanityId].requests[_requestId].challenges[_challengeId].rounds[
            _roundId
        ];

        uint256 remainingETH = 0;
        uint256 contribution = msg.value;
        uint256 requiredAmount = _totalRequired.subCap(
            _side == Party.Requester ? round.paidFees.forRequester : round.paidFees.forChallenger
        );
        if (requiredAmount <= msg.value) {
            contribution = requiredAmount;
            remainingETH = msg.value - requiredAmount;

            paidInFull = true;
            round.sideFunded = round.sideFunded == Party.None ? _side : Party.None;
        }

        if (_side == Party.Requester) {
            round.contributions[msg.sender].forRequester += contribution;
            round.paidFees.forRequester += contribution;
        } else {
            round.contributions[msg.sender].forChallenger += contribution;
            round.paidFees.forChallenger += contribution;
        }
        round.feeRewards += contribution;

        emit Contribution(_humanityId, _requestId, _challengeId, _roundId, msg.sender, contribution, _side);

        if (remainingETH != 0) payable(msg.sender).safeSend(remainingETH, wNative);
    }

    /// ====== GETTERS ====== ///

    function _getForkModule() internal view returns (IForkModule oldPoH) {
        assembly {
            oldPoH := sload(_FORK_MODULE_SLOT)
        }
    }

    /** @notice Check whether humanity is claimed or not.
     *  @param _humanityId The id of the humanity to check.
     *  @return Whether humanity is claimed.
     */
    function isClaimed(bytes20 _humanityId) external view override returns (bool) {
        Humanity storage humanity = humanityMapping[_humanityId];
        return
            (humanity.owner != address(0x0) && humanity.expirationTime >= block.timestamp) ||
            _getForkModule().isRegistered(address(_humanityId));
    }

    /** @notice Return true if the human has a claimed humanity.
     *  @param _account The address of the human.
     *  @return Whether the human has a valid humanity.
     */
    function isHuman(address _account) public view override returns (bool) {
        Humanity storage humanity = humanityMapping[humans[_account]];
        return
            (humanity.owner == _account && humanity.expirationTime >= block.timestamp) ||
            _getForkModule().isRegistered(_account);
    }

    /** @notice Get the owner of a humanity.
     *  @param _humanityId The id of the humanity.
     *  @return account The owner of the humanity.
     */
    function boundTo(bytes20 _humanityId) external view returns (address) {
        Humanity storage humanity = humanityMapping[_humanityId];
        if (humanity.owner != address(0x0) && humanity.expirationTime >= block.timestamp) return humanity.owner;
        if (_getForkModule().isRegistered(address(_humanityId))) return address(_humanityId);
        return address(0x0);
    }

    /** @notice Get the humanity corresponding to an address. Returns zero address if it corresponds to no humanity.
     *  @param _account The address to get the correspding humanity of.
     *  @return humanityId The humanity corresponding to the address.
     */
    function humanityOf(address _account) public view returns (bytes20 humanityId) {
        humanityId = humans[_account];
        Humanity storage humanity = humanityMapping[humanityId];
        if (humanity.owner != _account || block.timestamp > humanity.expirationTime) {
            if (_getForkModule().isRegistered(_account)) humanityId = bytes20(_account);
            else humanityId = bytes20(0x0);
        }
    }

    /** @notice Get the number of times the arbitrator data was updated.
     *  @return The number of arbitrator data updates.
     */
    function getArbitratorDataListCount() external view returns (uint256) {
        return arbitratorDataList.length;
    }

    /** @notice Get info about the humanity.
     *  @param _humanityId The ID of the humanity to get info about.
     */
    function getHumanityInfo(
        bytes20 _humanityId
    )
        external
        view
        override
        returns (
            bool vouching,
            bool pendingRevocation,
            uint48 nbPendingRequests,
            uint40 expirationTime,
            address owner,
            uint256 nbRequests
        )
    {
        Humanity storage humanity = humanityMapping[_humanityId];
        bool registeredOnV1 = false;
        owner = address(_humanityId);
        (registeredOnV1, expirationTime) = _getForkModule().getSubmissionInfo(owner);
        if (!registeredOnV1) {
            owner = humanity.owner;
            expirationTime = humanity.expirationTime;
        }
        vouching = humanity.vouching;
        nbPendingRequests = humanity.nbPendingRequests;
        nbRequests = humanity.requests.length;
        pendingRevocation = humanity.pendingRevocation;
    }

    /** @notice Get request ID of a claimer.
     *  @param _claimer Address of the claimer.
     */
    function getClaimerRequestId(address _claimer) external view returns (uint256) {
        return humanityMapping[humans[_claimer]].requestCount[_claimer] - 1;
    }

    /** @notice Get information of a request of a humanity.
     *  @param _humanityId The address of the humanity.
     *  @param _requestId The request
     */
    function getRequestInfo(
        bytes20 _humanityId,
        uint256 _requestId
    )
        external
        view
        returns (
            bool punishedVouch,
            uint8 usedReasons,
            uint16 arbitratorDataId,
            uint16 lastChallengeId,
            uint40 challengePeriodStart,
            address payable requester,
            address payable ultimateChallenger,
            Status status,
            Reason currentReason
        )
    {
        Request storage request = humanityMapping[_humanityId].requests[_requestId];
        return (
            request.punishedVouch,
            request.usedReasons,
            request.arbitratorDataId,
            request.lastChallengeId,
            request.challengePeriodStart,
            request.requester,
            request.ultimateChallenger,
            request.status,
            request.currentReason
        );
    }

    /** @notice Get the information of a particular challenge of the request.
     *  @param _humanityId The queried humanity Id.
     *  @param _requestId The request to query.
     *  @param _challengeId The challenge to query.
     *  @return lastRoundId Id of last round.
     *  @return challenger Address that challenged the request.
     *  @return disputeId Id of the dispute related to the challenge.
     *  @return ruling Ruling given by the arbitrator of the dispute.
     */
    function getChallengeInfo(
        bytes20 _humanityId,
        uint256 _requestId,
        uint256 _challengeId
    ) external view returns (uint16 lastRoundId, address challenger, uint256 disputeId, Party ruling) {
        Challenge storage challenge = humanityMapping[_humanityId].requests[_requestId].challenges[_challengeId];
        return (challenge.lastRoundId, challenge.challenger, challenge.disputeId, challenge.ruling);
    }

    /** @notice Get the information of a round of a request.
     *  @param _humanityId The queried humanity Id.
     *  @param _requestId The request to query.
     *  @param _challengeId The challenge to query.
     *  @param _round The round to query.
     */
    function getRoundInfo(
        bytes20 _humanityId,
        uint256 _requestId,
        uint256 _challengeId,
        uint256 _round
    )
        external
        view
        returns (
            bool appealed,
            uint256 paidFeesRequester,
            uint256 paidFeesChallenger,
            Party sideFunded,
            uint256 feeRewards
        )
    {
        Challenge storage challenge = humanityMapping[_humanityId].requests[_requestId].challenges[_challengeId];
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
     *  @param _humanityId The humanity id.
     *  @param _requestId The request to query.
     *  @param _challengeId the challenge to query.
     *  @param _round The round to query.
     *  @param _contributor The address of the contributor.
     */
    function getContributions(
        bytes20 _humanityId,
        uint256 _requestId,
        uint256 _challengeId,
        uint256 _round,
        address _contributor
    ) external view returns (uint256 forRequester, uint256 forChallenger) {
        ContributionsSet memory contributions = humanityMapping[_humanityId]
            .requests[_requestId]
            .challenges[_challengeId]
            .rounds[_round]
            .contributions[_contributor];
        return (contributions.forRequester, contributions.forChallenger);
    }

    /** @notice Get the number of vouches of a particular request.
     *  @param _humanityId The Id of the queried human.
     *  @param _requestId The request to query.
     */
    function getNumberOfVouches(bytes20 _humanityId, uint256 _requestId) external view returns (uint256) {
        return humanityMapping[_humanityId].requests[_requestId].vouches.length;
    }
}
