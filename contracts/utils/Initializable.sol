// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

abstract contract Initializable {
    bool public initialized; // Indicates that the contract has been initialized.

    modifier initializer() {
        require(!initialized, "Contract is already initialized");
        initialized = true;
        _;
    }
}
