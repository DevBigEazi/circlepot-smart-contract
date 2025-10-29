// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {UserProfileV1} from "../../src/UserProfileV1.sol";
import {UserProfileV1Setup} from "./UserProfileSetup.t.sol";

contract UserProfileV1Advanced is UserProfileV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_DuplicateUsernameRevert() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");

        vm.prank(bob);
        vm.expectRevert(UserProfileV1.UsernameAlreadyTaken.selector);
        userProfile.createProfile("bob@example.com", "alice", "ipfs://p2");
    }

    function test_UpdateUsernameCooldownRevert() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");

        // Set initial timestamp to when profile was created
        uint256 creationTime = block.timestamp;

        // Update username first time
        vm.prank(alice);
        userProfile.updateUsername("alice2");

        // Try to update again before cooldown period is over
        vm.warp(creationTime + 15 days); // Only wait 15 days (cooldown is 30 days)

        vm.prank(alice);
        vm.expectRevert(UserProfileV1.UsernameUpdateCooldownNotMet.selector);
        userProfile.updateUsername("alice3");

        // Verify we can update after cooldown period
        vm.warp(creationTime + 31 days);
        vm.prank(alice);
        userProfile.updateUsername("alice3");
    }

    function test_UpdateProfileBothFields() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");

        // warp past cooldown for username and photo
        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        userProfile.updateProfile("alice2", "ipfs://p2");

        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        assertEq(p.username, "alice2");
        assertEq(p.profilePhoto, "ipfs://p2");
    }

    function test_GetAddressByUsernameAndAvailability() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");

        address addr = userProfile.getAddressByUsername("alice");
        assertEq(addr, alice);

        bool available = userProfile.isUsernameAvailable("someoneelse");
        assertTrue(available);
    }
}
