// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IProofOfHumanity {
    function isHuman(address _account) external view returns (bool);

    function humanityOf(address _account) external view returns (bytes20);
}

interface ERC20 {
    function transfer(address _to, uint256 _value) external returns (bool success);

    function approve(address _spender, uint256 _value) external returns (bool success);

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool success);
}

interface IGCT is ERC20 {
    function addDelegatedTrustee(address _member) external;

    function addMemberToken(address _member) external;

    function removeMemberToken(address _member) external;

    function mintDelegate(
        address _trustedBy,
        address _collateral,
        uint256 _amount
    ) external returns (uint256);
}

interface Token is ERC20 {
    function owner() external view returns (address);
}

interface IHub {
    function organizationSignup() external;

    function userToToken(address) external returns (address);

    function tokenToUser(address) external returns (address);

    function trust(address, uint256) external;

    function transferThrough(
        address[] memory tokenOwners,
        address[] memory srcs,
        address[] memory dests,
        uint256[] memory wads
    ) external;
}

/** @title PoHGroupCircleManager
 *  @dev Is GCT Owner
 *  @dev Is GCT treasury
 *  @dev Is Organization in hub?
 */
contract PoHGroupCircleManager {
    // ========== STORAGE ==========

    address public governor;

    IProofOfHumanity public poh;
    IGCT public gct;
    IHub public hub;

    mapping(bytes20 => address) public humanityToAccount;

    // ========== CONSTRUCTOR ==========

    constructor(
        address _poh,
        address _gct,
        address _hub
    ) {
        governor = msg.sender;
        poh = IProofOfHumanity(_poh);
        gct = IGCT(_gct);
        hub = IHub(_hub);
    }

    // ========== ACCESS ==========

    modifier onlyGovernor() {
        require(msg.sender == governor, "Not governor");
        _;
    }

    // ========== GOVERNANCE ==========

    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
    }

    function changePoH(address _poh) external onlyGovernor {
        poh = IProofOfHumanity(_poh);
    }

    function changeGCT(address _gct) external onlyGovernor {
        gct = IGCT(_gct);
    }

    function changeHub(address _hub) external onlyGovernor {
        hub = IHub(_hub);
    }

    function setup() external onlyGovernor {
        hub.organizationSignup();
        gct.addDelegatedTrustee(address(this));
    }

    // Trust must be called by this contract (as a delegate) on Hub
    function trust(address _trustee) external onlyGovernor {
        hub.trust(_trustee, 100);
    }

    // ========== FUNCTIONS ==========

    function addHuman(address _account) external {
        bytes20 humanity = poh.humanityOf(_account);
        require(humanity != bytes20(0x0), "Not registered on PoH");

        if (humanityToAccount[humanity] == address(0x0)) humanityToAccount[humanity] = _account;
        else require(humanityToAccount[humanity] == _account, "Can't reassign humanity");

        address humanityToken = hub.userToToken(_account);
        require(humanityToken != address(0x0), "No corresponding token");

        gct.addMemberToken(humanityToken);
    }

    function removeHuman(address _account) external {
        require(!poh.isHuman(_account), "Must no longer be registered on PoH");
        gct.removeMemberToken(hub.userToToken(_account));
    }

    function redeem(
        address _redeemer,
        uint256 _wad,
        address _collateral
    ) external {
        _redeem(_redeemer, _collateral, _wad);
    }

    function redeem(uint256 _wad, address _collateral) external {
        _redeem(msg.sender, _collateral, _wad);
    }

    function _redeem(
        address _redeemer,
        address _collateral,
        uint256 _wad
    ) internal {
        require(poh.isHuman(hub.tokenToUser(_collateral)), "Collateral owner not registered on PoH");
        require(gct.transferFrom(_redeemer, address(0x0), _wad), "Burning group tokens failed");
        Token(_collateral).transfer(_redeemer, _wad);
    }

    function redeemMany(
        uint256 _wad,
        address[] memory _collateral,
        uint256[] memory _amount
    ) external {
        require(gct.transferFrom(msg.sender, address(0x0), _wad), "Burning group tokens failed");

        uint256 toTransfer;
        uint256 i = 0;
        while (_wad > 0) {
            toTransfer = _amount[i];
            if (toTransfer > _wad) toTransfer = _wad;
            _wad -= toTransfer;

            Token(_collateral[i++]).transfer(msg.sender, toTransfer);
        }
    }

    // // Group currently is created from collateral tokens. Collateral is directly part of the directMembers dictionary.
    // function mintTransitive(
    //     address[] memory tokenOwners,
    //     address[] memory srcs,
    //     address[] memory dests,
    //     uint256[] memory wads
    // ) external {
    //     require(tokenOwners[0] == msg.sender, "First token owner must be message sender");
    //     uint256 lastElementIdx = tokenOwners.length - 1;
    //     require(dests[lastElementIdx] == address(this), "GroupCurrencyTokenOwner must be final receiver in the path");
    //     hub.transferThrough(tokenOwners, srcs, dests, wads);
    //     // approve GCT for CRC to be swapped so CRC can be transferred to Treasury
    //     Token(hub.userToToken(tokenOwners[lastElementIdx])).approve(address(gct), wads[lastElementIdx]);
    //     uint256 mintedAmount = IGCT(gct).mintDelegate(address(this), hub.userToToken(tokenOwners[lastElementIdx]), wads[lastElementIdx]);
    //     gct.transfer(srcs[0], mintedAmount);
    // }
}
