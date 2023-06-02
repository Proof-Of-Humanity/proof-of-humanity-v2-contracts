// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IForkModule {
    function remove(address _submissionID) external;

    function tryRemove(address _submissionID) external returns (uint40);

    function isRegistered(address _submissionID) external view returns (bool);

    function getSubmissionInfo(address _submissionID) external view returns (bool registered, uint40 expirationTime);
}
