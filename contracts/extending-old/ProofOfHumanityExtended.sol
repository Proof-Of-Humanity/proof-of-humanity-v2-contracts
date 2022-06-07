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

import {CappedMath} from "../utils/libraries/CappedMath.sol";
import {IProofOfHumanityOld} from "../interfaces/IProofOfHumanityOld.sol";
import {IProofOfHumanity} from "../interfaces/IProofOfHumanity.sol";

import {Phase} from "../utils/enums/Phase.sol";
import {Status} from "../utils/enums/Status.sol";
import {Party} from "../utils/enums/Party.sol";
import {Reason} from "../utils/enums/Reason.sol";
import {OldStatus} from "../utils/enums/OldStatus.sol";

/** @title ProofOfHumanity
 *  This contract is a curated registry for people. The users are identified by their address and can be added or removed through the request-challenge protocol.
 *  In order to challenge a registration request the challenger must provide one of the four reasons.
 *  New registration requests firstly should gain sufficient amount of vouches from other registered users and only after that they can be accepted or challenged.
 *  The users who vouched for a human that lost the challenge with the reason Duplicate or DoesNotExist would be penalized with optional fine or ban period.
 *  NOTE: This contract trusts that the Arbitrator is honest and will not reenter or modify its costs during a call.
 *  The arbitrator must support appeal period.
 */
