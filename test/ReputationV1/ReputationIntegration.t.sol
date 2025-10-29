// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {ReputationSetup} from "./ReputationSetup.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {PersonalSavingsV1} from "../../src/PersonalSavingsV1.sol";
import {PersonalSavingsProxy} from "../../src/proxies/PersonalSavingsProxy.sol";
import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsProxy} from "../../src/proxies/CircleSavingsProxy.sol";

/**
 * @title ReputationIntegration
 * @dev Integration tests for Reputation with other contracts
 */
contract ReputationIntegration is ReputationSetup {
    uint256 public constant CONTRIBUTION_AMOUNT = 100e18;
    uint256 public constant TARGET_AMOUNT = 100e18; // match one contribution for simplicity
    uint256 public constant DEADLINE = 30 days;

    // Test contracts
    MockERC20 public mockCUSD;
    PersonalSavingsV1 public personalSavingsImpl;
    PersonalSavingsProxy public savingsProxy;
    PersonalSavingsV1 public personalSavings;
    CircleSavingsV1 public circleSavingsImpl;
    CircleSavingsProxy public circleProxy;
    CircleSavingsV1 public circleSavings;

    function setUp() public override {
        super.setUp();

        // Additional setup for integration tests
        mockCUSD = new MockERC20();

        // Mint tokens to users for testing (cover collateral + contributions)
        mockCUSD.mint(user1, 3000e18);
        mockCUSD.mint(user2, 3000e18);
        mockCUSD.mint(user3, 3000e18);

        // Deploy proxies with reputation integration
        vm.startPrank(owner);

        // Deploy implementations
        personalSavingsImpl = new PersonalSavingsV1();
        circleSavingsImpl = new CircleSavingsV1();

        // Deploy proxies with reputation integration
        savingsProxy = new PersonalSavingsProxy(
            address(personalSavingsImpl),
            address(mockCUSD),
            address(reputation),
            owner
        );
        personalSavings = PersonalSavingsV1(address(savingsProxy));

        circleProxy = new CircleSavingsProxy(
            address(circleSavingsImpl),
            address(mockCUSD),
            treasury,
            address(reputation),
            owner
        );
        circleSavings = CircleSavingsV1(address(circleProxy));

        // Authorize the contracts
        reputation.authorizeContract(address(savingsProxy), "PersonalSavings");
        reputation.authorizeContract(address(circleProxy), "CircleSavings");

        vm.stopPrank();
    }

    function test_savingsGoalCompletion() public {
        // User approves token spending
        vm.startPrank(user1);
        mockCUSD.approve(address(savingsProxy), type(uint256).max);

        // Create a personal savings goal
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "Test Goal",
                targetAmount: TARGET_AMOUNT,
                contributionAmount: CONTRIBUTION_AMOUNT,
                frequency: PersonalSavingsV1.Frequency.DAILY,
                deadline: block.timestamp + DEADLINE
            });
        uint256 goalId = personalSavings.createPersonalGoal(params);

        // Make a single contribution to reach target
        personalSavings.ContributeToGoal(goalId);

        // Complete the goal
        personalSavings.CompleteGoal(goalId);

        // Check reputation was increased
        assertGt(reputation.getReputation(user1), 0);
        vm.stopPrank();
    }

    function test_savingsEarlyWithdrawal() public {
        // User approves token spending
        vm.startPrank(user1);
        mockCUSD.approve(address(savingsProxy), type(uint256).max);

        // Create a personal savings goal
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1
            .CreateGoalParams({
                name: "Test Goal",
                targetAmount: TARGET_AMOUNT,
                contributionAmount: CONTRIBUTION_AMOUNT,
                frequency: PersonalSavingsV1.Frequency.DAILY,
                deadline: block.timestamp + DEADLINE
            });
        uint256 goalId = personalSavings.createPersonalGoal(params);

        // Make a single contribution
        personalSavings.ContributeToGoal(goalId);

        // Withdraw early within available balance
        uint256 withdrawAmount = CONTRIBUTION_AMOUNT / 2;
        personalSavings.withdrawFromGoal(goalId, withdrawAmount);

        // After reaching target (+10) and withdrawing early (-5), net reputation should be 5
        uint256 rep = reputation.getReputation(user1);
        assertEq(rep, 5);
        vm.stopPrank();
    }

    function test_circleCompletionReputation() public {
        // Setup users
        address[] memory users = new address[](5);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        users[3] = makeAddr("user4");
        users[4] = makeAddr("user5");

        // Give tokens to all users
        for (uint256 i = 0; i < users.length; i++) {
            mockCUSD.mint(users[i], 3000e18);
            vm.prank(users[i]);
            mockCUSD.approve(address(circleProxy), type(uint256).max);
        }

        // Create circle
        vm.prank(user1);
        uint256 circleId = circleSavings.createCircle(
            CircleSavingsV1.CreateCircleParams({
                contributionAmount: CONTRIBUTION_AMOUNT,
                frequency: CircleSavingsV1.Frequency.DAILY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PUBLIC
            })
        );

        // Have other users join
        for (uint256 i = 1; i < users.length; i++) {
            vm.prank(users[i]);
            circleSavings.joinCircle(circleId);
        }

        // Should auto-start since max members reached

        // Make contributions for all 5 rounds so each member gets a payout
        for (uint256 round = 1; round <= 5; round++) {
            for (uint256 i = 0; i < users.length; i++) {
                vm.prank(users[i]);
                circleSavings.contribute(circleId);
            }
            // advance to the next round interval
            vm.warp(block.timestamp + 7 days);
        }

        // Check reputation changes: at least one member has positive reputation
        bool anyPositive = false;
        for (uint256 i = 0; i < users.length; i++) {
            if (reputation.getReputation(users[i]) > 0) {
                anyPositive = true;
                break;
            }
        }
        assertTrue(anyPositive, "At least one member should have positive reputation");
    }

    function test_circleLatePayment() public {
        // Setup similar to previous test...
        address[] memory users = new address[](5);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        users[3] = makeAddr("user4");
        users[4] = makeAddr("user5");

        // Give tokens and approvals
        for (uint256 i = 0; i < users.length; i++) {
            mockCUSD.mint(users[i], 1000e18);
            vm.prank(users[i]);
            mockCUSD.approve(address(circleProxy), type(uint256).max);
        }

        // Create and start circle
        vm.prank(user1);
        uint256 circleId = circleSavings.createCircle(
            CircleSavingsV1.CreateCircleParams({
                contributionAmount: CONTRIBUTION_AMOUNT,
                frequency: CircleSavingsV1.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavingsV1.Visibility.PUBLIC
            })
        );

        // Have others join
        for (uint256 i = 1; i < users.length; i++) {
            vm.prank(users[i]);
            circleSavings.joinCircle(circleId);
        }

        // Have others contribute on time
        vm.prank(user1);
        circleSavings.contribute(circleId);
        vm.prank(user3);
        circleSavings.contribute(circleId);
        vm.prank(users[3]);
        circleSavings.contribute(circleId);
        vm.prank(users[4]);
        circleSavings.contribute(circleId);

        // Move time past grace period for user2
        vm.warp(block.timestamp + 9 days + 1 hours); // 7 days + 48 hours grace + buffer

        // User makes late payment
        vm.prank(user2);
        circleSavings.contribute(circleId);

        // Check negative reputation impact
        (, , uint256 latePayments, ) = reputation.getUserReputationData(user2);
        assertEq(latePayments, 1, "Should record late payment");
        (, , uint256 latePay, ) = reputation.getUserReputationData(user2);
        assertGt(latePay, 0, "Should have late payment recorded");
    }
}
