// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {CirclePotV1} from "../../src/CirclePotV1.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract CirclePotTestHelpers is Test {
    CirclePotV1 internal circlePot;
    MockERC20 internal cUSD;
    
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;
    address internal eve;
    address internal frank;

    function _createDefaultCircle(address circleCreator) internal returns (uint256) {
        address[] memory invitees = new address[](5);
        invitees[0] = bob;
        invitees[1] = charlie;
        invitees[2] = david;
        invitees[3] = eve;
        invitees[4] = frank;

        vm.startPrank(circleCreator);
        CirclePotV1.CreateCircleParams memory params = CirclePotV1.CreateCircleParams({
            contributionAmount: 100e18,
            frequency: CirclePotV1.Frequency.WEEKLY,
            maxMembers: 5,
            visibility: CirclePotV1.Visibility.PRIVATE
        });

        uint256 circleId = circlePot.createCircle(params);
        circlePot.inviteMembers(circleId, invitees);
        vm.stopPrank();

        return circleId;
    }

    function _setupVotingCircle() internal returns (uint256) {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);

        vm.warp(block.timestamp + 8 days);

        vm.prank(alice);
        circlePot.initiateVoting(circleId);

        return circleId;
    }

    function _createAndStartCircle() internal returns (uint256) {
        uint256 circleId = _createDefaultCircle(alice);

        vm.prank(bob);
        circlePot.joinCircle(circleId);
        vm.prank(charlie);
        circlePot.joinCircle(circleId);
        vm.prank(david);
        circlePot.joinCircle(circleId);
        vm.prank(eve);
        circlePot.joinCircle(circleId);

        return circleId;
    }

    function _createDefaultGoal(address goalOwner) internal returns (uint256) {
        vm.startPrank(goalOwner);

        CirclePotV1.CreateGoalParams memory params = CirclePotV1.CreateGoalParams({
            name: "Emergency Fund",
            targetAmount: 1000e18,
            contributionAmount: 50e18,
            frequency: CirclePotV1.Frequency.WEEKLY,
            deadline: block.timestamp + 365 days
        });

        uint256 goalId = circlePot.createPersonalGoal(params);
        vm.stopPrank();

        return goalId;
    }
}
