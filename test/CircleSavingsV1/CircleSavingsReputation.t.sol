// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";

contract CircleSavingsReputationTests is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function testCircleCompletionReputation() public {
        // Create and start a circle
        uint256 cid = _createAndStartCircle();

        // All members contribute for first round
        vm.prank(alice);
        circleSavings.contribute(cid);
        vm.prank(bob);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);

        // Check that first person in rotation received payout and reputation
        uint256 recipientRep = reputation.getReputation(alice);
        assertGt(recipientRep, 0, "First recipient should gain reputation");

        // Check circle completion was recorded
        (, uint256 circles, , ) = reputation.getUserReputationData(alice);
        assertEq(circles, 1, "Should record circle completion");
    }

    function testLatePaymentReputation() public {
        uint256 cid = _createAndStartCircle();

        // Have other members contribute on time
        vm.prank(alice);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);

        // Move time strictly past the deadline + grace period for Bob
        vm.warp(block.timestamp + 9 days + 1 hours); // 7 days + 48 hours grace + buffer

        // Bob makes late contribution
        vm.prank(bob);
        circleSavings.contribute(cid);

        // Check reputation impact
        uint256 bobRep = reputation.getReputation(bob);
        assertEq(bobRep, 0, "Late payment should not be negative and remains zero");

        // Check late payment was recorded
        (, , uint256 latePayments, ) = reputation.getUserReputationData(bob);
        assertEq(latePayments, 1, "Should record late payment");
    }

    function testPositionAssignmentByReputation() public {
        // First give some reputation to Bob
        address mockContract = makeAddr("mockContract");
        vm.prank(testOwner);
        reputation.authorizeContract(mockContract, "MockContract");

        vm.prank(mockContract);
        reputation.increaseReputation(bob, 50, "Prior good behavior");

        // Now create and start a circle
        uint256 cid = _createDefaultCircle(alice);

        // Have members join
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.prank(david);
        circleSavings.joinCircle(cid);
        vm.prank(eve);
        circleSavings.joinCircle(cid);

        // Get member info to check positions
        (uint256 bobPosition, , , , , ) = circleSavings.circleMembers(
            cid,
            bob
        );

        assertEq(
            bobPosition,
            2,
            "Bob should be second in rotation due to high reputation"
        );
    }

    function testSuccessfulCircleCompletionReputation() public {
        uint256 cid = _createAndStartCircle();

        // Complete all 5 rounds with all members contributing
        for (uint256 round = 0; round < 5; round++) {
            vm.prank(alice);
            circleSavings.contribute(cid);
            vm.prank(bob);
            circleSavings.contribute(cid);
            vm.prank(charlie);
            circleSavings.contribute(cid);
            vm.prank(david);
            circleSavings.contribute(cid);
            vm.prank(eve);
            circleSavings.contribute(cid);

            // Move to next round
            vm.warp(block.timestamp + 7 days);
        }

        // Check reputation for all members
        address[] memory members = new address[](5);
        members[0] = alice;
        members[1] = bob;
        members[2] = charlie;
        members[3] = david;
        members[4] = eve;

        for (uint256 i = 0; i < members.length; i++) {
            (
                uint256 rep,
                uint256 circles,
                uint256 latePayments,
                uint256 score
            ) = reputation.getUserReputationData(members[i]);

            assertGt(rep, 0, "Member should have positive reputation");
            assertEq(circles, 1, "Member should have completed one circle");
            assertEq(latePayments, 0, "Member should have no late payments");
            assertGt(score, rep, "Score should be higher than base reputation");
        }
    }

    function testReputationNotAffectedByPlatformFees() public {
        uint256 cid = _createAndStartCircle();

        // All members contribute
        vm.prank(alice);
        circleSavings.contribute(cid);
        vm.prank(bob);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);

        // Check that platform fee collection doesn't affect reputation
        uint256 aliceRep = reputation.getReputation(alice);

        vm.prank(testOwner);
        circleSavings.withdrawPlatformFees();

        assertEq(
            reputation.getReputation(alice),
            aliceRep,
            "Platform fee withdrawal should not affect reputation"
        );
    }

    function test_GetMemberInfo() public {
        uint256 cid = _createAndStartCircle();
        (CircleSavingsV1.Member memory m, bool hasContributed, uint256 nextDeadline) = circleSavings.getMemberInfo(cid, alice);
        assertTrue(m.isActive);
        assertEq(m.position, 1);
        assertGt(nextDeadline, 0);
        assertFalse(hasContributed);
    }

    function test_GetCircleMembers() public {
        uint256 cid = _createAndStartCircle();
        address[] memory members = circleSavings.getCircleMembers(cid);
        assertEq(members.length, 5);
        assertEq(members[0], alice);
    }
}
