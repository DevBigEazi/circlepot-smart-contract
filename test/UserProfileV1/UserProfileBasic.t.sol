// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {UserProfileV1} from "../../src/UserProfileV1.sol";
import {UserProfileV1Setup} from "./UserProfileSetup.t.sol";

contract UserProfileV1BasicTests is UserProfileV1Setup {
    function setUp() public override {
        super.setUp();
    }

    function testCreateAndGetProfile() public {
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "alice",
            "ipfs://photo1"
        );

        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        assertEq(p.userAddress, alice);
        assertEq(p.email, "alice@example.com");
        assertEq(p.username, "alice");
    }

    function testUpdateUsernameAndPhoto() public {
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "alice",
            "ipfs://photo1"
        );

        // Update username first
        vm.warp(block.timestamp + 1); // small time advance for first update
        vm.prank(alice);
        userProfile.updateUsername("alice2");

        // Wait past cooldown period
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        userProfile.updatePhoto("ipfs://photo2");

        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        assertEq(p.username, "alice2");
        assertEq(p.profilePhoto, "ipfs://photo2");
    }
}
