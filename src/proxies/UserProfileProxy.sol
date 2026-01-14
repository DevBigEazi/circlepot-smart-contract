// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UserProfile} from "../UserProfile.sol";

/**
 * @title UserProfileProxy
 * @dev ERC1967 Proxy for UserProfile (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (UserProfile)
 */
contract UserProfileProxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address _initialOwner
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                UserProfile.initialize.selector,
                _initialOwner
            )
        )
    {}
}

/**
 * @dev Factory function to deploy UserProfile with proxy
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to UserProfile)
 */
function createUserProfile(address _initialOwner) returns (UserProfile proxy) {
    // Deploy implementation
    UserProfile implementation = new UserProfile();

    // Deploy proxy pointing to the implementation
    UserProfileProxy _proxy = new UserProfileProxy(
        address(implementation),
        _initialOwner
    );

    // Return proxy as UserProfile interface
    proxy = UserProfile(address(_proxy));
    return proxy;
}
