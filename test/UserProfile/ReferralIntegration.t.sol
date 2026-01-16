// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {UserProfile} from "../../src/UserProfile.sol";
import {PersonalSavings} from "../../src/PersonalSavings.sol";
import {
    PersonalSavingsSetup
} from "../PersonalSavings/PersonalSavingsSetup.t.sol";

/**
 * @title ReferralIntegration
 * @dev Integration tests for the referral reward system between UserProfile and PersonalSavings
 */
contract ReferralIntegrationTest is PersonalSavingsSetup {
    function setUp() public override {
        super.setUp();

        // Mint USDm to testOwner for funding referral rewards
        USDm.mint(testOwner, 10000e18);

        // Fund the UserProfile contract with USDm for rewards and enable rewards
        vm.startPrank(testOwner);
        USDm.transfer(address(userProfile), 10000e18); // Fund the contract
        userProfile.setReferralRewardsEnabled(true);
        vm.stopPrank();
    }

    function test_ReferralReward_PaidOnFirstGoal() public {
        // Alice creates profile (no referrer)
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://alice",
            address(0)
        );

        // Bob creates profile with Alice as referrer
        vm.prank(bob);
        userProfile.createProfile(
            "bob@example.com",
            "",
            "bob",
            "Bob Smith",
            "ipfs://bob",
            alice // Alice referred Bob
        );

        // Check initial state
        assertEq(
            userProfile.referredBy(bob),
            alice,
            "Bob should be referred by Alice"
        );
        assertEq(
            userProfile.referralCount(alice),
            0,
            "Alice should have 0 successful referrals initially"
        );
        assertFalse(
            userProfile.hasFirstGoalReward(bob),
            "Bob shouldn't have first goal reward yet"
        );

        uint256 aliceBalanceBefore = USDm.balanceOf(alice);

        // Bob creates his first savings goal - this should trigger referral reward
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params);

        uint256 aliceBalanceAfter = USDm.balanceOf(alice);

        // Alice should receive referral reward
        uint256 expectedReward = userProfile.referralBonusAmount(address(USDm));
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore + expectedReward,
            "Alice should receive referral reward"
        );

        // Check state updates
        assertEq(
            userProfile.referralCount(alice),
            1,
            "Alice should have 1 successful referral"
        );
        assertTrue(
            userProfile.hasFirstGoalReward(bob),
            "Bob should be marked as rewarded"
        );
    }

    function test_ReferralReward_NotPaidOnSecondGoal() public {
        // Setup: Alice refers Bob, Bob creates first goal
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://alice",
            address(0)
        );

        vm.prank(bob);
        userProfile.createProfile(
            "bob@example.com",
            "",
            "bob",
            "Bob Smith",
            "ipfs://bob",
            alice
        );

        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params1 = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params1);

        uint256 aliceBalanceAfter1st = USDm.balanceOf(alice);

        // Bob creates second goal - should NOT trigger reward
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params2 = PersonalSavings
            .CreateGoalParams({
                name: "Bob's Second Goal",
                targetAmount: 1000e18,
                contributionAmount: 200e18,
                frequency: PersonalSavings.Frequency.MONTHLY,
                deadline: block.timestamp + 60 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params2);

        uint256 aliceBalanceAfter2nd = USDm.balanceOf(alice);

        // Alice balance should not change
        assertEq(
            aliceBalanceAfter2nd,
            aliceBalanceAfter1st,
            "Alice should not receive additional reward for second goal"
        );

        // Referral count should still be 1
        assertEq(
            userProfile.referralCount(alice),
            1,
            "Alice should still have only 1 successful referral"
        );
    }

    function test_ReferralReward_NotPaidWhenDisabled() public {
        // Disable referral rewards
        vm.prank(testOwner);
        userProfile.setReferralRewardsEnabled(false);

        // Alice refers Bob
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://alice",
            address(0)
        );

        vm.prank(bob);
        userProfile.createProfile(
            "bob@example.com",
            "",
            "bob",
            "Bob Smith",
            "ipfs://bob",
            alice
        );

        uint256 aliceBalanceBefore = USDm.balanceOf(alice);

        // Bob creates first goal
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params);

        uint256 aliceBalanceAfter = USDm.balanceOf(alice);

        // Alice should NOT receive reward
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore,
            "Alice should not receive reward when disabled"
        );

        // Referral count should be 1 (condition fulfilled)
        assertEq(
            userProfile.referralCount(alice),
            1,
            "Alice should have 1 successful referral"
        );
        assertTrue(
            userProfile.hasFirstGoalReward(bob),
            "Bob should be marked as processed"
        );
    }

    function test_ReferralReward_NoRewardWithoutReferrer() public {
        // Bob creates profile WITHOUT referrer
        vm.prank(bob);
        userProfile.createProfile(
            "bob@example.com",
            "",
            "bob",
            "Bob Smith",
            "ipfs://bob",
            address(0) // No referrer
        );

        // Bob creates first goal
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params);

        // Should silently skip (no revert)
        // No one gets rewarded
        assertFalse(
            userProfile.hasFirstGoalReward(bob),
            "Bob should not be marked as rewarded"
        );
    }

    function test_ReferralReward_CampaignBonus() public {
        // Start a campaign
        vm.prank(testOwner);
        userProfile.startReferralCampaign(30); // 30 days

        // Set higher bonus for campaign
        vm.prank(testOwner);
        userProfile.setCampaignBonusAmount(address(USDm), 10_000_000); // $10 bonus

        // Alice refers Bob
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://alice",
            address(0)
        );

        vm.prank(bob);
        userProfile.createProfile(
            "bob@example.com",
            "",
            "bob",
            "Bob Smith",
            "ipfs://bob",
            alice
        );

        uint256 aliceBalanceBefore = USDm.balanceOf(alice);

        // Bob creates first goal during campaign
        vm.prank(bob);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Bob's First Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            });
        personalSavings.createPersonalGoal(params);

        uint256 aliceBalanceAfter = USDm.balanceOf(alice);

        // Alice should receive CAMPAIGN bonus (higher)
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore + 10_000_000,
            "Alice should receive campaign bonus"
        );
    }

    function test_MultipleReferrals() public {
        // Alice creates profile
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://alice",
            address(0)
        );

        // Bob referred by Alice
        vm.prank(bob);
        userProfile.createProfile(
            "bob@example.com",
            "",
            "bob",
            "Bob Smith",
            "ipfs://bob",
            alice
        );

        // Charlie also referred by Alice
        vm.prank(charlie);
        userProfile.createProfile(
            "charlie@example.com",
            "",
            "charlie",
            "Charlie Brown",
            "ipfs://charlie",
            alice
        );

        uint256 aliceBalanceBefore = USDm.balanceOf(alice);

        // Bob creates first goal
        vm.prank(bob);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Bob's Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            })
        );

        uint256 expectedReward = userProfile.referralBonusAmount(address(USDm));
        uint256 aliceBalanceAfter1 = USDm.balanceOf(alice);
        assertEq(
            aliceBalanceAfter1,
            aliceBalanceBefore + expectedReward,
            "Alice should receive 1st reward"
        );
        assertEq(
            userProfile.referralCount(alice),
            1,
            "Alice should have 1 successful referral"
        );

        // Charlie creates first goal
        vm.prank(charlie);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Charlie's Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            })
        );

        uint256 aliceBalanceAfter2 = USDm.balanceOf(alice);
        assertEq(
            aliceBalanceAfter2,
            aliceBalanceAfter1 + expectedReward,
            "Alice should receive 2nd reward"
        );
        assertEq(
            userProfile.referralCount(alice),
            2,
            "Alice should have 2 successful referrals"
        );
    }

    function test_ReferralChain() public {
        // Alice creates profile (no referrer)
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://alice",
            address(0)
        );

        // Bob referred by Alice
        vm.prank(bob);
        userProfile.createProfile(
            "bob@example.com",
            "",
            "bob",
            "Bob Smith",
            "ipfs://bob",
            alice
        );

        // Charlie referred by Bob
        vm.prank(charlie);
        userProfile.createProfile(
            "charlie@example.com",
            "",
            "charlie",
            "Charlie Brown",
            "ipfs://charlie",
            bob
        );

        uint256 bobBalanceBefore = USDm.balanceOf(bob);
        uint256 aliceBalanceBefore = USDm.balanceOf(alice);

        // Charlie creates first goal - should reward Bob, not Alice
        vm.prank(charlie);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Charlie's Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            })
        );

        uint256 bobBalanceAfter = USDm.balanceOf(bob);
        uint256 aliceBalanceAfter = USDm.balanceOf(alice);

        uint256 expectedReward = userProfile.referralBonusAmount(address(USDm));
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
            userProfile.referralCount(bob),
            1,
            "Bob should have 1 successful referral"
        );
        assertEq(
            userProfile.referralCount(alice),
            0,
            "Alice should have 0 successful referrals"
        );
    }

    function test_ReferralReward_CumulativePayout() public {
        // Alice refers Bob
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://alice",
            address(0)
        );

        vm.prank(bob);
        userProfile.createProfile(
            "bob@example.com",
            "",
            "bob",
            "Bob Smith",
            "ipfs://bob",
            alice
        );

        // Charlie also referred by Alice
        vm.prank(charlie);
        userProfile.createProfile(
            "charlie@example.com",
            "",
            "charlie",
            "Charlie Brown",
            "ipfs://charlie",
            alice
        );

        // 1. Drain UserProfile funds
        uint256 currentBalance = USDm.balanceOf(address(userProfile));
        vm.prank(testOwner);
        userProfile.withdrawReferralFunds(address(USDm), currentBalance);

        // 2. Bob creates first goal - should record PENDING reward
        vm.prank(bob);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Bob's Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            })
        );

        uint256 expectedReward = userProfile.referralBonusAmount(address(USDm));
        assertEq(
            userProfile.pendingRewards(alice, address(USDm)),
            expectedReward,
            "Reward should be pending for Alice"
        );

        // 3. Fund the contract
        vm.startPrank(testOwner);
        USDm.transfer(address(userProfile), 1000e18);
        vm.stopPrank();

        // 4. Charlie creates first goal - should trigger CUMULATIVE payout
        uint256 aliceBalanceBefore = USDm.balanceOf(alice);
        vm.prank(charlie);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Charlie's Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            })
        );

        // Total should be 2 rewards (5 from Bob + 5 from Charlie)
        assertEq(
            USDm.balanceOf(alice),
            aliceBalanceBefore + (expectedReward * 2),
            "Alice should receive cumulative reward (Current + Pending)"
        );
        assertEq(
            userProfile.pendingRewards(alice, address(USDm)),
            0,
            "Pending reward should be cleared"
        );
        assertEq(
            userProfile.referralCount(alice),
            2,
            "Alice should have 2 successful referrals"
        );
    }

    function test_ReferralReward_AdminProcessPending() public {
        // Alice refers Bob
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://alice",
            address(0)
        );

        vm.prank(bob);
        userProfile.createProfile(
            "bob@example.com",
            "",
            "bob",
            "Bob Smith",
            "ipfs://bob",
            alice
        );

        // 1. Drain funds
        uint256 currentBalance = USDm.balanceOf(address(userProfile));
        vm.prank(testOwner);
        userProfile.withdrawReferralFunds(address(USDm), currentBalance);

        // 2. Bob creates goal -> Pending
        vm.prank(bob);
        personalSavings.createPersonalGoal(
            PersonalSavings.CreateGoalParams({
                name: "Bob's Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDm),
                yieldAPY: 0
            })
        );

        uint256 expectedReward = userProfile.referralBonusAmount(address(USDm));
        assertEq(
            userProfile.pendingRewards(alice, address(USDm)),
            expectedReward
        );
        assertTrue(userProfile.isUserPendingForToken(address(USDm), alice));
        assertEq(userProfile.getPendingUserCount(address(USDm)), 1);

        // 3. Fund contract
        vm.prank(testOwner);
        USDm.transfer(address(userProfile), 1000e18);

        // 4. Admin processes pending rewards
        uint256 aliceBalanceBefore = USDm.balanceOf(alice);
        vm.prank(testOwner);
        userProfile.processPendingRewards(address(USDm), 10); // Process up to 10 users

        assertEq(USDm.balanceOf(alice), aliceBalanceBefore + expectedReward);
        assertEq(userProfile.pendingRewards(alice, address(USDm)), 0);
        assertFalse(userProfile.isUserPendingForToken(address(USDm), alice));
        assertEq(userProfile.getPendingUserCount(address(USDm)), 0);
    }
}
