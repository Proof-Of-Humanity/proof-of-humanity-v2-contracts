/**
 *  @authors: [@unknownunknown1*, @clesaege]
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 *  @tools: []
 */

pragma solidity 0.8.20;

import {IProofOfHumanity} from "./interfaces/IProofOfHumanity.sol";

/**
 *  @title ProofOfHumanityProxyV2
 *  A proxy contract for ProofOfHumanity that implements a token interface to interact with other dapps.
 *  Note that it isn't an ERC20 and only implements its interface in order to be compatible with Snapshot.
 */
contract ProofOfHumanityProxyV2 {

    // ========== STORAGE ==========

    /// @dev The address that can make governance changes to the parameters of the contract.
    address public governor;

    /// @dev Instance of the ProofOfHumanity contract
    IProofOfHumanity public proofOfHumanity;
    
    string public name = "Human Vote";
    string public symbol = "VOTE";
    uint8 public decimals = 0;

    /* Modifiers */

    modifier onlyGovernor() {
        require(msg.sender == governor);
        _;
    }

    // ========== CONSTRUCTOR ==========

    /** @dev Constructor.
     *  @param _proofOfHumanity The address of the related ProofOfHumanity contract.
     */
    constructor(IProofOfHumanity _proofOfHumanity) {
        proofOfHumanity = _proofOfHumanity;
        governor = msg.sender;
    }


    /** @dev Changes the address of the the related ProofOfHumanity contract.
     *  @param _proofOfHumanity The address of the new contract.
     */
    function changePoH(IProofOfHumanity _proofOfHumanity) external onlyGovernor {
        proofOfHumanity = _proofOfHumanity;
    }
    
    /** @dev Changes the address of the the governor.
     *  @param _governor The address of the new governor.
     */
    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
    }
    

    /** @dev Returns true if the account corresponds to a claimed humanity.
     *  @param _account The account address.
     *  @return Whether the account is registered or not.
     */
    function isHuman(address _account) public view returns (bool) {
        return proofOfHumanity.isHuman(_account);
    }

    // ******************** //
    // *      IERC20      * //
    // ******************** //

    /** @dev Returns the balance of a particular account of the ProofOfHumanity contract.
     *  Note that this function takes the expiration date into account.
     *  @param _account The account address.
     *  @return The balance of the account.
     */
    function balanceOf(address _account) external view returns (uint256) {
        return isHuman(_account) ? 1 : 0;
    }

    /** @dev Returns the count of all humanities that made a registration request at some point.
     *  Note that with the current implementation of ProofOfHumanity it'd be very costly to count only the humanities that are currently registered.
     *  @return The total count of humanities.
     */
    function totalSupply() external view returns (uint256) {
        return proofOfHumanity.getHumanityCount();
    }

    function transfer(address _recipient, uint256 _amount) external pure returns (bool) { return false; }

    function allowance(address _owner, address _spender) external view returns (uint256) {}

    function approve(address _spender, uint256 _amount) external pure returns (bool) { return false; }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external pure returns (bool) { return false; }
} 