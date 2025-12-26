// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";

contract PositionSortingTest is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Comprehensive test to verify position assignment sorts by reputation (HIGH to LOW)
     * @dev This test creates members with SPECIFIC reputation scores and verifies correct ordering
     */
    function test_PositionsSortedByReputationHighToLow() public {
        // Setup: Give each member a SPECIFIC reputation score
        address mockContract = makeAddr("mockContract");
        vm.prank(testOwner);
        reputation.authorizeContract(mockContract);

        // Set specific reputation scores (higher reputation = earlier payout position)
        // Default is 300, so we increase/decrease from there
        vm.startPrank(mockContract);
        reputation.increaseReputation(alice, 0, "Alice: 300 (default)"); // Alice: 300 (creator, position 1)
        reputation.increaseReputation(bob, 100, "Bob: 400"); // Bob: 400
        reputation.increaseReputation(charlie, 50, "Charlie: 350"); // Charlie: 350
        reputation.increaseReputation(david, 150, "David: 450"); // David: 450 (HIGHEST)
        reputation.decreaseReputation(eve, 10, "Eve: 290"); // Eve: 290 (LOWEST)
        vm.stopPrank();

        // Verify reputation scores BEFORE circle creation
        uint256 aliceRep = reputation.getReputation(alice);
        uint256 bobRep = reputation.getReputation(bob);
        uint256 charlieRep = reputation.getReputation(charlie);
        uint256 davidRep = reputation.getReputation(david);
        uint256 eveRep = reputation.getReputation(eve);

        emit log_named_uint("Alice reputation (creator)", aliceRep);
        emit log_named_uint("Bob reputation", bobRep);
        emit log_named_uint("Charlie reputation", charlieRep);
        emit log_named_uint("David reputation", davidRep);
        emit log_named_uint("Eve reputation", eveRep);

        // Create circle with Alice as creator
        uint256 cid = _createDefaultCircle(alice);

        // Members join IN ORDER: bob, charlie, david, eve (NOT reputation order)
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        
        vm.prank(david);
        circleSavings.joinCircle(cid);
        
        vm.prank(eve);
        circleSavings.joinCircle(cid);

        // Circle should auto-start and assign positions

        // Get positions
        (uint256 alicePos, , , , , ) = circleSavings.circleMembers(cid, alice);
        (uint256 bobPos, , , , , ) = circleSavings.circleMembers(cid, bob);
        (uint256 charliePos, , , , , ) = circleSavings.circleMembers(cid, charlie);
        (uint256 davidPos, , , , , ) = circleSavings.circleMembers(cid, david);
        (uint256 evePos, , , , , ) = circleSavings.circleMembers(cid, eve);

        emit log_named_uint("Alice position (creator, always 1)", alicePos);
        emit log_named_uint("David position (450 rep, should be 2)", davidPos);
        emit log_named_uint("Bob position (400 rep, should be 3)", bobPos);
        emit log_named_uint("Charlie position (350 rep, should be 4)", charliePos);
        emit log_named_uint("Eve position (290 rep, should be 5)", evePos);

        // VERIFY POSITIONS ARE SORTED BY REPUTATION (HIGH TO LOW)
        // Expected order:
        // Position 1: Alice (300, creator - always first)
        // Position 2: David (450, highest reputation)
        // Position 3: Bob (400, second highest)
        // Position 4: Charlie (350, third highest)
        // Position 5: Eve (290, lowest reputation)

        assertEq(alicePos, 1, "Alice (creator) should always be position 1");
        assertEq(davidPos, 2, "David (450 rep) should be position 2");
        assertEq(bobPos, 3, "Bob (400 rep) should be position 3");
        assertEq(charliePos, 4, "Charlie (350 rep) should be position 4");
        assertEq(evePos, 5, "Eve (290 rep) should be position 5");
    }

    /**
     * @notice Test that join order does NOT affect position assignment
     * @dev Members join in reverse reputation order, but positions should still be by reputation
     */
    function test_JoinOrderDoesNotAffectPositions() public {
        // Setup reputation (same as above)
        address mockContract = makeAddr("mockContract");
        vm.prank(testOwner);
        reputation.authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(bob, 100, "Bob: 400");
        reputation.increaseReputation(charlie, 50, "Charlie: 350");
        reputation.increaseReputation(david, 150, "David: 450");
        reputation.decreaseReputation(eve, 10, "Eve: 290");
        vm.stopPrank();

        uint256 cid = _createDefaultCircle(alice);

        // Join in REVERSE reputation order: eve (lowest), charlie, bob, david (highest)
        vm.prank(eve);
        circleSavings.joinCircle(cid); // 290 rep joins first
        
        vm.prank(charlie);
        circleSavings.joinCircle(cid); // 350 rep joins second
        
        vm.prank(bob);
        circleSavings.joinCircle(cid); // 400 rep joins third
        
        vm.prank(david);
        circleSavings.joinCircle(cid); // 450 rep joins LAST

        // Get positions
        (uint256 davidPos, , , , , ) = circleSavings.circleMembers(cid, david);
        (uint256 bobPos, , , , , ) = circleSavings.circleMembers(cid, bob);
        (uint256 charliePos, , , , , ) = circleSavings.circleMembers(cid, charlie);
        (uint256 evePos, , , , , ) = circleSavings.circleMembers(cid, eve);

        // Positions should STILL be by reputation, not join order
        assertEq(davidPos, 2, "David (highest rep, joined LAST) should still be position 2");
        assertEq(bobPos, 3, "Bob should be position 3");
        assertEq(charliePos, 4, "Charlie should be position 4");
        assertEq(evePos, 5, "Eve (lowest rep, joined FIRST) should still be position 5");
    }

    /**
     * @notice Test edge case: All members have same reputation
     * @dev Should assign positions in a consistent manner (join order in this case)
     */
    function test_SameReputationAllMembers() public {
        // All members have default 300 reputation
        uint256 cid = _createDefaultCircle(alice);

        vm.prank(bob);
        circleSavings.joinCircle(cid);
        
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        
        vm.prank(david);
        circleSavings.joinCircle(cid);
        
        vm.prank(eve);
        circleSavings.joinCircle(cid);

        // Get positions
        (uint256 alicePos, , , , , ) = circleSavings.circleMembers(cid, alice);
        (uint256 bobPos, , , , , ) = circleSavings.circleMembers(cid, bob);
        (uint256 charliePos, , , , , ) = circleSavings.circleMembers(cid, charlie);
        (uint256 davidPos, , , , , ) = circleSavings.circleMembers(cid, david);
        (uint256 evePos, , , , , ) = circleSavings.circleMembers(cid, eve);

        // Creator always position 1
        assertEq(alicePos, 1, "Alice (creator) always position 1");
        
        // Others should get consistent positions (stable sort - maintains join order for equal values)
        assertEq(bobPos, 2, "Bob joined first");
        assertEq(charliePos, 3, "Charlie joined second");
        assertEq(davidPos, 4, "David joined third");
        assertEq(evePos, 5, "Eve joined fourth");
    }
}
