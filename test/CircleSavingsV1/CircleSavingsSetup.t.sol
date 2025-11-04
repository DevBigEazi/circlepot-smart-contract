// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CircleSavingsV1} from "../../src/CircleSavingsV1.sol";
import {ReputationV1} from "../../src/ReputationV1.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract CircleSavingsV1Setup is Test, TestHelpers {
    CircleSavingsV1 public implementation;
    CircleSavingsV1 public circleSavings;
    ReputationV1 public reputationImpl;
    ReputationV1 public reputation;

    address public testOwner = address(1);
    address public testTreasury = address(2);

    function setUp() public virtual {
        _setupMockTokenAndUsers();

        // Deploy reputation system first
        reputationImpl = new ReputationV1();
        bytes memory repInitData = abi.encodeWithSelector(ReputationV1.initialize.selector, testOwner);
        ERC1967Proxy repProxy = new ERC1967Proxy(address(reputationImpl), repInitData);
        reputation = ReputationV1(address(repProxy));

        // Deploy implementation and proxy
        implementation = new CircleSavingsV1();

        bytes memory initData = abi.encodeWithSelector(
            CircleSavingsV1.initialize.selector, address(cUSD), testTreasury, address(reputation), testOwner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        circleSavings = CircleSavingsV1(address(proxy));

        // Approve contract to spend user's cUSD
        address[] memory users = new address[](6);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;
        users[4] = eve;
        users[5] = frank;

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            cUSD.approve(address(circleSavings), type(uint256).max);
        }

        // Authorize CircleSavings in reputation system
        vm.prank(testOwner);
        reputation.authorizeContract(address(circleSavings));
    }

    // Helper to create a default circle and have enough members join so it becomes active
    function _createAndStartCircle() internal returns (uint256) {
        // Create circle
        vm.prank(alice);
        CircleSavingsV1.CreateCircleParams memory params = CircleSavingsV1.CreateCircleParams({
            title: "Test Circle",
            description: "Test Description",
            contributionAmount: 100e18,
            frequency: CircleSavingsV1.Frequency.WEEKLY,
            maxMembers: 5,
            visibility: CircleSavingsV1.Visibility.PRIVATE
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
        deal(address(cUSD), bob, collateral);
        deal(address(cUSD), charlie, collateral);
        deal(address(cUSD), david, collateral);
        deal(address(cUSD), eve, collateral);

        // Provide additional funds for contributions across rounds
        cUSD.mint(bob, 1000e18);
        cUSD.mint(charlie, 1000e18);
        cUSD.mint(david, 1000e18);
        cUSD.mint(eve, 1000e18);

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
        CircleSavingsV1.CreateCircleParams memory params = CircleSavingsV1.CreateCircleParams({
            title: "Test Circle",
            description: "Test Description",
            contributionAmount: 100e18,
            frequency: CircleSavingsV1.Frequency.WEEKLY,
            maxMembers: 5,
            visibility: CircleSavingsV1.Visibility.PUBLIC
        });

        return circleSavings.createCircle(params);
    }
}
