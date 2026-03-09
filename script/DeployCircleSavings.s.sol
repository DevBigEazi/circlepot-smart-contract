// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {CircleSavings} from "../src/CircleSavings.sol";
import {CircleSavingsProxy} from "../src/proxies/CircleSavingsProxy.sol";
import {Reputation} from "../src/Reputation.sol";

contract DeployCircleSavings is Script {
    function run() external {
        address treasury = vm.envOr(
            "TREASURY_ADDRESS",
            address(0x4781070885eA1E2Ec9aE46201703172c576cDA1A)
        );
        address USDT = vm.envOr(
            "USDT_ADDRESS",
            address(0xe033DDef5ef67Cbc7CeC24fe5C58eC06E9BfFD67)
        );
        address reputationProxy = vm.envOr(
            "REPUTATION_PROXY",
            address(0x26a606222894d22CDEA34F2D0Ca705e082e86372)
        );

        vm.startBroadcast();

        // Deploy implementation
        CircleSavings implementation = new CircleSavings();
        console2.log(
            "CircleSavings Implementation deployed at:",
            address(implementation)
        );

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = USDT;

        // Deploy proxy
        CircleSavingsProxy proxy = new CircleSavingsProxy(
            address(implementation),
            supportedTokens,
            treasury,
            reputationProxy,
            msg.sender
        );
        console2.log("CircleSavings Proxy deployed at:", address(proxy));

        // Authorize the new proxy in the reputation contract
        // This requires the deployer to be the owner of the Reputation contract
        try Reputation(reputationProxy).authorizeContract(address(proxy)) {
            console2.log("Authorized new proxy in Reputation contract");
        } catch {
            console2.log(
                "Warning: Could not authorize proxy in Reputation. Deployer might not be the owner."
            );
        }
        vm.stopBroadcast();
    }
}
