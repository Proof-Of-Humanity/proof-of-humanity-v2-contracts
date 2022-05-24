// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

enum Status {
    None, // The submission doesn't have a pending status.
    PendingAcceptance, // The submission is in the state where it can be challenged or accepted, if there are no challenges within the time limit.
    PendingRevokal // The submission is in the state where it can be challenged or revoked, if there are no challenges within the time limit.
}
