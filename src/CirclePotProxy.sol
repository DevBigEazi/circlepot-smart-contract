// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CirclePotV1} from "./CirclePotV1.sol";

/**
 * @title CirclePotProxy
 * @dev ERC1967 Proxy for CirclePot (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (CirclePotV1)
 */
contract CirclePotProxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address _cUSDToken,
        address _treasury,
        address _initialOwner
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                CirclePotV1.initialize.selector,
                _cUSDToken,
                _treasury,
                _initialOwner
            )
        )
    {}
}

/**
 * @dev Factory function to deploy CirclePot with proxy
 * @param _cUSDToken Address of cUSD token on Celo L2
 * @param _treasury Address for platform fees
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to CirclePotV1)
 */
function createCirclePot(
    address _cUSDToken,
    address _treasury,
    address _initialOwner
) returns (CirclePotV1 proxy) {
    // Deploy implementation
    CirclePotV1 implementation = new CirclePotV1();

    // Deploy proxy pointing to the implementation
    CirclePotProxy _proxy = new CirclePotProxy(
        address(implementation),
        _cUSDToken,
        _treasury,
        _initialOwner
    );

    // Return proxy as CirclePotV1 interface
    proxy = CirclePotV1(address(_proxy));
    return proxy;
}