// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

/**
 * @title IReputation
 * @dev Interface for the Reputation contract
 */
interface IReputation {
    /**
     * @dev Increase user's reputation
     * @param _user User address
     * @param _amount Amount to increase
     * @param _source Source description
     */
    function increaseReputation(
        address _user,
        uint256 _amount,
        string calldata _source
    ) external;

    /**
     * @dev Decrease user's reputation
     * @param _user User address
     * @param _amount Amount to decrease
     * @param _source Source description
     */
    function decreaseReputation(
        address _user,
        uint256 _amount,
        string calldata _source
    ) external;

    /**
     * @dev Record a completed circle for a user
     * @param _user User address
     */
    function recordCircleCompleted(address _user) external;

    /**
     * @dev Record a late payment for a user
     * @param _user User address
     */
    function recordLatePayment(address _user) external;

    /**
     * @dev Get user's reputation score
     * @param _user User address
     * @return Reputation score
     */
    function getReputation(address _user) external view returns (uint256);

    /**
     * @dev Get comprehensive reputation data for a user
     * @param _user User address
     * @return reputation Total reputation score
     * @return circlesCompleted Number of circles completed
     * @return latePaymentsCount Number of late payments
     * @return reputationScore Calculated weighted score
     */
    function getUserReputationData(
        address _user
    )
        external
        view
        returns (
            uint256 reputation,
            uint256 circlesCompleted,
            uint256 latePaymentsCount,
            uint256 reputationScore
        );

    /**
     * @dev Check if a contract is authorized
     * @param _contract Contract address
     * @return True if authorized
     */
    function isAuthorized(address _contract) external view returns (bool);
}
