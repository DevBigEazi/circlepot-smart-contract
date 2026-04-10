// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FamCircle} from "../FamCircle.sol";

/**
 * @title FamCircleProxy
 * @dev ERC1967 Proxy for FamCircle (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation
 */
contract FamCircleProxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address _treasury,
        address _reputationContract,
        address _initialOwner,
        address[] memory _supportedTokens
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                FamCircle.initialize.selector,
                _treasury,
                _reputationContract,
                _initialOwner,
                _supportedTokens
            )
        )
    {}
}

/**
 * @dev Factory function to deploy FamCircle with proxy
 * @param _treasury Address for platform fees
 * @param _reputationContract Address of the reputation contract
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to FamCircle)
 */
function createFamCircle(
    address _treasury,
    address _reputationContract,
    address _initialOwner,
    address[] memory _supportedTokens
) returns (FamCircle proxy) {
    // Deploy implementation
    FamCircle implementation = new FamCircle();

    // Deploy proxy pointing to the implementation
    FamCircleProxy _proxy = new FamCircleProxy(
        address(implementation),
        _treasury,
        _reputationContract,
        _initialOwner,
        _supportedTokens
    );

    // Return proxy as FamCircle interface
    proxy = FamCircle(address(_proxy));
    return proxy;
}
