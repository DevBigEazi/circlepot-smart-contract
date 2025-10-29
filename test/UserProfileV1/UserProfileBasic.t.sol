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
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");

        // Fast-forward time to bypass cooldowns
        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        userProfile.updateUsername("aliceupdated");

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        userProfile.updatePhoto("ipfs://newphoto");

        UserProfileV1.UserProfile memory profile = userProfile.getProfile(
            alice
        );
        assertEq(profile.username, "aliceupdated");
        assertEq(profile.profilePhoto, "ipfs://newphoto");
    }

    function testUpdateProfile_UsernameOnly() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        userProfile.updateProfile("alice2", "");
        UserProfileV1.UserProfile memory profile = userProfile.getProfile(alice);
        assertEq(profile.username, "alice2");
    }

    function testUpdateProfile_PhotoOnly() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        userProfile.updateProfile("", "ipfs://newphoto");
        UserProfileV1.UserProfile memory profile = userProfile.getProfile(alice);
        assertEq(profile.profilePhoto, "ipfs://newphoto");
    }

    function testUpdatePhoto_CooldownNotMet() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        userProfile.updatePhoto("ipfs://p2");
        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.UsernameUpdateCooldownNotMet.selector);
        userProfile.updatePhoto("ipfs://p3");
    }
}
