// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UserProfile} from "../../src/UserProfile.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract UserProfileSetup is Test, TestHelpers {
    UserProfile public implementation;
    UserProfile public userProfile;

    address public testOwner = address(1);
    address public testPersonalSavings = address(2); // Mock PersonalSavings address

    function setUp() public virtual {
        _setupMockTokenAndUsers();

        implementation = new UserProfile();

        // Initialize with only owner
        bytes memory initData = abi.encodeWithSelector(
            UserProfile.initialize.selector,
            testOwner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        userProfile = UserProfile(address(proxy));

        // Use setters for other configurations
        vm.startPrank(testOwner);
        userProfile.setPersonalSavingsContract(testPersonalSavings);

        // Setup multi-token referral rewards
        userProfile.addSupportedToken(address(USDm));
        userProfile.setReferralBonusAmount(address(USDm), 5_000_000); // $5
        vm.stopPrank();
    }
}
