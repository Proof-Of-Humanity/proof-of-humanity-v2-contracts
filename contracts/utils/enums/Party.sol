// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

enum Party {
    None, // Party per default when there is no challenger or requester. Also used for unconclusive ruling.
    Requester, // Party that made the request to change a status.
    Challenger // Party that challenged the request to change a status.
}
