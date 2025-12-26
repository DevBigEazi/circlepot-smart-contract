// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";

/**
 * @title BugFixVerificationTest
 * @notice Tests to verify the forfeit bug fix - recipient should NOT be forfeited
 */
contract BugFixVerificationTest is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test that the recipient is exempt from forfeiture
     * @dev This test verifies the fix for the bug where the recipient was being unjustly forfeited
     */
    function test_RecipientExemptFromForfeiture() public {
        uint256 cid = _createAndStartCircle();
        
        // Alice is position 1 (recipient of round 1)
        // Everyone except Alice contributes
        vm.prank(bob);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);

        // Warp past grace period
        vm.warp(block.timestamp + 9 days + 1 hours);

        // Get Alice's collateral before forfeit attempt
        (CircleSavingsV1.Member memory aliceBefore, , ) = circleSavings.getMemberInfo(cid, alice);
        uint256 aliceCollateralBefore = aliceBefore.collateralLocked;
        
        // Get Alice's reputation before forfeit attempt
        (, , , , , , , uint256 aliceLatePaymentsBefore, ) = reputation.getUserReputationDetails(alice);

        // Bob tries to forfeit Alice (the recipient)
        address[] memory lateMembers = new address[](1);
        lateMembers[0] = alice;
        vm.prank(bob);
        circleSavings.forfeitMember(cid, lateMembers);

        // Verify Alice was NOT forfeited
        (CircleSavingsV1.Member memory aliceAfter, bool hasContributed, ) = circleSavings.getMemberInfo(cid, alice);
        
        // Alice's collateral should be unchanged
        assertEq(
            aliceAfter.collateralLocked,
            aliceCollateralBefore,
            "Recipient's collateral should NOT be deducted"
        );
        
        // Alice should NOT be marked as contributed
        assertFalse(hasContributed, "Recipient should NOT be marked as contributed");
        
        // Alice's reputation should be unchanged
        (, , , , , , , uint256 aliceLatePaymentsAfter, ) = reputation.getUserReputationDetails(alice);
        assertEq(
            aliceLatePaymentsAfter,
            aliceLatePaymentsBefore,
            "Recipient should NOT have late payment recorded"
        );
    }

    /**
     * @notice Test that non-recipients ARE forfeited correctly
     * @dev Verifies that the fix doesn't break normal forfeiture logic
     */
    function test_NonRecipientsAreForfeited() public {
        uint256 cid = _createAndStartCircle();
        
        // Only Bob contributes (Alice is recipient, Charlie/David/Eve are late)
        vm.prank(bob);
        circleSavings.contribute(cid);

        // Warp past grace period
        vm.warp(block.timestamp + 9 days + 1 hours);

        // Get collateral before forfeit
        (CircleSavingsV1.Member memory charlieBefore, , ) = circleSavings.getMemberInfo(cid, charlie);
        (CircleSavingsV1.Member memory davidBefore, , ) = circleSavings.getMemberInfo(cid, david);
        (CircleSavingsV1.Member memory eveBefore, , ) = circleSavings.getMemberInfo(cid, eve);

        // Forfeit the late non-recipients
        address[] memory lateMembers = new address[](3);
        lateMembers[0] = charlie;
        lateMembers[1] = david;
        lateMembers[2] = eve;
        vm.prank(bob);
        circleSavings.forfeitMember(cid, lateMembers);

        // Verify they were forfeited
        (CircleSavingsV1.Member memory charlieAfter, , ) = circleSavings.getMemberInfo(cid, charlie);
        (CircleSavingsV1.Member memory davidAfter, , ) = circleSavings.getMemberInfo(cid, david);
        (CircleSavingsV1.Member memory eveAfter, , ) = circleSavings.getMemberInfo(cid, eve);

        uint256 expectedDeduction = 100e18 + (100e18 * 100) / 10000;

        assertEq(
            charlieBefore.collateralLocked - charlieAfter.collateralLocked,
            expectedDeduction,
            "Charlie should be forfeited"
        );
        assertEq(
            davidBefore.collateralLocked - davidAfter.collateralLocked,
            expectedDeduction,
            "David should be forfeited"
        );
        assertEq(
            eveBefore.collateralLocked - eveAfter.collateralLocked,
            expectedDeduction,
            "Eve should be forfeited"
        );
    }

    /**
     * @notice Test that recipient changes each round
     * @dev Verifies that the exemption applies to the correct person in each round
     */
    function test_RecipientExemptionChangesPerRound() public {
        uint256 cid = _createAndStartCircle();
        
        // Round 1: Alice is recipient (position 1)
        // Everyone contributes except Alice
        vm.prank(bob);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);
        
        // Alice contributes to complete round 1
        vm.prank(alice);
        circleSavings.contribute(cid);

        // Now in Round 2: Bob is recipient (position 2)
        vm.warp(block.timestamp + 7 days);
        
        // Everyone contributes except Bob
        vm.prank(alice);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);

        // Warp past grace period
        vm.warp(block.timestamp + 9 days + 1 hours);

        // Get Bob's collateral before forfeit attempt
        (CircleSavingsV1.Member memory bobBefore, , ) = circleSavings.getMemberInfo(cid, bob);

        // Try to forfeit Bob (the round 2 recipient)
        address[] memory lateMembers = new address[](1);
        lateMembers[0] = bob;
        vm.prank(alice);
        circleSavings.forfeitMember(cid, lateMembers);

        // Verify Bob was NOT forfeited (he's the recipient in round 2)
        (CircleSavingsV1.Member memory bobAfter, , ) = circleSavings.getMemberInfo(cid, bob);
        assertEq(
            bobAfter.collateralLocked,
            bobBefore.collateralLocked,
            "Round 2 recipient (Bob) should NOT be forfeited"
        );
    }
}
