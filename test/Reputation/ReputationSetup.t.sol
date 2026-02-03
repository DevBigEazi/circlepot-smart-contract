// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Reputation} from "../../src/Reputation.sol";
import {ReputationProxy} from "../../src/proxies/ReputationProxy.sol";
import {PersonalSavingsProxy} from "../../src/proxies/PersonalSavingsProxy.sol";
import {CircleSavingsProxy} from "../../src/proxies/CircleSavingsProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/**
 * @title ReputationSetup
 * @dev Base contract for Reputation tests with common setup
 */
contract ReputationSetup is Test {
    // Contracts
    Reputation public reputationImpl;
    ReputationProxy public reputationProxy;
    Reputation public reputation;

    // Accounts
    address public owner;
    address public treasury;
    address public user1;
    address public user2;
    address public user3;

    // Mock contracts
    MockERC20 public USDCToken;

    function setUp() public virtual {
        // Setup accounts
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.startPrank(owner);

        // Deploy mock USDC token
        USDCToken = new MockERC20();

        // Deploy reputation implementation and proxy
        reputationImpl = new Reputation();
        reputationProxy = new ReputationProxy(address(reputationImpl), owner);
        reputation = Reputation(address(reputationProxy));

        vm.stopPrank();
    }

    /**
     * @dev Helper function to authorize a contract (made virtual for overriding)
     * Note: This is virtual so child test contracts can override if needed
     */
    function _authorizeContract(address _contract) internal virtual {
        vm.prank(owner);
        reputation.authorizeContract(_contract);
    }
}
