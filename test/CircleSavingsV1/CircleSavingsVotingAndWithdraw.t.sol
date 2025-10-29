// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";

contract CircleSavingsVotingAndWithdraw is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_InitiateAndExecuteVoteStart() public {
        uint256 cid = _createDefaultCircle(alice);

        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);

        // warp past ultimatum
        vm.warp(block.timestamp + 15 days);

        vm.prank(alice);
        circleSavings.initiateVoting(cid);

        vm.prank(alice);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
        vm.prank(bob);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
        vm.prank(charlie);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);

        // warp past voting period
        vm.warp(block.timestamp + 3 days);

        vm.prank(alice);
        circleSavings.executeVote(cid);

        (CircleSavingsV1.Circle memory c, , , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(uint256(c.state), uint256(CircleSavingsV1.CircleState.ACTIVE));
    }

    function test_ExecuteVoteWithdrawAndCollateralWithdraw() public {
        uint256 cid = _createDefaultCircle(alice);

        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);

        vm.warp(block.timestamp + 15 days);

        vm.prank(alice);
        circleSavings.initiateVoting(cid);

        vm.prank(alice);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.WITHDRAW);
        vm.prank(bob);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.WITHDRAW);

        vm.warp(block.timestamp + 3 days);

        vm.prank(alice);
        circleSavings.executeVote(cid);

        // after failed vote, members can withdraw collateral
        uint256 before = cUSD.balanceOf(alice);
        vm.prank(alice);
        circleSavings.WithdrawCollateral(cid);
        uint256 afterBalance = cUSD.balanceOf(alice);

        assertTrue(
            afterBalance > before,
            "Alice should have received collateral after failed vote"
        );
    }

    function test_RevertInitiateVotingBeforeUltimatumOrBelowThreshold() public {
        uint256 cid = _createDefaultCircle(alice);

        // First try before ultimatum - should fail with UltimatumNotReached
        // Add enough members to pass threshold
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);

        // At 3 members we have 60% of 5 max members
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.UltimatumNotReached.selector);
        circleSavings.initiateVoting(cid);

        // Now test member threshold by creating a new circle
        uint256 cid2 = _createDefaultCircle(alice);

        // Try voting with just one member
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.MinMembersNotReached.selector);
        circleSavings.initiateVoting(cid2);
    }

    function test_InviteAndJoinPrivateCircleReverts() public {
        vm.prank(alice);
        CircleSavingsV1.CreateCircleParams memory params = CircleSavingsV1
            .CreateCircleParams({
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PRIVATE
            });

        uint256 cid = circleSavings.createCircle(params);

        // bob tries to join without invite
        vm.prank(bob);
        vm.expectRevert(CircleSavingsV1.NotInvited.selector);
        circleSavings.joinCircle(cid);

        // invite bob and join
        address[] memory invitees = new address[](1);
        invitees[0] = bob;
        vm.prank(alice);
        circleSavings.inviteMembers(cid, invitees);

        vm.prank(bob);
        circleSavings.joinCircle(cid);

        (CircleSavingsV1.Member memory m, , ) = circleSavings.getMemberInfo(
            cid,
            bob
        );
        assertTrue(m.isActive);
    }
}
