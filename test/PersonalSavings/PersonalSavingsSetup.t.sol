// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PersonalSavings} from "../../src/PersonalSavings.sol";
import {Reputation} from "../../src/Reputation.sol";
import {ReferralRewards} from "../../src/ReferralRewards.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract PersonalSavingsSetup is Test, TestHelpers {
    PersonalSavings public implementation;
    PersonalSavings public personalSavings;
    Reputation public reputationImpl;
    Reputation public reputation;
    ReferralRewards public referralRewardsImpl;
    ReferralRewards public referralRewards;

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

        // Deploy ReferralRewards
        referralRewardsImpl = new ReferralRewards();
        bytes memory referralRewardsInitData = abi.encodeWithSelector(
            ReferralRewards.initialize.selector,
            testOwner
        );
        ERC1967Proxy referralRewardsProxy = new ERC1967Proxy(
            address(referralRewardsImpl),
            referralRewardsInitData
        );
        referralRewards = ReferralRewards(address(referralRewardsProxy));

        // Deploy PersonalSavings
        implementation = new PersonalSavings();

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(USDT);

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

        // Link ReferralRewards to PersonalSavings and USDT
        vm.startPrank(testOwner);
        referralRewards.setPersonalSavingsContract(address(personalSavings));

        // Setup multi-token referral rewards in ReferralRewards
        referralRewards.setTokenSupport(address(USDT), true);
        referralRewards.setBonusAmount(address(USDT), 5_000_000); // $5

        // Link PersonalSavings to ReferralRewards
        personalSavings.setReferralRewardsContract(address(referralRewards));

        // Authorize PersonalSavings in reputation system
        reputation.authorizeContract(address(personalSavings));
        vm.stopPrank();

        // Approve contract to spend user's USDT
        address[] memory users = new address[](6);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;
        users[4] = eve;
        users[5] = frank;

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            USDT.approve(address(personalSavings), type(uint256).max);
        }
    }

    // Helper to create a default personal goal for a creator
    function _createDefaultGoal(address creator) internal returns (uint256) {
        vm.prank(creator);
        PersonalSavings.CreateGoalParams memory params = PersonalSavings
            .CreateGoalParams({
                name: "Default Goal",
                targetAmount: 500e6,
                contributionAmount: 100e6,
                frequency: PersonalSavings.Frequency.WEEKLY,
                deadline: block.timestamp + 30 days,
                enableYield: false,
                token: address(USDT),
                yieldAPY: 0
            });

        return personalSavings.createPersonalGoal(params);
    }
}
