// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import {Status} from "../utils/enums/Status.sol";
import {RequesterStatus} from "../utils/enums/RequesterStatus.sol";

interface IProofOfHumanity {
    /* Manual adding/removing */

    function acceptHumanityManually(
        uint160 _qid,
        address _submissionID,
        uint64 _submissionTime
    ) external;

    function revokeHumanityManually(address _submissionID) external;

    /* Views */
    function isRegistered(address _submissionID) external view returns (bool);

    function submissionDuration() external view returns (uint64);

    function getSubmissionInfo(address _submissionID)
        external
        view
        returns (
            bool registered,
            bool hasVouched,
            uint64 submissionTime,
            uint160 qid,
            RequesterStatus status,
            uint256 lastRequestID
        );
}
