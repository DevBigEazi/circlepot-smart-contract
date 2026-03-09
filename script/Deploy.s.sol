// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ReferralRewards} from "../src/ReferralRewards.sol";
import {PersonalSavings} from "../src/PersonalSavings.sol";
import {CircleSavings} from "../src/CircleSavings.sol";
import {Reputation} from "../src/Reputation.sol";
import {CircleSavingsProxy} from "../src/proxies/CircleSavingsProxy.sol";
import {PersonalSavingsProxy} from "../src/proxies/PersonalSavingsProxy.sol";
import {ReferralRewardsProxy} from "../src/proxies/ReferralRewardsProxy.sol";
import {ReputationProxy} from "../src/proxies/ReputationProxy.sol";
import {YieldVault} from "../src/mocks/YieldVault.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() external {
        address treasury = vm.envOr("TREASURY_ADDRESS", msg.sender);
        // Avalanche USDT address (testnet or mainnet)
        address USDT = vm.envOr(
            "USDT_ADDRESS",
            address(0xe033DDef5ef67Cbc7CeC24fe5C58eC06E9BfFD67) // Fuji USDT
        );

        vm.startBroadcast();

        // Deploy implementation contracts
        ReferralRewards referralRewardsImpl = new ReferralRewards();
        PersonalSavings personalSavingsImpl = new PersonalSavings();
        CircleSavings circleSavingsImpl = new CircleSavings();
        Reputation reputationImpl = new Reputation();

        // Deploy yield vault (testnet only)
        YieldVault yieldVault = new YieldVault(
            USDT,
            "Yield Bearing USDT",
            "yUSDT"
        );

        // Deploy reputation proxy first as it's needed by other contracts
        ReputationProxy reputationProxy = new ReputationProxy(
            address(reputationImpl),
            msg.sender // initialOwner
        );

        // Deploy ReferralRewards proxy
        ReferralRewardsProxy referralRewardsProxy = new ReferralRewardsProxy(
            address(referralRewardsImpl),
            msg.sender // initialOwner
        );

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = USDT;

        PersonalSavingsProxy personalSavingsProxy = new PersonalSavingsProxy(
            address(personalSavingsImpl),
            supportedTokens, // Supported tokens array
            treasury, // treasury address
            address(reputationProxy), // reputation contract address
            msg.sender // initialOwner
        );

        // Set vault for USDT token
        PersonalSavings(address(personalSavingsProxy)).setTokenVault(
            USDT,
            address(yieldVault),
            "moola-market"
        );

        CircleSavingsProxy circleSavingsProxy = new CircleSavingsProxy(
            address(circleSavingsImpl),
            supportedTokens, // Supported tokens array
            treasury, // treasury address
            address(reputationProxy), // reputation contract address
            msg.sender // initialOwner
        );

        // Authorize contracts in the reputation system
        Reputation(address(reputationProxy)).authorizeContract(
            address(personalSavingsProxy)
        );
        Reputation(address(reputationProxy)).authorizeContract(
            address(circleSavingsProxy)
        );

        // Link ReferralRewards to PersonalSavings and setup initial reward token
        ReferralRewards referralRewards = ReferralRewards(
            address(referralRewardsProxy)
        );
        referralRewards.setPersonalSavingsContract(
            address(personalSavingsProxy)
        );
        referralRewards.setTokenSupport(USDT, true);
        referralRewards.setBonusAmount(USDT, 100_000); // $0.1 bonus (6 decimals)
        referralRewards.setRelayerStatus(msg.sender, true); // Admin as first relayer

        // Link PersonalSavings to ReferralRewards
        PersonalSavings(address(personalSavingsProxy))
            .setReferralRewardsContract(address(referralRewardsProxy));

        // Log deployed addresses
        console2.log("Deployment Complete");
        console2.log("==================");
        console2.log(
            "ReferralRewards Implementation:",
            address(referralRewardsImpl)
        );
        console2.log("ReferralRewards Proxy:", address(referralRewardsProxy));
        console2.log(
            "PersonalSavings Implementation:",
            address(personalSavingsImpl)
        );
        console2.log("PersonalSavings Proxy:", address(personalSavingsProxy));
        console2.log(
            "CircleSavings Implementation:",
            address(circleSavingsImpl)
        );
        console2.log("CircleSavings Proxy:", address(circleSavingsProxy));
        console2.log("YieldVault:", address(yieldVault));
        console2.log("Reputation Implementation:", address(reputationImpl));
        console2.log("Reputation Proxy:", address(reputationProxy));

        vm.stopBroadcast();
    }
}
