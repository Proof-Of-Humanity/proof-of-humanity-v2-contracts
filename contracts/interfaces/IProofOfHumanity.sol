// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IProofOfHumanity {
    /* Manual adding/removing */

    function grantManually(bytes20 _qid, address _owner, uint40 _expirationTime) external returns (bool success);

    function revokeManually(address _owner) external returns (uint40 expirationTime, bytes20 humanityId);

    /* Views */

    function isClaimed(bytes20 _humanityId) external view returns (bool);

    function isHuman(address _address) external view returns (bool);

    function boundTo(bytes20 _humanityId) external view returns (address);

    function humanityOf(address _account) external view returns (bytes20 humanityId);

    function getHumanityInfo(
        bytes20 _humanityId
    )
        external
        view
        returns (
            bool vouching,
            bool pendingRevokal,
            uint48 nbPendingRequests,
            uint40 expirationTime,
            address owner,
            uint256 nbRequests
        );
}
