// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ReputationV1} from "../ReputationV1.sol";

/**
 * @title ReputationProxy
 * @dev ERC1967 Proxy for Reputation (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (ReputationV1)
 */
contract ReputationProxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address _initialOwner
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                ReputationV1.initialize.selector,
                _initialOwner
            )
        )
    {}
}

/**
 * @dev Factory function to deploy Reputation with proxy
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to ReputationV1)
 */
function createReputation(address _initialOwner) returns (ReputationV1 proxy) {
    // Deploy implementation
    ReputationV1 implementation = new ReputationV1();

    // Deploy proxy pointing to the implementation
    ReputationProxy _proxy = new ReputationProxy(
        address(implementation),
        _initialOwner
    );

    // Return proxy as ReputationV1 interface
    proxy = ReputationV1(address(_proxy));
    return proxy;
}
