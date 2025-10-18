// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotCircleCreationTests
 * @notice Tests for creating circles with various parameters
 */
contract CirclePotCircleCreationTests is CirclePotV1Test {
    
    function test_CreateCircle() public {
        vm.startPrank(alice);

        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CirclePotV1.Visibility.PRIVATE
            });

        uint256 circleId = circlePot.createCircle(params);

        assertEq(circleId, 1);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );

        assertEq(circle.circleId, 1);
        assertEq(circle.creator, alice);
        assertEq(circle.contributionAmount, 100e18);
        assertEq(uint(circle.frequency), uint(CirclePotV1.Frequency.WEEKLY));
        assertEq(circle.maxMembers, 5);
        assertEq(circle.currentMembers, 1);
        assertEq(uint(circle.state), uint(CirclePotV1.CircleState.CREATED));

        vm.stopPrank();
    }

    function test_CreatePublicCircle() public {
        vm.startPrank(alice);

        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CirclePotV1.Visibility.PUBLIC
            });

        uint256 circleId = circlePot.createCircle(params);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );

        assertEq(uint(circle.visibility), uint(CirclePotV1.Visibility.PUBLIC));

        vm.stopPrank();
    }

    function test_RevertCreateCircleInvalidContribution() public {
        vm.startPrank(alice);

        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 0.5e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CirclePotV1.Visibility.PRIVATE
            });

        vm.expectRevert(CirclePotV1.InvalidContributionAmount.selector);
        circlePot.createCircle(params);

        vm.stopPrank();
    }

    function test_RevertCreateCircleInvalidMemberCount() public {
        vm.startPrank(alice);

        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.WEEKLY,
                maxMembers: 3,
                visibility: CirclePotV1.Visibility.PRIVATE
            });

        vm.expectRevert(CirclePotV1.InvalidMemberCount.selector);
        circlePot.createCircle(params);

        vm.stopPrank();
    }

    function test_CreateDailyCircle() public {
        vm.startPrank(alice);

        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.DAILY,
                maxMembers: 5,
                visibility: CirclePotV1.Visibility.PRIVATE
            });

        uint256 circleId = circlePot.createCircle(params);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.frequency), uint(CirclePotV1.Frequency.DAILY));

        vm.stopPrank();
    }

    function test_CreateMonthlyCircle() public {
        vm.startPrank(alice);

        CirclePotV1.CreateCircleParams memory params = CirclePotV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CirclePotV1.Frequency.MONTHLY,
                maxMembers: 5,
                visibility: CirclePotV1.Visibility.PRIVATE
            });

        uint256 circleId = circlePot.createCircle(params);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.frequency), uint(CirclePotV1.Frequency.MONTHLY));

        vm.stopPrank();
    }
}