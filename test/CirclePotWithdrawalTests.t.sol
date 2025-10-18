// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotWithdrawalTests
 * @notice Tests for collateral withdrawal and edge cases
 */
contract CirclePotWithdrawalTests is CirclePotV1Test {
    function test_WithdrawCollateralBelowThresholdAfterUltimatum() public {
        vm.startPrank(alice);
        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                maxMembers: 10,
                visibility: CirclePotV1.Visibility.PRIVATE
            });

        uint256 circleId = circlePot.createCircle(params);

        address[] memory invitees = new address[](9);
        invitees[0] = bob;
        invitees[1] = charlie;
        invitees[2] = david;
        invitees[3] = eve;
        invitees[4] = frank;
        invitees[5] = address(10);
        invitees[6] = address(11);
        invitees[7] = address(12);
        invitees[8] = address(13);
        circlePot.inviteMembers(circleId, invitees);
        vm.stopPrank();

        for (uint i = 10; i <= 13; i++) {
            cUSD.mint(address(uint160(i)), 100000e18);
            vm.prank(address(uint160(i)));
            cUSD.approve(address(circlePot), type(uint256).max);
        }

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);
        vm.prank(david);
        circlePot.joinCircle(circleId);
        vm.prank(eve);
        circlePot.joinCircle(circleId);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(circle.currentMembers, 5);

        vm.warp(block.timestamp + 6 days);

        uint256 aliceBalBefore = cUSD.balanceOf(alice);

        vm.prank(alice);
        circlePot.WithdrawCollateral(circleId);

        uint256 aliceBalAfter = cUSD.balanceOf(alice);
        assertTrue(
            aliceBalAfter > aliceBalBefore,
            "Alice should receive collateral back"
        );
    }

    function test_RevertWithdrawCollateralWhenNotAllowed() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);

        vm.prank(charlie);
        circlePot.joinCircle(circleId);

        vm.warp(block.timestamp + 8 days);

        vm.prank(alice);
        circlePot.startCircle(circleId);

        vm.prank(alice);
        vm.expectRevert(CirclePotV1.InvalidCircle.selector);
        circlePot.WithdrawCollateral(circleId);
    }
}
