// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PersonalSavingsV1} from "../../src/PersonalSavingsV1.sol";
import {ReputationV1} from "../../src/ReputationV1.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract PersonalSavingsV1Setup is Test, TestHelpers {
    PersonalSavingsV1 public implementation;
    PersonalSavingsV1 public personalSavings;
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

        // Deploy personal savings
        implementation = new PersonalSavingsV1();

        bytes memory initData = abi.encodeWithSelector(
            PersonalSavingsV1.initialize.selector, address(cUSD), testTreasury, address(reputation), testOwner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        personalSavings = PersonalSavingsV1(address(proxy));

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
            cUSD.approve(address(personalSavings), type(uint256).max);
        }

        // Authorize PersonalSavings in reputation system
        vm.prank(testOwner);
        reputation.authorizeContract(address(personalSavings));
    }

    // Helper to create a default personal goal for a creator
    function _createDefaultGoal(address creator) internal returns (uint256) {
        vm.prank(creator);
        PersonalSavingsV1.CreateGoalParams memory params = PersonalSavingsV1.CreateGoalParams({
            name: "Default Goal",
            targetAmount: 500e18,
            contributionAmount: 100e18,
            frequency: PersonalSavingsV1.Frequency.WEEKLY,
            deadline: block.timestamp + 30 days
        });

        return personalSavings.createPersonalGoal(params);
    }
}
