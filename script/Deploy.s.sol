// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UserProfile} from "../src/UserProfile.sol";
import {PersonalSavings} from "../src/PersonalSavings.sol";
import {CircleSavings} from "../src/CircleSavings.sol";
import {Reputation} from "../src/Reputation.sol";
import {CircleSavingsProxy} from "../src/proxies/CircleSavingsProxy.sol";
import {PersonalSavingsProxy} from "../src/proxies/PersonalSavingsProxy.sol";
import {UserProfileProxy} from "../src/proxies/UserProfileProxy.sol";
import {ReputationProxy} from "../src/proxies/ReputationProxy.sol";
import {YieldVault} from "../src/mocks/YieldVault.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() external {
        address treasury = vm.envOr("TREASURY_ADDRESS", msg.sender);
        // Base Sepolia USDC address
        address USDC = vm.envOr(
            "USDC_ADDRESS",
            address(0x036CbD53842c5426634e7929541eC2318f3dCF7e)
        );

        vm.startBroadcast();

        // Deploy implementation contracts
        UserProfile userProfileImpl = new UserProfile();
        PersonalSavings personalSavingsImpl = new PersonalSavings();
        CircleSavings circleSavingsImpl = new CircleSavings();
        Reputation reputationImpl = new Reputation();

        // Deploy yield vault
        YieldVault yieldVault = new YieldVault(
            USDC,
            "Yield Bearing USDC",
            "yUSDC"
        );

        // Deploy reputation proxy first as it's needed by other contracts
        ReputationProxy reputationProxy = new ReputationProxy(
            address(reputationImpl),
            msg.sender // initialOwner
        );

        // Deploy proxies — use constructors defined in proxy contracts
        UserProfileProxy userProfileProxy = new UserProfileProxy(
            address(userProfileImpl),
            msg.sender // initialOwner
        );

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = USDC;

        PersonalSavingsProxy personalSavingsProxy = new PersonalSavingsProxy(
            address(personalSavingsImpl),
            supportedTokens, // Supported tokens array
            treasury, // treasury address
            address(reputationProxy), // reputation contract address
            msg.sender // initialOwner
        );

        // Set vault for USDC token
        PersonalSavings(address(personalSavingsProxy)).setTokenVault(
            USDC,
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

        // Set vault for USDC token
        CircleSavings(address(circleSavingsProxy)).setTokenVault(
            USDC,
            address(yieldVault),
            "moola-market"
        );

        // Authorize contracts in the reputation system
        Reputation(address(reputationProxy)).authorizeContract(
            address(personalSavingsProxy)
        );
        Reputation(address(reputationProxy)).authorizeContract(
            address(0xceB735CF16d8Cc2F388F78f1139360A0A4594102)
        );

        // Link UserProfile to PersonalSavings and setup initial reward token
        UserProfile userProfile = UserProfile(address(userProfileProxy));
        userProfile.setPersonalSavingsContract(address(personalSavingsProxy));
        userProfile.addSupportedToken(USDC);
        userProfile.setReferralBonusAmount(USDC, 1_000_000_000_000_000_00); // $0.1 bonus 18 decimal
        userProfile.setReferralRewardsEnabled(true);

        // Link PersonalSavings to UserProfile
        PersonalSavings(address(personalSavingsProxy)).setUserProfileContract(
            address(userProfileProxy)
        );

        // Log deployed addresses
        console2.log("Deployment Complete");
        console2.log("==================");
        console2.log("UserProfile Implementation:", address(userProfileImpl));
        console2.log("UserProfile Proxy:", address(userProfileProxy));
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
