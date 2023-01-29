// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./Base.sol";

contract VouchTest is ProofOfHumanityBase {
    address[3] internal vouchers;

    function setUp() external {
        init();

        poh.changeRequiredNumberOfVouches(uint64(0));

        vouchers[0] = makeAddr("voucher one");
        vouchers[1] = makeAddr("voucher two");
        vouchers[2] = makeAddr("voucher three");

        for (uint i = 0; i < 3; i++) {
            vm.deal(vouchers[i], 20 ether);
            registerVoucher(vouchers[i]);
        }

        poh.changeRequiredNumberOfVouches(2);
    }

    function registerVoucher(address _voucher) internal {
        vm.prank(_voucher);
        poh.claimHumanity{value: params.totalCost}("evidence", "voucher");

        poh.advanceState(_voucher, new address[](0), new ProofOfHumanity.SignatureVouch[](0));
        skip(params.challengePeriodDuration + 1 days);
        poh.executeRequest(bytes20(uint160(_voucher)), 0);
    }

    function testAddingVanillaVouches() external {
        bytes20 humanityId = bytes20(uint160(me));

        assertFalse(poh.vouches(vouchers[0], me, humanityId));

        vm.prank(vouchers[0]);
        vm.expectEmit(true, false, false, true);
        emit VouchAdded(vouchers[0], me, humanityId);
        poh.addVouch(me, humanityId);

        assertTrue(poh.vouches(vouchers[0], me, humanityId));

        poh.claimHumanity("evidence", "tester");

        assertFalse(poh.vouches(vouchers[2], me, humanityId));

        vm.prank(vouchers[2]);
        poh.addVouch(me, humanityId);
        vm.stopPrank();
        assertTrue(poh.vouches(vouchers[2], me, humanityId));
    }

    function testRemovingVanillaVouches() external {
        bytes20 humanityId = bytes20(uint160(me));

        assertFalse(poh.vouches(vouchers[0], me, humanityId));
        vm.prank(vouchers[0]);
        poh.addVouch(me, humanityId);

        assertTrue(poh.vouches(vouchers[0], me, humanityId));

        poh.claimHumanity("evidence", "tester");

        assertTrue(poh.vouches(vouchers[0], me, humanityId));

        vm.prank(vouchers[0]);
        vm.expectEmit(true, false, false, true);
        emit VouchRemoved(vouchers[0], me, humanityId);
        poh.removeVouch(me, humanityId);

        assertFalse(poh.vouches(vouchers[0], me, humanityId));
    }

    function testRevertingOnInsufficientVouches() external {
        bytes20 humanityId = bytes20(uint160(me));

        poh.claimHumanity("evidence", "tester");

        vm.prank(vouchers[0]);
        poh.addVouch(me, humanityId);

        ProofOfHumanity.SignatureVouch[] memory offChainVouches;
        address[] memory onChainVouches = new address[](2);
        onChainVouches[0] = vouchers[0];
        onChainVouches[1] = vouchers[1];

        vm.expectRevert();
        poh.advanceState(me, onChainVouches, offChainVouches);
    }
}
