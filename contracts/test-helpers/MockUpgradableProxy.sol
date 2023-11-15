// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract MockUpgradableProxy {
    // keccak256("proof-of-humanity.proxiable")
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x26974a05cdcf64ad7ce50c30741f81d31ef71478fe0381e3c11c9efc2e25c538;

    function setImplementation(address _implementation) external {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, _implementation)
        }
    }

    function _delegate(address _implementation) internal virtual {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), _implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
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
