// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotContributionTests
 * @notice Tests for contributions and payouts in active circles
 */
contract CirclePotContributionTests is CirclePotV1Test {
    function test_Contribute() public {
        uint256 circleId = _createAndStartCircle();

        vm.prank(alice);
        circlePot.contribute(circleId);

        (CirclePotV1.Member memory memberInfo, , ) = circlePot.getMemberInfo(
            circleId,
            alice
        );
        assertEq(memberInfo.totalContributed, 100e18);
    }

    function test_RevertContributeTwiceInSameRound() public {
        uint256 circleId = _createAndStartCircle();

        vm.startPrank(alice);
        circlePot.contribute(circleId);

        vm.expectRevert(CirclePotV1.AlreadyContributed.selector);
        circlePot.contribute(circleId);
        vm.stopPrank();
    }

    function test_RoundCompleteAndPayout() public {
        uint256 circleId = _createAndStartCircle();

        uint256 aliceBalanceBefore = cUSD.balanceOf(alice);

        vm.prank(alice);
        circlePot.contribute(circleId);
        vm.prank(bob);
        circlePot.contribute(circleId);
        vm.prank(charlie);
        circlePot.contribute(circleId);
        vm.prank(david);
        circlePot.contribute(circleId);
        vm.prank(eve);
        circlePot.contribute(circleId);

        uint256 aliceBalanceAfter = cUSD.balanceOf(alice);

        // Alice receives payout as position 1 (creator)
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 500e18 - 100e18);
    }

    function test_LateContribution() public {
        uint256 circleId = _createAndStartCircle();

        vm.prank(bob);
        circlePot.contribute(circleId);
        vm.prank(charlie);
        circlePot.contribute(circleId);
        vm.prank(david);
        circlePot.contribute(circleId);
        vm.prank(eve);
        circlePot.contribute(circleId);

        vm.warp(block.timestamp + 8 days + 49 hours);

        uint256 reputationBefore = circlePot.userReputation(alice);

        vm.prank(alice);
        circlePot.contribute(circleId);

        uint256 reputationAfter = circlePot.userReputation(alice);
        assertTrue(reputationAfter < reputationBefore || reputationBefore == 0);

        assertEq(circlePot.latePayments(alice), 1);
    }

    function test_LateContributionDeductsFromCollateral() public {
        uint256 circleId = _createAndStartCircle();

        (CirclePotV1.Member memory aliceMemberBefore, , ) = circlePot
            .getMemberInfo(circleId, alice);
        uint256 collateralBefore = aliceMemberBefore.collateralLocked;

        vm.prank(bob);
        circlePot.contribute(circleId);
        vm.prank(charlie);
        circlePot.contribute(circleId);
        vm.prank(david);
        circlePot.contribute(circleId);
        vm.prank(eve);
        circlePot.contribute(circleId);

        vm.warp(block.timestamp + 8 days + 49 hours);

        vm.prank(alice);
        circlePot.contribute(circleId);

        (CirclePotV1.Member memory aliceMemberAfter, , ) = circlePot
            .getMemberInfo(circleId, alice);
        uint256 collateralAfter = aliceMemberAfter.collateralLocked;

        uint256 expectedDeduction = 100e18 + (100e18 * 100) / 10000;
        assertEq(collateralBefore - collateralAfter, expectedDeduction);
    }

    function test_CompleteCircleAllRounds() public {
        uint256 circleId = _createAndStartCircle();

        for (uint256 round = 1; round <= 5; round++) {
            vm.prank(alice);
            circlePot.contribute(circleId);
            vm.prank(bob);
            circlePot.contribute(circleId);
            vm.prank(charlie);
            circlePot.contribute(circleId);
            vm.prank(david);
            circlePot.contribute(circleId);
            vm.prank(eve);
            circlePot.contribute(circleId);

            if (round < 5) {
                vm.warp(block.timestamp + 8 days);
            }
        }

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.state), uint(CirclePotV1.CircleState.COMPLETED));

        (CirclePotV1.Member memory aliceMember, , ) = circlePot.getMemberInfo(
            circleId,
            alice
        );
        assertEq(aliceMember.collateralLocked, 0);
    }

    function test_CollateralReleasedAfterCompletion() public {
        uint256 circleId = _createAndStartCircle();

        uint256 bobBalanceBefore = cUSD.balanceOf(bob);

        for (uint256 round = 1; round <= 5; round++) {
            vm.prank(alice);
            circlePot.contribute(circleId);
            vm.prank(bob);
            circlePot.contribute(circleId);
            vm.prank(charlie);
            circlePot.contribute(circleId);
            vm.prank(david);
            circlePot.contribute(circleId);
            vm.prank(eve);
            circlePot.contribute(circleId);

            if (round < 5) {
                vm.warp(block.timestamp + 8 days);
            }
        }

        uint256 bobBalanceAfter = cUSD.balanceOf(bob);

        assertTrue(bobBalanceAfter > bobBalanceBefore - (500e18));
    }

    function test_DailyCircleContributions() public {
        vm.startPrank(alice);
        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.DAILY,
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
        vm.prank(david);
        circlePot.joinCircle(circleId);
        vm.prank(eve);
        circlePot.joinCircle(circleId);

        vm.prank(alice);
        circlePot.contribute(circleId);

        vm.warp(block.timestamp + 1 days);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.frequency), uint(CirclePotV1.Frequency.DAILY));
    }

    function test_MonthlyCircleContributions() public {
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
        vm.prank(david);
        circlePot.joinCircle(circleId);
        vm.prank(eve);
        circlePot.joinCircle(circleId);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.frequency), uint(CirclePotV1.Frequency.MONTHLY));
    }
}
