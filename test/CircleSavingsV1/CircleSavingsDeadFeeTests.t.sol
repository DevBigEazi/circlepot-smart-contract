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

        // SCENARIO 1: Bob withdraws first. This triggers bulk release and sets state to DEAD.
        uint256 bobBalBefore = USDm.balanceOf(bob);
        uint256 aliceBalBefore = USDm.balanceOf(alice);

        (CircleSavingsV1.Member memory mVal, , ) = circleSavings.getMemberInfo(
            cid,
            alice
        );
        uint256 aliceLocked = mVal.collateralLocked;

        vm.prank(bob);
        circleSavings.WithdrawCollateral(cid);

        uint256 bobBalAfter = USDm.balanceOf(bob);
        uint256 aliceBalAfter = USDm.balanceOf(alice);

        // Bob should get full collateral back (no fee for non-creator)
        assertGt(bobBalAfter, bobBalBefore);

        // Alice should have ALREADY received her funds (minus fee) automatically
        assertGt(aliceBalAfter, aliceBalBefore);
        assertLt(
            aliceBalAfter - aliceBalBefore,
            aliceLocked,
            "Creator should have been charged dead fee automatically"
        );

        // Verify state is DEAD
        (, CircleSavingsV1.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(status.state),
            uint256(CircleSavingsV1.CircleState.DEAD)
        );

        // SCENARIO 2: Alice attempts to withdraw manually - should revert as already processed
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.NotActiveMember.selector);
        circleSavings.WithdrawCollateral(cid);

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
        (, CircleSavingsV1.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(status.state),
            uint256(CircleSavingsV1.CircleState.DEAD)
        );
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
                visibility: CircleSavingsV1.Visibility.PUBLIC,
                enableYield: true
            });
        uint256 cid = circleSavings.createCircle(params);

        // Check initial state
        (, CircleSavingsV1.CircleStatus memory status1, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            status1.currentMembers,
            1,
            "Initial members should be 1 (creator)"
        );
        assertEq(status1.currentRound, 0, "Initial round should be 0");
        assertEq(
            status1.totalRounds,
            1,
            "Total rounds should match members initially"
        );

        // Bob joins
        vm.prank(bob);
        circleSavings.joinCircle(cid);

        (, CircleSavingsV1.CircleStatus memory status2, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(status2.currentMembers, 2, "Members should increase to 2");
        assertEq(status2.totalRounds, 2, "Total rounds should increase to 2");

        // Charlie joins
        vm.prank(charlie);
        circleSavings.joinCircle(cid);

        (, CircleSavingsV1.CircleStatus memory status3, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(status3.currentMembers, 3, "Members should increase to 3");

        // Fill circle to start it
        vm.prank(david);
        circleSavings.joinCircle(cid);
        vm.prank(eve);
        circleSavings.joinCircle(cid);

        // Circle should now be started automatically (max members reached)
        (, CircleSavingsV1.CircleStatus memory statusStart, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(statusStart.state),
            uint256(CircleSavingsV1.CircleState.ACTIVE),
            "Circle should be active"
        );
        assertEq(statusStart.currentRound, 1, "Round should be 1 after start");

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

        (, CircleSavingsV1.CircleStatus memory statusRound2, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(statusRound2.currentRound, 2, "Round should increment to 2");
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
                visibility: CircleSavingsV1.Visibility.PUBLIC,
                enableYield: true
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

        // Initiate voting to start circle
        vm.prank(alice);
        circleSavings.initiateVoting(cid);

        // All members vote to start
        vm.prank(alice);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
        vm.prank(bob);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
        vm.prank(charlie);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START); // This will trigger early execution

        // Verify state
        (
            CircleSavingsV1.CircleConfig memory config,
            CircleSavingsV1.CircleStatus memory status,
            ,

        ) = circleSavings.getCircleDetails(cid);

        assertEq(
            uint256(status.state),
            uint256(CircleSavingsV1.CircleState.ACTIVE),
            "Circle should be active"
        );
        assertEq(status.currentMembers, 3, "Current members should be 3");
        assertEq(config.maxMembers, 5, "Max members should remain 5");

        // CRITICAL CHECK: totalRounds should equal currentMembers (3), NOT maxMembers (5)
        assertEq(
            status.totalRounds,
            3,
            "Total rounds should be equal to current members (3)"
        );
    }
}
