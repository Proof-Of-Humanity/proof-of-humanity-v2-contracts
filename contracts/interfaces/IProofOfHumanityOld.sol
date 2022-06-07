// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import {OldStatus} from "../utils/enums/OldStatus.sol";

interface IProofOfHumanityOld {
    /* Governance */

    function removeSubmissionManually(address _submissionID) external;

    /* Views */

    function isRegistered(address _submissionID) external view returns (bool);

    function getSubmissionInfo(address _submissionID)
        external
        view
        returns (
            OldStatus status,
            uint64 submissionTime,
            uint64 index,
            bool registered,
            bool hasVouched,
            uint256 numberOfRequests
        );
}
