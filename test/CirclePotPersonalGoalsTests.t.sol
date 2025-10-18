// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotPersonalGoalsTests
 * @notice Tests for personal savings goals functionality
 */
contract CirclePotPersonalGoalsTests is CirclePotV1Test {
    function test_CreatePersonalGoal() public {
        vm.startPrank(alice);

        CirclePotV1.CreateGoalParams memory params = CirclePotV1
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 1000e18,
                contributionAmount: 50e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            });

        uint256 goalId = circlePot.createPersonalGoal(params);

        assertEq(goalId, 1);

        (
            address goalOwner,
            string memory name,
            uint256 targetAmount,
            uint256 currentAmount,
            ,
            ,
            ,
            ,
            bool isActive,

        ) = circlePot.personalGoals(goalId);

        assertEq(goalOwner, alice);
        assertEq(name, "Emergency Fund");
        assertEq(targetAmount, 1000e18);
        assertEq(currentAmount, 0);
        assertTrue(isActive);

        vm.stopPrank();
    }

    function test_ContributeToGoal() public {
        uint256 goalId = _createDefaultGoal(alice);

        vm.prank(alice);
        circlePot.ContributeToGoal(goalId);

        (, , , uint256 currentAmount, , , , , , ) = circlePot.personalGoals(
            goalId
        );
        assertEq(currentAmount, 50e18);
    }

    function test_CompleteGoal() public {
        uint256 goalId = _createDefaultGoal(alice);

        uint256 aliceBalanceBefore = cUSD.balanceOf(alice);

        vm.startPrank(alice);
        for (uint i = 0; i < 20; i++) {
            if (i > 0) {
                vm.warp(block.timestamp + 8 days);
            }
            circlePot.ContributeToGoal(goalId);
        }

        uint256 aliceBalanceAfterContributions = cUSD.balanceOf(alice);

        circlePot.CompleteGoal(goalId);
        vm.stopPrank();

        uint256 aliceBalanceAfter = cUSD.balanceOf(alice);

        (, , , , , , , , bool isActive, ) = circlePot.personalGoals(goalId);
        assertFalse(isActive);

        assertEq(aliceBalanceAfter, aliceBalanceBefore);

        assertEq(aliceBalanceAfter - aliceBalanceAfterContributions, 1000e18);
    }

    function test_WithdrawFromGoalWithPenalty() public {
        uint256 goalId = _createDefaultGoal(alice);

        vm.startPrank(alice);
        circlePot.ContributeToGoal(goalId);

        uint256 aliceBalanceBefore = cUSD.balanceOf(alice);

        circlePot.withdrawFromGoal(goalId, 50e18);
        vm.stopPrank();

        uint256 aliceBalanceAfter = cUSD.balanceOf(alice);

        assertEq(aliceBalanceAfter - aliceBalanceBefore, 49.5e18);
    }

    function test_RevertWithdrawFromGoalInsufficientBalance() public {
        uint256 goalId = _createDefaultGoal(alice);

        vm.prank(alice);
        vm.expectRevert(CirclePotV1.InsufficientBalance.selector);
        circlePot.withdrawFromGoal(goalId, 50e18);
    }

    function test_RevertCreateGoalInvalidAmount() public {
        vm.startPrank(alice);

        CirclePotV1.CreateGoalParams memory params = CirclePotV1
            .CreateGoalParams({
                name: "Too Small",
                targetAmount: 5e18,
                contributionAmount: 1e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            });

        vm.expectRevert(CirclePotV1.InvalidGoalAmount.selector);
        circlePot.createPersonalGoal(params);

        vm.stopPrank();
    }

    function test_RevertCreateGoalInvalidDeadline() public {
        vm.startPrank(alice);

        vm.warp(block.timestamp + 365 days);

        CirclePotV1.CreateGoalParams memory params = CirclePotV1
            .CreateGoalParams({
                name: "Past Deadline",
                targetAmount: 1000e18,
                contributionAmount: 50e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                deadline: block.timestamp - 1 days
            });

        vm.expectRevert(CirclePotV1.InvalidDeadline.selector);
        circlePot.createPersonalGoal(params);

        vm.stopPrank();
    }

    function test_RevertContributeToGoalNotOwner() public {
        uint256 goalId = _createDefaultGoal(alice);

        vm.prank(bob);
        vm.expectRevert(CirclePotV1.NotGoalOwner.selector);
        circlePot.ContributeToGoal(goalId);
    }

    function test_RevertCompleteGoalNotReached() public {
        uint256 goalId = _createDefaultGoal(alice);

        vm.startPrank(alice);
        circlePot.ContributeToGoal(goalId);

        vm.expectRevert(CirclePotV1.InsufficientBalance.selector);
        circlePot.CompleteGoal(goalId);

        vm.stopPrank();
    }

    function test_RevertWithdrawFromInactiveGoal() public {
        uint256 goalId = _createDefaultGoal(alice);

        vm.startPrank(alice);

        for (uint i = 0; i < 20; i++) {
            if (i > 0) vm.warp(block.timestamp + 8 days);
            circlePot.ContributeToGoal(goalId);
        }

        circlePot.CompleteGoal(goalId);

        vm.expectRevert(CirclePotV1.GoalNotActive.selector);
        circlePot.withdrawFromGoal(goalId, 1e18);

        vm.stopPrank();
    }

    function test_WithdrawGoalWithDifferentPenalties() public {
        // Test 1: Less than 25% progress (1% penalty)
        uint256 goalId1 = _createDefaultGoal(alice);
        vm.startPrank(alice);
        circlePot.ContributeToGoal(goalId1);
        vm.warp(block.timestamp + 8 days);
        circlePot.ContributeToGoal(goalId1);
        vm.warp(block.timestamp + 8 days);
        circlePot.ContributeToGoal(goalId1);
        vm.warp(block.timestamp + 8 days);
        circlePot.ContributeToGoal(goalId1);
        uint256 balBefore1 = cUSD.balanceOf(alice);
        circlePot.withdrawFromGoal(goalId1, 100e18);
        uint256 balAfter1 = cUSD.balanceOf(alice);
        assertEq(balAfter1 - balBefore1, 99e18);
        vm.stopPrank();

        // Test 2: 25-50% progress (0.6% penalty)
        uint256 goalId2 = _createDefaultGoal(bob);
        vm.startPrank(bob);
        for (uint i = 0; i < 8; i++) {
            if (i > 0) vm.warp(block.timestamp + 8 days);
            circlePot.ContributeToGoal(goalId2);
        }
        uint256 balBefore2 = cUSD.balanceOf(bob);
        circlePot.withdrawFromGoal(goalId2, 100e18);
        uint256 balAfter2 = cUSD.balanceOf(bob);
        assertEq(balAfter2 - balBefore2, 99.4e18);
        vm.stopPrank();

        // Test 3: 50-75% progress (0.3% penalty)
        uint256 goalId3 = _createDefaultGoal(charlie);
        vm.startPrank(charlie);
        for (uint i = 0; i < 13; i++) {
            if (i > 0) vm.warp(block.timestamp + 8 days);
            circlePot.ContributeToGoal(goalId3);
        }
        uint256 balBefore3 = cUSD.balanceOf(charlie);
        circlePot.withdrawFromGoal(goalId3, 100e18);
        uint256 balAfter3 = cUSD.balanceOf(charlie);
        assertEq(balAfter3 - balBefore3, 99.7e18);
        vm.stopPrank();

        // Test 4: 75-100% progress (0.1% penalty)
        uint256 goalId4 = _createDefaultGoal(david);
        vm.startPrank(david);
        for (uint i = 0; i < 18; i++) {
            if (i > 0) vm.warp(block.timestamp + 8 days);
            circlePot.ContributeToGoal(goalId4);
        }
        uint256 balBefore4 = cUSD.balanceOf(david);
        circlePot.withdrawFromGoal(goalId4, 100e18);
        uint256 balAfter4 = cUSD.balanceOf(david);
        assertEq(balAfter4 - balBefore4, 99.9e18);
        vm.stopPrank();
    }

    function test_MultipleGoalsForSameUser() public {
        vm.startPrank(alice);

        CirclePotV1.CreateGoalParams memory params1 = CirclePotV1
            .CreateGoalParams({
                name: "Goal 1",
                targetAmount: 1000e18,
                contributionAmount: 50e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            });

        CirclePotV1.CreateGoalParams memory params2 = CirclePotV1
            .CreateGoalParams({
                name: "Goal 2",
                targetAmount: 2000e18,
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.MONTHLY,
                deadline: block.timestamp + 365 days
            });

        uint256 goalId1 = circlePot.createPersonalGoal(params1);
        uint256 goalId2 = circlePot.createPersonalGoal(params2);

        vm.stopPrank();

        uint256[] memory goals = circlePot.getUserGoals(alice);
        assertEq(goals.length, 2);
        assertEq(goals[0], goalId1);
        assertEq(goals[1], goalId2);
    }
}
