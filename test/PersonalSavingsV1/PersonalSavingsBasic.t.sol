// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PersonalSavingsV1} from "../../src/PersonalSavingsV1.sol";
import {PersonalSavingsV1Setup} from "./PersonalSavingsSetup.t.sol";

contract PersonalSavingsV1BasicTests is PersonalSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function testCreatePersonalGoal() public {
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 1000e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            });

        uint256 gid = personalSavings.createPersonalGoal(params);

        (
            address owner,
            ,
            uint256 targetAmount,
            uint256 currentAmount,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = personalSavings.personalGoals(gid);
        assertEq(owner, alice);
        assertEq(targetAmount, 1000e18);
        assertEq(currentAmount, 50e18); // First contribution made automatically

        // Should start with DEFAULT_SCORE reputation
        assertEq(reputation.getReputation(alice), 300);
    }

    function testcontributeToGoal() public {
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 200e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            });

        uint256 gid = personalSavings.createPersonalGoal(params);

        // Wait for the contribution interval before making second contribution
        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        personalSavings.contributeToGoal(gid);

        (, , , uint256 currentAmount, , , , , , , ) = personalSavings
            .personalGoals(gid);
        assertEq(currentAmount, 100e18); // First contribution (50) + second contribution (50)

        // Should still have DEFAULT_SCORE reputation (not complete yet)
        assertEq(reputation.getReputation(alice), 300);
    }

    function testcompleteGoal() public {
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 100e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            });

        uint256 gid = personalSavings.createPersonalGoal(params);
        // First contribution already made (50e18)

        // Make one more contribution to reach target (total 100e18)
        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        personalSavings.contributeToGoal(gid);

        vm.prank(alice);
        personalSavings.completeGoal(gid);

        // Should gain reputation for completing goal (+10) = 10 * 5 = 50 points
        // The actual score is 350 (300 + 50)
        assertEq(reputation.getReputation(alice), 350);
    }

    function testEarlyWithdrawalPenalty() public {
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 200e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            });

        uint256 gid = personalSavings.createPersonalGoal(params);
        // First contribution already made (50e18)

        // Withdraw early from the initial contribution
        vm.prank(alice);
        personalSavings.withdrawFromGoal(gid, 25e18);

        // Should lose reputation for early withdrawal but not below MIN_SCORE (300)
        assertEq(reputation.getReputation(alice), 300);
    }

    function testMultipleGoalReputationTracking() public {
        // Create first goal
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params1 = PersonalSavingsV1
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 100e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            });

        uint256 gid1 = personalSavings.createPersonalGoal(params1);
        // First contribution already made (50e18)

        // Create second goal
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params2 = PersonalSavingsV1
            .CreateGoalParams({
                name: "Vacation Fund",
                targetAmount: 200e18,
                contributionAmount: 100e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            });

        uint256 gid2 = personalSavings.createPersonalGoal(params2);
        // First contribution already made (100e18)

        // Complete first goal - need only one more contribution
        vm.warp(block.timestamp + 7 days);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid1);
        personalSavings.completeGoal(gid1);
        vm.stopPrank();

        // Should have reputation from first goal (10 on complete) added to DEFAULT_SCORE
        // The actual score is 350 (300 + 50)
        assertEq(reputation.getReputation(alice), 350);

        // Complete second goal - need only one more contribution
        vm.warp(block.timestamp + 7 days + 1);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid2);
        personalSavings.completeGoal(gid2);
        vm.stopPrank();

        // Should have cumulative reputation from both goals (10 + 10) added to DEFAULT_SCORE
        // The actual score is 400 (300 + 50 + 50)
        assertEq(reputation.getReputation(alice), 400);
    }

    function testCreateGoal_MonthlyFrequency() public {
        vm.prank(alice);
        uint256 gid = personalSavings.createPersonalGoal(
            PersonalSavingsV1.CreateGoalParams({
                name: "Monthly Goal",
                targetAmount: 200e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.MONTHLY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            })
        );
        // Goal created with MONTHLY frequency - first contribution already made
        // Verify by making second contribution after interval
        vm.warp(block.timestamp + 31 days);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid);
        vm.stopPrank();
    }

    function testWithdraw_HighProgressPenalty() public {
        vm.prank(alice);
        uint256 gid = personalSavings.createPersonalGoal(
            PersonalSavingsV1.CreateGoalParams({
                name: "High Progress",
                targetAmount: 200e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            })
        );
        // First contribution already made (50e18)
        uint256 t = block.timestamp;
        t += 7 days + 1;
        vm.warp(t);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid);
        t += 7 days + 1;
        vm.warp(t);
        personalSavings.contributeToGoal(gid);
        // Now at 75% progress (150e18 / 200e18) - penalty should apply
        uint256 balBefore = USDm.balanceOf(alice);
        personalSavings.withdrawFromGoal(gid, 50e18);
        uint256 balAfter = USDm.balanceOf(alice);
        assertLt(balAfter - balBefore, 50e18); // penalty applied
        vm.stopPrank();
    }

    function testGetUserGoals() public {
        uint256 gid1 = _createDefaultGoal(alice);
        vm.prank(alice);
        uint256 gid2 = personalSavings.createPersonalGoal(
            PersonalSavingsV1.CreateGoalParams({
                name: "Goal 2",
                targetAmount: 100e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            })
        );
        uint256[] memory goals = personalSavings.getUserGoals(alice);
        assertEq(goals.length, 2);
        assertEq(goals[0], gid1);
        assertEq(goals[1], gid2);
    }

    function testContribute_DailyFrequency() public {
        vm.prank(alice);
        uint256 gid = personalSavings.createPersonalGoal(
            PersonalSavingsV1.CreateGoalParams({
                name: "Daily",
                targetAmount: 100e18,
                contributionAmount: 10e18,
                frequency: PersonalSavingsV1.Frequency.DAILY,
                deadline: block.timestamp + 365 days,
                enableYield: false
            })
        );
        // First contribution already made
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid);
        vm.stopPrank();
    }
}
