// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {ReputationSetup} from "./ReputationSetup.t.sol";
import {ReputationV1} from "../../src/ReputationV1.sol";

/**
 * @title ReputationBasic
 * @dev Basic test cases for Reputation contract
 */
contract ReputationBasic is ReputationSetup {
    function test_initializer() public {
        // Check initialized values
        assertEq(reputation.owner(), owner);
    }

    function test_contractAuthorization() public {
        address mockContract = makeAddr("mockContract");

        vm.prank(owner);
        reputation.authorizeContract(mockContract, "MockContract");

        assertTrue(reputation.isAuthorized(mockContract));
        assertEq(reputation.getContractName(mockContract), "MockContract");
    }

    function test_revertNotAuthorized() public {
        vm.expectRevert(ReputationV1.NotAuthorized.selector);
        reputation.increaseReputation(user1, 10, "Test");
    }

    function test_reputationIncrease() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract, "MockContract");

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 10, "Test Increase");

        assertEq(reputation.getReputation(user1), 10);
    }

    function test_reputationDecrease() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract, "MockContract");

        // First increase reputation
        vm.prank(mockContract);
        reputation.increaseReputation(user1, 20, "Initial");

        // Then decrease it
        vm.prank(mockContract);
        reputation.decreaseReputation(user1, 10, "Test Decrease");

        assertEq(reputation.getReputation(user1), 10);
    }

    function test_recordCircleCompletion() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract, "MockContract");

        vm.prank(mockContract);
        reputation.recordCircleCompleted(user1);

        (, uint256 circles, , ) = reputation.getUserReputationData(user1);
        assertEq(circles, 1);
    }

    function test_recordLatePayment() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract, "MockContract");

        vm.prank(mockContract);
        reputation.recordLatePayment(user1);

        (, , uint256 latePayments, ) = reputation.getUserReputationData(user1);
        assertEq(latePayments, 1);
    }

    function test_batchUpdateReputation() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract, "MockContract");

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        int256[] memory amounts = new int256[](3);
        amounts[0] = 10; // Increase
        amounts[1] = -5; // Decrease
        amounts[2] = 15; // Increase

        vm.prank(mockContract);
        reputation.batchUpdateReputation(users, amounts, "Batch Update");

        assertEq(reputation.getReputation(user1), 10);
        assertEq(reputation.getReputation(user2), 0); // Can't go below 0
        assertEq(reputation.getReputation(user3), 15);
    }

    function test_getReputationData() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract, "MockContract");

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 20, "Base Score");
        reputation.recordCircleCompleted(user1);
        reputation.recordLatePayment(user1);
        vm.stopPrank();

        (
            uint256 rep,
            uint256 circles,
            uint256 latePayments,
            uint256 score
        ) = reputation.getUserReputationData(user1);

        assertEq(rep, 20);
        assertEq(circles, 1);
        assertEq(latePayments, 1);
        assertEq(score, 30); // 20 + (1 circle * 10)
    }

    function test_onlyOwnerFunctions() public {
        address mockContract = makeAddr("mockContract");

        // Try to authorize contract as non-owner
        vm.prank(user1);
        vm.expectRevert();
        reputation.authorizeContract(mockContract, "MockContract");

        // Try to deauthorize contract as non-owner
        vm.prank(user1);
        vm.expectRevert();
        reputation.deauthorizeContract(mockContract);

        // Try to upgrade as non-owner
        vm.prank(user1);
        vm.expectRevert();
        reputation.upgrade(1);
    }
}
