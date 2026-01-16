// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Reputation} from "../Reputation.sol";

/**
 * @title ReputationProxy
 * @dev ERC1967 Proxy for Reputation (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (Reputation)
 */
contract ReputationProxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address _initialOwner
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                Reputation.initialize.selector,
                _initialOwner
            )
        )
    {}
}

/**
 * @dev Factory function to deploy Reputation with proxy
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to Reputation)
 */
function createReputation(address _initialOwner) returns (Reputation proxy) {
    // Deploy implementation
    Reputation implementation = new Reputation();

    // Deploy proxy pointing to the implementation
    ReputationProxy _proxy = new ReputationProxy(
        address(implementation),
        _initialOwner
    );

    // Return proxy as Reputation interface
    proxy = Reputation(address(_proxy));
    return proxy;
}
