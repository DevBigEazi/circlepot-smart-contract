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

    function test_GetAddressByUsernameAndAvailability() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");

        address addr = userProfile.getAddressByUsername("alice");
        assertEq(addr, alice);

        bool available = userProfile.isUsernameAvailable("someoneelse");
        assertTrue(available);
    }

    function test_GetAddressByUsername_RevertProfileDoesNotExist() public {
        vm.expectRevert(UserProfileV1.ProfileDoesNotExist.selector);
        userProfile.getAddressByUsername("nonexistent");
    }

    function test_IsUsernameAvailable_ReturnsFalse() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");
        bool available = userProfile.isUsernameAvailable("alice");
        assertFalse(available);
    }

    function test_UpdatePhoto_Only() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        userProfile.updatePhoto("ipfs://newphoto");
        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        assertEq(p.profilePhoto, "ipfs://newphoto");
        assertEq(p.username, "alice");
    }

    function test_CreateProfile_RevertProfileAlreadyExists() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.ProfileAlreadyExists.selector);
        userProfile.createProfile("alice2@example.com", "alice2", "ipfs://p2");
    }

    function test_UpdatePhoto_RevertEmptyPhoto() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.EmptyPhoto.selector);
        userProfile.updatePhoto("");
    }

    function test_GetProfile_RevertProfileDoesNotExist() public {
        vm.expectRevert(UserProfileV1.ProfileDoesNotExist.selector);
        userProfile.getProfile(bob);
    }

    function test_CreateProfile_EmptyFields() public {
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.EmptyEmail.selector);
        userProfile.createProfile("", "alice", "ipfs://p1");
    }

    function test_CreateProfile_EmptyUsername() public {
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.EmptyUsername.selector);
        userProfile.createProfile("alice@example.com", "", "ipfs://p1");
    }

    function test_UpdatePhoto_RevertProfileDoesNotExist() public {
        vm.prank(bob);
        vm.expectRevert(UserProfileV1.ProfileDoesNotExist.selector);
        userProfile.updatePhoto("ipfs://new");
    }
}
