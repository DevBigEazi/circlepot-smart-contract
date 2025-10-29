// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";
import {IReputation} from "../../src/interfaces/IReputation.sol";

contract CircleSavingsPenalties is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_LateContributionDeductsCollateralAndMarksLate() public {
        uint256 cid = _createAndStartCircle();

        // Fund everyone for contributions
        uint256 contribution = 100e18;
        deal(address(cUSD), alice, contribution);
        deal(address(cUSD), bob, contribution);
        deal(address(cUSD), charlie, contribution);
        deal(address(cUSD), david, contribution);
        deal(address(cUSD), eve, contribution);

        // other members contribute
        vm.prank(bob);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);

        // warp to after grace period
        vm.warp(block.timestamp + 8 days + 49 hours);

        (CircleSavingsV1.Member memory aliceMemberBefore, , ) = circleSavings
            .getMemberInfo(cid, alice);
        uint256 collateralBefore = aliceMemberBefore.collateralLocked;

        vm.prank(alice);
        circleSavings.contribute(cid);

        (CircleSavingsV1.Member memory aliceMemberAfter, , ) = circleSavings
            .getMemberInfo(cid, alice);
        uint256 collateralAfter = aliceMemberAfter.collateralLocked;

        uint256 expectedDeduction = 100e18 +
            (100e18 * circleSavings.LATE_FEE_BPS()) /
            10000;
        assertEq(collateralBefore - collateralAfter, expectedDeduction);
        (, , uint256 latePayments, ) = reputation.getUserReputationData(alice);
        assertEq(latePayments, 1);
    }

    function test_RoundCompletePayoutAndReputationIncrease() public {
        uint256 cid = _createAndStartCircle();

        // Fund everyone for contributions
        uint256 contribution = 100e18;
        deal(address(cUSD), alice, contribution);
        deal(address(cUSD), bob, contribution);
        deal(address(cUSD), charlie, contribution);
        deal(address(cUSD), david, contribution);
        deal(address(cUSD), eve, contribution);

        uint256 aliceBalBefore = cUSD.balanceOf(alice);

        vm.prank(alice);
        circleSavings.contribute(cid);
        vm.prank(bob);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);

        uint256 aliceBalAfter = cUSD.balanceOf(alice);
        // Creator receives pot (500) minus their own contribution (100)
        assertEq(aliceBalAfter - aliceBalBefore, 500e18 - 100e18);

        (uint256 rep, uint256 completed, , ) = reputation.getUserReputationData(
            alice
        );
        assertEq(completed, 1);
        assertTrue(rep >= 5);
    }
}
