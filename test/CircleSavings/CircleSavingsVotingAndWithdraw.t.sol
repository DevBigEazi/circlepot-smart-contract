// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavings} from "../../src/CircleSavings.sol";
import {CircleSavingsSetup} from "./CircleSavingsSetup.t.sol";

contract CircleSavingsVotingAndWithdraw is CircleSavingsSetup {
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
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);
        vm.prank(bob);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);
        vm.prank(charlie);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);

        // Voting should have executed immediately since all members (3/3) voted
        (, CircleSavings.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(status.state),
            uint256(CircleSavings.CircleState.ACTIVE)
        );
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
        circleSavings.castVote(cid, CircleSavings.VoteChoice.WITHDRAW);
        vm.prank(bob);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.WITHDRAW);

        vm.warp(block.timestamp + 3 days);

        // after failed vote, members are automatically paid out during execution
        uint256 aliceBalBefore = USDT.balanceOf(alice);
        uint256 bobBalBefore = USDT.balanceOf(bob);

        vm.prank(alice);
        circleSavings.executeVote(cid);

        uint256 aliceBalAfter = USDT.balanceOf(alice);
        uint256 bobBalAfter = USDT.balanceOf(bob);

        assertTrue(
            aliceBalAfter > aliceBalBefore,
            "Alice should have received collateral automatically"
        );
        assertTrue(
            bobBalAfter > bobBalBefore,
            "Bob should have received collateral automatically"
        );

        // Verify circle is dead
        (, CircleSavings.CircleStatus memory stat, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(uint256(stat.state), uint256(CircleSavings.CircleState.DEAD));
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
        vm.expectRevert(CircleSavings.UltimatumNotReached.selector);
        circleSavings.initiateVoting(cid);

        // Now test member threshold by creating a new circle
        uint256 cid2 = _createDefaultCircle(alice);

        // Try voting with just one member
        vm.prank(alice);
        vm.expectRevert(CircleSavings.MinMembersNotReached.selector);
        circleSavings.initiateVoting(cid2);
    }

    function test_InviteAndJoinPrivateCircleReverts() public {
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

        // bob tries to join without invite
        vm.prank(bob);
        vm.expectRevert(CircleSavings.NotInvited.selector);
        circleSavings.joinCircle(cid);

        // invite bob and join
        address[] memory invitees = new address[](1);
        invitees[0] = bob;
        vm.prank(alice);
        circleSavings.inviteMembers(cid, invitees);

        vm.prank(bob);
        circleSavings.joinCircle(cid);

        (CircleSavings.Member memory m, , ) = circleSavings.getMemberInfo(
            cid,
            bob
        );
        assertTrue(m.isActive);
    }

    function test_CastVote_RevertInvalidVoteChoice() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        circleSavings.initiateVoting(cid);
        vm.prank(alice);
        vm.expectRevert(CircleSavings.InvalidVoteChoice.selector);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.NONE);
    }

    function test_CastVote_RevertAlreadyVoted() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        circleSavings.initiateVoting(cid);
        vm.prank(alice);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);
        vm.prank(alice);
        vm.expectRevert(CircleSavings.AlreadyVoted.selector);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.WITHDRAW);
    }

    function test_ExecuteVote_RevertVotingStillActive() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        circleSavings.initiateVoting(cid);
        vm.prank(alice);
        vm.expectRevert(CircleSavings.VotingStillActive.selector);
        circleSavings.executeVote(cid);
    }

    function test_ExecuteVote_RevertVoteAlreadyExecuted() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        circleSavings.initiateVoting(cid);
        vm.prank(alice);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);
        vm.warp(block.timestamp + 3 days);
        vm.prank(alice);
        circleSavings.executeVote(cid);
        // After execution, circle is ACTIVE so VotingNotActive error expected
        vm.prank(alice);
        vm.expectRevert(CircleSavings.VotingNotActive.selector);
        circleSavings.executeVote(cid);
    }

    function test_WithdrawCollateral_UltimatumPath() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.warp(block.timestamp + 8 days);
        uint256 balBefore = USDT.balanceOf(alice);
        vm.prank(alice);
        circleSavings.WithdrawCollateral(cid);
        uint256 balAfter = USDT.balanceOf(alice);
        assertGt(balAfter, balBefore);
    }

    function test_StartCircle_ViaVoting() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.warp(block.timestamp + 8 days);

        // Initiate voting
        vm.prank(alice);
        circleSavings.initiateVoting(cid);

        // All members vote to start (triggers early execution)
        vm.prank(alice);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);
        vm.prank(bob);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);
        vm.prank(charlie);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);

        (, CircleSavings.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(status.state),
            uint256(CircleSavings.CircleState.ACTIVE)
        );
    }

    function test_UpdateReputationContract() public {
        vm.prank(testOwner);
        vm.expectRevert(CircleSavings.AddressZeroNotAllowed.selector);
        circleSavings.updateReputationContract(address(0));
    }

    function test_CastVote_RevertVotingPeriodEnded() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        circleSavings.initiateVoting(cid);
        vm.warp(block.timestamp + 3 days);
        vm.prank(alice);
        vm.expectRevert(CircleSavings.VotingPeriodEnded.selector);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);
    }

    function test_CastVote_RevertNotActiveMember() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        circleSavings.initiateVoting(cid);
        vm.prank(david);
        vm.expectRevert(CircleSavings.NotActiveMember.selector);
        circleSavings.castVote(cid, CircleSavings.VoteChoice.START);
    }

    function test_WithdrawCollateral_RevertUltimatumNotPassed() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.prank(alice);
        vm.expectRevert(CircleSavings.UltimatumNotPassed.selector);
        circleSavings.WithdrawCollateral(cid);
    }

    function test_InitiateVoting_AnyMemberCanInitiate() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.warp(block.timestamp + 8 days);

        // Any member can initiate voting (not just creator)
        vm.prank(bob);
        circleSavings.initiateVoting(cid);

        (, CircleSavings.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(status.state),
            uint256(CircleSavings.CircleState.VOTING)
        );
    }

    function test_JoinCircle_RevertCircleNotOpen() public {
        uint256 cid = _createAndStartCircle();
        vm.prank(frank);
        vm.expectRevert(CircleSavings.CircleNotOpen.selector);
        circleSavings.joinCircle(cid);
    }
}
