// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotCircleManagementTests
 * @notice Tests for circle management, visibility updates, and manual start
 */
contract CirclePotCircleManagementTests is CirclePotV1Test {
    
    function test_StartCircleManually() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);

        vm.warp(block.timestamp + 8 days);

        vm.prank(alice);
        circlePot.startCircle(circleId);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.state), uint(CirclePotV1.CircleState.ACTIVE));
    }

    function test_RevertStartCircleNotCreator() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);

        vm.warp(block.timestamp + 8 days);

        vm.prank(bob);
        vm.expectRevert(CirclePotV1.OnlyCreator.selector);
        circlePot.startCircle(circleId);
    }

    function test_UpdateCircleVisibility() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(alice);
        circlePot.updateCircleVisibility(
            circleId,
            CirclePotV1.Visibility.PUBLIC
        );

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.visibility), uint(CirclePotV1.Visibility.PUBLIC));
    }

    function test_RevertUpdateVisibilitySameValue() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(alice);
        vm.expectRevert(CirclePotV1.SameVisibility.selector);
        circlePot.updateCircleVisibility(
            circleId,
            CirclePotV1.Visibility.PRIVATE
        );
    }

    function test_RevertUpdateVisibilityNotCreator() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        vm.expectRevert(CirclePotV1.OnlyCreator.selector);
        circlePot.updateCircleVisibility(
            circleId,
            CirclePotV1.Visibility.PUBLIC
        );
    }

    function test_MonthlyCircleUltimatum() public {
        vm.startPrank(alice);
        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.MONTHLY,
                maxMembers: 5,
                visibility: CirclePotV1.Visibility.PRIVATE
            });

        uint256 circleId = circlePot.createCircle(params);

        address[] memory invitees = new address[](4);
        invitees[0] = bob;
        invitees[1] = charlie;
        invitees[2] = david;
        invitees[3] = eve;
        circlePot.inviteMembers(circleId, invitees);
        vm.stopPrank();

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);

        vm.warp(block.timestamp + 15 days);

        vm.prank(alice);
        circlePot.initiateVoting(circleId);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.state), uint(CirclePotV1.CircleState.VOTING));
    }
}