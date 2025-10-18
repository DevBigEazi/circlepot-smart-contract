// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotVotingTests
 * @notice Tests for voting mechanisms in circles
 */
contract CirclePotVotingTests is CirclePotV1Test {
    function test_InitiateVoting() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);

        vm.warp(block.timestamp + 8 days);

        vm.prank(alice);
        circlePot.initiateVoting(circleId);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.state), uint(CirclePotV1.CircleState.VOTING));
    }

    function test_CastVote() public {
        uint256 circleId = _setupVotingCircle();

        vm.prank(alice);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.START);

        (, uint256 startVoteCount, , , , ) = circlePot.getVoteInfo(circleId);
        assertEq(startVoteCount, 1);
    }

    function test_ExecuteVoteStart() public {
        uint256 circleId = _setupVotingCircle();

        vm.prank(alice);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.START);
        vm.prank(bob);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.START);
        vm.prank(charlie);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.START);

        vm.warp(block.timestamp + 3 days);

        vm.prank(alice);
        circlePot.executeVote(circleId);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.state), uint(CirclePotV1.CircleState.ACTIVE));
    }

    function test_RevertCastVoteAlreadyVoted() public {
        uint256 circleId = _setupVotingCircle();

        vm.prank(alice);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.START);

        vm.prank(alice);
        vm.expectRevert(CirclePotV1.AlreadyVoted.selector);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.START);
    }

    function test_RevertExecuteVoteBeforeVotingEnds() public {
        uint256 circleId = _setupVotingCircle();

        vm.prank(alice);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.START);

        vm.prank(alice);
        vm.expectRevert(CirclePotV1.VotingStillActive.selector);
        circlePot.executeVote(circleId);
    }

    function test_ExecuteVoteWithdraw() public {
        uint256 circleId = _setupVotingCircle();

        vm.prank(alice);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.WITHDRAW);
        vm.prank(bob);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.WITHDRAW);

        vm.warp(block.timestamp + 3 days);

        vm.prank(alice);
        circlePot.executeVote(circleId);

        (CirclePotV1.Circle memory circle, , , ) = circlePot.getCircleDetails(
            circleId
        );
        assertEq(uint(circle.state), uint(CirclePotV1.CircleState.CREATED));
    }

    function test_RevertVoteExecutedTwice() public {
        uint256 circleId = _setupVotingCircle();

        vm.prank(alice);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.START);
        vm.prank(bob);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.START);

        vm.warp(block.timestamp + 3 days);

        vm.prank(alice);
        circlePot.executeVote(circleId);

        vm.prank(alice);
        vm.expectRevert(CirclePotV1.VotingNotActive.selector);
        circlePot.executeVote(circleId);
    }

    function test_RevertInitiateVotingBeforeUltimatum() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);

        vm.prank(alice);
        vm.expectRevert(CirclePotV1.UltimatumNotReached.selector);
        circlePot.initiateVoting(circleId);
    }

    function test_RevertInitiateVotingBelowThreshold() public {
        uint256 circleId = _createDefaultCircle(alice);

        vm.warp(block.timestamp + 8 days);

        vm.prank(alice);
        vm.expectRevert(CirclePotV1.MinMembersNotReached.selector);
        circlePot.initiateVoting(circleId);
    }

    function test_WithdrawCollateralAfterFailedVote() public {
        uint256 circleId = _setupVotingCircle();

        vm.prank(alice);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.WITHDRAW);
        vm.prank(bob);
        circlePot.castVote(circleId, CirclePotV1.VoteChoice.WITHDRAW);

        vm.warp(block.timestamp + 3 days);

        vm.prank(alice);
        circlePot.executeVote(circleId);

        uint256 aliceBalanceBefore = cUSD.balanceOf(alice);

        vm.prank(alice);
        circlePot.WithdrawCollateral(circleId);

        uint256 aliceBalanceAfter = cUSD.balanceOf(alice);
        assertTrue(aliceBalanceAfter > aliceBalanceBefore);
    }
}
