// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.27;

import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PersonalSavings} from "../PersonalSavings.sol";

/**
 * @title PersonalSavingsProxy
 * @dev ERC1967 Proxy for PersonalSavings (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (PersonalSavings)
 */
contract PersonalSavingsProxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address[] memory _supportedTokens,
        address _treasury,
        address _reputationContract,
        address _initialOwner
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                PersonalSavings.initialize.selector,
                _supportedTokens,
                _treasury,
                _reputationContract,
                _initialOwner
            )
        )
    {}
}

/**
 * @dev Factory function to deploy PersonalSavings with proxy
 * @param _supportedTokens Array of supported ERC20 token addresses
 * @param _treasury Address for platform fees
 * @param _reputationContract Address of the reputation contract
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to PersonalSavings)
 */
function createPersonalSavings(
    address[] memory _supportedTokens,
    address _treasury,
    address _reputationContract,
    address _initialOwner
) returns (PersonalSavings proxy) {
    // Deploy implementation
    PersonalSavings implementation = new PersonalSavings();

    // Deploy proxy pointing to the implementation
    PersonalSavingsProxy _proxy = new PersonalSavingsProxy(
        address(implementation),
        _supportedTokens,
        _treasury,
        _reputationContract,
        _initialOwner
    );

    // Return proxy as PersonalSavings interface
    proxy = PersonalSavings(address(_proxy));
    return proxy;
}
