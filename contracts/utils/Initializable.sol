// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

error AlreadyInitialized();

abstract contract Initializable {
    bool public initialized; // Indicates that the contract has been initialized.

    modifier initializer() {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        _;
    }
}
