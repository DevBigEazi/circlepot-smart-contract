// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PersonalSavings} from "../../src/PersonalSavings.sol";
import {PersonalSavingsSetup} from "./PersonalSavingsSetup.t.sol";

contract PersonalSavingsAdvanced is PersonalSavingsSetup {
    function setUp() public override {
        super.setUp();
    }

    function test_completeGoalAndWithdrawFull() public {
        vm.prank(alice);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "GoalFull",
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

        // Make 3 more contributions to reach 200e6
        uint256 t = block.timestamp;
        t += 8 days + 1;
        vm.warp(t);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid, 0);
        t += 8 days + 1;
        vm.warp(t);
        personalSavings.contributeToGoal(gid, 0);
        t += 8 days + 1;
        vm.warp(t);
        personalSavings.contributeToGoal(gid, 0);
        vm.stopPrank();

        uint256 balBefore = USDT.balanceOf(alice);

        vm.prank(alice);
        personalSavings.completeGoal(gid);

        uint256 balAfter = USDT.balanceOf(alice);
        // User pays 0.1% fee on completion (200e6 * 0.001 = 0.2e6)
        assertEq(balAfter - balBefore, 199.8e6);
    }

    function test_WithdrawFromGoalWithPenaltyLevels() public {
        uint256 gid = _createDefaultGoal(alice);
        // First contribution already made (100e6)

        uint256 balBefore = USDT.balanceOf(alice);
        vm.prank(alice);
        personalSavings.withdrawFromGoal(gid, 50e6);
        uint256 balAfter = USDT.balanceOf(alice);
        // Progress is 100/500 = 20% (< 25%), so penalty is 1% = 0.5e6
        assertEq(balAfter - balBefore, 49.5e6);
    }

    function test_RevertContributeTooSoon() public {
        uint256 gid = _createDefaultGoal(alice);
        // First contribution already made

        // try to contribute again immediately
        vm.prank(alice);
        vm.expectRevert(PersonalSavings.AlreadyContributed.selector);
        personalSavings.contributeToGoal(gid, 0);
    }

    function test_RevertWithdrawInsufficientBalance() public {
        vm.prank(alice);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Small Goal",
                targetAmount: 500e6,
                contributionAmount: 10e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });
        uint256 gid = personalSavings.createPersonalGoal(params);
        // First contribution made (10e6)

        vm.prank(alice);
        vm.expectRevert(PersonalSavings.InsufficientBalance.selector);
        personalSavings.withdrawFromGoal(gid, 50e6); // Try to withdraw more than available
    }

    function test_CreateGoal_RevertInvalidTarget() public {
        vm.prank(alice);
        vm.expectRevert(PersonalSavings.InvalidGoalAmount.selector);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Low",
                targetAmount: 1e17,
                contributionAmount: 1e17,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );
    }

    function test_CreateGoal_RevertInvalidContribution() public {
        vm.prank(alice);
        vm.expectRevert(PersonalSavings.InvalidContributionAmount.selector);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Zero",
                targetAmount: 100e6,
                contributionAmount: 0,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );
    }

    function test_CreateGoal_RevertInvalidDeadline() public {
        vm.prank(alice);
        vm.expectRevert(PersonalSavings.InvalidDeadline.selector);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Past",
                targetAmount: 100e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp - 1,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );
    }

    function test_Complete_RevertInsufficientBalance() public {
        uint256 gid = _createDefaultGoal(alice);
        vm.prank(alice);
        vm.expectRevert(PersonalSavings.InsufficientBalance.selector);
        personalSavings.completeGoal(gid);
    }

    function test_Contribute_RevertNotOwner() public {
        uint256 gid = _createDefaultGoal(alice);
        vm.prank(bob);
        vm.expectRevert(PersonalSavings.NotGoalOwner.selector);
        personalSavings.contributeToGoal(gid, 0);
    }

    function test_Withdraw_RevertNotOwner() public {
        uint256 gid = _createDefaultGoal(alice);
        // First contribution already made (100e6)
        vm.prank(bob);
        vm.expectRevert(PersonalSavings.NotGoalOwner.selector);
        personalSavings.withdrawFromGoal(gid, 10e6);
    }

    function test_Complete_RevertNotOwner() public {
        uint256 gid = _createDefaultGoal(alice);
        // First contribution already made (100e6)
        // Need to reach 500e6 target
        uint256 t = block.timestamp;
        vm.startPrank(alice);
        for (uint256 i = 0; i < 4; i++) {
            t += 8 days;
            vm.warp(t);
            personalSavings.contributeToGoal(gid, 0);
        }
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(PersonalSavings.NotGoalOwner.selector);
        personalSavings.completeGoal(gid);
    }

    function test_Withdraw_25PercentProgress() public {
        vm.prank(alice);
        uint256 gid = personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Low Progress",
                targetAmount: 200e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );
        // First contribution made (50e6), progress = 25%
        uint256 balBefore = USDT.balanceOf(alice);
        vm.prank(alice);
        personalSavings.withdrawFromGoal(gid, 25e6);
        uint256 balAfter = USDT.balanceOf(alice);
        assertLt(balAfter - balBefore, 25e6);
    }

    function test_Withdraw_50PercentProgress() public {
        vm.prank(alice);
        uint256 gid = personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Mid Progress",
                targetAmount: 100e6,
                contributionAmount: 50e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );
        // First contribution made (50e6), progress = 50%
        uint256 balBefore = USDT.balanceOf(alice);
        vm.prank(alice);
        personalSavings.withdrawFromGoal(gid, 25e6);
        uint256 balAfter = USDT.balanceOf(alice);
        assertLt(balAfter - balBefore, 25e6);
        vm.stopPrank();
    }
}
