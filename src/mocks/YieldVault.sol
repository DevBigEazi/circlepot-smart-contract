// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title YieldVault
 * @dev A simple ERC-4626 vault that allows simulating yield by direct token transfers 
 * or using the simulateYield function.
 */
contract YieldVault is ERC4626, Ownable {
    constructor(
        address asset_, 
        string memory name_, 
        string memory symbol_
    ) 
        ERC4626(ERC20(asset_)) 
        ERC20(name_, symbol_) 
        Ownable(msg.sender)
    {}

    /**
     * @dev Simulation function: Transfer tokens to this contract to increase share price.
     * This mimics yield being "earned" by the underlying asset in a real DeFi protocol.
     */
    function simulateYield(uint256 amount) external onlyOwner {
        ERC20(asset()).transferFrom(msg.sender, address(this), amount);
    }

    // Allow the contract to receive ETH (some vaults might support this)
    receive() external payable {}
}
