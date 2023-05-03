/** @authors: []
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.18;

import {CappedMath} from "../libraries/CappedMath.sol";

enum OldStatus {
    None, // The submission doesn't have a pending status.
    Vouching, // The submission is in the state where it can be vouched for and crowdfunded.
    PendingRegistration, // The submission is in the state where it can be challenged. Or accepted to the list, if there are no challenges within the time limit.
    PendingRemoval // The submission is in the state where it can be challenged. Or removed from the list, if there are no challenges within the time limit.
}

interface IProofOfHumanityOld {
    /* Views */

    function submissionDuration() external view returns (uint64);

    function isRegistered(address _submissionID) external view returns (bool);

    function getSubmissionInfo(
        address _submissionID
    )
        external
        view
        returns (
            OldStatus status,
            uint64 submissionTime,
            uint64 index,
            bool registered,
            bool isVouching,
            uint256 numberOfRequests
        );
}

interface IForkModule {
    function removeFromRequest(address _submissionID) external returns (bool);

    function removeForTransfer(address _submissionID) external returns (uint64);

    function isRegistered(address _submissionID) external view returns (bool);

    function hasLockedState(address _submissionID) external view returns (bool);

    function vouchReady(address _submissionID) external view returns (bool);

    function removalReady(address _submissionID) external view returns (bool);

    function getSubmissionInfo(address _submissionID) external view returns (bool registered, uint64 expirationTime);
}

/** PoHV2 functions which interact with the old PoH contract.
 *  * -> Part of process of potential removal   |   *** -> Includes removal
 *  grantManually
 *  revokeManually ***
 *  claimHumanity
 *  revokeHumanity *
 *  advanceState   *
 *  executeRequest ***
 *  processVouches ***
 *  rule           ***
 */

contract ForkModule is IForkModule {
    using CappedMath for uint64;

    /// ====== STORAGE ====== ///

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    IProofOfHumanityOld public oldProofOfHumanity;
    address public proofOfHumanityV2;

    uint64 public submissionDuration;

    mapping(address => bool) public removed;

    modifier initializer() {
        require(!initialized);
        initialized = true;
        _;
    }

    modifier onlyV2() {
        require(msg.sender == address(proofOfHumanityV2), "!V2");
        _;
    }

    /// ====== CONSTRUCTION ====== ///

    function initialize(address _proofOfHumanityV2, address _oldProofOfHumanity) public initializer {
        proofOfHumanityV2 = _proofOfHumanityV2;
        oldProofOfHumanity = IProofOfHumanityOld(_oldProofOfHumanity);
        submissionDuration = oldProofOfHumanity.submissionDuration();
    }

    /// ====== FUNCTIONS ====== ///

    /** @dev Marks a submission as removed. Should not revert.
     *  @dev Called when removing as result of revocation request or bad vouching.
     *
     *  @param _submissionID The address of the submission to remove.
     *  @return Whether the submission was successfully removed.
     */
    function removeFromRequest(address _submissionID) external override onlyV2 returns (bool) {
        if (removed[_submissionID]) return false;

        (, , , bool registered, , ) = oldProofOfHumanity.getSubmissionInfo(_submissionID);

        if (registered) {
            //? && status <= OldStatus.Vouching
            removed[_submissionID] = true;

            return true;
        }

        return false;
    }

    /** @dev Remove a submission because of a transfer request. Should revert in case of not meeting conditions.
     *
     *  @dev Requirements:
     *  - Submission must be registered in v1.
     *  - Must have a locked state (None/Vouching).
     *  - Must not be vouching.
     *
     *  @param _submissionID Address corresponding to the human.
     *  @return expirationTime Expiration time of the revoked humanity.
     */
    function removeForTransfer(address _submissionID) external override onlyV2 returns (uint64 expirationTime) {
        require(!removed[_submissionID], "!removed");

        (OldStatus status, uint64 submissionTime, , bool registered, bool isVouching, ) = oldProofOfHumanity
            .getSubmissionInfo(_submissionID);

        expirationTime = submissionTime.addCap64(submissionDuration);

        require(
            registered && expirationTime > block.timestamp && status <= OldStatus.Vouching && !isVouching,
            "!transfer"
        );

        removed[_submissionID] = true;
    }

    /// ====== VIEWS ====== ///

    /** @notice Check if a submission has a locked state.
     *
     *  @dev Requirements:
     *  - Locked state means passing one of following conditions:
     *      - Must have status None/Vouching.
     *
     *  @param _submissionID Address corresponding to the human.
     *  @return lockedState True if the submission has a locked state.
     */
    function hasLockedState(address _submissionID) external view override returns (bool) {
        //? if (removed[_submissionID]) return true;

        (OldStatus status, , , , , ) = oldProofOfHumanity.getSubmissionInfo(_submissionID);
        return status <= OldStatus.Vouching;
    }

    /** @notice Check if a human is ready to be vouch.
     *
     *  @dev Requirements:
     *  - Must be registered.
     *  - Must not be vouching.
     *
     *  @param _submissionID Address corresponding to the human.
     *  @return ready True if the human is ready to be vouch.
     */
    function vouchReady(address _submissionID) external view override returns (bool) {
        if (removed[_submissionID]) return false;

        (OldStatus status, uint64 submissionTime, , bool registered, bool isVouching, ) = oldProofOfHumanity
            .getSubmissionInfo(_submissionID);

        return (registered &&
            submissionTime.addCap64(submissionDuration) > block.timestamp &&
            status <= OldStatus.Vouching &&
            !isVouching);
    }

    /** @notice Check if a human is ready to be removed via `revokeHumanity`.
     *
     *  @dev Requirements:
     *  - Must be registered.
     *  - Must have locked state.
     *
     *  @param _submissionID Address corresponding to the human.
     *  @return ready True if the human is ready to be removed.
     */
    function removalReady(address _submissionID) external view override returns (bool) {
        if (removed[_submissionID]) return false;

        (OldStatus status, uint64 submissionTime, , bool registeredOnV1, , ) = oldProofOfHumanity.getSubmissionInfo(
            _submissionID
        );

        uint64 expirationTime = submissionTime.addCap64(submissionDuration);

        return (registeredOnV1 && expirationTime > block.timestamp && status <= OldStatus.Vouching);
    }

    function isRegistered(address _submissionID) external view override returns (bool) {
        return !removed[_submissionID] && oldProofOfHumanity.isRegistered(_submissionID);
    }

    function getSubmissionInfo(
        address _submissionID
    ) external view override returns (bool registered, uint64 expirationTime) {
        (, uint64 submissionTime, , bool registeredOnV1, , ) = oldProofOfHumanity.getSubmissionInfo(_submissionID);

        expirationTime = submissionTime.addCap64(submissionDuration);

        if (registeredOnV1 && expirationTime > block.timestamp) registered = true;
    }
}
