// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {UserProfileV1} from "../../src/UserProfileV1.sol";
import {UserProfileV1Setup} from "./UserProfileSetup.t.sol";

contract UserProfileV1Advanced is UserProfileV1Setup {
    function setUp() public override {
        super.setUp();
    }

    // ============ Username Tests ============

    function test_DuplicateUsernameRevert() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");

        vm.prank(bob);
        vm.expectRevert(UserProfileV1.UsernameAlreadyTaken.selector);
        userProfile.createProfile("bob@example.com", "alice", "Alice Johnson", "ipfs://p2");
    }

    function test_GetAddressByUsernameAndAvailability() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");

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
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        bool available = userProfile.isUsernameAvailable("alice");
        assertFalse(available);
    }

    // ============ Photo Update Tests ============

    function test_UpdatePhoto_Only() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        userProfile.updatePhoto("ipfs://newphoto");
        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        assertEq(p.profilePhoto, "ipfs://newphoto");
        assertEq(p.username, "alice");
    }

    function test_UpdatePhoto_RevertEmptyPhoto() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.EmptyPhoto.selector);
        userProfile.updatePhoto("");
    }

    function test_UpdatePhoto_RevertProfileDoesNotExist() public {
        vm.prank(bob);
        vm.expectRevert(UserProfileV1.ProfileDoesNotExist.selector);
        userProfile.updatePhoto("ipfs://new");
    }

    // ============ Profile Creation Tests ============

    function test_CreateProfile_RevertProfileAlreadyExists() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.ProfileAlreadyExists.selector);
        userProfile.createProfile("alice2@example.com", "alice2", "Alice Johnson", "ipfs://p2");
    }

    function test_GetProfile_RevertProfileDoesNotExist() public {
        vm.expectRevert(UserProfileV1.ProfileDoesNotExist.selector);
        userProfile.getProfile(bob);
    }

    function test_CreateProfile_EmptyEmail() public {
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.EmptyEmail.selector);
        userProfile.createProfile("", "alice", "Alice Johnson", "ipfs://p1");
    }

    function test_CreateProfile_EmptyUsername() public {
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.EmptyUsername.selector);
        userProfile.createProfile("alice@example.com", "", "Alice Johnson", "ipfs://p1");
    }

    function test_CreateProfile_EmptyFullName() public {
        vm.prank(alice);
        vm.expectRevert(UserProfileV1.EmptyFullName.selector);
        userProfile.createProfile("alice@example.com", "alice", "", "ipfs://p1");
    }

    // ============ Account ID Tests ============

    function test_AccountId_GeneratedOnProfileCreation() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        
        // Check account ID is within valid range (10-digit number)
        assertGe(p.accountId, 1000000000, "Account ID should be at least 1000000000");
        assertLe(p.accountId, 9999999999, "Account ID should be at most 9999999999");
    }

    function test_AccountId_UniqueForMultipleUsers() public {
        // Create profiles for multiple users
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        vm.prank(bob);
        userProfile.createProfile("bob@example.com", "bob", "Bob Smith", "ipfs://p2");
        
        vm.prank(charlie);
        userProfile.createProfile("charlie@example.com", "charlie", "Charlie Brown", "ipfs://p3");
        
        // Get all profiles
        UserProfileV1.UserProfile memory aliceProfile = userProfile.getProfile(alice);
        UserProfileV1.UserProfile memory bobProfile = userProfile.getProfile(bob);
        UserProfileV1.UserProfile memory charlieProfile = userProfile.getProfile(charlie);
        
        // All account IDs should be different
        assertTrue(aliceProfile.accountId != bobProfile.accountId, "Alice and Bob should have different account IDs");
        assertTrue(bobProfile.accountId != charlieProfile.accountId, "Bob and Charlie should have different account IDs");
        assertTrue(aliceProfile.accountId != charlieProfile.accountId, "Alice and Charlie should have different account IDs");
        
        // All should be valid 10-digit numbers
        assertGe(aliceProfile.accountId, 1000000000);
        assertLe(aliceProfile.accountId, 9999999999);
        assertGe(bobProfile.accountId, 1000000000);
        assertLe(bobProfile.accountId, 9999999999);
        assertGe(charlieProfile.accountId, 1000000000);
        assertLe(charlieProfile.accountId, 9999999999);
    }

    function test_GetAddressByAccountId_Success() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        uint256 accountId = p.accountId;
        
        address retrievedAddress = userProfile.getAddressByAccountId(accountId);
        assertEq(retrievedAddress, alice, "Should retrieve correct address by account ID");
    }

    function test_GetAddressByAccountId_RevertInvalidAccountId() public {
        // Test with account ID below minimum
        vm.expectRevert(UserProfileV1.InvalidAccountId.selector);
        userProfile.getAddressByAccountId(999999999);
        
        // Test with account ID above maximum
        vm.expectRevert(UserProfileV1.InvalidAccountId.selector);
        userProfile.getAddressByAccountId(10000000000);
        
        // Test with zero
        vm.expectRevert(UserProfileV1.InvalidAccountId.selector);
        userProfile.getAddressByAccountId(0);
    }

    function test_GetAddressByAccountId_RevertProfileDoesNotExist() public {
        // Valid account ID range but no profile exists
        vm.expectRevert(UserProfileV1.ProfileDoesNotExist.selector);
        userProfile.getAddressByAccountId(1234567890);
    }

    function test_GetUserDetailsByAccountId_Success() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        uint256 accountId = p.accountId;
        
        (
            address userAddress,
            string memory fullName,
            string memory email,
            string memory username
        ) = userProfile.getUserDetailsByAccountId(accountId);
        
        assertEq(userAddress, alice, "Should return correct user address");
        assertEq(fullName, "Alice Johnson", "Should return correct full name");
        assertEq(email, "alice@example.com", "Should return correct email");
        assertEq(username, "alice", "Should return correct username");
    }

    function test_GetUserDetailsByAccountId_RevertInvalidAccountId() public {
        // Test below minimum
        vm.expectRevert(UserProfileV1.InvalidAccountId.selector);
        userProfile.getUserDetailsByAccountId(999999999);
        
        // Test above maximum
        vm.expectRevert(UserProfileV1.InvalidAccountId.selector);
        userProfile.getUserDetailsByAccountId(10000000000);
    }

    function test_GetUserDetailsByAccountId_RevertProfileDoesNotExist() public {
        // Valid range but no profile
        vm.expectRevert(UserProfileV1.ProfileDoesNotExist.selector);
        userProfile.getUserDetailsByAccountId(5555555555);
    }

    function test_GetUserDetailsByIdentifier_ByUsername() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        (
            address userAddress,
            string memory fullName,
            uint256 accountId,
            string memory email,
            string memory username
        ) = userProfile.getUserDetailsByIdentifier("alice");
        
        assertEq(userAddress, alice, "Should return correct user address");
        assertEq(fullName, "Alice Johnson", "Should return correct full name");
        assertGe(accountId, 1000000000, "Should return valid account ID");
        assertLe(accountId, 9999999999, "Should return valid account ID");
        assertEq(email, "alice@example.com", "Should return correct email");
        assertEq(username, "alice", "Should return correct username");
    }

    function test_GetUserDetailsByIdentifier_ByEmail() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        (
            address userAddress,
            string memory fullName,
            uint256 accountId,
            string memory email,
            string memory username
        ) = userProfile.getUserDetailsByIdentifier("alice@example.com");
        
        assertEq(userAddress, alice, "Should return correct user address");
        assertEq(fullName, "Alice Johnson", "Should return correct full name");
        assertGe(accountId, 1000000000, "Should return valid account ID");
        assertLe(accountId, 9999999999, "Should return valid account ID");
        assertEq(email, "alice@example.com", "Should return correct email");
        assertEq(username, "alice", "Should return correct username");
    }

    function test_GetUserDetailsByIdentifier_RevertProfileDoesNotExist() public {
        vm.expectRevert(UserProfileV1.ProfileDoesNotExist.selector);
        userProfile.getUserDetailsByIdentifier("nonexistent");
    }

    function test_GetRemainingAccountIds() public {
        uint256 initialRemaining = userProfile.getRemainingAccountIds();
        
        // Should start with maximum available
        assertEq(initialRemaining, 9999999999 - 1000000000 + 1, "Should have all account IDs available initially");
        
        // Create a profile
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        uint256 afterOneProfile = userProfile.getRemainingAccountIds();
        
        // Should decrease by at least 1 (could be more due to collision handling)
        assertLe(afterOneProfile, initialRemaining - 1, "Remaining account IDs should decrease");
    }

    function test_AccountId_MappingConsistency() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        UserProfileV1.UserProfile memory p = userProfile.getProfile(alice);
        uint256 accountId = p.accountId;
        
        // Check mapping consistency
        address mappedAddress = userProfile.accountIdToAddress(accountId);
        assertEq(mappedAddress, alice, "accountIdToAddress mapping should be consistent");
        
        // Verify reverse lookup works
        address retrievedByAccountId = userProfile.getAddressByAccountId(accountId);
        assertEq(retrievedByAccountId, alice, "Should retrieve same address");
    }

    // ============ Email Tests ============

    function test_DuplicateEmailRevert() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");

        vm.prank(bob);
        vm.expectRevert(UserProfileV1.EmailAlreadyTaken.selector);
        userProfile.createProfile("alice@example.com", "bob", "Bob Smith", "ipfs://p2");
    }

    function test_GetAddressByEmail_Success() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");

        address addr = userProfile.getAddressByEmail("alice@example.com");
        assertEq(addr, alice, "Should retrieve correct address by email");
    }

    function test_GetAddressByEmail_RevertProfileDoesNotExist() public {
        vm.expectRevert(UserProfileV1.ProfileDoesNotExist.selector);
        userProfile.getAddressByEmail("nonexistent@example.com");
    }

    function test_IsEmailAvailable_ReturnsFalse() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        bool available = userProfile.isEmailAvailable("alice@example.com");
        assertFalse(available, "Email should not be available after being used");
    }

    function test_IsEmailAvailable_ReturnsTrue() public view {
        bool available = userProfile.isEmailAvailable("unused@example.com");
        assertTrue(available, "Unused email should be available");
    }

    // ============ Profile Management Tests ============

    function test_HasUserProfile() public {
        assertFalse(userProfile.hasUserProfile(alice), "Should return false before profile creation");
        
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        assertTrue(userProfile.hasUserProfile(alice), "Should return true after profile creation");
        assertFalse(userProfile.hasUserProfile(bob), "Should still return false for bob");
    }

    function test_GetTotalProfiles() public {
        assertEq(userProfile.getTotalProfiles(), 0, "Should start with 0 profiles");
        
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        assertEq(userProfile.getTotalProfiles(), 1, "Should have 1 profile");
        
        vm.prank(bob);
        userProfile.createProfile("bob@example.com", "bob", "Bob Smith", "ipfs://p2");
        assertEq(userProfile.getTotalProfiles(), 2, "Should have 2 profiles");
        
        vm.prank(charlie);
        userProfile.createProfile("charlie@example.com", "charlie", "Charlie Brown", "ipfs://p3");
        assertEq(userProfile.getTotalProfiles(), 3, "Should have 3 profiles");
    }

    // ============ Event Tests ============

    function test_ProfileCreatedEvent() public {
        vm.prank(alice);
        
        // We can't predict the exact account ID due to obfuscation, so we don't check it
        vm.expectEmit(true, true, true, false);
        emit UserProfileV1.ProfileCreated(alice, "alice@example.com", "alice", "Alice Johnson", 0, "ipfs://p1", block.timestamp, true);
        
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
    }

    function test_PhotoUpdatedEvent() public {
        vm.prank(alice);
        userProfile.createProfile("alice@example.com", "alice", "Alice Johnson", "ipfs://p1");
        
        vm.warp(block.timestamp + 31 days);
        
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit UserProfileV1.PhotoUpdated(alice, "ipfs://newphoto");
        
        userProfile.updatePhoto("ipfs://newphoto");
    }

    // ============ Edge Case Tests ============
    function test_AccountId_ObfuscationPattern() public {
        // Create multiple profiles and verify they don't follow a simple sequential pattern
        address[] memory users = new address[](5);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = address(0x123456); 
        users[4] = address(0x789ABC);
        
        uint256[] memory accountIds = new uint256[](5);
        
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            userProfile.createProfile(
                string(abi.encodePacked("user", i, "@example.com")),
                string(abi.encodePacked("user", i)),
                string(abi.encodePacked("User ", i)),
                "ipfs://photo"
            );
            
            UserProfileV1.UserProfile memory p = userProfile.getProfile(users[i]);
            accountIds[i] = p.accountId;
        }
        
        // Verify account IDs are not sequential (difference shouldn't be 1)
        for (uint256 i = 1; i < accountIds.length; i++) {
            uint256 diff = accountIds[i] > accountIds[i-1] 
                ? accountIds[i] - accountIds[i-1] 
                : accountIds[i-1] - accountIds[i];
            assertTrue(diff != 1, "Account IDs should not be sequential");
        }
    }
}