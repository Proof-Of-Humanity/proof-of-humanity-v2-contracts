/** @authors: []
 *  @reviewers: [@divyangchauhan, @Harman-singh-waraich]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.20;

import {CappedMath} from "../libraries/CappedMath.sol";
import {IForkModule} from "../interfaces/IForkModule.sol";
import {IProofOfHumanityOld} from "../interfaces/IProofOfHumanityOld.sol";

/** @title ForkModule
 *
 *  PoHV2 functions which interact with the old PoH contract.
 *  * -> Part of process of potential removal   |   *** -> Includes removal
 *  ccGrantHumanity
 *  ccDischargeHumanity ***
 *  claimHumanity
 *  revokeHumanity *
 *  advanceState   *
 *  executeRequest ***
 *  processVouches ***
 *  rule           ***
 */
contract ForkModule is IForkModule {
    using CappedMath for uint40;

    /// ====== STORAGE ====== ///

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @dev PoH v1 contract instance.
    IProofOfHumanityOld public proofOfHumanityV1;

    /// @dev Address of PoH v2 contract instance.
    address public proofOfHumanityV2;

    /// @dev The submissionDuration fetched from PoH v1 at the initialization of this contract.
    uint40 public submissionDuration;

    /// @dev The time when the fork is considered as started.
    uint40 public forkTime;

    /// @dev The removed flag used to overwrite the v1 submission status.
    mapping(address => bool) public removed;

    /* Modifiers */

    modifier initializer() {
        require(!initialized);
        initialized = true;
        _;
    }

    modifier onlyV2() {
        require(msg.sender == address(proofOfHumanityV2), "!poh");
        _;
    }

    /// ====== CONSTRUCTOR ====== ///

    /** @notice Initializes the ForkModule contract.
     *  @param _proofOfHumanityV1 The address of the PoH v1 contract.
     *  @param _proofOfHumanityV2 The address of the PoH v2 contract.
     */
    function initialize(address _proofOfHumanityV1, address _proofOfHumanityV2) public initializer {
        proofOfHumanityV1 = IProofOfHumanityOld(_proofOfHumanityV1);
        proofOfHumanityV2 = _proofOfHumanityV2;

        forkTime = uint40(block.timestamp);

        submissionDuration = uint40(proofOfHumanityV1.submissionDuration());
    }

    /// ====== FUNCTIONS ====== ///

    /** @dev Directly mark a submission as removed.
     *  @dev Called when removing as result of finalized revocation request or bad vouching.
     *
     *  @param _submissionID The address of the submission to mark as removed.
     */
    function remove(address _submissionID) external override onlyV2 {
        removed[_submissionID] = true;
    }

    /** @dev Remove a submission because of a transfer request. Should revert in case of not meeting conditions.
     *  @dev Returns expirationTime for better interaction with PoHv2 instance.
     *
     *  @dev Requirements:
     *  - Submission must be registered in v1.
     *
     *  @param _submissionID Address corresponding to the human.
     *  @return expirationTime Expiration time of the revoked humanity.
     */
    function tryRemove(address _submissionID) external override onlyV2 returns (uint40 expirationTime) {
        require(!removed[_submissionID], "removed!");

        (, uint64 submissionTime, , bool registered, , ) = proofOfHumanityV1.getSubmissionInfo(_submissionID);

        expirationTime = uint40(submissionTime).addCap40(submissionDuration);

        require(registered && block.timestamp < expirationTime && submissionTime < forkTime, "Not registered, expired or submitted after the fork!");

        removed[_submissionID] = true;
    }

    /// ====== VIEWS ====== ///

    /** @dev Return true if the submission is registered on v1 and not removed here and not expired.
     *  @param _submissionID The address of the submission.
     *  @return Whether the submission is registered or not.
     */
    function isRegistered(address _submissionID) external view override returns (bool) {
        if (removed[_submissionID]) return false;

        (, uint64 submissionTime, , bool registered, , ) = proofOfHumanityV1.getSubmissionInfo(_submissionID);

        uint40 expirationTime = uint40(submissionTime).addCap40(submissionDuration);

        return registered && block.timestamp < expirationTime && submissionTime < forkTime;
    }

    /** @dev Returns the registration status and the expiration time of the submission.
     *  @param _submissionID The address of the queried submission.
     */
    function getSubmissionInfo(
        address _submissionID
    ) external view override returns (bool registered, uint40 expirationTime) {
        (, uint64 submissionTime, , bool registeredOnV1, , ) = proofOfHumanityV1.getSubmissionInfo(_submissionID);

        expirationTime = uint40(submissionTime).addCap40(submissionDuration);

        if (registeredOnV1 && expirationTime > block.timestamp)
            registered = !removed[_submissionID] && submissionTime < forkTime;
    }
}
