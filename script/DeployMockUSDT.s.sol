// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/**
 * @title DeployMockUSDT
 * @notice One-time script to deploy a MockERC20 USDT token and mint 1,000,000 USDT
 *         to a specified test address.
 *
 * Usage (Fuji):
 *   forge script script/DeployMockUSDT.s.sol \
 *     --rpc-url fuji \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     -vvvv
 */
contract DeployMockUSDT is Script {
    // The test wallet that will receive 1,000,000 USDT
    address public constant RECIPIENT =
        0xED0fa5f6749b398DcD10A1E643cC0aBc3096bEa4;

    // 1,000,000 USDT — MockERC20 has 6 decimals, so 1e6 * 1e6 = 1e12
    uint256 public constant MINT_AMOUNT = 1_000_000 * 10 ** 6;

    function run() external {
        vm.startBroadcast();

        // Deploy the mock token
        MockERC20 usdt = new MockERC20();

        // Mint 1,000,000 USDT to the recipient
        usdt.mint(RECIPIENT, MINT_AMOUNT);

        vm.stopBroadcast();

        // Log results
        console2.log("========================================");
        console2.log("  Mock USDT deployed & funded");
        console2.log("========================================");
        console2.log("MockUSDT address : ", address(usdt));
        console2.log("Recipient        : ", RECIPIENT);
        console2.log("Balance (raw)    : ", usdt.balanceOf(RECIPIENT));
        console2.log("Balance (USDT)   : 1,000,000");
        console2.log("(Set USDT_ADDRESS=<address above> in your .env)");
    }
}
