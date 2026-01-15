// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CircleSavings} from "../../src/CircleSavings.sol";
import {Reputation} from "../../src/Reputation.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

import {YieldVault} from "../../src/mocks/YieldVault.sol";

contract CircleSavingsSetup is Test, TestHelpers {
    CircleSavings public implementation;
    CircleSavings public circleSavings;
    Reputation public reputationImpl;
    Reputation public reputation;
    YieldVault public yieldVault;

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

        // Deploy implementation and proxy
        implementation = new CircleSavings();

        // Deploy yield vault
        yieldVault = new YieldVault(
            address(USDm),
            "Yield Bearing USDm",
            "yUSDm"
        );

        // Prepare supported tokens array
        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(USDm);

        bytes memory initData = abi.encodeWithSelector(
            CircleSavings.initialize.selector,
            supportedTokens,
            testTreasury,
            address(reputation),
            testOwner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        circleSavings = CircleSavings(address(proxy));

        // Set vault for USDm token
        vm.prank(testOwner);
        circleSavings.setTokenVault(
            address(USDm),
            address(yieldVault),
            "Mock Yield Vault"
        );

        // Approve contract to spend user's USDm
        address[] memory users = new address[](6);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;
        users[4] = eve;
        users[5] = frank;

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            USDm.approve(address(circleSavings), type(uint256).max);
        }

        // Authorize CircleSavings in reputation system
        vm.prank(testOwner);
        reputation.authorizeContract(address(circleSavings));
    }

    // Helper to create a default circle and have enough members join so it becomes active
    function _createAndStartCircle() internal returns (uint256) {
        // Create circle
        vm.prank(alice);
        CircleSavings.CreateCircleParams memory params = CircleSavings
            .CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e18,
                frequency: CircleSavings.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavings.Visibility.PRIVATE,
                enableYield: true,
                token: address(USDm),
                yieldAPY: 0
            });

        uint256 cid = circleSavings.createCircle(params);

        // Create array of addresses to invite
        address[] memory invitees = new address[](4);
        invitees[0] = bob;
        invitees[1] = charlie;
        invitees[2] = david;
        invitees[3] = eve;

        // Invite members
        vm.prank(alice);
        circleSavings.inviteMembers(cid, invitees);

        // Fund accounts for joining
        uint256 collateral = 100e18 * 5 + ((100e18 * 5 * 100) / 10000); // contributionAmount * maxMembers + 1% buffer
        deal(address(USDm), bob, collateral);
        deal(address(USDm), charlie, collateral);
        deal(address(USDm), david, collateral);
        deal(address(USDm), eve, collateral);

        // Provide additional funds for contributions across rounds
        USDm.mint(bob, 1000e18);
        USDm.mint(charlie, 1000e18);
        USDm.mint(david, 1000e18);
        USDm.mint(eve, 1000e18);

        // Have members join
        vm.prank(bob);
        circleSavings.joinCircle(cid);
        vm.prank(charlie);
        circleSavings.joinCircle(cid);
        vm.prank(david);
        circleSavings.joinCircle(cid);
        vm.prank(eve);
        circleSavings.joinCircle(cid);

        return cid;
    }

    // Helper to create a default circle without adding other members
    function _createDefaultCircle(address creator) internal returns (uint256) {
        vm.prank(creator);
        CircleSavings.CreateCircleParams memory params = CircleSavings
            .CreateCircleParams({
                title: "Test Circle",
                description: "Test Description",
                contributionAmount: 100e18,
                frequency: CircleSavings.Frequency.WEEKLY,
                maxMembers: 5,
                visibility: CircleSavings.Visibility.PUBLIC,
                enableYield: true,
                token: address(USDm),
                yieldAPY: 0
            });

        return circleSavings.createCircle(params);
    }
}
