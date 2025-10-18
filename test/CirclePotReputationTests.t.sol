// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotReputationTests
 * @notice Tests for reputation system and position assignment
 */
contract CirclePotReputationTests is CirclePotV1Test {
    function test_GetUserReputation() public view {
        (uint256 reputation, uint256 completed, uint256 late) = circlePot
            .getUserReputation(alice);

        assertEq(reputation, 0);
        assertEq(completed, 0);
        assertEq(late, 0);
    }

    function test_PositionAssignmentWithReputation() public {
        // First complete a circle to give members reputation
        uint256 tempCircleId = _createAndStartCircle();

        // Complete all 5 rounds to give everyone reputation
        for (uint256 round = 1; round <= 5; round++) {
            vm.prank(alice);
            circlePot.contribute(tempCircleId);
            vm.prank(bob);
            circlePot.contribute(tempCircleId);
            vm.prank(charlie);
            circlePot.contribute(tempCircleId);
            vm.prank(david);
            circlePot.contribute(tempCircleId);
            vm.prank(eve);
            circlePot.contribute(tempCircleId);

            if (round < 5) {
                vm.warp(block.timestamp + 8 days);
            }
        }

        // Verify reputation was gained
        (uint256 bobRep, uint256 bobCompleted, ) = circlePot.getUserReputation(
            bob
        );
        (uint256 frankRep, uint256 frankCompleted, ) = circlePot
            .getUserReputation(frank);

        assertEq(bobCompleted, 1);
        assertEq(frankCompleted, 0);
        assertTrue(bobRep > frankRep || bobCompleted > frankCompleted);

        // Create a new circle
        vm.startPrank(alice);
        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CirclePotV1.Visibility.PRIVATE
            });

        uint256 newCircleId = circlePot.createCircle(params);

        address[] memory invitees = new address[](4);
        invitees[0] = bob;
        invitees[1] = frank;
        invitees[2] = charlie;
        invitees[3] = david;
        circlePot.inviteMembers(newCircleId, invitees);
        vm.stopPrank();

        // Members join
        vm.prank(bob);
        circlePot.joinCircle(newCircleId);
        vm.prank(frank);
        circlePot.joinCircle(newCircleId);
        vm.prank(charlie);
        circlePot.joinCircle(newCircleId);
        vm.prank(david);
        circlePot.joinCircle(newCircleId);

        // Check positions
        (CirclePotV1.Member memory bobMember, , ) = circlePot.getMemberInfo(
            newCircleId,
            bob
        );
        (CirclePotV1.Member memory frankMember, , ) = circlePot.getMemberInfo(
            newCircleId,
            frank
        );

        assertEq(
            bobMember.position,
            2,
            "Bob should get position 2 with highest reputation"
        );
        assertTrue(
            frankMember.position > bobMember.position,
            "Frank with no reputation should have worse position than Bob"
        );
    }

    function test_PositionAssignmentWithZeroReputation() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);
        vm.prank(david);
        circlePot.joinCircle(circleId);
        vm.prank(eve);
        circlePot.joinCircle(circleId);

        (CirclePotV1.Member memory aliceMember, , ) = circlePot.getMemberInfo(
            circleId,
            alice
        );
        (CirclePotV1.Member memory bobMember, , ) = circlePot.getMemberInfo(
            circleId,
            bob
        );

        assertEq(aliceMember.position, 1);
        assertTrue(bobMember.position >= 2 && bobMember.position <= 5);
    }
}
