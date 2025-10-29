// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";

contract CircleSavingsV1BasicTests is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function testCreateCircleAndDetails() public {
        vm.prank(alice);
        CircleSavingsV1.CreateCircleParams memory params = CircleSavingsV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PRIVATE
            });

        uint256 cid = circleSavings.createCircle(params);

        (CircleSavingsV1.Circle memory c, , , ) = circleSavings
            .getCircleDetails(cid);

        assertEq(c.creator, alice);
        assertEq(c.contributionAmount, 100e18);
        assertEq(c.maxMembers, 5);
        assertEq(
            uint256(c.state),
            uint256(CircleSavingsV1.CircleState.CREATED)
        );
    }

    function testJoinMembersAndAutoStart() public {
        vm.prank(alice);
        CircleSavingsV1.CreateCircleParams memory params = CircleSavingsV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PRIVATE
            });

        uint256 cid = circleSavings.createCircle(params);

        // Create array of addresses to invite
        address[] memory invitees = new address[](4);
        invitees[0] = bob;
        invitees[1] = charlie;
        invitees[2] = david;
        invitees[3] = eve;

        // Invite members
        vm.prank(alice);
        circleSavings.inviteMembers(cid, invitees);

        // Fund accounts for joining
        uint256 collateral = 100e18 * 5 + ((100e18 * 5 * 100) / 10000); // contributionAmount * maxMembers + 1% buffer
        deal(address(cUSD), bob, collateral);
        deal(address(cUSD), charlie, collateral);
        deal(address(cUSD), david, collateral);
        deal(address(cUSD), eve, collateral);

        // Approve token spending
        vm.startPrank(bob);
        cUSD.approve(address(circleSavings), collateral);
        circleSavings.joinCircle(cid);
        vm.stopPrank();

        vm.startPrank(charlie);
        cUSD.approve(address(circleSavings), collateral);
        circleSavings.joinCircle(cid);
        vm.stopPrank();

        vm.startPrank(david);
        cUSD.approve(address(circleSavings), collateral);
        circleSavings.joinCircle(cid);
        vm.stopPrank();

        vm.startPrank(eve);
        cUSD.approve(address(circleSavings), collateral);
        circleSavings.joinCircle(cid);
        vm.stopPrank();

        // After the fifth member joins, circle should be ACTIVE and currentRound 1
        (CircleSavingsV1.Circle memory c, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(uint256(c.state), uint256(CircleSavingsV1.CircleState.ACTIVE));
        assertEq(c.currentRound, 1);
    }
}
