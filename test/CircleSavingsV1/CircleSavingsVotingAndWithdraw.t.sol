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

        // Voting should have executed immediately since all members (3/3) voted
        (, CircleSavingsV1.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(status.state),
            uint256(CircleSavingsV1.CircleState.ACTIVE)
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
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.WITHDRAW);
        vm.prank(bob);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.WITHDRAW);

        vm.warp(block.timestamp + 3 days);

        // after failed vote, members are automatically paid out during execution
        uint256 aliceBalBefore = USDm.balanceOf(alice);
        uint256 bobBalBefore = USDm.balanceOf(bob);

        vm.prank(alice);
        circleSavings.executeVote(cid);

        uint256 aliceBalAfter = USDm.balanceOf(alice);
        uint256 bobBalAfter = USDm.balanceOf(bob);

        assertTrue(
            aliceBalAfter > aliceBalBefore,
            "Alice should have received collateral automatically"
        );
        assertTrue(
            bobBalAfter > bobBalBefore,
            "Bob should have received collateral automatically"
        );

        // Verify circle is dead
        (, CircleSavingsV1.CircleStatus memory stat, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(stat.state),
            uint256(CircleSavingsV1.CircleState.DEAD)
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
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e18,
                frequency: CircleSavingsV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PRIVATE,
                enableYield: true
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
        vm.expectRevert(CircleSavingsV1.InvalidVoteChoice.selector);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.NONE);
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
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.AlreadyVoted.selector);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.WITHDRAW);
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
        vm.expectRevert(CircleSavingsV1.VotingStillActive.selector);
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
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
        vm.warp(block.timestamp + 3 days);
        vm.prank(alice);
        circleSavings.executeVote(cid);
        // After execution, circle is ACTIVE so VotingNotActive error expected
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.VotingNotActive.selector);
        circleSavings.executeVote(cid);
    }

    function test_WithdrawCollateral_UltimatumPath() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.warp(block.timestamp + 8 days);
        uint256 balBefore = USDm.balanceOf(alice);
        vm.prank(alice);
        circleSavings.WithdrawCollateral(cid);
        uint256 balAfter = USDm.balanceOf(alice);
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
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
        vm.prank(bob);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
        vm.prank(charlie);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);

        (, CircleSavingsV1.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(status.state),
            uint256(CircleSavingsV1.CircleState.ACTIVE)
        );
    }

    function test_UpdateReputationContract() public {
        vm.prank(testOwner);
        vm.expectRevert(CircleSavingsV1.AddressZeroNotAllowed.selector);
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
        vm.expectRevert(CircleSavingsV1.VotingPeriodEnded.selector);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
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
        vm.expectRevert(CircleSavingsV1.NotActiveMember.selector);
        circleSavings.castVote(cid, CircleSavingsV1.VoteChoice.START);
    }

    function test_WithdrawCollateral_RevertUltimatumNotPassed() public {
        uint256 cid = _createDefaultCircle(alice);
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.UltimatumNotPassed.selector);
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

        (, CircleSavingsV1.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            uint256(status.state),
            uint256(CircleSavingsV1.CircleState.VOTING)
        );
    }

    function test_JoinCircle_RevertCircleNotOpen() public {
        uint256 cid = _createAndStartCircle();
        vm.prank(frank);
        vm.expectRevert(CircleSavingsV1.CircleNotOpen.selector);
        circleSavings.joinCircle(cid);
    }
}
