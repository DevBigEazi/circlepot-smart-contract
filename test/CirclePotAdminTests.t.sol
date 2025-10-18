// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";

/**
 * @title CirclePotAdminTests
 * @notice Tests for administrative functions and fee management
 */
contract CirclePotAdminTests is CirclePotV1Test {
    
    function test_WithdrawPlatformFees() public {
        uint256 circleId = _createAndStartCircle();

        // Round 1 - Alice gets payout (creator, no fee)
        vm.prank(alice);
        circlePot.contribute(circleId);
        vm.prank(bob);
        circlePot.contribute(circleId);
        vm.prank(charlie);
        circlePot.contribute(circleId);
        vm.prank(david);
        circlePot.contribute(circleId);
        vm.prank(eve);
        circlePot.contribute(circleId);

        // Move to next round
        vm.warp(block.timestamp + 8 days);

        // Round 2 - Non-creator gets payout (with fee)
        vm.prank(alice);
        circlePot.contribute(circleId);
        vm.prank(bob);
        circlePot.contribute(circleId);
        vm.prank(charlie);
        circlePot.contribute(circleId);
        vm.prank(david);
        circlePot.contribute(circleId);
        vm.prank(eve);
        circlePot.contribute(circleId);

        uint256 totalFees = circlePot.totalPlatformFees();

        assertTrue(totalFees > 0, "Platform fees should be greater than 0");

        uint256 treasuryBalanceBefore = cUSD.balanceOf(testTreasury);

        vm.prank(testOwner);
        circlePot.withdrawPlatformFees();

        uint256 treasuryBalanceAfter = cUSD.balanceOf(testTreasury);

        assertEq(
            treasuryBalanceAfter - treasuryBalanceBefore,
            totalFees,
            "Treasury should receive all platform fees"
        );

        assertEq(
            circlePot.totalPlatformFees(),
            0,
            "Platform fees should be reset to 0"
        );
    }

    function test_UpdateTreasury() public {
        address newTreasury = address(99);

        vm.prank(testOwner);
        circlePot.updateTreasury(newTreasury);

        assertEq(circlePot.treasury(), newTreasury);
    }

    function test_SetPlatformFeeBps() public {
        vm.prank(testOwner);
        circlePot.setPlatformFeeBps(50);

        assertEq(circlePot.platformFeeBps(), 50);
    }

    function test_RevertSetPlatformFeeToohigh() public {
        vm.prank(testOwner);
        vm.expectRevert("fee too high");
        circlePot.setPlatformFeeBps(150);
    }

    function test_RevertUpdateTreasuryZeroAddress() public {
        vm.prank(testOwner);
        vm.expectRevert(CirclePotV1.InvalidTreasuryAddress.selector);
        circlePot.updateTreasury(address(0));
    }
}