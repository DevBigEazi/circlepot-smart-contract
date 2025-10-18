// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotJoiningTests
 * @notice Tests for joining circles and invitation management
 */
contract CirclePotJoiningTests is CirclePotV1Test {
    function test_JoinCircle() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(circle.currentMembers, 2);

        (CirclePotV1.Member memory memberInfo, , ) = circlePot.getMemberInfo(
            circleId,
            bob
        );
        assertTrue(memberInfo.isActive);
    }

    function test_AutoStartWhenMaxMembersReached() public {
        uint256 circleId = _createDefaultCircle(alice);

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
        assertEq(uint(circle.state), uint(CirclePotV1.CircleState.ACTIVE));
    }

    function test_RevertJoinFullCircle() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);
        vm.prank(david);
        circlePot.joinCircle(circleId);
        vm.prank(eve);
        circlePot.joinCircle(circleId);

        vm.prank(frank);
        vm.expectRevert(CirclePotV1.CircleNotOpen.selector);
        circlePot.joinCircle(circleId);
    }

    function test_RevertJoinTwice() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);

        vm.prank(bob);
        vm.expectRevert(CirclePotV1.AlreadyJoined.selector);
        circlePot.joinCircle(circleId);
    }

    function test_InviteMembers() public {
        uint256 circleId = _createDefaultCircle(alice);

        address[] memory invitees = new address[](2);
        invitees[0] = bob;
        invitees[1] = charlie;

        vm.prank(alice);
        circlePot.inviteMembers(circleId, invitees);

        assertTrue(circlePot.isInvited(circleId, bob));
        assertTrue(circlePot.isInvited(circleId, charlie));
    }

    function test_RevertJoinPrivateCircleWithoutInvite() public {
        vm.startPrank(alice);
        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CirclePotV1.Visibility.PRIVATE
            });

        uint256 circleId = circlePot.createCircle(params);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(CirclePotV1.NotInvited.selector);
        circlePot.joinCircle(circleId);
    }

    function test_JoinPrivateCircleWithInvite() public {
        uint256 circleId = _createDefaultCircle(alice);

        address[] memory invitees = new address[](1);
        invitees[0] = bob;

        vm.prank(alice);
        circlePot.inviteMembers(circleId, invitees);

        vm.prank(bob);
        circlePot.joinCircle(circleId);

        (CirclePotV1.Member memory memberInfo, , ) = circlePot.getMemberInfo(
            circleId,
            bob
        );
        assertTrue(memberInfo.isActive);
    }

    function test_RevertInviteMembersNotCreator() public {
        uint256 circleId = _createDefaultCircle(alice);

        address[] memory invitees = new address[](1);
        invitees[0] = charlie;

        vm.prank(bob);
        vm.expectRevert(CirclePotV1.OnlyCreator.selector);
        circlePot.inviteMembers(circleId, invitees);
    }
}
