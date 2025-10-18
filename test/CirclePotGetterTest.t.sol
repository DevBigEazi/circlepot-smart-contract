// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotGetterTests
 * @notice Tests for all getter/view functions
 */
contract CirclePotGetterTests is CirclePotV1Test {
    function test_GetUserCircles() public {
        uint256 circleId1 = _createDefaultCircle(alice);

        vm.startPrank(alice);
        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CirclePotV1.Visibility.PRIVATE
            });
        uint256 circleId2 = circlePot.createCircle(params);
        vm.stopPrank();

        uint256[] memory aliceCircles = circlePot.getUserCircles(alice);
        assertEq(aliceCircles.length, 2);
        assertEq(aliceCircles[0], circleId1);
        assertEq(aliceCircles[1], circleId2);
    }

    function test_GetUserGoals() public {
        uint256 goalId1 = _createDefaultGoal(alice);

        vm.startPrank(alice);
        CirclePotV1.CreateGoalParams memory params = CirclePotV1
            .CreateGoalParams({
                name: "Second Goal",
                targetAmount: 2000e18,
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.MONTHLY,
                deadline: block.timestamp + 365 days
            });
        uint256 goalId2 = circlePot.createPersonalGoal(params);
        vm.stopPrank();

        uint256[] memory aliceGoals = circlePot.getUserGoals(alice);
        assertEq(aliceGoals.length, 2);
        assertEq(aliceGoals[0], goalId1);
        assertEq(aliceGoals[1], goalId2);
    }

    function test_GetCircleProgress() public {
        uint256 circleId = _createAndStartCircle();

        vm.prank(alice);
        circlePot.contribute(circleId);
        vm.prank(bob);
        circlePot.contribute(circleId);

        (
            uint256 currentRound,
            uint256 totalRounds,
            uint256 contributions,
            uint256 totalMembers
        ) = circlePot.getCircleProgress(circleId);

        assertEq(currentRound, 1);
        assertEq(totalRounds, 5);
        assertEq(contributions, 2);
        assertEq(totalMembers, 5);
    }

    function test_GetCircleMembers() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);

        address[] memory members = circlePot.getCircleMembers(circleId);
        assertEq(members.length, 2);
        assertEq(members[0], alice);
        assertEq(members[1], bob);
    }
}
