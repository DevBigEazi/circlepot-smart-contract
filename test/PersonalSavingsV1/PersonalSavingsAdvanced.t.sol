// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PersonalSavingsV1} from "../../src/PersonalSavingsV1.sol";
import {PersonalSavingsV1Setup} from "./PersonalSavingsSetup.t.sol";

contract PersonalSavingsV1Advanced is PersonalSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_completeGoalAndWithdrawFull() public {
        vm.prank(alice);
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "GoalFull",
                targetAmount: 200e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            });

        uint256 gid = personalSavings.createPersonalGoal(params);

        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid);
        uint256 t = block.timestamp;
        t += 8 days + 1;
        vm.warp(t);
        personalSavings.contributeToGoal(gid);
        t += 8 days + 1;
        vm.warp(t);
        personalSavings.contributeToGoal(gid);
        t += 8 days + 1;
        vm.warp(t);
        personalSavings.contributeToGoal(gid);
        vm.stopPrank();

        uint256 balBefore = cUSD.balanceOf(alice);

        vm.prank(alice);
        personalSavings.completeGoal(gid);

        uint256 balAfter = cUSD.balanceOf(alice);
        assertEq(balAfter - balBefore, 200e18);
    }

    function test_WithdrawFromGoalWithPenaltyLevels() public {
        uint256 gid = _createDefaultGoal(alice);

        // one contribution => progress small => 1% penalty
        vm.prank(alice);
        personalSavings.contributeToGoal(gid);

        uint256 balBefore = cUSD.balanceOf(alice);
        vm.prank(alice);
        personalSavings.withdrawFromGoal(gid, 50e18);
        uint256 balAfter = cUSD.balanceOf(alice);
        assertEq(balAfter - balBefore, 49.5e18);
    }

    function test_RevertContributeTooSoon() public {
        uint256 gid = _createDefaultGoal(alice);

        vm.prank(alice);
        personalSavings.contributeToGoal(gid);

        // try to contribute again immediately
        vm.prank(alice);
        vm.expectRevert(PersonalSavingsV1.AlreadyContributed.selector);
        personalSavings.contributeToGoal(gid);
    }

    function test_RevertWithdrawInsufficientBalance() public {
        uint256 gid = _createDefaultGoal(alice);

        vm.prank(alice);
        vm.expectRevert(PersonalSavingsV1.InsufficientBalance.selector);
        personalSavings.withdrawFromGoal(gid, 50e18);
    }

    function test_CreateGoal_RevertInvalidTarget() public {
        vm.prank(alice);
        vm.expectRevert(PersonalSavingsV1.InvalidGoalAmount.selector);
        personalSavings.createPersonalGoal(
            PersonalSavingsV1.CreateGoalParams({
                name: "Low",
                targetAmount: 1e17,
                contributionAmount: 1e17,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            })
        );
    }

    function test_CreateGoal_RevertInvalidContribution() public {
        vm.prank(alice);
        vm.expectRevert(PersonalSavingsV1.InvalidContributionAmount.selector);
        personalSavings.createPersonalGoal(
            PersonalSavingsV1.CreateGoalParams({
                name: "Zero",
                targetAmount: 100e18,
                contributionAmount: 0,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            })
        );
    }

    function test_CreateGoal_RevertInvalidDeadline() public {
        vm.prank(alice);
        vm.expectRevert(PersonalSavingsV1.InvalidDeadline.selector);
        personalSavings.createPersonalGoal(
            PersonalSavingsV1.CreateGoalParams({
                name: "Past",
                targetAmount: 100e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp - 1
            })
        );
    }

    function test_Complete_RevertInsufficientBalance() public {
        uint256 gid = _createDefaultGoal(alice);
        vm.prank(alice);
        vm.expectRevert(PersonalSavingsV1.InsufficientBalance.selector);
        personalSavings.completeGoal(gid);
    }

    function test_Contribute_RevertNotOwner() public {
        uint256 gid = _createDefaultGoal(alice);
        vm.prank(bob);
        vm.expectRevert(PersonalSavingsV1.NotGoalOwner.selector);
        personalSavings.contributeToGoal(gid);
    }

    function test_Withdraw_RevertNotOwner() public {
        uint256 gid = _createDefaultGoal(alice);
        vm.prank(alice);
        personalSavings.contributeToGoal(gid);
        vm.prank(bob);
        vm.expectRevert(PersonalSavingsV1.NotGoalOwner.selector);
        personalSavings.withdrawFromGoal(gid, 10e18);
    }

    function test_Complete_RevertNotOwner() public {
        uint256 gid = _createDefaultGoal(alice);
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid);
        vm.warp(block.timestamp + 8 days);
        personalSavings.contributeToGoal(gid);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(PersonalSavingsV1.NotGoalOwner.selector);
        personalSavings.completeGoal(gid);
    }

    function test_Withdraw_25PercentProgress() public {
        vm.prank(alice);
        uint256 gid = personalSavings.createPersonalGoal(
            PersonalSavingsV1.CreateGoalParams({
                name: "Low Progress",
                targetAmount: 400e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            })
        );
        vm.prank(alice);
        personalSavings.contributeToGoal(gid);
        uint256 balBefore = cUSD.balanceOf(alice);
        vm.prank(alice);
        personalSavings.withdrawFromGoal(gid, 25e18);
        uint256 balAfter = cUSD.balanceOf(alice);
        assertLt(balAfter - balBefore, 25e18);
    }

    function test_Withdraw_50PercentProgress() public {
        vm.prank(alice);
        uint256 gid = personalSavings.createPersonalGoal(
            PersonalSavingsV1.CreateGoalParams({
                name: "Mid Progress",
                targetAmount: 200e18,
                contributionAmount: 50e18,
                frequency: PersonalSavingsV1.Frequency.WEEKLY,
                deadline: block.timestamp + 365 days
            })
        );
        vm.startPrank(alice);
        personalSavings.contributeToGoal(gid);
        vm.warp(block.timestamp + 8 days);
        personalSavings.contributeToGoal(gid);
        uint256 balBefore = cUSD.balanceOf(alice);
        personalSavings.withdrawFromGoal(gid, 50e18);
        uint256 balAfter = cUSD.balanceOf(alice);
        assertLt(balAfter - balBefore, 50e18);
        vm.stopPrank();
    }
}

