// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";

/**
 * @title WithdrawalScenariosTest
 * @notice Tests for various withdrawal scenarios including solo creator and sub-60% threshold
 */
contract WithdrawalScenariosTest is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test that solo creator can withdraw after ultimatum
     * @dev Creator creates circle, no one joins, after ultimatum they can withdraw
     */
    function test_SoloCreatorCanWithdrawAfterUltimatum() public {
        // Alice creates a circle (becomes only member)
        uint256 cid = _createDefaultCircle(alice);

        // Check initial state
        (CircleSavingsV1.Circle memory circle, , , ) = circleSavings.getCircleDetails(cid);
        assertEq(circle.currentMembers, 1, "Should only have creator");
        assertEq(uint256(circle.state), 1, "Should be in CREATED state (1)");

        // Get Alice's collateral before
        (CircleSavingsV1.Member memory aliceBefore, , ) = circleSavings.getMemberInfo(cid, alice);
        uint256 collateralBefore = aliceBefore.collateralLocked;
        assertGt(collateralBefore, 0, "Creator should have collateral locked");

        // Try to withdraw before ultimatum - should fail
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.UltimatumNotPassed.selector);
        circleSavings.WithdrawCollateral(cid);

        // Warp past ultimatum period (7 days for WEEKLY)
        vm.warp(block.timestamp + 7 days + 1 hours);

        // Now Alice should be able to withdraw (solo creator, below 60% threshold)
        uint256 aliceBalanceBefore = USDm.balanceOf(alice);

        vm.prank(alice);
        circleSavings.WithdrawCollateral(cid);

        // Verify withdrawal
        uint256 aliceBalanceAfter = USDm.balanceOf(alice);
        (CircleSavingsV1.Member memory aliceAfter, , ) = circleSavings.getMemberInfo(cid, alice);

        // Creator pays dead circle fee
        uint256 expectedFee = 0.5 * 10**18; // PUBLIC_CIRCLE_DEAD_FEE = 0.5 USDm
        uint256 expectedReturn = collateralBefore - expectedFee;

        assertEq(aliceAfter.collateralLocked, 0, "Collateral should be zero after withdrawal");
        assertFalse(aliceAfter.isActive, "Member should be inactive");
        assertEq(
            aliceBalanceAfter - aliceBalanceBefore,
            expectedReturn,
            "Should receive collateral minus dead fee"
        );

        // Check circle state
        (CircleSavingsV1.Circle memory circleAfter, , , ) = circleSavings.getCircleDetails(cid);
        assertEq(uint256(circleAfter.state), 5, "Circle should be DEAD (5)");
    }

    /**
     * @notice Test that members can withdraw when below 60% threshold without voting
     * @dev Circle has 2 members (40% of 5), after ultimatum they can withdraw without voting
     */
    function test_Sub60ThresholdAllowsWithdrawalWithoutVoting() public {
        // Alice creates circle (maxMembers = 5)
        uint256 cid = _createDefaultCircle(alice);

        // Only Bob joins (2 members = 40% of 5, below 60% threshold)
        vm.prank(bob);
        circleSavings.joinCircle(cid);

        // Verify state
        (CircleSavingsV1.Circle memory circle, , , ) = circleSavings.getCircleDetails(cid);
        assertEq(circle.currentMembers, 2, "Should have 2 members");
        
        // Calculate threshold: 2 < (5 * 60 / 100) = 2 < 3 = true
        assertTrue(circle.currentMembers < (circle.maxMembers * 60) / 100, "Below 60% threshold");

        // Get collateral amounts
        (CircleSavingsV1.Member memory aliceMember, , ) = circleSavings.getMemberInfo(cid, alice);
        (CircleSavingsV1.Member memory bobMember, , ) = circleSavings.getMemberInfo(cid, bob);
        uint256 aliceCollateral = aliceMember.collateralLocked;
        uint256 bobCollateral = bobMember.collateralLocked;

        // Warp past ultimatum
        vm.warp(block.timestamp + 7 days + 1 hours);

        // Both should be able to withdraw WITHOUT voting
        uint256 aliceBalanceBefore = USDm.balanceOf(alice);
        uint256 bobBalanceBefore = USDm.balanceOf(bob);

        // Alice (creator) withdraws
        vm.prank(alice);
        circleSavings.WithdrawCollateral(cid);

        // Bob (member) withdraws
        vm.prank(bob);
        circleSavings.WithdrawCollateral(cid);

        // Verify withdrawals
        uint256 aliceBalanceAfter = USDm.balanceOf(alice);
        uint256 bobBalanceAfter = USDm.balanceOf(bob);

        // Alice pays dead fee, Bob doesn't
        uint256 expectedFee = 0.5 * 10**18; // PUBLIC_CIRCLE_DEAD_FEE = 0.5 USDm
        assertEq(
            aliceBalanceAfter - aliceBalanceBefore,
            aliceCollateral - expectedFee,
            "Alice should receive collateral minus fee"
        );
        assertEq(
            bobBalanceAfter - bobBalanceBefore,
            bobCollateral,
            "Bob should receive full collateral"
        );
    }

    /**
     * @notice Test that withdrawal is blocked if above 60% threshold before ultimatum
     * @dev Circle reaches 60% threshold, withdrawal should require voting
     */
    function test_Above60ThresholdBlocksDirectWithdrawal() public {
        // Alice creates circle (maxMembers = 5)
        uint256 cid = _createDefaultCircle(alice);

        // 2 more members join (3 members = 60% of 5, AT threshold)
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);

        // Verify state
        (CircleSavingsV1.Circle memory circle, , , ) = circleSavings.getCircleDetails(cid);
        assertEq(circle.currentMembers, 3, "Should have 3 members");
        
        // Calculate threshold: 3 >= (5 * 60 / 100) = 3 >= 3 = true (AT or ABOVE threshold)
        assertFalse(
            circle.currentMembers < (circle.maxMembers * 60) / 100,
            "AT or above 60% threshold"
        );

        // Warp past ultimatum
        vm.warp(block.timestamp + 7 days + 1 hours);

        // Should NOT be able to withdraw directly (need voting)
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.UltimatumNotPassed.selector);
        circleSavings.WithdrawCollateral(cid);
    }

    /**
     * @notice Test exact threshold boundary (60%)
     * @dev At exactly 60%, withdrawal should be blocked
     */
    function test_Exact60ThresholdBlocksWithdrawal() public {
        // Create circle with maxMembers = 10 for clearer percentage
        CircleSavingsV1.CreateCircleParams memory params = CircleSavingsV1
            .CreateCircleParams({
            title: "Test Circle",
            description: "Test",
            contributionAmount: 100 * 10 ** 18,
            frequency: CircleSavingsV1.Frequency.WEEKLY,
            maxMembers: 10,
            visibility: CircleSavingsV1.Visibility.PUBLIC
        });

        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(params);

        // Add exactly 5 more members (6 total = 60% of 10)
        address[] memory members = new address[](5);
        members[0] = bob;
        members[1] = charlie;
        members[2] = david;
        members[3] = eve;
        members[4] = makeAddr("member6");

        for (uint256 i = 0; i < 5; i++) {
            // Mint USDm for the member (collateral requirement)
            USDm.mint(members[i], 1100 * 10**18); // Enough for collateral
            
            vm.prank(members[i]);
            USDm.approve(address(circleSavings), type(uint256).max);
            
            vm.prank(members[i]);
            circleSavings.joinCircle(cid);
        }

        // Verify: 6 members = 60% of 10 (AT threshold, not below)
        (CircleSavingsV1.Circle memory circle, , , ) = circleSavings.getCircleDetails(cid);
        assertEq(circle.currentMembers, 6, "Should have 6 members (60%)");
        assertFalse(
            circle.currentMembers < (circle.maxMembers * 60) / 100,
            "Not below 60%"
        );

        // Warp past ultimatum
        vm.warp(block.timestamp + 7 days + 1 hours);

        // Should NOT be able to withdraw (need voting or manual start)
        vm.prank(alice);
        vm.expectRevert(CircleSavingsV1.UltimatumNotPassed.selector);
        circleSavings.WithdrawCollateral(cid);
    }
}
