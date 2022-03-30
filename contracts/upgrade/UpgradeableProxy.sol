// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

contract UpgradeableProxy {
    //keccak256("proof-of-humanity.proxiable")
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x26974a05cdcf64ad7ce50c30741f81d31ef71478fe0381e3c11c9efc2e25c538;

    constructor(bytes memory _constructData, address _implementation) {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, _implementation)
        }

        (bool success, ) = _implementation.delegatecall(_constructData);
        require(success, "Construction failed");
    }

    function _functionDelegateCall(bytes memory data) internal {
        (bool success, ) = _getImplementation().delegatecall(data);
        require(success, "Delegatecall failed");
    }

    function _delegate(address _implementation) internal {
        assembly {
            // copy incoming call data
            calldatacopy(0, 0, calldatasize())

            // forward call to logic contract
            let result := delegatecall(gas(), _implementation, 0, calldatasize(), 0, 0)

            // retrieve return data
            returndatacopy(0, 0, returndatasize())

            // forward return data back to caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    fallback() external payable {
        _delegate(_getImplementation());
    }

    receive() external payable {
        _delegate(_getImplementation());
    }

    function _getImplementation() internal view returns (address implementation) {
        assembly {
            implementation := sload(_IMPLEMENTATION_SLOT)
        }
    }
}
