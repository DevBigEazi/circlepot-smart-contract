// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

/**
 * @title IUserProfile
 * @dev Interface for UserProfile contract to trigger referral rewards
 */
interface IUserProfile {
    function payReferralReward(address _referee, address _token) external;
}
