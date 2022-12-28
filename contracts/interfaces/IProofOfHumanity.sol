// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IProofOfHumanity {
    /* Manual adding/removing */

    function grantManually(
        bytes20 _qid,
        address _owner,
        uint64 _submissionTime
    ) external returns (bool success);

    function revokeManually(address _owner) external returns (uint64 expirationTime, bytes20 humanityId);

    /* Views */

    function isClaimed(bytes20 _humanityId) external view returns (bool);

    function isHuman(address _address) external view returns (bool);

    function getHumanityInfo(bytes20 _humanityId)
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
