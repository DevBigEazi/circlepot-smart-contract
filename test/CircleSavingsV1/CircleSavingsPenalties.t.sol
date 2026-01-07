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
        deal(address(USDm), alice, contribution);
        deal(address(USDm), bob, contribution);
        deal(address(USDm), charlie, contribution);
        deal(address(USDm), david, contribution);
        deal(address(USDm), eve, contribution);

        // other members contribute
        vm.prank(alice);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);

        // warp to after grace period
        vm.warp(block.timestamp + 8 days + 49 hours);

        (CircleSavingsV1.Member memory bobMemberBefore, , ) = circleSavings
            .getMemberInfo(cid, bob);
        uint256 collateralBefore = bobMemberBefore.collateralLocked;

        vm.prank(bob);
        circleSavings.contribute(cid);

        (CircleSavingsV1.Member memory bobMemberAfter, , ) = circleSavings
            .getMemberInfo(cid, bob);
        uint256 collateralAfter = bobMemberAfter.collateralLocked;

        uint256 expectedDeduction = 100e18 +
            (100e18 * circleSavings.LATE_FEE_BPS()) /
            10000;
        assertEq(collateralBefore - collateralAfter, expectedDeduction);
        (, , , , , , , uint256 latePayments, ) = reputation
            .getUserReputationDetails(bob);
        assertEq(latePayments, 1);
    }

    function test_RoundCompletePayoutAndReputationIncrease() public {
        uint256 cid = _createAndStartCircle();

        // Fund everyone for contributions
        uint256 contribution = 100e18;
        deal(address(USDm), alice, contribution);
        deal(address(USDm), bob, contribution);
        deal(address(USDm), charlie, contribution);
        deal(address(USDm), david, contribution);
        deal(address(USDm), eve, contribution);

        uint256 aliceBalBefore = USDm.balanceOf(alice);

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

        uint256 aliceBalAfter = USDm.balanceOf(alice);
        // Creator receives pot (500) minus their own contribution (100)
        assertEq(aliceBalAfter - aliceBalBefore, 500e18 - 100e18);

        (uint256 positiveActions, , uint256 completed, ) = reputation
            .getUserReputationData(alice);
        assertEq(
            completed,
            0,
            "Should not have completed circle yet (only 1 round done)"
        );
        assertGt(positiveActions, 0, "Should have positive actions");
    }

    function test_RoundAdvanceWithReputation() public {
        uint256 cid = _createAndStartCircle();

        // Complete round 1
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

        // Check that round advanced
        (, CircleSavingsV1.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(status.currentRound, 2);

        // Check that first position holder got reputation increase
        uint256 rep = reputation.getReputation(alice);
        assertGt(rep, 0);
    }

    function test_Payout_CreatorReceivesFullAmount() public {
        uint256 cid = _createAndStartCircle();
        uint256 balBefore = USDm.balanceOf(alice);
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
        uint256 balAfter = USDm.balanceOf(alice);
        assertGt(balAfter, balBefore);
    }

    function test_Payout_NonCreatorWithPlatformFee() public {
        uint256 cid = _createAndStartCircle();
        // Complete round 1 (alice gets payout)
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
        // Round 2 - bob gets payout (non-creator, fee applies)
        uint256 balBefore = USDm.balanceOf(bob);
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
        uint256 balAfter = USDm.balanceOf(bob);
        assertGt(balAfter, balBefore);
        // Payout should be less than full 500e18 due to 1% fee
        assertLt(balAfter - balBefore, 500e18);
    }

    function test_CircleCompletion_CollateralReleased() public {
        uint256 cid = _createAndStartCircle();
        uint256 balBefore = USDm.balanceOf(alice);
        // Complete all 5 rounds
        for (uint256 round = 0; round < 5; round++) {
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
            vm.warp(block.timestamp + 7 days);
        }
        // Alice should receive collateral back
        uint256 balAfter = USDm.balanceOf(alice);
        assertGt(balAfter, balBefore);
    }
}
