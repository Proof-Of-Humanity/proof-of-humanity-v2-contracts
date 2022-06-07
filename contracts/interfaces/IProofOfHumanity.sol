// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import {Status} from "../utils/enums/Status.sol";
import {Phase} from "../utils/enums/Phase.sol";

interface IProofOfHumanity {
    /* Manual adding/removing */

    function grantSoulManually(
        uint160 _qid,
        address _submissionID,
        uint64 _submissionTime
    ) external;

    function revokeSoulManually(address _submissionID) external returns (uint64 claimTime, uint160 soulID);

    /* Views */

    function soulLifespan() external view returns (uint64);

    function boundTo(uint160 _soulID) external view returns (address owner);

    function isRegistered(address _submissionID) external view returns (bool);

    function getSoulInfo(uint160 _soulID)
        external
        view
        returns (
            uint64 claimTime,
            address owner,
            uint256 numberOfRequests,
            Status status
        );

    function getHumanInfo(address _humanID)
        external
        view
        returns (
            bool isVouching,
            uint160 targetSoul,
            uint256 lastRequestID,
            Phase phase
        );
}
