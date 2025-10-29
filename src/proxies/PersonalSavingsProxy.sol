// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PersonalSavingsV1} from "../PersonalSavingsV1.sol";

/**
 * @title PersonalSavingsProxy
 * @dev ERC1967 Proxy for PersonalSavings (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (PersonalSavingsV1)
 */
contract PersonalSavingsProxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address _cUSDToken,
        address _reputationContract,
        address _initialOwner
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                PersonalSavingsV1.initialize.selector,
                _cUSDToken,
                _reputationContract,
                _initialOwner
            )
        )
    {}
}

/**
 * @dev Factory function to deploy PersonalSavings with proxy
 * @param _cUSDToken Address of cUSD token on Celo L2
 * @param _reputationContract Address of the reputation contract
 * @param _initialOwner Address of contract owner
 * @return proxy Address of the deployed proxy (which delegates to PersonalSavingsV1)
 */
function createPersonalSavings(
    address _cUSDToken,
    address _reputationContract,
    address _initialOwner
) returns (PersonalSavingsV1 proxy) {
    // Deploy implementation
    PersonalSavingsV1 implementation = new PersonalSavingsV1();

    // Deploy proxy pointing to the implementation
    PersonalSavingsProxy _proxy = new PersonalSavingsProxy(
        address(implementation),
        _cUSDToken,
        _reputationContract,
        _initialOwner
    );

    // Return proxy as PersonalSavingsV1 interface
    proxy = PersonalSavingsV1(address(_proxy));
    return proxy;
}
