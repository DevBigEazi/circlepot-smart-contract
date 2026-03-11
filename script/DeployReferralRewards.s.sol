// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {ReferralRewards} from "../src/ReferralRewards.sol";
import {ReferralRewardsProxy} from "../src/proxies/ReferralRewardsProxy.sol";
import {PersonalSavings} from "../src/PersonalSavings.sol";

contract DeployReferralRewards is Script {
    function run() external {
        address USDT = vm.envOr(
            "USDT_ADDRESS",
            address(0xe033DDef5ef67Cbc7CeC24fe5C58eC06E9BfFD67)
        );
        address personalSavingsProxy = vm.envOr(
            "PERSONAL_SAVINGS_PROXY",
            address(0x123bFf8D754b29772E1EfAD5B075F55600577DcD)
        );
        address admin = 0x92d3CD8bBe0d05Bbd86DE7F3A4aD9Dd1f0032767;

        vm.startBroadcast();

        // 1. Deploy Implementation
        ReferralRewards implementation = new ReferralRewards();
        console2.log(
            "ReferralRewards Implementation deployed at:",
            address(implementation)
        );

        // 2. Deploy Proxy
        // Explicitly set the owner to the expected deployer address
        address owner = 0x4781070885eA1E2Ec9aE46201703172c576cDA1A;
        ReferralRewardsProxy proxy = new ReferralRewardsProxy(
            address(implementation),
            owner
        );
        console2.log("ReferralRewards Proxy deployed at:", address(proxy));

        // 3. Initial Configuration
        ReferralRewards referralRewards = ReferralRewards(address(proxy));

        // Link to PersonalSavings
        referralRewards.setPersonalSavingsContract(personalSavingsProxy);

        // Setup USDT Support
        referralRewards.setTokenSupport(USDT, true);
        referralRewards.setBonusAmount(USDT, 100_000); // $0.1 bonus (6 decimals)

        // Authorize Admin as Relayer
        referralRewards.setRelayerStatus(admin, true);

        // Link PersonalSavings back to ReferralRewards (optional if already linked)
        try
            PersonalSavings(personalSavingsProxy).setReferralRewardsContract(
                address(proxy)
            )
        {
            console2.log("Updated ReferralRewards context in PersonalSavings");
        } catch {
            console2.log(
                "Warning: Could not update PersonalSavings. Ensure deployer has permissions."
            );
        }
        vm.stopBroadcast();
    }
}
