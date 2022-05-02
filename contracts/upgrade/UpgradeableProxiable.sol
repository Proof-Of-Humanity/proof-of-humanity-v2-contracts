// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

error UPG_MustBeDelegatecall();
error UPG_MustBeCalledThroughActiveProxy();
error UPG_UnsupportedProxiableUUID();
error UPG_NotUUPS();

abstract contract UpgradeableProxiable {
    // keccak256("proof-of-humanity.proxiable")
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x26974a05cdcf64ad7ce50c30741f81d31ef71478fe0381e3c11c9efc2e25c538;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable state-variable-assignment
    address private immutable __self = address(this);

    modifier onlyProxy() {
        if (address(this) == __self) revert UPG_MustBeDelegatecall();
        if (_getImplementation() != __self) revert UPG_MustBeCalledThroughActiveProxy();
        _;
    }

    function upgradeTo(address _implementation) public onlyProxy {
        _authorizeUpgrade();
        try UpgradeableProxiable(_implementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != _IMPLEMENTATION_SLOT) revert UPG_UnsupportedProxiableUUID();
        } catch {
            revert UPG_NotUUPS();
        }

        assembly {
            sstore(_IMPLEMENTATION_SLOT, _implementation)
        }
    }

    function _authorizeUpgrade() internal virtual;

    function _getImplementation() internal view returns (address implementation) {
        assembly {
            implementation := sload(_IMPLEMENTATION_SLOT)
        }
    }

    function proxiableUUID() external pure returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }
}
