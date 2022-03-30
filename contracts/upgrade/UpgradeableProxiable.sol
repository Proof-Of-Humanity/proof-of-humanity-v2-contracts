// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

contract UpgradeableProxiable {
    //keccak256("proof-of-humanity.proxiable")
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x26974a05cdcf64ad7ce50c30741f81d31ef71478fe0381e3c11c9efc2e25c538;

    address private immutable __self = address(this);

    modifier onlyProxy() {
        require(address(this) != __self, "Function must be called through delegatecall");
        require(_getImplementation() == __self, "Function must be called through active proxy");
        _;
    }

    function upgradeTo(address _implementation) internal onlyProxy {
        try UpgradeableProxiable(_implementation).proxiableUUID() returns (bytes32 slot) {
            require(slot == _IMPLEMENTATION_SLOT, "ERC1967Upgrade: unsupported proxiableUUID");
        } catch {
            revert("ERC1967Upgrade: new implementation is not UUPS");
        }

        assembly {
            sstore(_IMPLEMENTATION_SLOT, _implementation)
        }
    }

    function _getImplementation() internal view returns (address implementation) {
        assembly {
            implementation := sload(_IMPLEMENTATION_SLOT)
        }
    }

    function proxiableUUID() external pure returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }
}
