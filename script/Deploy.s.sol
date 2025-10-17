// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {CirclePotV1} from "../src/CirclePotV1.sol";
import {CirclePotProxy} from "../src/CirclePotProxy.sol";

/// @notice Deploys CirclePotV1 imple,entation and ERC1967 proxy pre-initialized via constructor
contract Deploy is Script {
    function run() external {
        // Read env vars
        address cUSDToken = vm.envAddress("CUSD_TEST_TOKEN");
        address treasury = vm.envAddress("TREASURY");
        address owner = vm.envAddress("OWNER");

        vm.startBroadcast();

        // Deploy Implementation
        CirclePotV1 implementation = new CirclePotV1();
        console2.log("CirclePotV1 implementat", address(implementation));

        // Deploy proxy which encodes initialize(cUSDToken, treasury, owner)
        CirclePotProxy proxy = new CirclePotProxy(
            address(implementation),
            cUSDToken,
            treasury,
            owner
        );
        console2.log("CirclePot proxy", address(proxy));

        // Log the variable by interacting with proxy via implementation ABI
        CirclePotV1 circle = CirclePotV1(address(proxy));
        console2.log("CirclePot (proxied) owner: ", circle.owner());
        console2.log("CirclePot (proxied) cUSDToken: ", circle.cUSDToken());
        console2.log("CirclePot (proxied) treasury: ", circle.treasury());

        vm.stopBroadcast();

    }
}
