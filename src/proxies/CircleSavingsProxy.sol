// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CircleSavingsV1} from "../CircleSavingsV1.sol";

/**
 * @title CircleSavingsProxy
 * @dev ERC1967 Proxy for CircleSavings (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (CircleSavingsV1)
 */
contract CircleSavingsProxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address _cUSDToken,
        address _treasury,
        address _reputationContract,
        address _initialOwner
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                CircleSavingsV1.initialize.selector,
                _cUSDToken,
                _treasury,
                _reputationContract,
                _initialOwner
            )
        )
    {}
}

/**
 * @dev Factory function to deploy CircleSavings with proxy
 * @param _cUSDToken Address of cUSD token on Celo L2
 * @param _treasury Address for platform fees
 * @param _reputationContract Address of the reputation contract
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to CircleSavingsV1)
 */
function createCircleSavings(
    address _cUSDToken,
    address _treasury,
    address _reputationContract,
    address _initialOwner
) returns (CircleSavingsV1 proxy) {
    // Deploy implementation
    CircleSavingsV1 implementation = new CircleSavingsV1();

    // Deploy proxy pointing to the implementation
    CircleSavingsProxy _proxy = new CircleSavingsProxy(
        address(implementation),
        _cUSDToken,
        _treasury,
        _reputationContract,
        _initialOwner
    );

    // Return proxy as CircleSavingsV1 interface
    proxy = CircleSavingsV1(address(_proxy));
    return proxy;
}
