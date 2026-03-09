// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReferralRewards} from "../../src/ReferralRewards.sol";
import {PersonalSavings} from "../../src/PersonalSavings.sol";
import {
    PersonalSavingsSetup
} from "../PersonalSavings/PersonalSavingsSetup.t.sol";

/**
 * @title ReferralIntegration
 * @dev Integration tests for the referral reward system between ReferralRewards and PersonalSavings
 */
contract ReferralIntegrationTest is PersonalSavingsSetup {
    function setUp() public override {
        super.setUp();

        // Mint USDT to testOwner for funding referral rewards
        USDT.mint(testOwner, 10000e6);

        // Fund the ReferralRewards contract with USDT for rewards
        vm.startPrank(testOwner);
        USDT.transfer(address(referralRewards), 10000e6);
        referralRewards.setRelayerStatus(testOwner, true); // Owner acts as relayer for tests
        vm.stopPrank();
    }

    function test_ReferralReward_PaidOnFirstGoal() public {
        // Bob creates profile with Alice as referrer - API triggers recordReferral
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(bob, alice);

        // Check initial state
        assertEq(
            referralRewards.referredBy(bob),
            alice,
            "Bob should be referred by Alice"
        );
        assertEq(
            referralRewards.referralCount(alice),
            0,
            "Alice should have 0 successful referrals initially"
        );
        assertFalse(
            referralRewards.hasFirstGoalReward(bob),
            "Bob shouldn't have first goal reward yet"
        );

        uint256 aliceBalanceBefore = USDT.balanceOf(alice);

        // Bob creates his first savings goal - this should trigger referral reward
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params);

        uint256 aliceBalanceAfter = USDT.balanceOf(alice);

        // Alice should receive referral reward
        uint256 expectedReward = referralRewards.referralBonusAmount(
            address(USDT)
        );
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore + expectedReward,
            "Alice should receive referral reward"
        );

        // Check state updates
        assertEq(
            referralRewards.referralCount(alice),
            1,
            "Alice should have 1 successful referral"
        );
        assertTrue(
            referralRewards.hasFirstGoalReward(bob),
            "Bob should be marked as rewarded"
        );
    }

    function test_ReferralReward_NotPaidOnSecondGoal() public {
        // Setup: Alice refers Bob
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(bob, alice);

        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params1 = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params1);

        uint256 aliceBalanceAfter1st = USDT.balanceOf(alice);

        // Bob creates second goal - should NOT trigger reward
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params2 = PersonalSavings
            .CreateGoalParams({
                name: "Bob's Second Goal",
                targetAmount: 1000e6,
                contributionAmount: 200e6,
                frequency: PersonalSavings.Frequency.MONTHLY,
                deadline: block.timestamp + 60 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params2);

        uint256 aliceBalanceAfter2nd = USDT.balanceOf(alice);

        // Alice balance should not change
        assertEq(
            aliceBalanceAfter2nd,
            aliceBalanceAfter1st,
            "Alice should not receive additional reward for second goal"
        );

        // Referral count should still be 1
        assertEq(
            referralRewards.referralCount(alice),
            1,
            "Alice should still have only 1 successful referral"
        );
    }

    function test_ReferralReward_NotPaidWhenDisabled() public {
        // Alice refers Bob
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(bob, alice);

        // Disable referral rewards
        vm.prank(testOwner);
        referralRewards.setTokenSupport(address(USDT), false);

        uint256 aliceBalanceBefore = USDT.balanceOf(alice);

        // Bob creates first goal
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params);

        uint256 aliceBalanceAfter = USDT.balanceOf(alice);

        // Alice should NOT receive reward
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore,
            "Alice should not receive reward when disabled"
        );

        // Referral count should be 1 (condition fulfilled)
        assertEq(
            referralRewards.referralCount(alice),
            1,
            "Alice should have 1 successful referral"
        );
        assertTrue(
            referralRewards.hasFirstGoalReward(bob),
            "Bob should be marked as processed"
        );
    }

    function test_ReferralReward_NoRewardWithoutReferrer() public {
        // Bob creates first goal
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params);

        // Should silently skip (no revert)
        // No one gets rewarded
        assertFalse(
            referralRewards.hasFirstGoalReward(bob),
            "Bob should not be rewarded"
        );
    }

    function test_ReferralReward_CampaignBonus() public {
        // Start a campaign
        vm.prank(testOwner);
        referralRewards.startReferralCampaign(30); // 30 days

        // Set higher bonus for campaign
        vm.prank(testOwner);
        referralRewards.setCampaignBonusAmount(address(USDT), 10_000_000); // $10 bonus

        // Alice refers Bob
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(bob, alice);

        uint256 aliceBalanceBefore = USDT.balanceOf(alice);

        // Bob creates first goal during campaign
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params);

        uint256 aliceBalanceAfter = USDT.balanceOf(alice);

        // Alice should receive CAMPAIGN bonus (higher)
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore + 10_000_000,
            "Alice should receive campaign bonus"
        );
    }

    function test_MultipleReferrals() public {
        // Bob referred by Alice
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(bob, alice);

        // Charlie also referred by Alice
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(charlie, alice);

        uint256 aliceBalanceBefore = USDT.balanceOf(alice);

        // Bob creates first goal
        vm.prank(bob);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Bob's Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );

        uint256 expectedReward = referralRewards.referralBonusAmount(
            address(USDT)
        );
        uint256 aliceBalanceAfter1 = USDT.balanceOf(alice);
        assertEq(
            aliceBalanceAfter1,
            aliceBalanceBefore + expectedReward,
            "Alice should receive 1st reward"
        );
        assertEq(
            referralRewards.referralCount(alice),
            1,
            "Alice should have 1 successful referral"
        );

        // Charlie creates first goal
        vm.prank(charlie);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Charlie's Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );

        uint256 aliceBalanceAfter2 = USDT.balanceOf(alice);
        assertEq(
            aliceBalanceAfter2,
            aliceBalanceAfter1 + expectedReward,
            "Alice should receive 2nd reward"
        );
        assertEq(
            referralRewards.referralCount(alice),
            2,
            "Alice should have 2 successful referrals"
        );
    }

    function test_ReferralChain() public {
        // Bob referred by Alice
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(bob, alice);

        // Charlie referred by Bob
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(charlie, bob);

        uint256 bobBalanceBefore = USDT.balanceOf(bob);
        uint256 aliceBalanceBefore = USDT.balanceOf(alice);

        // Charlie creates first goal - should reward Bob, not Alice
        vm.prank(charlie);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Charlie's Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );

        uint256 bobBalanceAfter = USDT.balanceOf(bob);
        uint256 aliceBalanceAfter = USDT.balanceOf(alice);

        uint256 expectedReward = referralRewards.referralBonusAmount(
            address(USDT)
        );
        assertEq(
            bobBalanceAfter,
            bobBalanceBefore + expectedReward,
            "Bob should receive reward for referring Charlie"
        );
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore,
            "Alice should not receive reward"
        );
        assertEq(
            referralRewards.referralCount(bob),
            1,
            "Bob should have 1 successful referral"
        );
        assertEq(
            referralRewards.referralCount(alice),
            0,
            "Alice should have 0 successful referrals"
        );
    }

    function test_ReferralReward_CumulativePayout() public {
        // Bob referred by Alice
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(bob, alice);

        // Charlie also referred by Alice
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(charlie, alice);

        // 1. Drain ReferralRewards funds
        uint256 currentBalance = USDT.balanceOf(address(referralRewards));
        vm.prank(testOwner);
        referralRewards.withdrawFunds(address(USDT), currentBalance);

        // 2. Bob creates first goal - should record PENDING reward
        vm.prank(bob);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Bob's Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );

        uint256 expectedReward = referralRewards.referralBonusAmount(
            address(USDT)
        );
        assertEq(
            referralRewards.pendingRewards(alice, address(USDT)),
            expectedReward,
            "Reward should be pending for Alice"
        );

        // 3. Fund the contract
        vm.startPrank(testOwner);
        USDT.transfer(address(referralRewards), 1000e6);
        vm.stopPrank();

        // 4. Charlie creates first goal - should trigger CUMULATIVE payout
        uint256 aliceBalanceBefore = USDT.balanceOf(alice);
        vm.prank(charlie);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Charlie's Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );

        // Total should be 2 rewards (5 from Bob + 5 from Charlie)
        assertEq(
            USDT.balanceOf(alice),
            aliceBalanceBefore + (expectedReward * 2),
            "Alice should receive cumulative reward (Current + Pending)"
        );
        assertEq(
            referralRewards.pendingRewards(alice, address(USDT)),
            0,
            "Pending reward should be cleared"
        );
        assertEq(
            referralRewards.referralCount(alice),
            2,
            "Alice should have 2 successful referrals"
        );
    }

    function test_ReferralReward_AdminProcessPending() public {
        // Alice refers Bob
        vm.prank(testOwner); // Relayer
        referralRewards.recordReferral(bob, alice);

        // 1. Drain funds
        uint256 currentBalance = USDT.balanceOf(address(referralRewards));
        vm.prank(testOwner);
        referralRewards.withdrawFunds(address(USDT), currentBalance);

        // 2. Bob creates goal -> Pending
        vm.prank(bob);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Bob's Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            })
        );

        uint256 expectedReward = referralRewards.referralBonusAmount(
            address(USDT)
        );
        assertEq(
            referralRewards.pendingRewards(alice, address(USDT)),
            expectedReward
        );
        assertTrue(referralRewards.isUserPendingForToken(address(USDT), alice));
        assertEq(referralRewards.getPendingUserCount(address(USDT)), 1);

        // 3. Fund contract
        vm.prank(testOwner);
        USDT.transfer(address(referralRewards), 1000e6);

        // 4. Admin processes pending rewards
        uint256 aliceBalanceBefore = USDT.balanceOf(alice);
        vm.prank(testOwner);
        referralRewards.processPendingRewards(address(USDT), 10); // Process up to 10 users

        assertEq(USDT.balanceOf(alice), aliceBalanceBefore + expectedReward);
        assertEq(referralRewards.pendingRewards(alice, address(USDT)), 0);
        assertFalse(
            referralRewards.isUserPendingForToken(address(USDT), alice)
        );
        assertEq(referralRewards.getPendingUserCount(address(USDT)), 0);
    }
}
