// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {CircleSavingsV1Setup} from "./CircleSavingsSetup.t.sol";
import {YieldVault} from "../../src/mocks/YieldVault.sol";

contract YieldIntegrationTest is CircleSavingsV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_ImmediateDepositOnCreateAndJoin() public {
        vm.startPrank(alice);
        CircleSavingsV1.CreateCircleParams memory params = CircleSavingsV1.CreateCircleParams({
            title: "Yield Circle",
            description: "Testing immediate yield",
            contributionAmount: 100e18,
            frequency: CircleSavingsV1.Frequency.WEEKLY,
            maxMembers: 5,
            visibility: CircleSavingsV1.Visibility.PUBLIC,
            enableYield: true
        });

        uint256 cid = circleSavings.createCircle(params);
        vm.stopPrank();

        // Check that Alice's collateral is in the vault
        // Collateral = 100e18 * 5 + 1% = 505e18
        uint256 expectedCollateral = 505e18;
        uint256 aliceShares = circleSavings.circleShares(cid);
        assertGt(aliceShares, 0, "Shares should be minted for creator");
        assertEq(yieldVault.previewRedeem(aliceShares), expectedCollateral, "Vault should hold Alice's collateral");

        // Bob joins
        vm.prank(bob);
        circleSavings.joinCircle(cid);

        uint256 totalShares = circleSavings.circleShares(cid);
        assertEq(yieldVault.previewRedeem(totalShares), expectedCollateral * 2, "Vault should hold both members' collateral");
    }

    function test_YieldSplit90_10_OnCircleCompletion() public {
        // Create a 5-member circle
        uint256 cid = _create5MemberCircleAndStart();

        // Total Collateral = 5 * 505e18 = 2525e18
        // Let's simulate 100e18 organic yield in the vault
        deal(address(USDm), address(this), 100e18);
        USDm.approve(address(yieldVault), 100e18);
        yieldVault.simulateYield(100e18);

        uint256 platformFeesBefore = circleSavings.totalPlatformFees();

        // Complete 5 rounds
        address[] memory members = new address[](5);
        members[0] = alice;
        members[1] = bob;
        members[2] = charlie;
        members[3] = david;
        members[4] = eve;

        for (uint256 r = 1; r <= 5; r++) {
            for (uint256 i = 0; i < 5; i++) {
                _contributeOnTime(cid, members[i]);
            }
        }

        uint256 platformFeesAfter = circleSavings.totalPlatformFees();
        uint256 platformFeesCollected = platformFeesAfter - platformFeesBefore;

        // Platform collections:
        // 1. Payout fees: 4 rounds (Bob, Charlie, David, Eve) * 5e18 (1% of 500) = 20e18
        // 2. Yield share: 10% of 100e18 yield = 10e18
        // Total expected: ~30e18
        
        assertApproxEqAbs(platformFeesCollected, 30e18, 1e15, "Platform should get payout fees + 10% yield share");
    }

    function test_PlatformSweepOnDeadCircle() public {
        vm.startPrank(alice);
        uint256 cid = circleSavings.createCircle(CircleSavingsV1.CreateCircleParams({
            title: "Dead Pool",
            description: "Interest for platform",
            contributionAmount: 100e18,
            frequency: CircleSavingsV1.Frequency.WEEKLY,
            maxMembers: 5,
            visibility: CircleSavingsV1.Visibility.PUBLIC,
            enableYield: true
        }));
        vm.stopPrank();

        // uint256 initialShares = circleSavings.circleShares(cid);
        // Alice shares = 505 for 505 assets.

        // Add 10e18 yield to the vault while it's pending
        deal(address(USDm), address(this), 10e18);
        USDm.approve(address(yieldVault), 10e18);
        yieldVault.simulateYield(10e18);

        // Alice decides to withdraw (Ultimatum passed)
        vm.warp(block.timestamp + 8 days);
        
        uint256 platformFeesBefore = circleSavings.totalPlatformFees();
        
        vm.prank(alice);
        circleSavings.WithdrawCollateral(cid);

        uint256 platformFeesAfter = circleSavings.totalPlatformFees();
        uint256 collection = platformFeesAfter - platformFeesBefore;
        
        // Expected collection: 
        // 1. Dead fee: 0.5 (added to totalPlatformFees immediately)
        // 2. Residual yield sweep: ~10.5 (the 10 yield + the 0.5 fee left in vault)
        // Total: ~11.0
        
        assertApproxEqAbs(collection, 11.0e18, 1e15, "Platform should collect fee plus swept yield");
    }

    // Helper functions
    function _create5MemberCircleAndStart() internal returns (uint256) {
        vm.prank(alice);
        uint256 cid = circleSavings.createCircle(CircleSavingsV1.CreateCircleParams({
            title: "5 Member Circle",
            description: "Simple test",
            contributionAmount: 100e18,
            frequency: CircleSavingsV1.Frequency.WEEKLY,
            maxMembers: 5,
            visibility: CircleSavingsV1.Visibility.PUBLIC,
            enableYield: true
        }));

        address[] memory others = new address[](4);
        others[0] = bob;
        others[1] = charlie;
        others[2] = david;
        others[3] = eve;

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(others[i]);
            circleSavings.joinCircle(cid);
        }
        
        return cid;
    }

    function _contributeOnTime(uint256 cid, address user) internal {
        vm.prank(user);
        circleSavings.contribute(cid);
    }
}
