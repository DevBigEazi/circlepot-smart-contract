// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title ReputationV1
 * @dev Credit score-style reputation system (300-850 range)
 * @notice Compatible with PersonalSavingsV1 and CircleSavingsV1 contracts
 * @notice Mimics FICO/VantageScore models with savings-specific features
 */
contract ReputationV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // ============ Constants ============
    uint256 public constant VERSION = 1;

    // Standard credit score range (like FICO/VantageScore)
    uint256 public constant MIN_SCORE = 300;
    uint256 public constant MAX_SCORE = 850;
    uint256 public constant DEFAULT_SCORE = 300; // Starting score for new users

    // Score Categories (FICO-style)
    uint256 public constant POOR_THRESHOLD = 579; // 300-579: Poor
    uint256 public constant FAIR_THRESHOLD = 669; // 580-669: Fair
    uint256 public constant GOOD_THRESHOLD = 739; // 670-739: Good
    uint256 public constant VERY_GOOD_THRESHOLD = 799; // 740-799: Very Good
    // 800-850: Exceptional

    // Score requirements for features
    uint256 public constant MIN_SCORE_LARGE_GOAL = 600; // Fair category
    uint256 public constant MIN_SCORE_CIRCLE_CREATE = 580; // Fair category
    uint256 public constant MIN_SCORE_PREMIUM = 740; // Very Good category

    // ============ Enums ============
    enum ScoreCategory {
        POOR, // 300-579
        FAIR, // 580-669
        GOOD, // 670-739
        VERY_GOOD, // 740-799
        EXCEPTIONAL // 800-850

    }

    // ============ Structs ============
    struct UserReputation {
        uint256 score;
        uint256 totalPositiveActions;
        uint256 totalNegativeActions;
        uint256 consecutiveOnTimePayments;
        uint256 circlesCompleted;
        uint256 goalsCompleted;
        uint256 latePayments;
        uint256 lastUpdated;
        bool isInitialized;
    }

    struct ReputationHistory {
        uint256 timestamp;
        int256 scoreChange;
        string reason;
        uint256 newScore;
    }

    // ============ Storage ============
    mapping(address => UserReputation) public userReputations;
    mapping(address => ReputationHistory[]) public reputationHistory;
    mapping(address => bool) public authorizedContracts;

    // ============ Events ============
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event ReputationIncreased(address indexed user, uint256 points, string reason, uint256 newScore);
    event ReputationDecreased(address indexed user, uint256 points, string reason, uint256 newScore);
    event ContractAuthorized(address indexed contractAddress);
    event ContractRevoked(address indexed contractAddress);
    event ScoreCategoryChanged(address indexed user, ScoreCategory oldCategory, ScoreCategory newCategory);
    event CircleCompleted(address indexed user, uint256 indexed cid, uint256 totalCompleted);
    event LatePaymentRecorded(address indexed user, uint256 indexed cid, uint256 indexed round, uint256 fee, uint256 totalLatePayments);
    event GoalCompleted(address indexed user, uint256 indexed goalId, uint256 totalCompleted);
    // ============ Errors ============
    error UnauthorizedContract();
    error InvalidScoreChange();
    error ScoreOutOfBounds();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the reputation contract
     * @param initialOwner Address of the initial owner
     */
    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);

        // transfer ownership if a different initialOwner was provided
        if (initialOwner != address(0) && initialOwner != owner()) {
            _transferOwnership(initialOwner);
        }
    }

    /**
     * @dev Authorizes upgrade to new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        emit ContractUpgraded(newImplementation, VERSION);
    }

    // ============ Modifiers ============
    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender]) revert UnauthorizedContract();
        _;
    }

    // ============ Core Functions ============

    /**
     * @dev Initialize a new user's reputation score
     */
    function _initializeUser(address _user) private {
        if (!userReputations[_user].isInitialized) {
            userReputations[_user] = UserReputation({
                score: DEFAULT_SCORE,
                totalPositiveActions: 0,
                totalNegativeActions: 0,
                consecutiveOnTimePayments: 0,
                circlesCompleted: 0,
                goalsCompleted: 0,
                latePayments: 0,
                lastUpdated: block.timestamp,
                isInitialized: true
            });
        }
    }

    /**
     * @dev Increase user's reputation score
     * @param _user Address of the user
     * @param _points Points to increase (maps to score increase)
     * @param _reason Reason for increase
     */
    function increaseReputation(address _user, uint256 _points, string calldata _reason) external onlyAuthorized {
        _initializeUser(_user);

        UserReputation storage rep = userReputations[_user];
        ScoreCategory oldCategory = getScoreCategory(_user);

        uint256 oldScore = rep.score;
        uint256 scoreIncrease = _calculateScoreIncrease(_points, rep.score);
        uint256 newScore = oldScore + scoreIncrease;

        // Cap at MAX_SCORE
        if (newScore > MAX_SCORE) {
            newScore = MAX_SCORE;
        }

        rep.score = newScore;
        rep.totalPositiveActions++;
        rep.lastUpdated = block.timestamp;

        // Track specific achievements
        if (_containsString(_reason, "Goal completed") || _containsString(_reason, "Goal target reached")) {
            rep.goalsCompleted++;
            rep.consecutiveOnTimePayments++;
        }

        if (_containsString(_reason, "Contribution") || _containsString(_reason, "Payment")) {
            rep.consecutiveOnTimePayments++;
        }

        // Record history
        reputationHistory[_user].push(
            ReputationHistory({
                timestamp: block.timestamp,
                scoreChange: int256(scoreIncrease),
                reason: _reason,
                newScore: newScore
            })
        );

        emit ReputationIncreased(_user, scoreIncrease, _reason, newScore);

        // Check for category change
        ScoreCategory newCategory = getScoreCategory(_user);
        if (newCategory != oldCategory) {
            emit ScoreCategoryChanged(_user, oldCategory, newCategory);
        }
    }

    /**
     * @dev Decrease user's reputation score
     * @param _user Address of the user
     * @param _points Points to decrease (maps to score decrease)
     * @param _reason Reason for decrease
     */
    function decreaseReputation(address _user, uint256 _points, string calldata _reason) external onlyAuthorized {
        _initializeUser(_user);

        UserReputation storage rep = userReputations[_user];
        ScoreCategory oldCategory = getScoreCategory(_user);

        uint256 oldScore = rep.score;
        uint256 scoreDecrease = _calculateScoreDecrease(_points, rep.score);
        uint256 newScore = oldScore > scoreDecrease ? oldScore - scoreDecrease : MIN_SCORE;

        // Floor at MIN_SCORE
        if (newScore < MIN_SCORE) {
            newScore = MIN_SCORE;
        }

        rep.score = newScore;
        rep.totalNegativeActions++;
        rep.consecutiveOnTimePayments = 0; // Reset streak on negative action
        rep.lastUpdated = block.timestamp;

        // Late payments are tracked separately via recordLatePayment
        // Do not increment latePayments here to avoid double counting

        // Record history
        reputationHistory[_user].push(
            ReputationHistory({
                timestamp: block.timestamp,
                scoreChange: -int256(scoreDecrease),
                reason: _reason,
                newScore: newScore
            })
        );

        emit ReputationDecreased(_user, scoreDecrease, _reason, newScore);

        // Check for category change
        ScoreCategory newCategory = getScoreCategory(_user);
        if (newCategory != oldCategory) {
            emit ScoreCategoryChanged(_user, oldCategory, newCategory);
        }
    }

    /**
     * @dev Record circle completion (called by CircleSavingsV1)
     * @param _user Address of the user
     * @param _cid Circle ID
     */
    function recordCircleCompleted(address _user, uint256 _cid) external onlyAuthorized {
        _initializeUser(_user);
        UserReputation storage rep = userReputations[_user];
        rep.circlesCompleted++;
        emit CircleCompleted(_user, _cid, rep.circlesCompleted);
    }

    /**
     * @dev Record late payment (called by CircleSavingsV1)
     * @param _user Address of the user
     * @param _cid Circle ID
     * @param _round Round number
     * @param _fee Fee amount
     */
    function recordLatePayment(address _user, uint256 _cid, uint256 _round, uint256 _fee) external onlyAuthorized {
        _initializeUser(_user);
        UserReputation storage rep = userReputations[_user];
        rep.latePayments++;
        emit LatePaymentRecorded(_user,  _cid, _round, _fee, rep.latePayments);
    }

    /**
     * @dev Record goal completion (called by PersonalSavingsV1)
     * @param _user Address of the user
     * @param _goalId Goal ID
     */
    function recordGoalCompleted(address _user, uint256 _goalId) external onlyAuthorized {
        _initializeUser(_user);
        UserReputation storage rep = userReputations[_user];
        rep.goalsCompleted++;

        emit GoalCompleted(_user, _goalId, rep.goalsCompleted);
    }

    // ============ Score Calculation Logic ============

    /**
     * @dev Calculate score increase based on current score
     * @notice Higher scores gain points more slowly (diminishing returns)
     */
    function _calculateScoreIncrease(uint256 _basePoints, uint256 _currentScore) private pure returns (uint256) {
        // Diminishing returns as score increases
        if (_currentScore >= 800) {
            return _basePoints * 1; // Hardest to improve exceptional scores
        } else if (_currentScore >= 740) {
            return _basePoints * 2; // Very good scores
        } else if (_currentScore >= 670) {
            return _basePoints * 3; // Good scores
        } else if (_currentScore >= 580) {
            return _basePoints * 4; // Fair scores
        } else {
            return _basePoints * 5; // Poor scores improve fastest
        }
    }

    /**
     * @dev Calculate score decrease based on current score
     * @notice Higher scores lose more points (more to lose)
     */
    function _calculateScoreDecrease(uint256 _basePoints, uint256 _currentScore) private pure returns (uint256) {
        // Steeper penalties for higher scores
        if (_currentScore >= 800) {
            return _basePoints * 8; // Exceptional scores drop significantly
        } else if (_currentScore >= 740) {
            return _basePoints * 6; // Very good scores
        } else if (_currentScore >= 670) {
            return _basePoints * 5; // Good scores
        } else if (_currentScore >= 580) {
            return _basePoints * 4; // Fair scores
        } else {
            return _basePoints * 3; // Poor scores have less to lose
        }
    }

    // ============ View Functions (CircleSavingsV1 Compatibility) ============

    /**
     * @dev Get user reputation data (for CircleSavingsV1 _getReputationScore)
     * @return positiveActions Total positive actions
     * @return negativeActions Total negative actions
     * @return circlesCompleted Total circles completed
     * @return score Current reputation score
     */
    function getUserReputationData(address _user)
        external
        view
        returns (uint256 positiveActions, uint256 negativeActions, uint256 circlesCompleted, uint256 score)
    {
        if (!userReputations[_user].isInitialized) {
            return (0, 0, 0, DEFAULT_SCORE);
        }

        UserReputation storage rep = userReputations[_user];
        return (rep.totalPositiveActions, rep.totalNegativeActions, rep.circlesCompleted, rep.score);
    }

    /**
     * @dev Get user's reputation score (for PersonalSavingsV1 getUserReputation)
     */
    function getReputation(address _user) external view returns (uint256) {
        if (!userReputations[_user].isInitialized) {
            return DEFAULT_SCORE;
        }
        return userReputations[_user].score;
    }

    /**
     * @dev Get user's score category
     */
    function getScoreCategory(address _user) public view returns (ScoreCategory) {
        uint256 score = userReputations[_user].isInitialized ? userReputations[_user].score : DEFAULT_SCORE;

        if (score <= POOR_THRESHOLD) return ScoreCategory.POOR;
        if (score <= FAIR_THRESHOLD) return ScoreCategory.FAIR;
        if (score <= GOOD_THRESHOLD) return ScoreCategory.GOOD;
        if (score <= VERY_GOOD_THRESHOLD) return ScoreCategory.VERY_GOOD;
        return ScoreCategory.EXCEPTIONAL;
    }

    /**
     * @dev Get score category as string
     */
    function getScoreCategoryString(address _user) external view returns (string memory) {
        ScoreCategory category = getScoreCategory(_user);

        if (category == ScoreCategory.POOR) return "Poor (300-579)";
        if (category == ScoreCategory.FAIR) return "Fair (580-669)";
        if (category == ScoreCategory.GOOD) return "Good (670-739)";
        if (category == ScoreCategory.VERY_GOOD) return "Very Good (740-799)";
        return "Exceptional (800-850)";
    }

    /**
     * @dev Get full user reputation details
     */
    function getUserReputationDetails(address _user)
        external
        view
        returns (
            uint256 score,
            ScoreCategory category,
            uint256 positiveActions,
            uint256 negativeActions,
            uint256 consecutivePayments,
            uint256 circlesCompleted,
            uint256 goalsCompleted,
            uint256 latePayments,
            uint256 lastUpdated
        )
    {
        UserReputation storage rep = userReputations[_user];

        score = rep.isInitialized ? rep.score : DEFAULT_SCORE;
        category = getScoreCategory(_user);
        positiveActions = rep.totalPositiveActions;
        negativeActions = rep.totalNegativeActions;
        consecutivePayments = rep.consecutiveOnTimePayments;
        circlesCompleted = rep.circlesCompleted;
        goalsCompleted = rep.goalsCompleted;
        latePayments = rep.latePayments;
        lastUpdated = rep.lastUpdated;
    }

    /**
     * @dev Get user's reputation history
     */
    function getReputationHistory(address _user) external view returns (ReputationHistory[] memory) {
        return reputationHistory[_user];
    }

    /**
     * @dev Check if user meets score requirement for a feature
     */
    function meetsScoreRequirement(address _user, uint256 _requiredScore) external view returns (bool) {
        uint256 score = userReputations[_user].isInitialized ? userReputations[_user].score : DEFAULT_SCORE;
        return score >= _requiredScore;
    }

    /**
     * @dev Check if user can create large personal goals (600+ score)
     */
    function canCreateLargeGoal(address _user) external view returns (bool) {
        uint256 score = userReputations[_user].isInitialized ? userReputations[_user].score : DEFAULT_SCORE;
        return score >= MIN_SCORE_LARGE_GOAL;
    }

    /**
     * @dev Check if user can create savings circles (580+ score)
     */
    function canCreateCircle(address _user) external view returns (bool) {
        uint256 score = userReputations[_user].isInitialized ? userReputations[_user].score : DEFAULT_SCORE;
        return score >= MIN_SCORE_CIRCLE_CREATE;
    }

    /**
     * @dev Check if user qualifies for premium features (740+ score)
     */
    function hasPremiumAccess(address _user) external view returns (bool) {
        uint256 score = userReputations[_user].isInitialized ? userReputations[_user].score : DEFAULT_SCORE;
        return score >= MIN_SCORE_PREMIUM;
    }

    /**
     * @dev Calculate dynamic penalty reduction based on score
     * @return penaltyMultiplier Multiplier in basis points (10000 = 100%)
     */
    function getPenaltyMultiplier(address _user) external view returns (uint256) {
        uint256 score = userReputations[_user].isInitialized ? userReputations[_user].score : DEFAULT_SCORE;

        // Better scores get penalty reductions
        if (score >= 800) return 5000; // 50% reduction (Exceptional)
        if (score >= 740) return 7000; // 30% reduction (Very Good)
        if (score >= 670) return 8500; // 15% reduction (Good)
        if (score >= 580) return 9500; // 5% reduction (Fair)
        return 10000; // No reduction (Poor)
    }

    /**
     * @dev Calculate collateral discount based on score
     * @return discountMultiplier Multiplier in basis points (10000 = 100%)
     */
    function getCollateralMultiplier(address _user) external view returns (uint256) {
        uint256 score = userReputations[_user].isInitialized ? userReputations[_user].score : DEFAULT_SCORE;

        // Better scores require less collateral
        if (score >= 800) return 8000; // 20% less (Exceptional)
        if (score >= 740) return 8500; // 15% less (Very Good)
        if (score >= 670) return 9000; // 10% less (Good)
        if (score >= 580) return 9500; // 5% less (Fair)
        return 10000; // No discount (Poor)
    }

    // ============ Admin Functions ============

    /**
     * @dev Authorize a contract to modify reputations
     */
    function authorizeContract(address _contract) external onlyOwner {
        authorizedContracts[_contract] = true;
        emit ContractAuthorized(_contract);
    }

    /**
     * @dev Revoke contract authorization
     */
    function revokeContract(address _contract) external onlyOwner {
        authorizedContracts[_contract] = false;
        emit ContractRevoked(_contract);
    }

    // ============ Helper Functions ============

    /**
     * @dev Check if string contains substring (case-sensitive)
     */
    function _containsString(string calldata _str, string memory _substr) private pure returns (bool) {
        bytes memory strBytes = bytes(_str);
        bytes memory substrBytes = bytes(_substr);

        if (substrBytes.length > strBytes.length) return false;

        for (uint256 i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    /**
     * @dev Returns contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
