// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

enum OldStatus {
    None, // The submission doesn't have a pending status.
    Vouching, // The submission is in the state where it can be vouched for and crowdfunded.
    PendingRegistration, // The submission is in the state where it can be challenged. Or accepted to the list, if there are no challenges within the time limit.
    PendingRemoval // The submission is in the state where it can be challenged. Or removed from the list, if there are no challenges within the time limit.
}