contract ProofOfHumanityExtended is IProofOfHumanity, IArbitrable, IEvidence {
    using CappedMath for uint256;
    using CappedMath for uint64;

    /* Constants and immutable */

    uint256 private constant _RULING_OPTIONS = 2; // The amount of non 0 choices the arbitrator can give.
    uint256 private constant _AUTO_PROCESSED_VOUCH = 10; // The number of vouches that will be automatically processed when executing a request.
    uint256 private constant _FULL_REASONS_SET = 15; // Indicates that reasons' bitmap is full. 0b1111.
    uint256 private constant _MULTIPLIER_DIVISOR = 10000; // Divisor parameter for multipliers.

    bytes32 private _DOMAIN_SEPARATOR; // The EIP-712 domainSeparator specific to this deployed instance. It is used to verify the IsHumanVoucher's signature.
    bytes32 private constant _IS_HUMAN_VOUCHER_TYPEHASH =
        0xa9e3fa1df5c3dbef1e9cfb610fa780355a0b5e0acb0fa8249777ec973ca789dc; // The EIP-712 typeHash of IsHumanVoucher. keccak256("IsHumanVoucher(address vouchedSubmission,uint256 voucherExpirationTimestamp)").

    // keccak256("old-proof-of-humanity")
    bytes32 private constant _OLD_POH_SLOT = 0x526164fb4adeea0c7815d0240c63ebf772859d7cea21e1bb488e78a2c7deab5b;

    /* Structs */

    // Soul corresponding to a soul id.
    // A human makes requests to become the owner of the soul.
    // When someone passes the vouching phase, and the soul has no status, it puts the soul in Resolving status.
    // Anyone can request the revokal of the soul, putting it in the Revoking status.
    // Multiple submitters can be in vouching phase for the same soul. Once one of them advances to Claiming phase, it locks the soul for the others to advance to that stage.
    struct Soul {
        uint64 claimTime; // The time when the soul was last claimed.
        address owner; // The address corresponding to the soul.
        Status status; // Current status of the soul: None / Resolving / Revoking.
        Request[] requests; // List of change requests made for the soul.
    }

    struct Human {
        bool isVouching; // True if the human used its vouch for another human. This is set back to false once the vouch is processed.
        uint160 soulID; // The soul ID the human made last request for.
        uint256 lastRequestID; // The last request ID for the corresponding soul.
        Phase phase; // Current phase of the human: None / Vouching / Claiming
    }

    struct Request {
        bool disputed; // True if a dispute was raised. Note that the request can enter disputed state multiple times, once per reason.
        bool resolved; // True if the request is executed and/or all raised disputes are resolved.
        bool requesterLost; // True if the requester has already had a dispute that wasn't ruled in his favor.
        uint8 usedReasons; // Bitmap of the reasons used by challengers of this request.
        uint16 arbitratorDataID; // The index of the relevant arbitratorData struct. All the arbitrator info is stored in a separate struct to reduce gas cost.
        uint16 lastChallengeID; // The ID of the last challenge, which is equal to the total number of challenges for the request.
        uint32 lastProcessedVouch; // Stores the index of the last processed vouch in the array of vouches. It is used for partial processing of the vouches in resolved requests.
        uint64 challengePeriodStart; // Time when the request can be challenged.
        Reason currentReason; // Current reason a registration request was challenged with. Is left empty for removal requests.
        address payable requester; // Address that made the request.
        address payable ultimateChallenger; // Address of the challenger who won a dispute. Users who vouched for the challenged human must pay the fines to this address.
        address[] vouches; // Stores the unique IDs of humans that vouched for this request and whose vouches were used in this request.
        mapping(uint256 => Challenge) challenges; // Stores all the challenges of this request. challengeID -> Challenge.
    }

    // Some arrays below have 3 elements to map with the Party enums for better readability:
    // - 0: is unused, matches `Party.None`.
    // - 1: for `Party.Requester`.
    // - 2: for `Party.Challenger`.
    struct Round {
        Party sideFunded; // Stores the side that successfully paid the appeal fees in the latest round. Note that if both sides have paid a new round is created.
        uint256 feeRewards; // Sum of reimbursable fees and stake rewards available to the parties that made contributions to the side that ultimately wins a dispute.
        uint256[3] paidFees; // Tracks the fees paid by each side in this round.
        mapping(address => uint256[3]) contributions; // Maps contributors to their contributions for each side.
    }

    struct Challenge {
        uint16 lastRoundID; // The ID of the last round.
        Party ruling; // Ruling given by the arbitrator of the dispute.
        uint256 disputeID; // The ID of the dispute related to the challenge.
        address payable challenger; // Address that challenged the request.
        mapping(uint256 => Round) rounds; // Tracks the info of each funding round of the challenge.
    }

    // The data tied to the arbitrator that will be needed to recover the info for arbitrator's call.
    struct DisputeData {
        uint96 requestID; // The ID of the request.
        uint96 challengeID; // The ID of the challenge of the request.
        uint160 soulID; // The ID of the soul involving the disputed request.
    }

    struct ArbitratorData {
        uint96 metaEvidenceUpdates; // The meta evidence to be used in disputes.
        IArbitrator arbitrator; // Address of the trusted arbitrator to solve disputes.
        bytes arbitratorExtraData; // Extra data for the arbitrator.
    }

    /* Storage */

    bool public initialized; // Indicates that the contract has been initialized.
    address public governor; // The address that can make governance changes to the parameters of the contract.

    address public crossChainProofOfHumanity; // The address of the CrossChainProofOfHumanity instance.

    uint256 public requestBaseDeposit; // The base deposit to make a new request for a soul.

    // Note that to ensure correct contract behaviour the sum of challengePeriodDuration and renewalPeriodDuration should be less than soulLifespan.
    uint64 public override soulLifespan; // Time after which the soul will no longer be considered claimed. The human has to renew the soul to refresh it.
    uint64 public renewalPeriodDuration; //  The duration of the period when the registered soul can be renewd.
    uint64 public challengePeriodDuration; // The time after which a request becomes executable if not challenged.

    uint64 public requiredNumberOfVouches; // The number of registered users that have to vouch for a new registration request in order for it to enter PendingAcceptance state.

    uint256 public sharedStakeMultiplier; // Multiplier for calculating the fee stake that must be paid in the case where arbitrator refused to arbitrate.
    uint256 public winnerStakeMultiplier; // Multiplier for calculating the fee stake paid by the party that won the previous round.
    uint256 public loserStakeMultiplier; // Multiplier for calculating the fee stake paid by the party that lost the previous round.

    uint256 public soulsCounter; // The total count of all souls that were claimed at some point. Includes manually granted souls as well.

    ArbitratorData[] public arbitratorDataList; // Stores the arbitrator data of the contract. Updated each time the data is changed.

    mapping(uint160 => Soul) private souls; // Maps the soul id to the Soul data. souls[soulID].
    mapping(address => Human) private humans; // Maps the address to human's data. humans[humanID].
    mapping(address => mapping(address => mapping(uint160 => bool))) public vouches; // Indicates whether or not the voucher has vouched for a certain human. vouches[voucherID][vouchedHumanID][soulID].
    mapping(address => mapping(uint256 => DisputeData)) public arbitratorDisputeIDToDisputeData; // Maps a dispute ID with its data. arbitratorDisputeIDToDisputeData[arbitrator][disputeID].

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

    /* Events */

    event ClaimSoul(address indexed humanID, uint256 requestID);
    event RenewSoul(address indexed humanID, uint256 requestID);
    event RevokeSoul(address indexed requester, uint160 indexed soulID, uint256 requestID);
    event VouchAdded(address indexed humanID, address indexed voucher);
    event VouchRemoved(address indexed humanID, address indexed voucher);
    event SubmissionChallenged(address indexed humanID, uint256 indexed requestID, uint256 challengeID);
    event AppealContribution(
        uint160 indexed soulID,
        uint256 indexed challengeID,
        Party party,
        address indexed contributor,
        uint256 amount
    );
    event HasPaidAppealFee(uint160 indexed soulID, uint256 indexed challengeID, Party side);
    event ChallengeResolved(address indexed humanID, uint256 indexed requestID, uint256 challengeID);

    /** @dev Constructor.
     *  @param _arbitrator The trusted arbitrator to resolve potential disputes.
     *  @param _arbitratorExtraData Extra data for the trusted arbitrator contract.
     *  @param _registrationMetaEvidence The URI of the meta evidence object for registration requests.
     *  @param _clearingMetaEvidence The URI of the meta evidence object for clearing requests.
     *  @param _requestBaseDeposit The base deposit to make a request for a soul.
     *  @param _soulLifespan Time in seconds during which the claimed soul won't automatically lose its status.
     *  @param _renewalPeriodDuration Value that defines the duration of soul's renewal period.
     *  @param _challengePeriodDuration The time in seconds during which the request can be challenged.
     *  @param _multipliers The array that contains fee stake multipliers to avoid 'stack too deep' error.
     *  @param _requiredNumberOfVouches The number of vouches the human has to have to pass from Vouching to Claiming phase.
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
        emit MetaEvidence(0, _registrationMetaEvidence);
        emit MetaEvidence(1, _clearingMetaEvidence);

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
    }

    /* External and Public */

    // ************************ //
    // *      Governance      * //
    // ************************ //

    /** @dev Manually grant soul via cross-chain instance.
     *  @param _soulID The unique id to be added.
     *  @param _humanID The addresses of newly added human.
     *  @param _claimTime The claim time of the newly added soul.
     */
    function grantSoulManually(
        uint160 _soulID,
        address _humanID,
        uint64 _claimTime
    ) external override onlyCrossChain {
        // Reverts if soul is not bound to anyone
        boundTo(_soulID);

        Human storage human = humans[_humanID];
        Soul storage soul = souls[_soulID];

        require(soul.status == Status.None && human.phase == Phase.None);

        uint256 requestID = soul.requests.length;
        if (requestID == 0) soulsCounter++;
        human.soulID = _soulID;
        human.lastRequestID = requestID;
        soul.owner = _humanID;
        soul.claimTime = _claimTime;
        soul.requests.push().resolved = true;
    }

    /** @dev Allow the governor to directly remove a registered entry from the list as a part of the seeding event.
     *  @param _humanID The human corresponding to the soul to be revoked.
     */
    function revokeSoulManually(address _humanID)
        external
        override
        onlyCrossChain
        returns (uint64 claimTime, uint160 soulID)
    {
        Human storage human = humans[_humanID];
        soulID = human.soulID;

        Soul storage soul = souls[soulID];
        claimTime = soul.claimTime;

        // Submission must not have vouched at the moment
        require(!human.isVouching);

        if (_isRegisteredLocally(_humanID)) {
            // Should not have an ongoing removal request
            require(soul.status == Status.None);
            delete soul.owner;
        } else {
            bool isVouchingOnOld;
            (, claimTime, , , isVouchingOnOld, ) = _getOldProofOfHumanity().getSubmissionInfo(_humanID);
            // Submission must not have vouched at the moment
            require(!isVouchingOnOld);
            soulID = uint160(_humanID);
            _getOldProofOfHumanity().removeSubmissionManually(_humanID);
        }
    }

    /** @dev Change the governor of the contract.
     *  @param _governor The address of the new governor.
     */
    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
    }

    /** @dev Change the base amount required as a deposit to make a request for a soul.
     *  @param _requestBaseDeposit The new base amount of wei required to make a new request.
     */
    function changeRequestBaseDeposit(uint256 _requestBaseDeposit) external onlyGovernor {
        requestBaseDeposit = _requestBaseDeposit;
    }

    /** @dev Change the duration of the soul lifespan, renewal and challenge periods.
     *  @param _soulLifespan The new lifespan of the time the soul is considered registered.
     *  @param _renewalPeriodDuration The new value that defines the duration of the soul's renewal period.
     *  @param _challengePeriodDuration The new duration of the challenge period. It should be lower than the time for a dispute.
     */
    function changeDurations(
        uint64 _soulLifespan,
        uint64 _renewalPeriodDuration,
        uint64 _challengePeriodDuration
    ) external onlyGovernor {
        require(_challengePeriodDuration.addCap64(_renewalPeriodDuration) < _soulLifespan);
        soulLifespan = _soulLifespan;
        renewalPeriodDuration = _renewalPeriodDuration;
        challengePeriodDuration = _challengePeriodDuration;
    }

    /** @dev Change the number of vouches required for the request to pass to the pending state.
     *  @param _requiredNumberOfVouches The new required number of vouches.
     */
    function changeRequiredNumberOfVouches(uint64 _requiredNumberOfVouches) external onlyGovernor {
        requiredNumberOfVouches = _requiredNumberOfVouches;
    }

    /** @dev Change the proportion of arbitration fees that must be paid as fee stake by parties when there is no winner or loser (e.g. when the arbitrator refused to rule).
     *  @param _sharedStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake. In basis points.
     */
    function changeSharedStakeMultiplier(uint256 _sharedStakeMultiplier) external onlyGovernor {
        sharedStakeMultiplier = _sharedStakeMultiplier;
    }

    /** @dev Change the proportion of arbitration fees that must be paid as fee stake by the winner of the previous round.
     *  @param _winnerStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake. In basis points.
     */
    function changeWinnerStakeMultiplier(uint256 _winnerStakeMultiplier) external onlyGovernor {
        winnerStakeMultiplier = _winnerStakeMultiplier;
    }

    /** @dev Change the proportion of arbitration fees that must be paid as fee stake by the party that lost the previous round.
     *  @param _loserStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake. In basis points.
     */
    function changeLoserStakeMultiplier(uint256 _loserStakeMultiplier) external onlyGovernor {
        loserStakeMultiplier = _loserStakeMultiplier;
    }

    /** @dev Update the meta evidence used for disputes.
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

    /** @dev Change the arbitrator to be used for disputes that may be raised in the next requests. The arbitrator is trusted to support appeal period and not reenter.
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
    }

    /** @dev Change the cross-chain instance
     *  @param _crossChainProofOfHumanity The new cross-chain instance to be used
     */
    function changeCrossChainProofOfHumanity(address _crossChainProofOfHumanity) external onlyGovernor {
        crossChainProofOfHumanity = _crossChainProofOfHumanity;
    }

    // ************************ //
    // *       Requests       * //
    // ************************ //

    /** @dev Make a request to enter the registry. Paying the full deposit right away is not required as it can be crowdfunded later.
     *  @param _soulID The soul id the human applies for.
     *  @param _evidence A link to evidence using its URI.
     *  @param _name The name of the human. This parameter is for Subgraph only and it won't be used in this function.
     */
    function claimSoul(
        uint160 _soulID,
        string calldata _evidence,
        string calldata _name
    ) external payable {
        // For UX, soulID parameter can be 0, in which case it is considered the sender wants to get the default value based on the address
        uint160 soulID = _soulID == 0 ? uint160(msg.sender) : _soulID;

        Human storage human = humans[msg.sender];
        Soul storage soul = souls[soulID];

        // The sender must not be registered and the soul not belong to anybody
        require(!isRegistered(msg.sender) && soul.owner == address(0x0));

        (OldStatus statusOnOld, uint64 claimnOld, , bool registeredOnOld, , ) = _getOldProofOfHumanity()
            .getSubmissionInfo(msg.sender);
        if (registeredOnOld) require(_isRenewalPeriod(claimnOld));
        require(statusOnOld <= OldStatus.Vouching);

        human.soulID = soulID;

        uint256 requestID = _requestSoul(soul, human, _evidence);

        // If soul has not had any requests before on this contract, increase the counter
        if (requestID == 0) soulsCounter++;

        emit ClaimSoul(msg.sender, requestID);
    }

    /** @dev Make a request to renew soul's lifespan. Paying the full deposit right away is not required as it can be crowdfunded later.
     *  Note that the user can reapply even when current lifespan has not expired, but only after the start of renewal period.
     *  @param _evidence A link to evidence using its URI.
     *  @param _name The name of the human. This parameter is for Subgraph only and it won't be used in this function.
     */
    function renewSoul(string calldata _evidence, string calldata _name) external {
        Human storage human = humans[msg.sender];
        Soul storage soul = souls[human.soulID];

        // There must be renewal period
        require(_isRenewalPeriod(soul.claimTime));

        uint256 requestID = _requestSoul(soul, human, _evidence);

        emit RenewSoul(msg.sender, requestID);
    }

    /** @dev Make a request to revoke a soul from the list. Requires full deposit. Accepts enough ETH to cover the deposit, reimburses the rest.
     *  @param _soulID The id of the soul to revoke.
     *  @param _evidence A link to evidence using its URI.
     */
    function revokeSoul(uint160 _soulID, string calldata _evidence) external payable {
        Soul storage soul = souls[_soulID];

        // Soul must have an owner to revoke and must have no status
        require(soul.owner != address(0x0) && soul.status == Status.None);

        // The request can't be made during the renewal period to avoid spam leading to soul's expiration.
        require(!_isRenewalPeriod(soul.claimTime));

        soul.status = Status.Revoking;
        uint256 requestID = soul.requests.length;

        Request storage request = soul.requests.push();
        request.requester = payable(msg.sender);
        uint256 arbitratorDataID = arbitratorDataList.length - 1;
        request.arbitratorDataID = uint16(arbitratorDataID);
        request.challengePeriodStart = uint64(block.timestamp);

        Round storage round = request.challenges[0].rounds[0];
        ArbitratorData storage arbitratorData = arbitratorDataList[arbitratorDataID];
        uint256 totalCost = _arbitrationCost(arbitratorData).addCap(requestBaseDeposit);

        // Must be fully paid
        require(_contribute(round, Party.Requester, totalCost));

        emit RevokeSoul(msg.sender, _soulID, requestID);

        if (bytes(_evidence).length > 0)
            emit Evidence(
                arbitratorData.arbitrator,
                soul.requests.length - 1 + uint256(_soulID),
                msg.sender,
                _evidence
            );
    }

    /** @dev Fund the requester's deposit. Accepts enough ETH to cover the deposit, reimburses the rest.
     *  @param _humanID The id of the human to fund the request for.
     */
    function fundRequest(address _humanID) external payable {
        Human storage human = humans[_humanID];
        require(human.phase == Phase.Vouching);
        Request storage request = souls[human.soulID].requests[human.lastRequestID];
        Round storage round = request.challenges[0].rounds[0];

        ArbitratorData storage arbitratorData = arbitratorDataList[request.arbitratorDataID];
        uint256 totalCost = _arbitrationCost(arbitratorData).addCap(requestBaseDeposit);
        _contribute(round, Party.Requester, totalCost);
    }

    /** @dev Vouch for the submission. Note that the event spam is not an issue as it will be handled by the UI.
     *  @param _humanID The address of the submission to vouch for.
     */
    function addVouch(address _humanID, uint160 _soulID) external {
        vouches[msg.sender][_humanID][_soulID] = true;
        emit VouchAdded(_humanID, msg.sender);
    }

    /** @dev Remove the submission's vouch that has been added earlier. Note that the event spam is not an issue as it will be handled by the UI.
     *  @param _humanID The address of the submission to remove vouch from.
     */
    function removeVouch(address _humanID, uint160 _soulID) external {
        vouches[msg.sender][_humanID][_soulID] = false;
        emit VouchRemoved(_humanID, msg.sender);
    }

    /** @dev Allow to withdraw a mistakenly added submission while it's still in a vouching state.
     */
    function withdrawSubmission() external {
        Human storage human = humans[msg.sender];
        require(human.phase == Phase.Vouching);
        Request storage request = souls[human.soulID].requests[human.lastRequestID];
        human.phase = Phase.None;
        request.resolved = true;

        withdrawFeesAndRewards(payable(msg.sender), msg.sender, human.lastRequestID, 0, 0); // Automatically withdraw for the requester.
    }

    /** @dev Change human's phase from Vouching to Claiming if all conditions are met.
     *  @param _humanID The address of the human which status to change.
     *  @param _vouches Array of users whose vouches to count.
     *  @param _signatures Array of EIP-712 signatures of struct IsHumanVoucher (optional).
     *  @param _expirationTimestamps Array of expiration timestamps for each signature (optional).
     *  struct IsHumanVoucher {
     *      address vouchedSubmission;
     *      uint256 voucherExpirationTimestamp;
     *  }
     */
    function changeStateToPending(
        address _humanID,
        address[] calldata _vouches,
        bytes[] calldata _signatures,
        uint256[] calldata _expirationTimestamps
    ) external {
        Human storage human = humans[_humanID];
        Soul storage soul = souls[human.soulID];
        require(human.phase == Phase.Vouching && soul.status == Status.None);
        Request storage request = soul.requests[human.lastRequestID];
        require(request.challenges[0].rounds[0].sideFunded == Party.Requester);

        uint256 timeOffset = block.timestamp - soulLifespan; // Precompute the offset before the loop for efficiency and then compare it with the human time to check the expiration.

        bytes2 PREFIX = "\x19\x01";
        for (uint256 i = 0; i < _signatures.length && request.vouches.length < requiredNumberOfVouches; i++) {
            address voucherAddress;
            {
                // Get typed structure hash.
                bytes32 messageHash = keccak256(
                    abi.encode(_IS_HUMAN_VOUCHER_TYPEHASH, _humanID, human.soulID, _expirationTimestamps[i])
                );
                bytes32 hash = keccak256(abi.encodePacked(PREFIX, _DOMAIN_SEPARATOR, messageHash));

                // Decode the signature.
                bytes memory signature = _signatures[i];
                bytes32 r;
                bytes32 s;
                uint8 v;
                assembly {
                    r := mload(add(signature, 0x20))
                    s := mload(add(signature, 0x40))
                    v := byte(0, mload(add(signature, 0x60)))
                }
                if (v < 27) v += 27;
                require(v == 27 || v == 28);

                // Recover the signer's address.
                voucherAddress = ecrecover(hash, v, r, s);
            }

            if (block.timestamp < _expirationTimestamps[i] && _isVouchValid(voucherAddress, _humanID, timeOffset)) {
                request.vouches.push(voucherAddress);
                humans[voucherAddress].isVouching = true;
                emit VouchAdded(_humanID, voucherAddress);
            }
        }

        for (uint256 i = 0; i < _vouches.length && request.vouches.length < requiredNumberOfVouches; i++) {
            // Check that the vouch isn't currently used by another human and the voucher has a right to vouch.
            if (vouches[_vouches[i]][_humanID][human.soulID] && _isVouchValid(_vouches[i], _humanID, timeOffset)) {
                request.vouches.push(_vouches[i]);
                humans[_vouches[i]].isVouching = true;
            }
        }
        require(request.vouches.length >= requiredNumberOfVouches);
        soul.status = Status.Resolving;
        human.phase = Phase.Claiming;
        request.challengePeriodStart = uint64(block.timestamp);
    }

    /** @dev Challenge the human's request. Accept enough ETH to cover the deposit, reimburse the rest.
     *  @param _humanID The address of the human which request to challenge.
     *  @param _reason The reason to challenge the request. Left empty for removal requests.
     *  @param _evidence A link to evidence using its URI. Ignored if not provided.
     */
    function challengeRequest(
        address _humanID,
        Reason _reason,
        string calldata _evidence
    ) external payable {
        Human storage human = humans[_humanID];
        Soul storage soul = souls[human.soulID];
        require(soul.status != Status.None && (soul.status == Status.Resolving) == (_reason != Reason.None));

        Request storage request = souls[human.soulID].requests[human.lastRequestID];
        require(!request.disputed && _isChallengePeriod(request));

        if (request.currentReason != _reason) {
            uint8 reasonBit = uint8(1 << (uint256(_reason) - 1)); // Get the bit that corresponds with reason's index.
            require((reasonBit & ~request.usedReasons) == reasonBit);
            request.usedReasons ^= reasonBit; // Mark the bit corresponding with reason's index as 'true', to indicate that the reason was used.
            request.currentReason = _reason;
        }

        Challenge storage challenge = request.challenges[request.lastChallengeID];
        Round storage round = challenge.rounds[0];

        ArbitratorData storage arbitratorData = arbitratorDataList[request.arbitratorDataID];
        uint256 arbitrationCost = _arbitrationCost(arbitratorData);
        require(_contribute(round, Party.Challenger, arbitrationCost));
        round.feeRewards = round.feeRewards.subCap(arbitrationCost);

        challenge.disputeID = arbitratorData.arbitrator.createDispute{value: arbitrationCost}(
            _RULING_OPTIONS,
            arbitratorData.arbitratorExtraData
        );
        challenge.challenger = payable(msg.sender);

        DisputeData storage disputeData = arbitratorDisputeIDToDisputeData[address(arbitratorData.arbitrator)][
            challenge.disputeID
        ];
        disputeData.soulID = human.soulID;
        disputeData.requestID = uint96(human.lastRequestID);
        disputeData.challengeID = uint96(request.lastChallengeID);

        request.disputed = true;
        request.lastChallengeID++;
        challenge.lastRoundID++;

        emit SubmissionChallenged(_humanID, human.lastRequestID, disputeData.challengeID);

        uint256 evidenceGroupID = human.lastRequestID + uint256(human.soulID);

        emit Dispute(
            arbitratorData.arbitrator,
            challenge.disputeID,
            soul.status == Status.Resolving
                ? 2 * arbitratorData.metaEvidenceUpdates
                : 2 * arbitratorData.metaEvidenceUpdates + 1,
            evidenceGroupID
        );

        if (bytes(_evidence).length > 0)
            emit Evidence(arbitratorData.arbitrator, evidenceGroupID, msg.sender, _evidence);
    }

    /** @dev Take up to the total amount required to fund a side of an appeal. Reimburse the rest. Create an appeal if both sides are fully funded.
     *  @param _soulID The address of the humamnity which request to fund.
     *  @param _challengeID The index of a dispute, created for the request.
     *  @param _side The recipient of the contribution.
     */
    function fundAppeal(
        uint160 _soulID,
        uint256 _challengeID,
        Party _side
    ) external payable {
        require(_side != Party.None); // You can only fund either requester or challenger.
        Soul storage soul = souls[_soulID];
        require(soul.status != Status.None);
        Request storage request = soul.requests[soul.requests.length - 1];
        require(request.disputed);
        require(_challengeID < request.lastChallengeID);

        Challenge storage challenge = request.challenges[_challengeID];
        ArbitratorData storage arbitratorData = arbitratorDataList[request.arbitratorDataID];

        (uint256 appealPeriodStart, uint256 appealPeriodEnd) = arbitratorData.arbitrator.appealPeriod(
            challenge.disputeID
        );
        require(block.timestamp >= appealPeriodStart && block.timestamp < appealPeriodEnd);

        uint256 multiplier;
        Party winner = Party(arbitratorData.arbitrator.currentRuling(challenge.disputeID));
        if (winner == _side) multiplier = winnerStakeMultiplier;
        else if (winner == Party.None) multiplier = sharedStakeMultiplier;
        else if (block.timestamp - appealPeriodStart >= (appealPeriodEnd - appealPeriodStart) / 2) revert();
        else multiplier = loserStakeMultiplier;

        Round storage round = challenge.rounds[challenge.lastRoundID];
        Party firstFunded = round.sideFunded;
        require(_side != firstFunded);

        emit AppealContribution(_soulID, _challengeID, _side, msg.sender, msg.value);

        uint256 appealCost = arbitratorData.arbitrator.appealCost(
            challenge.disputeID,
            arbitratorData.arbitratorExtraData
        );
        uint256 totalCost = appealCost.addCap((appealCost.mulCap(multiplier)) / _MULTIPLIER_DIVISOR);

        if (_contribute(round, _side, totalCost)) {
            if (firstFunded != Party.None) {
                // Both sides are fully funded. Create an appeal.
                arbitratorData.arbitrator.appeal{value: appealCost}(
                    challenge.disputeID,
                    arbitratorData.arbitratorExtraData
                );
                challenge.lastRoundID++;
                round.feeRewards = round.feeRewards.subCap(appealCost);
            }
            emit HasPaidAppealFee(_soulID, _challengeID, _side);
        }
    }

    /** @dev Execute a request if the challenge period passed and no one challenged the request.
     *  @param _humanID The address of the human whose request to execute.
     */
    function executeRequest(address _humanID) external {
        Human storage human = humans[_humanID];
        Soul storage soul = souls[human.soulID];
        Request storage request = soul.requests[human.lastRequestID];
        require(!request.disputed && !_isChallengePeriod(request));
        require(soul.status != Status.None);

        if (soul.status == Status.Revoking) delete soul.owner;
        else if (!request.requesterLost) {
            soul.owner = request.requester;
            soul.claimTime = uint64(block.timestamp);
        }

        soul.status = Status.None;
        request.resolved = true;

        if (request.vouches.length != 0) processVouches(_humanID, _AUTO_PROCESSED_VOUCH);

        withdrawFeesAndRewards(request.requester, _humanID, human.lastRequestID, 0, 0); // Automatically withdraw for the requester.
    }

    /** @dev Process vouches of the resolved request, so vouchings of users who vouched for it can be used for other humans.
     *  Penalize users who vouched for bad soul requests.
     *  @param _humanID Human for which vouches to iterate.
     *  @param _iterations The number of iterations to go through.
     */
    function processVouches(address _humanID, uint256 _iterations) public {
        Human storage human = humans[_humanID];
        Request storage request = souls[human.soulID].requests[human.lastRequestID];
        require(request.resolved);

        uint256 lastProcessedVouch = request.lastProcessedVouch;
        uint256 endIndex = _iterations.addCap(lastProcessedVouch);
        uint256 vouchCount = request.vouches.length;

        if (endIndex > vouchCount) endIndex = vouchCount;

        Reason currentReason = request.currentReason;
        bool applyPenalty = request.ultimateChallenger != address(0x0) &&
            (currentReason == Reason.Duplicate || currentReason == Reason.DoesNotExist);
        for (uint256 i = lastProcessedVouch; i < endIndex; i++) {
            Human storage voucher = humans[request.vouches[i]];
            Soul storage voucherSoul = souls[voucher.soulID];
            voucher.isVouching = false;
            if (applyPenalty) {
                if (_isRegisteredLocally(request.vouches[i])) {
                    // Check the situation when vouching address is in the middle of reapplication process.
                    if (voucher.phase != Phase.None) voucherSoul.requests[voucher.lastRequestID].requesterLost = true;

                    delete voucherSoul.owner;
                } else {
                    (OldStatus statusOnOld, , , bool registeredOnOld, , ) = _getOldProofOfHumanity().getSubmissionInfo(
                        request.vouches[i]
                    );
                    if (registeredOnOld && statusOnOld == OldStatus.None)
                        _getOldProofOfHumanity().removeSubmissionManually(request.vouches[i]);
                }
            }
        }
        request.lastProcessedVouch = uint32(endIndex);
    }

    /** @dev Reimburse contributions if no disputes were raised. If a dispute was raised, send the fee stake rewards and reimbursements proportionally to the contributions made to the winner of a dispute.
     *  @param _beneficiary The address that made contributions to a request.
     *  @param _humanID The address of the human with the request from which to withdraw.
     *  @param _requestID The request from which to withdraw.
     *  @param _challengeID The ID of the challenge from which to withdraw.
     *  @param _round The round from which to withdraw.
     */
    function withdrawFeesAndRewards(
        address payable _beneficiary,
        address _humanID,
        uint256 _requestID,
        uint256 _challengeID,
        uint256 _round
    ) public {
        Request storage request = souls[humans[_humanID].soulID].requests[_requestID];
        Challenge storage challenge = request.challenges[_challengeID];
        Round storage round = challenge.rounds[_round];
        require(request.resolved);
        require(_beneficiary != address(0x0));

        Party ruling = challenge.ruling;
        uint256 reward;
        uint256[3] storage beneficiaryContributions = round.contributions[_beneficiary];
        // Reimburse the payment if the last round wasn't fully funded.
        // Note that the 0 round is always considered funded if there is a challenge. If there was no challenge the requester will be reimbursed with the subsequent condition, since the ruling will be Party.None.
        if (_round != 0 && _round == challenge.lastRoundID) {
            reward =
                beneficiaryContributions[uint256(Party.Requester)] +
                beneficiaryContributions[uint256(Party.Challenger)];
        } else if (ruling == Party.None) {
            uint256 totalFeesInRound = round.paidFees[uint256(Party.Challenger)] +
                round.paidFees[uint256(Party.Requester)];
            uint256 claimableFees = beneficiaryContributions[uint256(Party.Challenger)] +
                beneficiaryContributions[uint256(Party.Requester)];
            reward = totalFeesInRound > 0 ? (claimableFees * round.feeRewards) / totalFeesInRound : 0;
        } else {
            // Challenger, who ultimately wins, will be able to get the deposit of the requester, even if he didn't participate in the initial dispute.
            if (_beneficiary == request.ultimateChallenger && _challengeID == 0 && _round == 0) {
                reward = round.feeRewards;
                round.feeRewards = 0;
                // This condition will prevent claiming a reward, intended for the ultimate challenger.
            } else if (request.ultimateChallenger == address(0x0) || _challengeID != 0 || _round != 0) {
                uint256 paidFees = round.paidFees[uint256(ruling)];
                reward = paidFees > 0 ? (beneficiaryContributions[uint256(ruling)] * round.feeRewards) / paidFees : 0;
            }
        }
        beneficiaryContributions[uint256(Party.Requester)] = 0;
        beneficiaryContributions[uint256(Party.Challenger)] = 0;
        _beneficiary.send(reward);
    }

    /** @dev Give a ruling for a dispute. Can only be called by the arbitrator. TRUSTED.
     *  Account for the situation where the winner loses a case due to paying less appeal fees than expected.
     *  @param _disputeID ID of the dispute in the arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Refused to arbitrate".
     */
    function rule(uint256 _disputeID, uint256 _ruling) public override {
        Party resultRuling = Party(_ruling);
        DisputeData storage disputeData = arbitratorDisputeIDToDisputeData[msg.sender][_disputeID];
        Soul storage soul = souls[disputeData.soulID];
        Request storage request = soul.requests[disputeData.requestID];
        Challenge storage challenge = request.challenges[disputeData.challengeID];
        Round storage round = challenge.rounds[challenge.lastRoundID];

        require(address(arbitratorDataList[request.arbitratorDataID].arbitrator) == msg.sender);
        require(!request.resolved);

        // The ruling is inverted if the loser paid its fees.
        if (round.sideFunded == Party.Requester)
            // If one side paid its fees, the ruling is in its favor. Note that if the other side had also paid, an appeal would have been created.
            resultRuling = Party.Requester;
        else if (round.sideFunded == Party.Challenger) resultRuling = Party.Challenger;

        // Store the rulings of each dispute for correct distribution of rewards.
        challenge.ruling = resultRuling;

        if (soul.status == Status.Resolving) {
            // For a registration request there can be more than one dispute.
            if (resultRuling == Party.Requester) {
                // Check whether or not the requester won all of his previous disputes for current reason.
                if (!request.requesterLost) {
                    // All reasons being used means the request can't be challenged again, so we can update its status.
                    if (request.usedReasons == _FULL_REASONS_SET) {
                        soul.owner = request.requester;
                        soul.claimTime = uint64(block.timestamp);
                    } else {
                        // Refresh the state of the request so it can be challenged again.
                        request.disputed = false;
                        request.challengePeriodStart = uint64(block.timestamp);
                        request.currentReason = Reason.None;
                        return;
                    }
                }
                // Challenger won or it’s a tie.
            } else {
                if (resultRuling == Party.Challenger) request.ultimateChallenger = challenge.challenger;
                request.requesterLost = true;
            }
        } else if (soul.status == Status.Revoking && resultRuling == Party.Requester) delete soul.owner;

        soul.status = Status.None;
        request.resolved = true;

        emit Ruling(IArbitrator(msg.sender), _disputeID, uint256(resultRuling));
        emit ChallengeResolved(request.requester, disputeData.requestID, disputeData.challengeID);
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _soulID The soul id the evidence is related to.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(uint160 _soulID, string calldata _evidence) external {
        Soul storage soul = souls[_soulID];
        uint256 requestID = soul.requests.length - 1;
        Request storage request = soul.requests[requestID];

        emit Evidence(
            arbitratorDataList[request.arbitratorDataID].arbitrator,
            requestID + uint256(_soulID),
            msg.sender,
            _evidence
        );
    }

    /* Internal */

    /** @dev Make a request to apply for/renew the humanity.
     *  @param _soul The humanity struct the request is made for.
     *  @param _human The human struct making the request for soul.
     *  @param _evidence A link to evidence using its URI.
     */
    function _requestSoul(
        Soul storage _soul,
        Human storage _human,
        string calldata _evidence
    ) internal returns (uint256 requestID) {
        // The soul and human must have no status/phase
        require(_soul.status == Status.None && _human.phase == Phase.None);

        requestID = _soul.requests.length;
        _human.lastRequestID = requestID;
        _human.phase = Phase.Vouching;

        Request storage request = _soul.requests.push();
        request.requester = payable(msg.sender);
        uint256 arbitratorDataID = arbitratorDataList.length - 1;
        request.arbitratorDataID = uint16(arbitratorDataID);

        Round storage round = request.challenges[0].rounds[0];
        uint256 totalCost = _arbitrationCost(arbitratorDataList[arbitratorDataID]).addCap(requestBaseDeposit);
        _contribute(round, Party.Requester, totalCost);

        if (bytes(_evidence).length > 0)
            emit Evidence(
                arbitratorDataList[arbitratorDataID].arbitrator,
                requestID + uint256(_human.soulID),
                msg.sender,
                _evidence
            );
    }

    /** @dev Make a fee contribution.
     *  @param _round The round to contribute to.
     *  @param _side The side to contribute to.
     *  @param _totalRequired The total amount required for this side.
     *  @return paidInFull Whether the contribution was paid in full
     */
    function _contribute(
        Round storage _round,
        Party _side,
        uint256 _totalRequired
    ) internal returns (bool paidInFull) {
        uint256 remainingETH;
        uint256 contribution = msg.value;
        uint256 requiredAmount = _totalRequired.subCap(_round.paidFees[uint256(_side)]);
        if (requiredAmount <= msg.value) {
            contribution = requiredAmount;
            remainingETH = msg.value - requiredAmount;

            paidInFull = true;
            _round.sideFunded = _round.sideFunded == Party.None ? _side : Party.None;
        }

        _round.contributions[msg.sender][uint256(_side)] += contribution;
        _round.paidFees[uint256(_side)] += contribution;
        _round.feeRewards += contribution;

        if (remainingETH != 0) payable(msg.sender).send(remainingETH);
    }

    /** @dev Return true if the vouch is valid.
     *  @param _voucherID The address of the voucher.
     *  @param _vouchedID The address of the vouched human.
     *  @param _timeOffset Precalculated offset for soul timeout.
     */
    function _isVouchValid(
        address _voucherID,
        address _vouchedID,
        uint256 _timeOffset
    ) internal view returns (bool) {
        if (_vouchedID == _voucherID) return false;
        Human storage voucher = humans[_voucherID];
        Soul storage voucherSoul = souls[voucher.soulID];
        (, uint256 soubmissionTimeOnOld, , bool registeredOnOld, bool isVouchingOnOld, ) = _getOldProofOfHumanity()
            .getSubmissionInfo(_voucherID);
        // Voucher must fit the conditions on one of the contracts
        return
            !voucher.isVouching &&
            ((voucherSoul.owner == _voucherID && _timeOffset <= voucherSoul.claimTime) ||
                (!isVouchingOnOld && registeredOnOld && _timeOffset <= soubmissionTimeOnOld));
    }

    /** @dev Return true if the claimTime corresponds to renewal period.
     *  @param _claimTime The claimTime to check.
     */
    function _isRenewalPeriod(uint64 _claimTime) internal view returns (bool) {
        return block.timestamp >= _claimTime.addCap64(soulLifespan.subCap64(renewalPeriodDuration));
    }

    /** @dev Return true if the request is in challenge period.
     *  @param _request The request from storage to check.
     */
    function _isChallengePeriod(Request storage _request) internal view returns (bool) {
        return block.timestamp - _request.challengePeriodStart <= challengePeriodDuration;
    }

    /** @dev Return the arbitration cost for the arbitratorData.
     *  @param _arbitratorData The arbitratorData from storage to get the arbitration cost for.
     */
    function _arbitrationCost(ArbitratorData storage _arbitratorData) internal view returns (uint256) {
        return _arbitratorData.arbitrator.arbitrationCost(_arbitratorData.arbitratorExtraData);
    }

    function _isRegisteredLocally(address _humanID) internal view returns (bool) {
        Soul storage soul = souls[humans[_humanID].soulID];
        if (soul.owner == address(0x0)) return false;
        return soul.owner == _humanID && block.timestamp - soul.claimTime <= soulLifespan;
    }

    function _getOldProofOfHumanity() internal view returns (IProofOfHumanityOld oldPoH) {
        assembly {
            oldPoH := sload(_OLD_POH_SLOT)
        }
    }

    // ************************ //
    // *       Getters        * //
    // ************************ //

    /** @dev Return the owner of the soul. Revert if not active.
     *  @param _soulID The soul ID to get the owner of.
     */
    function boundTo(uint160 _soulID) public view override returns (address owner) {
        Soul storage soul = souls[_soulID];
        owner = soul.owner;
        uint64 claimTime = soul.claimTime;
        if (owner == address(0)) {
            owner = address(_soulID);
            bool registered;
            (, claimTime, , registered, , ) = _getOldProofOfHumanity().getSubmissionInfo(owner);
            require(registered);
        }
        require(block.timestamp - claimTime <= soulLifespan);
    }

    /** @dev Return true if the human has a non expired soul.
     *  @param _humanID The address of the human.
     *  @return Whether the human has a valid soul or not.
     */
    function isRegistered(address _humanID) public view override returns (bool) {
        return _isRegisteredLocally(_humanID) || _getOldProofOfHumanity().isRegistered(_humanID);
    }

    /** @dev Get the number of times the arbitrator data was updated.
     *  @return The number of arbitrator data updates.
     */
    function getArbitratorDataListCount() external view returns (uint256) {
        return arbitratorDataList.length;
    }

    /** @dev Get the contributions made by a party for a given round of a given challenge of a request.
     *  @param _soulID The soul id.
     *  @param _requestID The request to query.
     *  @param _challengeID the challenge to query.
     *  @param _round The round to query.
     *  @param _contributor The address of the contributor.
     *  @return The contributions.
     */
    function getContributions(
        uint160 _soulID,
        uint256 _requestID,
        uint256 _challengeID,
        uint256 _round,
        address _contributor
    ) external view returns (uint256[3] memory) {
        Request storage request = souls[_soulID].requests[_requestID];
        Challenge storage challenge = request.challenges[_challengeID];
        Round storage round = challenge.rounds[_round];
        return round.contributions[_contributor];
    }

    /** @dev Return the information of the soul ID. Includes length of requests array.
     *  @param _soulID The queried soul id.
     */
    function getSoulInfo(uint160 _soulID)
        external
        view
        override
        returns (
            uint64 claimTime,
            address owner,
            uint256 numberOfRequests,
            Status status
        )
    {
        Soul storage soul = souls[_soulID];
        if (_getOldProofOfHumanity().isRegistered(address(_soulID))) {
            owner = address(_soulID);
            (, claimTime, , , , ) = _getOldProofOfHumanity().getSubmissionInfo(owner);
        } else {
            owner = soul.owner;
            claimTime = soul.claimTime;
        }
        status = soul.status;
        numberOfRequests = soul.requests.length;
    }

    /** @dev Return the information of the human. Includes length of requests array.
     *  @param _humanID The address of the queried human.
     */
    function getHumanInfo(address _humanID)
        external
        view
        override
        returns (
            bool isVouching,
            uint160 soulID,
            uint256 lastRequestID,
            Phase phase
        )
    {
        Human storage human = humans[_humanID];
        return (
            human.isVouching,
            _getOldProofOfHumanity().isRegistered(_humanID) ? uint160(_humanID) : human.soulID,
            human.lastRequestID,
            human.phase
        );
    }

    /** @dev Get the information of a particular challenge of the request.
     *  @param _soulID The queried soul ID.
     *  @param _requestID The request to query.
     *  @param _challengeID The challenge to query.
     */
    function getChallengeInfo(
        uint160 _soulID,
        uint256 _requestID,
        uint256 _challengeID
    )
        external
        view
        returns (
            uint16 lastRoundID,
            address challenger,
            uint256 disputeID,
            Party ruling
        )
    {
        Request storage request = souls[_soulID].requests[_requestID];
        Challenge storage challenge = request.challenges[_challengeID];
        return (challenge.lastRoundID, challenge.challenger, challenge.disputeID, challenge.ruling);
    }

    /** @dev Get information of a request of a soul.
     *  @param _soulID The address of the soul.
     *  @param _requestID The request
     */
    function getRequestInfo(uint160 _soulID, uint256 _requestID)
        external
        view
        returns (
            bool disputed,
            bool resolved,
            bool requesterLost,
            Reason currentReason,
            uint16 lastChallengeID,
            uint16 arbitratorDataID,
            address payable requester,
            address payable ultimateChallenger,
            uint8 usedReasons
        )
    {
        Request storage request = souls[_soulID].requests[_requestID];
        return (
            request.disputed,
            request.resolved,
            request.requesterLost,
            request.currentReason,
            request.lastChallengeID,
            request.arbitratorDataID,
            request.requester,
            request.ultimateChallenger,
            request.usedReasons
        );
    }

    /** @dev Get the number of vouches of a particular request.
     *  @param _soulID The ID of the queried human.
     *  @param _requestID The request to query.
     */
    function getNumberOfVouches(uint160 _soulID, uint256 _requestID) external view returns (uint256) {
        return souls[_soulID].requests[_requestID].vouches.length;
    }

    /** @dev Get the information of a round of a request.
     *  @param _soulID The queried soul ID.
     *  @param _requestID The request to query.
     *  @param _challengeID The challenge to query.
     *  @param _round The round to query.
     */
    function getRoundInfo(
        uint160 _soulID,
        uint256 _requestID,
        uint256 _challengeID,
        uint256 _round
    )
        external
        view
        returns (
            bool appealed,
            uint256[3] memory paidFees,
            Party sideFunded,
            uint256 feeRewards
        )
    {
        Request storage request = souls[_soulID].requests[_requestID];
        Challenge storage challenge = request.challenges[_challengeID];
        Round storage round = challenge.rounds[_round];
        appealed = _round < (challenge.lastRoundID);
        return (appealed, round.paidFees, round.sideFunded, round.feeRewards);
    }
}
