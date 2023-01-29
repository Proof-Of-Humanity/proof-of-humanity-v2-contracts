// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "src/interfaces/IArbitrator.sol";
import {ProofOfHumanity} from "src/ProofOfHumanity.sol";
import {MockArbitrator} from "src/test-helpers/MockArbitrator.sol";

import "forge-std/Test.sol";
import "./Events.sol";

contract ProofOfHumanityBase is Test, ProofOfHumanityEvents {
    struct Parameters {
        IArbitrator arbitrator;
        string registrationMetaEvidence;
        string clearingMetaEvidence;
        bytes arbitratorExtraData;
        uint64 humanityLifespan;
        uint64 renewalPeriodDuration;
        uint64 challengePeriodDuration;
        uint64 requiredNumberOfVouches;
        uint[3] multipliers;
        uint arbitrationCost;
        uint requestBaseDeposit;
        uint appealTimeOut;
        uint totalCost;
    }

    uint256 internal constant _MULTIPLIER_DIVISOR = 10000;

    Parameters internal params;

    MockArbitrator internal arbitrator;

    ProofOfHumanity internal poh;

    address internal me = address(this);

    fallback() external payable {}
    receive() external payable {}

    function init() internal {
        params.arbitratorExtraData = bytes.concat(bytes32(uint(0x85)));
        params.registrationMetaEvidence = "registration_meta";
        params.clearingMetaEvidence = "clearing_meta";

        params.humanityLifespan = 8 weeks;
        params.renewalPeriodDuration = 2 weeks;
        params.challengePeriodDuration = 3 days;
        params.appealTimeOut = 1 days;

        params.requiredNumberOfVouches = uint64(1);

        params.arbitrationCost = 1 ether;
        params.requestBaseDeposit = 10 ether;
        params.totalCost = params.arbitrationCost + params.requestBaseDeposit;

        params.multipliers = [uint(5000), uint(2000), uint(8000)];

        arbitrator = new MockArbitrator(params.arbitrationCost, params.appealTimeOut);
        params.arbitrator = IArbitrator(address(arbitrator));

        vm.deal(me, params.arbitrationCost);
        arbitrator.createDispute{value: params.arbitrationCost}(3, bytes.concat(bytes32(0)));

        poh = new ProofOfHumanity();
        poh.initialize(
            params.arbitrator,
            params.arbitratorExtraData,
            params.registrationMetaEvidence,
            params.clearingMetaEvidence,
            params.requestBaseDeposit,
            params.humanityLifespan,
            params.renewalPeriodDuration,
            params.challengePeriodDuration,
            params.multipliers,
            params.requiredNumberOfVouches
        );
    }
}
