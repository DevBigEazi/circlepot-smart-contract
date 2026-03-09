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
     * @param _points Amount to increase
     * @param _reason Source description
     */
    function increaseReputation(
        address _user,
        uint256 _points,
        string calldata _reason
    ) external;

    /**
     * @dev Decrease user's reputation
     * @param _user User address
     * @param _points Amount to decrease
     * @param _reason Source description
     */
    function decreaseReputation(
        address _user,
        uint256 _points,
        string calldata _reason
    ) external;

    /**
     * @dev Record a completed circle for a user
     * @param _user User address
     * @param _cid Circle ID
     */
    function recordCircleCompleted(address _user, uint256 _cid) external;

    /**
     * @dev Record a late payment for a user
     * @param _user User address
     * @param _cid Circle ID
     * @param _round Round number
     * @param _fee Fee amount
     */
    function recordLatePayment(
        address _user,
        uint256 _cid,
        uint256 _round,
        uint256 _fee
    ) external;

    /**
     * @dev Record a completed goal for a user
     * @param _user User address
     * @param _goalId Goal ID
     */
    function recordGoalCompleted(address _user, uint256 _goalId) external;

    /**
     * @dev Get user's reputation score
     * @param _user User address
     * @return Reputation score
     */
    function getReputation(address _user) external view returns (uint256);

    /**
     * @dev Get comprehensive reputation data for a user
     * @param _user User address
     * @return positiveActions Total positive actions
     * @return negativeActions Total negative actions
     * @return circlesCompleted Number of circles completed
     * @return score Calculated weighted score
     */
    function getUserReputationData(
        address _user
    )
        external
        view
        returns (
            uint256 positiveActions,
            uint256 negativeActions,
            uint256 circlesCompleted,
            uint256 score
        );

    /**
     * @dev Check if a contract is authorized
     * @param _contract Contract address
     * @return True if authorized
     */
    function isAuthorized(address _contract) external view returns (bool);
}
