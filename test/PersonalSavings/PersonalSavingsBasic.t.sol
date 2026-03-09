// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PersonalSavings} from "../../src/PersonalSavings.sol";
import {PersonalSavingsSetup} from "./PersonalSavingsSetup.t.sol";

contract PersonalSavingsBasicTests is PersonalSavingsSetup {
    function setUp() public override {
        super.setUp();
    }

    function testCreatePersonalGoal() public {
        vm.prank(alice);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 1000e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
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
            ,
            uint256 contributionCount
        ) = personalSavings.personalGoals(gid);
        assertEq(owner, alice);
        assertEq(targetAmount, 1000e6);
        assertEq(currentAmount, 50e6); // First contribution made automatically

        // Should start with DEFAULT_SCORE reputation
        assertEq(reputation.getReputation(alice), 300);
    }

    function testcontributeToGoal() public {
        vm.prank(alice);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 200e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });

        uint256 gid = personalSavings.createPersonalGoal(params);

        // Wait for the contribution interval before making second contribution
        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        personalSavings.contributeToGoal(gid, 0);

        (, , , uint256 currentAmount, , , , , , , , ) = personalSavings
            .personalGoals(gid);
        assertEq(currentAmount, 100e6); // First contribution (50) + second contribution (50)

        // Should still have DEFAULT_SCORE reputation (not complete yet)
        assertEq(reputation.getReputation(alice), 300);
    }

    function testcompleteGoal() public {
        vm.prank(alice);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 100e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });

        uint256 gid = personalSavings.createPersonalGoal(params);
        // First contribution already made (50e6)

        // Make one more contribution to reach target (total 100e6)
        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        personalSavings.contributeToGoal(gid, 0);

        vm.prank(alice);
        personalSavings.completeGoal(gid);

        // Should gain reputation for completing goal (+1) = 1 * 5 = 5 points
        // The actual score is 305 (300 + 5)
        assertEq(reputation.getReputation(alice), 305);
    }

    function testEarlyWithdrawalPenalty() public {
        vm.prank(alice);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 200e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });

        uint256 gid = personalSavings.createPersonalGoal(params);
        // First contribution already made (50e6)

        // Withdraw early from the initial contribution
        vm.prank(alice);
        personalSavings.withdrawFromGoal(gid, 25e6);

        // Should lose reputation for early withdrawal but not below MIN_SCORE (300)
        assertEq(reputation.getReputation(alice), 300);
    }

    function testCompleteGoalWithManyContributions() public {
        vm.prank(alice);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Many Contributions",
                targetAmount: 200e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });

        uint256 gid = personalSavings.createPersonalGoal(params); // Count 1

        // Make 3 more contributions (Total 4)
        uint256 nextContribution = block.timestamp + 7 days;
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(nextContribution);
            vm.prank(alice);
            personalSavings.contributeToGoal(gid, 0);
            nextContribution += 7 days;
        }

        vm.prank(alice);
        personalSavings.completeGoal(gid);

        // Should gain reputation for completing goal (+10) = 10 * 5 = 50 points
        // The actual score is 350 (300 + 50) because contributions >= 4
        assertEq(reputation.getReputation(alice), 350);
    }

    function testMultipleGoalReputationTracking() public {
        // Create first goal
        vm.prank(alice);
        PersonalSavings.CreateGoalParams memory params1 = PersonalSavings
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 100e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });

        uint256 gid1 = personalSavings.createPersonalGoal(params1);
        // First contribution already made (50e6)

        // Create second goal
        vm.prank(alice);
        PersonalSavings.CreateGoalParams memory params2 = PersonalSavings
            .CreateGoalParams({
                name: "Vacation Fund",
                targetAmount: 200e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });

        uint256 gid2 = personalSavings.createPersonalGoal(params2);
        // First contribution already made (100e6)

        // Complete first goal - need only one more contribution
        vm.warp(block.timestamp + 7 days);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid1, 0);
        personalSavings.completeGoal(gid1);
        vm.stopPrank();

        // Should have reputation from first goal (1 on complete) added to DEFAULT_SCORE
        // The actual score is 305 (300 + 5)
        assertEq(reputation.getReputation(alice), 305);

        // Complete second goal - need only one more contribution
        vm.warp(block.timestamp + 7 days + 1);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid2, 0);
        personalSavings.completeGoal(gid2);
        vm.stopPrank();

        // Should have cumulative reputation from both goals (1 + 1) added to DEFAULT_SCORE
        // The actual score is 310 (300 + 5 + 5)
        assertEq(reputation.getReputation(alice), 310);
    }

    function testCreateGoal_MonthlyFrequency() public {
        vm.prank(alice);
        uint256 gid = personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Monthly Goal",
                targetAmount: 200e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.MONTHLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );
        // Goal created with MONTHLY frequency - first contribution already made
        // Verify by making second contribution after interval
        vm.warp(block.timestamp + 31 days);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid, 0);
        vm.stopPrank();
    }

    function testWithdraw_HighProgressPenalty() public {
        vm.prank(alice);
        uint256 gid = personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "High Progress",
                targetAmount: 200e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );
        // First contribution already made (50e6)
        uint256 t = block.timestamp;
        t += 7 days + 1;
        vm.warp(t);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid, 0);
        t += 7 days + 1;
        vm.warp(t);
        personalSavings.contributeToGoal(gid, 0);
        // Now at 75% progress (150e6 / 200e6) - penalty should apply
        uint256 balBefore = USDT.balanceOf(alice);
        personalSavings.withdrawFromGoal(gid, 50e6);
        uint256 balAfter = USDT.balanceOf(alice);
        assertLt(balAfter - balBefore, 50e6); // penalty applied
        vm.stopPrank();
    }

    function testGetUserGoals() public {
        uint256 gid1 = _createDefaultGoal(alice);
        vm.prank(alice);
        uint256 gid2 = personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Goal 2",
                targetAmount: 100e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
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
            PersonalSavings.CreateGoalParams({
                name: "Daily",
                targetAmount: 100e6,
                contributionAmount: 10e6,
                frequency: PersonalSavings.Frequency.DAILY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );
        // First contribution already made
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid, 0);
        vm.stopPrank();
    }
}
