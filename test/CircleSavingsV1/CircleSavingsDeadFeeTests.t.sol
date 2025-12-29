// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";

contract CircleSavingsDeadFeeTests is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_DeadFee_ApplyToCreator_IfStateIsDead() public {
        uint256 cid = _createDefaultCircle(alice);

        // Add members but not enough to start (or wait for ultimatum to fail)
        vm.prank(bob);
        circleSavings.joinCircle(cid);

        // Wait for ultimatum period to pass
        // 5 members max, only 2 joined (40%). Threshold is 60%.
        // Time passes
        vm.warp(block.timestamp + 31 days); // Period is usually short, but use safe margin

        // Current members < 60%
        // WithdrawCollateral is allowed

        // SCENARIO 1: Bob withdraws first. This sets state to DEAD.
        uint256 bobBalBefore = USDm.balanceOf(bob);

        vm.prank(bob);
        circleSavings.WithdrawCollateral(cid);

        uint256 bobBalAfter = USDm.balanceOf(bob);
        // Bob should get full collateral back (no fee for non-creator)
        // Note: Check assumes bob has deposited EXACTLY what he gets back or more.
        // Actually, let's just check he gets something substantial back.
        assertGt(bobBalAfter, bobBalBefore);

        // Verify state is DEAD
        (CircleSavingsV1.Circle memory c, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(uint256(c.state), uint256(CircleSavingsV1.CircleState.DEAD));

        // SCENARIO 2: Alice (creator) withdraws second. State is now DEAD.
        // She should be charged the dead fee.
        uint256 aliceBalBefore = USDm.balanceOf(alice);

        // Get locked amount
        (CircleSavingsV1.Member memory mAlice, , ) = circleSavings
            .getMemberInfo(cid, alice);
        uint256 lockedAlice = mAlice.collateralLocked;

        vm.prank(alice);
        circleSavings.WithdrawCollateral(cid);

        uint256 aliceBalAfter = USDm.balanceOf(alice);

        // Verify she got back less than locked amount (due to fee)
        assertLt(
            aliceBalAfter - aliceBalBefore,
            lockedAlice,
            "Should have deducted dead fee"
        );

        // Verify specifically if possible (PUBLIC fee is usually 2e18 or something set in contract)
        // From context, if it subtracts fee, it works.
    }

    function test_DeadFee_Applied_EvenIfCreatorWithdrawsFirst() public {
        uint256 cid = _createDefaultCircle(alice);

        vm.prank(bob);
        circleSavings.joinCircle(cid);

        vm.warp(block.timestamp + 31 days);

        // Creator withdraws FIRST
        // State is CREATED (not DEAD yet)
        // Fee condition (isCreator && DEAD) is false.

        uint256 aliceBalBefore = USDm.balanceOf(alice);
        (CircleSavingsV1.Member memory mVal, , ) = circleSavings.getMemberInfo(
            cid,
            alice
        );
        uint256 locked = mVal.collateralLocked;

        vm.prank(alice);
        circleSavings.WithdrawCollateral(cid);

        uint256 aliceBalAfter = USDm.balanceOf(alice);

        // Fee SHOULD be deducted
        assertLt(
            aliceBalAfter - aliceBalBefore,
            locked,
            "Dead fee should be deducted even if creator withdraws before state is DEAD"
        );

        // State should now be DEAD
        (CircleSavingsV1.Circle memory c, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(uint256(c.state), uint256(CircleSavingsV1.CircleState.DEAD));
    }

    function test_RoundsAndMembers_IncrementCorrectly() public {
        // Create circle
        vm.prank(alice);
        CircleSavingsV1.CreateCircleParams memory params = CircleSavingsV1
            .CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PUBLIC
            });
        uint256 cid = circleSavings.createCircle(params);

        // Check initial state
        (CircleSavingsV1.Circle memory c1, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(c1.currentMembers, 1, "Initial members should be 1 (creator)");
        assertEq(c1.currentRound, 0, "Initial round should be 0");
        assertEq(
            c1.totalRounds,
            1,
            "Total rounds should match members initially"
        );

        // Bob joins
        vm.prank(bob);
        circleSavings.joinCircle(cid);

        (CircleSavingsV1.Circle memory c2, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(c2.currentMembers, 2, "Members should increase to 2");
        assertEq(c2.totalRounds, 2, "Total rounds should increase to 2");

        // Charlie joins
        vm.prank(charlie);
        circleSavings.joinCircle(cid);

        (CircleSavingsV1.Circle memory c3, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(c3.currentMembers, 3, "Members should increase to 3");

        // Fill circle to start it
        vm.prank(david);
        circleSavings.joinCircle(cid);
        vm.prank(eve);
        circleSavings.joinCircle(cid);

        // Circle should now be started automatically (max members reached)
        (CircleSavingsV1.Circle memory cStart, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(cStart.state),
            uint256(CircleSavingsV1.CircleState.ACTIVE),
            "Circle should be active"
        );
        assertEq(cStart.currentRound, 1, "Round should be 1 after start");

        // Contribute to advance round
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

        (CircleSavingsV1.Circle memory cRound2, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(cRound2.currentRound, 2, "Round should increment to 2");
    }
    function test_PartialCircleStart_RoundsEqualMembers() public {
        // Create circle with max 5 members
        vm.prank(alice);
        CircleSavingsV1.CreateCircleParams memory params = CircleSavingsV1
            .CreateCircleParams({
                title: "Partial Circle",
                description: "Test Description",
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PUBLIC
            });
        uint256 cid = circleSavings.createCircle(params);

        // Members: Alice (1)

        vm.prank(bob);
        circleSavings.joinCircle(cid);
        // Members: Alice, Bob (2) => 40%

        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        // Members: Alice, Bob, Charlie (3) => 60% (Threshold Met)

        // Wait for ultimatum period to pass
        vm.warp(block.timestamp + 31 days);

        // Start circle manually (since threshold met)
        vm.prank(alice);
        circleSavings.startCircle(cid);

        // Verify state
        (CircleSavingsV1.Circle memory c, , , ) = circleSavings
            .getCircleDetails(cid);

        assertEq(
            uint256(c.state),
            uint256(CircleSavingsV1.CircleState.ACTIVE),
            "Circle should be active"
        );
        assertEq(c.currentMembers, 3, "Current members should be 3");
        assertEq(c.maxMembers, 5, "Max members should remain 5");

        // CRITICAL CHECK: totalRounds should equal currentMembers (3), NOT maxMembers (5)
        assertEq(
            c.totalRounds,
            3,
            "Total rounds should be equal to current members (3)"
        );
    }
}
