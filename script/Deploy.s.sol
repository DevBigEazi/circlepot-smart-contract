// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UserProfileV1} from "../src/UserProfileV1.sol";
import {PersonalSavingsV1} from "../src/PersonalSavingsV1.sol";
import {CircleSavingsV1} from "../src/CircleSavingsV1.sol";
import {ReputationV1} from "../src/ReputationV1.sol";
import {CircleSavingsProxy} from "../src/proxies/CircleSavingsProxy.sol";
import {PersonalSavingsProxy} from "../src/proxies/PersonalSavingsProxy.sol";
import {UserProfileProxy} from "../src/proxies/UserProfileProxy.sol";
import {ReputationProxy} from "../src/proxies/ReputationProxy.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address cUSD = vm.envAddress("CUSD_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation contracts
        UserProfileV1 userProfileImpl = new UserProfileV1();
        PersonalSavingsV1 personalSavingsImpl = new PersonalSavingsV1();
        CircleSavingsV1 circleSavingsImpl = new CircleSavingsV1();
        ReputationV1 reputationImpl = new ReputationV1();

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

        PersonalSavingsProxy personalSavingsProxy = new PersonalSavingsProxy(
            address(personalSavingsImpl),
            cUSD, // cUSD token address
            treasury, // treasury address
            address(reputationProxy), // reputation contract address
            msg.sender // initialOwner
        );

        CircleSavingsProxy circleSavingsProxy = new CircleSavingsProxy(
            address(circleSavingsImpl),
            cUSD, // cUSD token address
            treasury, // treasury address
            address(reputationProxy), // reputation contract address
            msg.sender // initialOwner
        );

        // Authorize contracts in the reputation system
        ReputationV1(address(reputationProxy)).authorizeContract(address(personalSavingsProxy));
        ReputationV1(address(reputationProxy)).authorizeContract(address(circleSavingsProxy));

        // Log deployed addresses
        console2.log("Deployment Complete");
        console2.log("==================");
        console2.log("UserProfile Implementation:", address(userProfileImpl));
        console2.log("UserProfile Proxy:", address(userProfileProxy));
        console2.log("PersonalSavings Implementation:", address(personalSavingsImpl));
        console2.log("PersonalSavings Proxy:", address(personalSavingsProxy));
        console2.log("CircleSavings Implementation:", address(circleSavingsImpl));
        console2.log("CircleSavings Proxy:", address(circleSavingsProxy));
        console2.log("Reputation Implementation:", address(reputationImpl));
        console2.log("Reputation Proxy:", address(reputationProxy));

        vm.stopBroadcast();
    }

    function deployTestnet() external {
        // Use a different private key for testnet
        uint256 deployerPrivateKey = vm.envUint("TESTNET_PRIVATE_KEY");
        address treasury = vm.envAddress("TESTNET_TREASURY_ADDRESS");
        address cUSD = vm.envAddress("TESTNET_CUSD_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation contracts
        UserProfileV1 userProfileImpl = new UserProfileV1();
        PersonalSavingsV1 personalSavingsImpl = new PersonalSavingsV1();
        CircleSavingsV1 circleSavingsImpl = new CircleSavingsV1();
        ReputationV1 reputationImpl = new ReputationV1();

        // Deploy reputation proxy first as it's needed by other contracts
        ReputationProxy reputationProxy = new ReputationProxy(
            address(reputationImpl),
            msg.sender // initialOwner
        );

        // Deploy proxies with testnet configuration — pass explicit constructor args
        UserProfileProxy userProfileProxy = new UserProfileProxy(
            address(userProfileImpl),
            msg.sender // initialOwner
        );

        PersonalSavingsProxy personalSavingsProxy = new PersonalSavingsProxy(
            address(personalSavingsImpl),
            cUSD, // cUSD token address
            treasury, // treasury address
            address(reputationProxy), // reputation contract address
            msg.sender // initialOwner
        );

        CircleSavingsProxy circleSavingsProxy = new CircleSavingsProxy(
            address(circleSavingsImpl),
            cUSD, // cUSD token address
            treasury, // treasury address
            address(reputationProxy), // reputation contract address
            msg.sender // initialOwner
        );

        // Authorize contracts in the reputation system
        ReputationV1(address(reputationProxy)).authorizeContract(address(personalSavingsProxy));
        ReputationV1(address(reputationProxy)).authorizeContract(address(circleSavingsProxy));

        // Log deployed addresses
        console2.log("Testnet Deployment Complete");
        console2.log("=========================");
        console2.log("UserProfile Implementation:", address(userProfileImpl));
        console2.log("UserProfile Proxy:", address(userProfileProxy));
        console2.log("PersonalSavings Implementation:", address(personalSavingsImpl));
        console2.log("PersonalSavings Proxy:", address(personalSavingsProxy));
        console2.log("CircleSavings Implementation:", address(circleSavingsImpl));
        console2.log("CircleSavings Proxy:", address(circleSavingsProxy));
        console2.log("Reputation Implementation:", address(reputationImpl));
        console2.log("Reputation Proxy:", address(reputationProxy));

        vm.stopBroadcast();
    }
}
