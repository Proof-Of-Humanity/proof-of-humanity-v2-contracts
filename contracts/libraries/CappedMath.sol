/**
 * @authors: [@mtsalenc*, @hbarcelos*, @fnanni-0]
 * @reviewers: [@clesaege*, @ferittuncer*, @divyangchauhan, @wadader, @fcanela]
 * @auditors: []
 * @bounties: []
 * @deployments: []
 * SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.20;

/**
 * @title CappedMath
 * @dev Math operations with caps for under and overflow.
 */
library CappedMath {
    uint256 private constant UINT_MAX = type(uint256).max;
    uint40 private constant UINT40_MAX = type(uint40).max;

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
        unchecked {
            return _a - _b;
        }
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

    function addCap40(uint40 _a, uint40 _b) internal pure returns (uint40) {
        unchecked {
            uint40 c = _a + _b;
            return c >= _a ? c : UINT40_MAX;
        }
    }

    function subCap40(uint40 _a, uint40 _b) internal pure returns (uint40) {
        if (_b > _a) return 0;
        unchecked {
            return _a - _b;
        }
    }

    function mulCap40(uint40 _a, uint40 _b) internal pure returns (uint40) {
        // Gas optimization: this is cheaper than requiring '_a' not being zero, but the
        // benefit is lost if '_b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (_a == 0) return 0;

        unchecked {
            uint40 c = _a * _b;
            return c / _a == _b ? c : UINT40_MAX;
        }
    }
}
