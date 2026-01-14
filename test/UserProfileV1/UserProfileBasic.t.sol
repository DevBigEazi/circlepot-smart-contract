// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {UserProfile} from "../../src/UserProfile.sol";
import {UserProfileSetup} from "./UserProfileSetup.t.sol";

contract UserProfileBasicTests is UserProfileSetup {
    function setUp() public override {
        super.setUp();
    }

    function testCreateAndGetProfile() public {
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://photo1"
        );

        UserProfile.UserProfile memory p = userProfile.getProfile(alice);
        assertEq(p.userAddress, alice);
        assertEq(p.email, "alice@example.com");
        assertEq(p.username, "alice");
        assertEq(p.fullName, "Alice Johnson");
        assertEq(p.profilePhoto, "ipfs://photo1");
    }

    function testUpdatePhoto_CooldownNotMet() public {
        vm.prank(alice);
        userProfile.createProfile(
            "alice@example.com",
            "",
            "alice",
            "Alice Johnson",
            "ipfs://p1"
        );
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        userProfile.updateProfile("", "ipfs://p2");
        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        vm.expectRevert(UserProfile.ProfileUpdateCooldownNotMet.selector);
        userProfile.updateProfile("", "ipfs://p3");
    }
}
