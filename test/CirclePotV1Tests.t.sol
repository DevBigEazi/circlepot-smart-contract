// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {CirclePotTestHelpers} from "./helpers/CirclePotTestHelpers.sol";

contract CirclePotV1Test is Test, CirclePotTestHelpers {
    CirclePotV1 public implementation;

    address public testOwner = address(1);
    address public testTreasury = address(2);

    function setUp() public {
        // Initialize addresses from parent
        alice = address(3);
        bob = address(4);
        charlie = address(5);
        david = address(6);
        eve = address(7);
        frank = address(8);

        // Deploy mock cUSD token
        cUSD = new MockERC20();

        // Deploy implementation
        implementation = new CirclePotV1();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            CirclePotV1.initialize.selector,
            address(cUSD),
            testTreasury,
            testOwner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        circlePot = CirclePotV1(address(proxy));

        // Mint tokens to test users
        address[] memory users = new address[](6);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;
        users[4] = eve;
        users[5] = frank;

        for (uint i = 0; i < users.length; i++) {
            cUSD.mint(users[i], 100000e18);
            vm.prank(users[i]);
            cUSD.approve(address(circlePot), type(uint256).max);
        }
    }
}
