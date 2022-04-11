/** SPDX-License-Identifier: MIT
 *  @authors: [@clesaege, @n1c01a5, @epiqueras, @ferittuncer]
 *  @reviewers: [@clesaege*, @unknownunknown1*]
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 */

pragma solidity 0.8.11;

import {IArbitrator, IArbitrable} from "@kleros/erc-792/contracts/IArbitrator.sol";

/** @title Centralized Arbitrator
 *  @dev This is a centralized arbitrator deciding alone on the result of disputes. No appeals are possible.
 */
contract MockArbitrator is IArbitrator, IArbitrable {
    struct DisputeStruct {
        IArbitrable arbitrated;
        uint256 choices;
        uint256 fee;
        uint256 ruling;
        DisputeStatus status;
    }

    struct AppealDispute {
        uint256 rulingTime;
        IArbitrator arbitrator;
        uint256 appealDisputeID;
    }

    /* Storage */
    address public owner = msg.sender;
    uint256 public arbitrationPrice; // Not public because arbitrationCost already acts as an accessor.
    uint256 public constant NOT_PAYABLE_VALUE = (2**256 - 2) / 2; // High value to be sure that the appeal is too expensive.
    uint256 public timeOut;

    mapping(uint256 => AppealDispute) public appealDisputes;
    mapping(uint256 => uint256) public appealDisputeIDsToDisputeIDs;
    IArbitrator public arbitrator;
    bytes public arbitratorExtraData; // Extra data to require particular dispute and appeal behaviour.

    DisputeStruct[] public disputes;

    /* Modifiers */
    modifier onlyOwner() {
        require(msg.sender == owner, "Can only be called by the owner.");
        _;
    }
    modifier requireArbitrationFee(bytes memory _extraData) {
        require(msg.value >= arbitrationCost(_extraData), "Not enough ETH to cover arbitration costs.");
        _;
    }

    modifier onlyArbitrator() {
        require(msg.sender == address(arbitrator), "Can only be called by the arbitrator.");
        _;
    }
    modifier requireAppealFee(uint256 _disputeID, bytes memory _extraData) {
        require(msg.value >= appealCost(_disputeID, _extraData), "Not enough ETH to cover appeal costs.");
        _;
    }

    /* Constructor */

    /** @dev Constructs the `AppealableArbitrator` contract.
     *  @param _arbitrationPrice The amount to be paid for arbitration.
     *  @param _arbitrator The back up arbitrator.
     *  @param _arbitratorExtraData Not used by this contract.
     *  @param _timeOut The time out for the appeal period.
     */
    constructor(
        uint256 _arbitrationPrice,
        IArbitrator _arbitrator,
        bytes memory _arbitratorExtraData,
        uint256 _timeOut
    ) {
        arbitrationPrice = _arbitrationPrice;
        timeOut = _timeOut;
    }

    /** @dev Set the arbitration price. Only callable by the owner.
     *  @param _arbitrationPrice Amount to be paid for arbitration.
     */
    function setArbitrationPrice(uint256 _arbitrationPrice) public onlyOwner {
        arbitrationPrice = _arbitrationPrice;
    }

    /** @dev Cost of arbitration. Accessor to arbitrationPrice.
     *  @param _extraData Not used by this contract.
     *  @return fee Amount to be paid.
     */
    function arbitrationCost(bytes memory _extraData) public view override returns (uint256 fee) {
        return arbitrationPrice;
    }

    /** @dev Create a dispute. Must be called by the arbitrable contract.
     *  Must be paid at least arbitrationCost().
     *  @param _choices Amount of choices the arbitrator can make in this dispute. When ruling ruling<=choices.
     *  @param _extraData Can be used to give additional info on the dispute to be created.
     *  @return disputeID ID of the dispute created.
     */
    function createDispute(uint256 _choices, bytes memory _extraData)
        public
        payable
        override
        requireArbitrationFee(_extraData)
        returns (uint256 disputeID)
    {
        disputes.push(
            DisputeStruct({
                arbitrated: IArbitrable(msg.sender),
                choices: _choices,
                fee: msg.value,
                ruling: 0,
                status: DisputeStatus.Waiting
            })
        ); // Create the dispute
        disputeID = disputes.length - 1;
        emit DisputeCreation(disputeID, IArbitrable(msg.sender));
    }

    /** @dev Give a ruling. UNTRUSTED.
     *  @param _disputeID ID of the dispute to rule.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 means "Not able/wanting to make a decision".
     */
    function _giveRuling(uint256 _disputeID, uint256 _ruling) internal {
        DisputeStruct storage dispute = disputes[_disputeID];
        require(_ruling <= dispute.choices, "Invalid ruling.");
        require(dispute.status != DisputeStatus.Solved, "The dispute must not be solved already.");

        dispute.ruling = _ruling;
        dispute.status = DisputeStatus.Solved;

        payable(msg.sender).send(dispute.fee); // Avoid blocking.
        dispute.arbitrated.rule(_disputeID, _ruling);
    }

    /* External */

    /** @dev Changes the back up arbitrator.
     *  @param _arbitrator The new back up arbitrator.
     */
    function changeArbitrator(IArbitrator _arbitrator) external onlyOwner {
        arbitrator = _arbitrator;
    }

    /** @dev Changes the time out.
     *  @param _timeOut The new time out.
     */
    function changeTimeOut(uint256 _timeOut) external onlyOwner {
        timeOut = _timeOut;
    }

    /* External Views */

    /** @dev Gets the specified dispute's latest appeal ID.
     *  @param _disputeID The ID of the dispute.
     */
    function getAppealDisputeID(uint256 _disputeID) external view returns (uint256 disputeID) {
        if (appealDisputes[_disputeID].arbitrator != IArbitrator(address(0)))
            disputeID = MockArbitrator(address(appealDisputes[_disputeID].arbitrator)).getAppealDisputeID(
                appealDisputes[_disputeID].appealDisputeID
            );
        else disputeID = _disputeID;
    }

    /* Public */

    /** @dev Appeals a ruling.
     *  @param _disputeID The ID of the dispute.
     *  @param _extraData Additional info about the appeal.
     */
    function appeal(uint256 _disputeID, bytes memory _extraData)
        public
        payable
        override
        requireAppealFee(_disputeID, _extraData)
    {
        if (appealDisputes[_disputeID].arbitrator != IArbitrator(address(0)))
            appealDisputes[_disputeID].arbitrator.appeal{value: msg.value}(
                appealDisputes[_disputeID].appealDisputeID,
                _extraData
            );
        else {
            appealDisputes[_disputeID].arbitrator = arbitrator;
            appealDisputes[_disputeID].appealDisputeID = arbitrator.createDispute{value: msg.value}(
                disputes[_disputeID].choices,
                _extraData
            );
            appealDisputeIDsToDisputeIDs[appealDisputes[_disputeID].appealDisputeID] = _disputeID;
        }
    }

    /** @dev Gives a ruling.
     *  @param _disputeID The ID of the dispute.
     *  @param _ruling The ruling.
     */
    function giveRuling(uint256 _disputeID, uint256 _ruling) public {
        require(disputes[_disputeID].status != DisputeStatus.Solved, "The specified dispute is already resolved.");
        if (appealDisputes[_disputeID].arbitrator != IArbitrator(address(0))) {
            require(
                IArbitrator(msg.sender) == appealDisputes[_disputeID].arbitrator,
                "Appealed disputes must be ruled by their back up arbitrator."
            );
            _giveRuling(_disputeID, _ruling);
        } else {
            require(msg.sender == owner, "Not appealed disputes must be ruled by the owner.");
            if (disputes[_disputeID].status == DisputeStatus.Appealable) {
                if (block.timestamp - appealDisputes[_disputeID].rulingTime > timeOut)
                    _giveRuling(_disputeID, disputes[_disputeID].ruling);
                else revert("Time out time has not passed yet.");
            } else {
                disputes[_disputeID].ruling = _ruling;
                disputes[_disputeID].status = DisputeStatus.Appealable;
                appealDisputes[_disputeID].rulingTime = block.timestamp;
                emit AppealPossible(_disputeID, disputes[_disputeID].arbitrated);
            }
        }
    }

    /** @dev Give a ruling for a dispute. Must be called by the arbitrator.
     *  The purpose of this function is to ensure that the address calling it has the right to rule on the contract.
     *  @param _disputeID ID of the dispute in the IArbitrator contract.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
     */
    function rule(uint256 _disputeID, uint256 _ruling) public override onlyArbitrator {
        emit Ruling(IArbitrator(msg.sender), _disputeID, _ruling);

        executeRuling(_disputeID, _ruling);
    }

    /* Public Views */

    /** @dev Gets the cost of appeal for the specified dispute.
     *  @param _disputeID The ID of the dispute.
     *  @param _extraData Additional info about the appeal.
     */
    function appealCost(uint256 _disputeID, bytes memory _extraData) public view override returns (uint256 cost) {
        if (appealDisputes[_disputeID].arbitrator != IArbitrator(address(0)))
            cost = appealDisputes[_disputeID].arbitrator.appealCost(
                appealDisputes[_disputeID].appealDisputeID,
                _extraData
            );
        else if (disputes[_disputeID].status == DisputeStatus.Appealable) cost = arbitrator.arbitrationCost(_extraData);
        else cost = NOT_PAYABLE_VALUE;
    }

    /** @dev Gets the status of the specified dispute.
     *  @param _disputeID The ID of the dispute.
     */
    function disputeStatus(uint256 _disputeID) public view override returns (DisputeStatus status) {
        if (appealDisputes[_disputeID].arbitrator != IArbitrator(address(0)))
            status = appealDisputes[_disputeID].arbitrator.disputeStatus(appealDisputes[_disputeID].appealDisputeID);
        else status = disputes[_disputeID].status;
    }

    /** @dev Return the ruling of a dispute.
     *  @param _disputeID ID of the dispute to rule.
     *  @return ruling The ruling which would or has been given.
     */
    function currentRuling(uint256 _disputeID) public view override returns (uint256 ruling) {
        if (appealDisputes[_disputeID].arbitrator != IArbitrator(address(0)))
            // Appealed.
            ruling = appealDisputes[_disputeID].arbitrator.currentRuling(appealDisputes[_disputeID].appealDisputeID); // Retrieve ruling from the arbitrator whom the dispute is appealed to.
        else ruling = disputes[_disputeID].ruling; //  Not appealed, basic case.
    }

    /* Internal */

    /** @dev Executes the ruling of the specified dispute.
     *  @param _disputeID The ID of the dispute.
     *  @param _ruling The ruling.
     */
    function executeRuling(uint256 _disputeID, uint256 _ruling) internal {
        require(
            appealDisputes[appealDisputeIDsToDisputeIDs[_disputeID]].arbitrator != IArbitrator(address(0)),
            "The dispute must have been appealed."
        );
        giveRuling(appealDisputeIDsToDisputeIDs[_disputeID], _ruling);
    }

    /** @dev Compute the start and end of the dispute's current or next appeal period, if possible.
     *  @param _disputeID ID of the dispute.
     */
    function appealPeriod(uint256 _disputeID) public view override returns (uint256 start, uint256 end) {
        if (appealDisputes[_disputeID].arbitrator != IArbitrator(address(0)))
            (start, end) = appealDisputes[_disputeID].arbitrator.appealPeriod(
                appealDisputes[_disputeID].appealDisputeID
            );
        else {
            start = appealDisputes[_disputeID].rulingTime;
            require(start != 0, "The specified dispute is not appealable.");
            end = start + timeOut;
        }
    }
}
