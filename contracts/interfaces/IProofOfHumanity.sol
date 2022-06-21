// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

// import {Phase} from "../utils/enums/Phase.sol";

interface IProofOfHumanity {
    enum Phase {
        None, // Soul has no ongoing activity.
        Claiming, // Soul is in the process of someone claiming it.
        Revoking // Soul is in the process of someone revoking it.
    }

    /* Manual adding/removing */

    function grantSoulManually(
        uint160 _qid,
        address _submissionID,
        uint64 _submissionTime
    ) external;

    function revokeSoulManually(address _submissionID) external returns (uint64 expirationTime, uint160 soulID);

    /* Views */

    function isSoulClaimed(uint160 _soulId) external view returns (bool);

    function isRegistered(address _submissionID) external view returns (bool);

    function getSoulInfo(uint160 _soulId)
        external
        view
        returns (
            bool vouching,
            uint64 expirationTime,
            address owner,
            uint256 numberOfRequests,
            Phase phase
        );
}
