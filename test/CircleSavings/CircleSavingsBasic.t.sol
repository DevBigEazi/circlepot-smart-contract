// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavings} from "../../src/CircleSavings.sol";
import {CircleSavingsSetup} from "./CircleSavingsSetup.t.sol";

contract CircleSavingsBasicTests is CircleSavingsSetup {
    function setUp() public override {
        super.setUp();
    }

    function testCreateCircleAndDetails() public {
        vm.prank(alice);
        CircleSavings.CreateCircleParams memory params = CircleSavings
            .CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e6,
                frequency: CircleSavings.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavings.Visibility.PRIVATE,
                token: address(USDT)
            });

        uint256 cid = circleSavings.createCircle(params);

        (
            CircleSavings.CircleConfig memory config,
            CircleSavings.CircleStatus memory status,
            ,

        ) = circleSavings.getCircleDetails(cid);

        assertEq(config.creator, alice);
        assertEq(config.contributionAmount, 100e6);
        assertEq(config.maxMembers, 5);
        assertEq(
            uint256(status.state),
            uint256(CircleSavings.CircleState.CREATED)
        );
    }

    function testJoinMembersAndAutoStart() public {
        vm.prank(alice);
        CircleSavings.CreateCircleParams memory params = CircleSavings
            .CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e6,
                frequency: CircleSavings.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavings.Visibility.PRIVATE,
                token: address(USDT)
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
        uint256 collateral = 100e6 * 5 + ((100e6 * 5 * 100) / 10000); // contributionAmount * maxMembers + 1% buffer
        deal(address(USDT), bob, collateral);
        deal(address(USDT), charlie, collateral);
        deal(address(USDT), david, collateral);
        deal(address(USDT), eve, collateral);

        // Members join circle
        vm.startPrank(bob);
        circleSavings.joinCircle(cid);
        vm.stopPrank();

        vm.startPrank(charlie);
        circleSavings.joinCircle(cid);
        vm.stopPrank();

        vm.startPrank(david);
        circleSavings.joinCircle(cid);
        vm.stopPrank();

        vm.startPrank(eve);
        circleSavings.joinCircle(cid);
        vm.stopPrank();

        // After the fifth member joins, circle should be ACTIVE and currentRound 1
        (, CircleSavings.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(status.state),
            uint256(CircleSavings.CircleState.ACTIVE)
        );
        assertEq(status.currentRound, 1);
    }

    function test_UpdateCircleVisibility_RevertSameVisibility() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(alice);
        circleSavings.updateCircleVisibility(
            cid,
            CircleSavings.Visibility.PRIVATE
        );
        vm.prank(alice);
        vm.expectRevert(CircleSavings.SameVisibility.selector);
        circleSavings.updateCircleVisibility(
            cid,
            CircleSavings.Visibility.PRIVATE
        );
    }

    function test_UpdateCircleVisibility_RevertNotCreator() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        vm.expectRevert(CircleSavings.OnlyCreator.selector);
        circleSavings.updateCircleVisibility(
            cid,
            CircleSavings.Visibility.PRIVATE
        );
    }

    function test_InviteMembers_RevertCircleNotPrivate() public {
        uint256 cid = _createDefaultCircle(alice);
        address[] memory invitees = new address[](1);
        invitees[0] = bob;
        vm.prank(alice);
        vm.expectRevert(CircleSavings.CircleNotPrivate.selector);
        circleSavings.inviteMembers(cid, invitees);
    }

    function test_JoinCircle_RevertNotInvited() public {
        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(
            CircleSavings.CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e6,
                frequency: CircleSavings.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavings.Visibility.PRIVATE,
                token: address(USDT)
            })
        );
        address[] memory invitees = new address[](1);
        invitees[0] = charlie;
        vm.prank(alice);
        circleSavings.inviteMembers(cid, invitees);
        vm.prank(bob);
        vm.expectRevert(CircleSavings.NotInvited.selector);
        circleSavings.joinCircle(cid);
    }

    function test_JoinCircle_RevertAlreadyJoined() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(bob);
        vm.expectRevert(CircleSavings.AlreadyJoined.selector);
        circleSavings.joinCircle(cid);
    }

    function test_Contribute_RevertCircleNotActive() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(alice);
        vm.expectRevert(CircleSavings.CircleNotActive.selector);
        circleSavings.contribute(cid);
    }

    function test_Contribute_RevertAlreadyContributed() public {
        uint256 cid = _createAndStartCircle();
        vm.prank(alice);
        circleSavings.contribute(cid);
        vm.prank(alice);
        vm.expectRevert(CircleSavings.AlreadyContributed.selector);
        circleSavings.contribute(cid);
    }

    function test_CreateCircle_DailyFrequency() public {
        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(
            CircleSavings.CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e6,
                frequency: CircleSavings.Frequency.DAILY,
                maxMembers: 5,
                visibility: CircleSavings.Visibility.PUBLIC,
                token: address(USDT)
            })
        );
        (CircleSavings.CircleConfig memory config, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(config.frequency),
            uint256(CircleSavings.Frequency.DAILY)
        );
    }

    function test_CreateCircle_MonthlyFrequency() public {
        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(
            CircleSavings.CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e6,
                frequency: CircleSavings.Frequency.MONTHLY,
                maxMembers: 5,
                visibility: CircleSavings.Visibility.PUBLIC,
                token: address(USDT)
            })
        );
        (CircleSavings.CircleConfig memory config, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(config.frequency),
            uint256(CircleSavings.Frequency.MONTHLY)
        );
    }

    function test_Initialize_RevertZeroAddresses() public {
        CircleSavings impl = new CircleSavings();
        address[] memory emptyTokens = new address[](0);
        vm.expectRevert();
        impl.initialize(
            emptyTokens,
            testTreasury,
            address(reputation),
            testOwner
        );
    }

    function test_Upgrade_UpdatesAddresses() public {
        address newTreasury = makeAddr("newTreasury");
        vm.prank(testOwner);
        circleSavings.upgrade(newTreasury, address(0), 2);
        assertEq(circleSavings.treasury(), newTreasury);
    }

    function test_CreateCircle_PublicVisibility() public {
        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(
            CircleSavings.CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e6,
                frequency: CircleSavings.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavings.Visibility.PUBLIC,
                token: address(USDT)
            })
        );
        (CircleSavings.CircleConfig memory config, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(config.visibility),
            uint256(CircleSavings.Visibility.PUBLIC)
        );
    }

    function test_GetCircleDetails() public {
        uint256 cid = _createDefaultCircle(alice);
        (
            CircleSavings.CircleConfig memory config,
            CircleSavings.CircleStatus memory status,
            uint256 currentDeadline,
            bool canStart
        ) = circleSavings.getCircleDetails(cid);
        assertEq(config.creator, alice);
        assertEq(status.currentMembers, 1);
        assertEq(currentDeadline, 0);
        assertFalse(canStart);
    }

    function test_JoinCircle_SuccessPublic() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        (CircleSavings.Member memory m, bool hasContributed, ) = circleSavings
            .getMemberInfo(cid, bob);
        assertTrue(m.isActive);
        assertFalse(hasContributed);
    }
}
