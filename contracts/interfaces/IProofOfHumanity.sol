// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

interface IProofOfHumanity {
    /* Manual adding/removing */

    function grantSoulManually(
        uint160 _qid,
        address _submissionID,
        uint64 _submissionTime
    ) external returns (bool success);

    function revokeSoulManually(address _submissionID) external returns (uint64 expirationTime, uint160 soulID);

    /* Views */

    function isSoulClaimed(uint160 _soulId) external view returns (bool);

    function isRegistered(address _submissionID) external view returns (bool);

    function getSoulInfo(uint160 _soulId)
        external
        view
        returns (
            bool vouching,
            bool pendingRevokal,
            uint64 nbPendingRequests,
            uint64 expirationTime,
            address owner,
            uint256 nbRequests
        );
}
