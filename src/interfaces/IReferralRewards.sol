// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

/**
 * @title IReferralRewards
 * @dev Interface for ReferralRewards contract to trigger referral rewards
 */
interface IReferralRewards {
    function payReferralReward(address _referee, address _token) external;
}
