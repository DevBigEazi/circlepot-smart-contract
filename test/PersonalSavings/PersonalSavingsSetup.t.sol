// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PersonalSavings} from "../../src/PersonalSavings.sol";
import {Reputation} from "../../src/Reputation.sol";
import {UserProfile} from "../../src/UserProfile.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract PersonalSavingsSetup is Test, TestHelpers {
    PersonalSavings public implementation;
    PersonalSavings public personalSavings;
    Reputation public reputationImpl;
    Reputation public reputation;
    UserProfile public userProfileImpl;
    UserProfile public userProfile;

    address public testOwner = address(1);
    address public testTreasury = address(2);

    function setUp() public virtual {
        _setupMockTokenAndUsers();

        // Deploy reputation system first
        reputationImpl = new Reputation();
        bytes memory repInitData = abi.encodeWithSelector(
            Reputation.initialize.selector,
            testOwner
        );
        ERC1967Proxy repProxy = new ERC1967Proxy(
            address(reputationImpl),
            repInitData
        );
        reputation = Reputation(address(repProxy));

        // Deploy UserProfile
        userProfileImpl = new UserProfile();
        bytes memory userProfileInitData = abi.encodeWithSelector(
            UserProfile.initialize.selector,
            testOwner
        );
        ERC1967Proxy userProfileProxy = new ERC1967Proxy(
            address(userProfileImpl),
            userProfileInitData
        );
        userProfile = UserProfile(address(userProfileProxy));

        // Deploy PersonalSavings
        implementation = new PersonalSavings();

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(USDC);

        bytes memory initData = abi.encodeWithSelector(
            PersonalSavings.initialize.selector,
            supportedTokens,
            testTreasury,
            address(reputation),
            testOwner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        personalSavings = PersonalSavings(address(proxy));

        // Link UserProfile to PersonalSavings and USDC
        vm.startPrank(testOwner);
        userProfile.setPersonalSavingsContract(address(personalSavings));

        // Setup multi-token referral rewards in UserProfile
        userProfile.addSupportedToken(address(USDC));
        userProfile.setReferralBonusAmount(address(USDC), 5_000_000); // $5

        // Link PersonalSavings to UserProfile
        personalSavings.setUserProfileContract(address(userProfile));

        // Authorize PersonalSavings in reputation system
        reputation.authorizeContract(address(personalSavings));
        vm.stopPrank();

        // Approve contract to spend user's USDC
        address[] memory users = new address[](6);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;
        users[4] = eve;
        users[5] = frank;

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            USDC.approve(address(personalSavings), type(uint256).max);
        }
    }

    // Helper to create a default personal goal for a creator
    function _createDefaultGoal(address creator) internal returns (uint256) {
        vm.prank(creator);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Default Goal",
                targetAmount: 500e18,
                contributionAmount: 100e18,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDC),
                yieldAPY: 0
            });

        return personalSavings.createPersonalGoal(params);
    }
}
