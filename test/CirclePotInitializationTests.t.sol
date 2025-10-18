// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CirclePotV1Test} from "./CirclePotV1Tests.t.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title CirclePotInitializationTests
 * @notice Tests for contract initialization
 */
contract CirclePotInitializationTests is CirclePotV1Test {
    function test_Initialize() public view {
        assertEq(circlePot.cUSDToken(), address(cUSD));
        assertEq(circlePot.treasury(), testTreasury);
        assertEq(circlePot.owner(), testOwner);
        assertEq(circlePot.circleCounter(), 1);
        assertEq(circlePot.goalCounter(), 1);
    }

    function test_RevertInitializeWithZeroAddress() public {
        CirclePotV1 newImpl = new CirclePotV1();

        bytes memory initData = abi.encodeWithSelector(
            CirclePotV1.initialize.selector,
            address(0),
            testTreasury,
            testOwner
        );

        vm.expectRevert(CirclePotV1.InvalidTreasuryAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_ContractVersion() public view {
        string memory ver = circlePot.version();
        assertEq(ver, "1.0.0");
    }
}
