// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

enum Status {
    None, // Soul has no ongoing activity.
    Resolving, // Someone tries to claim the soul.
    Revoking // Someone tries to revoke the soul.
}
