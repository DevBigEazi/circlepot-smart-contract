// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PersonalSavingsV1} from "../../src/PersonalSavingsV1.sol";
import {PersonalSavingsV1Setup} from "./PersonalSavingsSetup.t.sol";

contract PersonalSavingsV1Advanced is PersonalSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_CompleteGoalAndWithdrawFull() public {
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
        personalSavings.ContributeToGoal(gid);
        uint256 t = block.timestamp;
        t += 8 days + 1;
        vm.warp(t);
        personalSavings.ContributeToGoal(gid);
        t += 8 days + 1;
        vm.warp(t);
        personalSavings.ContributeToGoal(gid);
        t += 8 days + 1;
        vm.warp(t);
        personalSavings.ContributeToGoal(gid);
        vm.stopPrank();

        uint256 balBefore = cUSD.balanceOf(alice);

        vm.prank(alice);
        personalSavings.CompleteGoal(gid);

        uint256 balAfter = cUSD.balanceOf(alice);
        assertEq(balAfter - balBefore, 200e18);
    }

    function test_WithdrawFromGoalWithPenaltyLevels() public {
        uint256 gid = _createDefaultGoal(alice);

        // one contribution => progress small => 1% penalty
        vm.prank(alice);
        personalSavings.ContributeToGoal(gid);

        uint256 balBefore = cUSD.balanceOf(alice);
        vm.prank(alice);
        personalSavings.withdrawFromGoal(gid, 50e18);
        uint256 balAfter = cUSD.balanceOf(alice);
        assertEq(balAfter - balBefore, 49.5e18);
    }

    function test_RevertContributeTooSoon() public {
        uint256 gid = _createDefaultGoal(alice);

        vm.prank(alice);
        personalSavings.ContributeToGoal(gid);

        // try to contribute again immediately
        vm.prank(alice);
        vm.expectRevert(PersonalSavingsV1.AlreadyContributed.selector);
        personalSavings.ContributeToGoal(gid);
    }

    function test_RevertWithdrawInsufficientBalance() public {
        uint256 gid = _createDefaultGoal(alice);

        vm.prank(alice);
        vm.expectRevert(PersonalSavingsV1.InsufficientBalance.selector);
        personalSavings.withdrawFromGoal(gid, 50e18);
    }
}
