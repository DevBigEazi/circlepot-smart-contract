// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract TestHelpers is Test {
    MockERC20 internal USDm;

    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;
    address internal eve;
    address internal frank;

    function _setupMockTokenAndUsers() internal {
        alice = address(3);
        bob = address(4);
        charlie = address(5);
        david = address(6);
        eve = address(7);
        frank = address(8);

        USDm = new MockERC20();

        address[] memory users = new address[](6);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;
        users[4] = eve;
        users[5] = frank;

        for (uint256 i = 0; i < users.length; i++) {
            USDm.mint(users[i], 100000e18);
        }
    }
}
