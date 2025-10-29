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
                deadline: block.timestamp + 365 days
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

        ) = personalSavings.personalGoals(gid);
        assertEq(owner, alice);
        assertEq(targetAmount, 1000e18);

        // Should start with 0 reputation
        assertEq(reputation.getReputation(alice), 0);
    }

    function testContributeToGoal() public {
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 200e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            });

        uint256 gid = personalSavings.createPersonalGoal(params);

        vm.prank(alice);
        personalSavings.ContributeToGoal(gid);

        (, , , uint256 currentAmount, , , , , , ) = personalSavings
            .personalGoals(gid);
        assertEq(currentAmount, 50e18);

        // Should still have 0 reputation (not complete yet)
        assertEq(reputation.getReputation(alice), 0);
    }

    function testCompleteGoal() public {
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 100e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            });

        uint256 gid = personalSavings.createPersonalGoal(params);

        // Make two contributions to reach target
        vm.prank(alice);
        personalSavings.ContributeToGoal(gid);

        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        personalSavings.ContributeToGoal(gid);

        vm.prank(alice);
        personalSavings.CompleteGoal(gid);

        // Should gain reputation for reaching target (+10) and completing goal (+10) = 20
        assertEq(reputation.getReputation(alice), 20);
    }

    function testEarlyWithdrawalPenalty() public {
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "Emergency Fund",
                targetAmount: 200e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            });

        uint256 gid = personalSavings.createPersonalGoal(params);

        // Make a contribution
        vm.prank(alice);
        personalSavings.ContributeToGoal(gid);

        // Withdraw early
        vm.prank(alice);
        personalSavings.withdrawFromGoal(gid, 25e18);

        // Should lose reputation for early withdrawal (clamped at 0 from starting 0)
        assertEq(reputation.getReputation(alice), 0);
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
                deadline: block.timestamp + 365 days
            });

        uint256 gid1 = personalSavings.createPersonalGoal(params1);

        // Create second goal
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params2 = PersonalSavingsV1
            .CreateGoalParams({
                name: "Vacation Fund",
                targetAmount: 200e18,
                contributionAmount: 100e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            });

        uint256 gid2 = personalSavings.createPersonalGoal(params2);

        // Complete first goal
        vm.startPrank(alice);
        personalSavings.ContributeToGoal(gid1);
        vm.warp(block.timestamp + 7 days);
        personalSavings.ContributeToGoal(gid1);
        personalSavings.CompleteGoal(gid1);
        vm.stopPrank();

        // Should have reputation from first goal (10 on target + 10 on complete)
        assertEq(reputation.getReputation(alice), 20);

        // Complete second goal
        vm.startPrank(alice);
        personalSavings.ContributeToGoal(gid2);
        vm.warp(block.timestamp + 7 days + 1);
        personalSavings.ContributeToGoal(gid2);
        personalSavings.CompleteGoal(gid2);
        vm.stopPrank();

        // Should have cumulative reputation from both goals (20 + 20)
        assertEq(reputation.getReputation(alice), 40);
    }
}
