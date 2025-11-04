// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UserProfileV1} from "../UserProfileV1.sol";

/**
 * @title UserProfileProxy
 * @dev ERC1967 Proxy for UserProfile (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (UserProfileV1)
 */
contract UserProfileProxy is ERC1967Proxy {
    constructor(address _implementation, address _initialOwner)
        ERC1967Proxy(_implementation, abi.encodeWithSelector(UserProfileV1.initialize.selector, _initialOwner))
    {}
}

/**
 * @dev Factory function to deploy UserProfile with proxy
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to UserProfileV1)
 */
function createUserProfile(address _initialOwner) returns (UserProfileV1 proxy) {
    // Deploy implementation
    UserProfileV1 implementation = new UserProfileV1();

    // Deploy proxy pointing to the implementation
    UserProfileProxy _proxy = new UserProfileProxy(address(implementation), _initialOwner);

    // Return proxy as UserProfileV1 interface
    proxy = UserProfileV1(address(_proxy));
    return proxy;
}
