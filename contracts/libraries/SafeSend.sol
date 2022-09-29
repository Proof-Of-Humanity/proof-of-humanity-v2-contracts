/**
 * @authors: []
 * @reviewers: []
 * @auditors: []
 * @bounties: []
 * SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.16;

// import {WethLike} from "../interfaces/WethLike.sol";

interface WethLike {
    function deposit() external payable;

    function transfer(address dst, uint256 wad) external;
}

library SafeSend {
    // Set before deploying
    WethLike internal constant W_NATIVE = WethLike(address(0x0));

    function safeSend(address payable _to, uint256 _value) internal {
        if (_to.send(_value)) return;

        W_NATIVE.deposit{value: _value}();
        W_NATIVE.transfer(_to, _value);
    }
}
