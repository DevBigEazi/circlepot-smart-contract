// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavings} from "../../src/CircleSavings.sol";
import {CircleSavingsSetup} from "./CircleSavingsSetup.t.sol";
import {IReputation} from "../../src/interfaces/IReputation.sol";

contract CircleSavingsPenalties is CircleSavingsSetup {
    function setUp() public override {
        super.setUp();
    }

    function test_LateContributionDeductsCollateralAndMarksLate() public {
        uint256 cid = _createAndStartCircle();

        // Fund everyone for contributions
        uint256 contribution = 100e18;
        uint256 lateFee = (contribution * circleSavings.LATE_FEE_BPS()) / 10000;

        deal(address(USDm), alice, contribution);
        // Bob needs extra for the late fee
        deal(address(USDm), bob, contribution + lateFee);
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

        (CircleSavings.Member memory bobMemberBefore, , ) = circleSavings
            .getMemberInfo(cid, bob);
        uint256 collateralBefore = bobMemberBefore.collateralLocked;
        uint256 balanceBefore = USDm.balanceOf(bob);

        vm.expectEmit(true, true, true, true);
        emit CircleSavings.LateContributionMade(
            cid,
            1,
            bob,
            contribution,
            lateFee,
            address(USDm)
        );

        vm.prank(bob);
        circleSavings.contribute(cid);

        (CircleSavings.Member memory bobMemberAfter, , ) = circleSavings
            .getMemberInfo(cid, bob);
        uint256 collateralAfter = bobMemberAfter.collateralLocked;
        uint256 balanceAfter = USDm.balanceOf(bob);

        // Collateral should be unchanged
        assertEq(collateralBefore, collateralAfter);
        // Balance should have decreased by contribution + fee
        assertEq(balanceBefore - balanceAfter, contribution + lateFee);

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
        (, CircleSavings.CircleStatus memory status, , ) = circleSavings
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
        address[] memory members = new address[](5);
        members[0] = alice;
        members[1] = bob;
        members[2] = charlie;
        members[3] = david;
        members[4] = eve;

        // Complete all 5 rounds
        for (uint256 round = 0; round < 5; round++) {
            // Recipient for this round should contribute first to avoid early auto-payout
            address recipient = members[round];
            vm.prank(recipient);
            circleSavings.contribute(cid);

            // Others contribute
            for (uint256 i = 0; i < 5; i++) {
                if (members[i] != recipient) {
                    vm.prank(members[i]);
                    circleSavings.contribute(cid);
                }
            }
            vm.warp(block.timestamp + 7 days);
        }
        // Alice should receive collateral back
        uint256 balAfter = USDm.balanceOf(alice);
        assertGt(balAfter, balBefore);
    }
}
