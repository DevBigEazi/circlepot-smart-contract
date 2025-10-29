// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UserProfileV1} from "../../src/UserProfileV1.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract UserProfileV1Setup is Test, TestHelpers {
    UserProfileV1 public implementation;
    UserProfileV1 public userProfile;

    address public testOwner = address(1);

    function setUp() public virtual {
        _setupMockTokenAndUsers();

        implementation = new UserProfileV1();

        bytes memory initData = abi.encodeWithSelector(
            UserProfileV1.initialize.selector,
            testOwner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        userProfile = UserProfileV1(address(proxy));
    }
}
