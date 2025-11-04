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
        userProfile.createProfile("alice@example.com", "alice", "ipfs://photo1");

        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        assertEq(p.userAddress, alice);
        assertEq(p.email, "alice@example.com");
        assertEq(p.username, "alice");
    }

    function testUpdatePhoto_CooldownNotMet() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "ipfs://p1");
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        userProfile.updatePhoto("ipfs://p2");
        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.PhotoUpdateCooldownNotMet.selector);
        userProfile.updatePhoto("ipfs://p3");
    }
}
