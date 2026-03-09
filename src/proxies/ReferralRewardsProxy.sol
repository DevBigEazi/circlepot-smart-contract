// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ReferralRewards} from "../ReferralRewards.sol";

/**
 * @title ReferralRewardsProxy
 * @dev ERC1967 Proxy for ReferralRewards (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (ReferralRewards)
 */
contract ReferralRewardsProxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address _initialOwner
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                ReferralRewards.initialize.selector,
                _initialOwner
            )
        )
    {}
}

/**
 * @dev Factory function to deploy ReferralRewards with proxy
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to ReferralRewards)
 */
function createReferralRewards(
    address _initialOwner
) returns (ReferralRewards proxy) {
    // Deploy implementation
    ReferralRewards implementation = new ReferralRewards();

    // Deploy proxy pointing to the implementation
    ReferralRewardsProxy _proxy = new ReferralRewardsProxy(
        address(implementation),
        _initialOwner
    );

    // Return proxy as ReferralRewards interface
    proxy = ReferralRewards(address(_proxy));
    return proxy;
}
