// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";

contract CircleSavingsRecipientEdgeCasesTests is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @dev Test that any member can trigger auto-resolution when only the recipient is missing
     */
    function test_AutoResolution_RecipientMissing_AfterGrace() public {
        uint256 cid = _createAndStartCircle();

        // Round 1: Everyone except Alice (recipient) contributes
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

        // Alice (recipient) has NOT contributed. Pot should be 400.
        (, CircleSavingsV1.CircleStatus memory statusBefore, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            statusBefore.totalPot,
            400e18,
            "Pot should have 4 members' contributions"
        );
        assertEq(statusBefore.currentRound, 1, "Should still be round 1");

        // Bob calls forfeitMember (with an empty list or just checking completion)
        address[] memory emptyList = new address[](0);
        vm.prank(bob);
        circleSavings.forfeitMember(cid, emptyList);

        // Round should have advanced because Alice was the only one missing after grace
        (, CircleSavingsV1.CircleStatus memory statusAfter, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            statusAfter.currentRound,
            2,
            "Round should have advanced via auto-resolution"
        );
        assertEq(statusAfter.totalPot, 0, "Pot should be empty after payout");

        // Verify Alice received the payout (Creator pays NO platform fee)
        // Alice balance = 100000 (init) - 505 (collateral) + 400 (payout) = 99895
        assertEq(
            USDm.balanceOf(alice),
            99895e18,
            "Alice (creator) should receive the full pot"
        );
    }

    /**
     * @dev Test auto-resolution for a non-creator recipient
     */
    function test_AutoResolution_NonCreatorRecipient() public {
        uint256 cid = _createAndStartCircle();

        // Round 1: Everyone contributes on time
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

        // Move to Round 2 (Bob is recipient)
        (, CircleSavingsV1.CircleStatus memory statusR2, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(statusR2.currentRound, 2, "Should be round 2");

        // Round 2: Everyone except Bob contributes
        vm.prank(alice);
        circleSavings.contribute(cid);
        vm.prank(charlie);
        circleSavings.contribute(cid);
        vm.prank(david);
        circleSavings.contribute(cid);
        vm.prank(eve);
        circleSavings.contribute(cid);

        // Warp past grace period (9 days = 7 days frequency + 2 days grace)
        vm.warp(block.timestamp + 9 days + 1 hours);

        // Bob (recipient) is missing. Trigger auto-resolution.
        vm.prank(alice);
        circleSavings.forfeitMember(cid, new address[](0));

        // Round should advance to 3
        (, CircleSavingsV1.CircleStatus memory statusR3, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(statusR3.currentRound, 3, "Should advance to round 3");

        // Bob (non-creator) pays 1% fee on $400 ($4) = $396 payout
        // Bob setup: deal(505) + mint(1000) = 1505
        // Bob join R1: 1505 - 505 (collateral) = 1000
        // Bob paid R1: 1000 - 100 = 900
        // Bob payout R2: 900 + 396 = 1296
        assertEq(
            USDm.balanceOf(bob),
            1296e18,
            "Bob (non-creator) should receive pot minus 1% fee"
        );
    }

    /**
     * @dev Test that recipient is NOT penalized for late payment
     */
    function test_RecipientExemptFromLateFees() public {
        uint256 cid = _createAndStartCircle();

        // Warp past grace period
        vm.warp(block.timestamp + 9 days + 1 hours);

        // Alice (recipient) contributes AFTER grace period
        (CircleSavingsV1.Member memory aliceBefore, , ) = circleSavings
            .getMemberInfo(cid, alice);
        uint256 collateralBefore = aliceBefore.collateralLocked;

        vm.prank(alice);
        circleSavings.contribute(cid);

        (CircleSavingsV1.Member memory aliceAfter, , ) = circleSavings
            .getMemberInfo(cid, alice);

        // Recipient should NOT have collateral deducted
        assertEq(
            aliceAfter.collateralLocked,
            collateralBefore,
            "Recipient should not lose collateral"
        );

        // Check reputation - should NOT have on-time payment points (10 points)
        // But also should not have "Late Payment" penalty (-5 points)
        // Wait, current implementation of _handleLate does -5.
        // My implementation bypassed _handleLate but also bypassed the points award.
        assertEq(
            aliceAfter.performancePoints,
            0,
            "Should not get on-time points"
        );

        // Verify reputation data (late payments counter)
        (, , , , , , , uint256 latePayments, ) = reputation
            .getUserReputationDetails(alice);
        assertEq(
            latePayments,
            0,
            "Should not record late payment for recipient"
        );
    }

    /**
     * @dev Test scenario where multiple members are late, including recipient
     */
    function test_AutoResolution_MultipleLate_RecipientIncluded() public {
        uint256 cid = _createAndStartCircle();

        // Only Bob contributes on time
        vm.prank(bob);
        circleSavings.contribute(cid);

        // Warp past grace period
        vm.warp(block.timestamp + 9 days + 1 hours);

        // Members late: Alice (recipient), Charlie, David, Eve
        address[] memory toForfeit = new address[](3);
        toForfeit[0] = charlie;
        toForfeit[1] = david;
        toForfeit[2] = eve;

        // Bob forfeits the others. This should eventually trigger auto-resolution for Alice.
        vm.prank(bob);
        circleSavings.forfeitMember(cid, toForfeit);

        // Check round advanced
        (, CircleSavingsV1.CircleStatus memory status, , ) = circleSavings
            .getCircleDetails(cid);
        assertEq(
            status.currentRound,
            2,
            "Round should have advanced after forfeiting others"
        );

        // Payout to Alice: Alice balance should be 99895 (as calculated above)
        assertEq(
            USDm.balanceOf(alice),
            99895e18,
            "Alice should receive payout from forfeited members"
        );
    }
}
