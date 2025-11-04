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
                title: "Test Circle",
                description: "Test Description",
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
                title: "Test Circle",
                description: "Test Description",
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

    function test_UpdateCircleVisibility_RevertSameVisibility() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(alice);
        circleSavings.updateCircleVisibility(cid, CircleSavingsV1.Visibility.PRIVATE);
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.SameVisibility.selector);
        circleSavings.updateCircleVisibility(cid, CircleSavingsV1.Visibility.PRIVATE);
    }

    function test_UpdateCircleVisibility_RevertNotCreator() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        vm.expectRevert(CircleSavingsV1.OnlyCreator.selector);
        circleSavings.updateCircleVisibility(cid, CircleSavingsV1.Visibility.PRIVATE);
    }

    function test_InviteMembers_RevertCircleNotPrivate() public {
        uint256 cid = _createDefaultCircle(alice);
        address[] memory invitees = new address[](1);
        invitees[0] = bob;
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.CircleNotPrivate.selector);
        circleSavings.inviteMembers(cid, invitees);
    }

    function test_JoinCircle_RevertNotInvited() public {
        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(
            CircleSavingsV1.CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PRIVATE
            })
        );
        address[] memory invitees = new address[](1);
        invitees[0] = charlie;
        vm.prank(alice);
        circleSavings.inviteMembers(cid, invitees);
        vm.prank(bob);
        vm.expectRevert(CircleSavingsV1.NotInvited.selector);
        circleSavings.joinCircle(cid);
    }

    function test_JoinCircle_RevertAlreadyJoined() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(bob);
        vm.expectRevert(CircleSavingsV1.AlreadyJoined.selector);
        circleSavings.joinCircle(cid);
    }

    function test_Contribute_RevertCircleNotActive() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.CircleNotActive.selector);
        circleSavings.contribute(cid);
    }

    function test_Contribute_RevertAlreadyContributed() public {
        uint256 cid = _createAndStartCircle();
        vm.prank(alice);
        circleSavings.contribute(cid);
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.AlreadyContributed.selector);
        circleSavings.contribute(cid);
    }

    function test_CreateCircle_DailyFrequency() public {
        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(
            CircleSavingsV1.CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.DAILY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PUBLIC
            })
        );
        (CircleSavingsV1.Circle memory c, , , ) = circleSavings.getCircleDetails(cid);
        assertEq(uint256(c.frequency), uint256(CircleSavingsV1.Frequency.DAILY));
    }

    function test_CreateCircle_MonthlyFrequency() public {
        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(
            CircleSavingsV1.CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.MONTHLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PUBLIC
            })
        );
        (CircleSavingsV1.Circle memory c, , , ) = circleSavings.getCircleDetails(cid);
        assertEq(uint256(c.frequency), uint256(CircleSavingsV1.Frequency.MONTHLY));
    }

    function test_Initialize_RevertZeroAddresses() public {
        CircleSavingsV1 impl = new CircleSavingsV1();
        vm.expectRevert();
        impl.initialize(address(0), testTreasury, address(reputation), testOwner);
    }

    function test_Upgrade_UpdatesAddresses() public {
        address newToken = makeAddr("newToken");
        vm.prank(testOwner);
        circleSavings.upgrade(newToken, address(0), address(0), 2);
        assertEq(circleSavings.cUSDToken(), newToken);
    }

    function test_CreateCircle_PublicVisibility() public {
        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(
            CircleSavingsV1.CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PUBLIC
            })
        );
        (CircleSavingsV1.Circle memory c, , , ) = circleSavings.getCircleDetails(cid);
        assertEq(uint256(c.visibility), uint256(CircleSavingsV1.Visibility.PUBLIC));
    }

    function test_GetCircleDetails() public {
        uint256 cid = _createDefaultCircle(alice);
        (CircleSavingsV1.Circle memory c, uint256 membersJoined, uint256 currentDeadline, bool canStart) = circleSavings.getCircleDetails(cid);
        assertEq(c.creator, alice);
        assertEq(membersJoined, 1);
        assertEq(currentDeadline, 0);
        assertFalse(canStart);
    }

    function test_JoinCircle_SuccessPublic() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        (CircleSavingsV1.Member memory m, bool hasContributed, ) = circleSavings.getMemberInfo(cid, bob);
        assertTrue(m.isActive);
        assertFalse(hasContributed);
    }
}
