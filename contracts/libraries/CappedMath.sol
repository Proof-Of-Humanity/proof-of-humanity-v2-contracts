/**
 * @authors: [@mtsalenc*, @hbarcelos*, @fnanni-0]
 * @reviewers: [@clesaege*, @ferittuncer*]
 * @auditors: []
 * @bounties: []
 * @deployments: []
 * SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.16;

/**
 * @title CappedMath
 * @dev Math operations with caps for under and overflow.
 */
library CappedMath {
    uint256 private constant UINT_MAX = type(uint256).max;
    uint64 private constant UINT64_MAX = type(uint64).max;

    /**
     * @dev Adds two unsigned integers, returns 2^256 - 1 on overflow.
     */
    function addCap(uint256 _a, uint256 _b) internal pure returns (uint256) {
        unchecked {
            uint256 c = _a + _b;
            return c >= _a ? c : UINT_MAX;
        }
    }

    /**
     * @dev Subtracts two integers, returns 0 on underflow.
     */
    function subCap(uint256 _a, uint256 _b) internal pure returns (uint256) {
        if (_b > _a) return 0;
        else return _a - _b;
    }

    /**
     * @dev Multiplies two unsigned integers, returns 2^256 - 1 on overflow.
     */
    function mulCap(uint256 _a, uint256 _b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring '_a' not being zero, but the
        // benefit is lost if '_b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (_a == 0) return 0;

        unchecked {
            uint256 c = _a * _b;
            return c / _a == _b ? c : UINT_MAX;
        }
    }

    function addCap64(uint64 _a, uint64 _b) internal pure returns (uint64) {
        unchecked {
            uint64 c = _a + _b;
            return c >= _a ? c : UINT64_MAX;
        }
    }

    function subCap64(uint64 _a, uint64 _b) internal pure returns (uint64) {
        if (_b > _a) return 0;
        else return _a - _b;
    }

    function mulCap64(uint64 _a, uint64 _b) internal pure returns (uint64) {
        // Gas optimization: this is cheaper than requiring '_a' not being zero, but the
        // benefit is lost if '_b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (_a == 0) return 0;

        unchecked {
            uint64 c = _a * _b;
            return c / _a == _b ? c : UINT64_MAX;
        }
    }
}
