// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReputation} from "./interfaces/IReputation.sol";

/**
 * @title PersonalSavingsV1
 * @dev Personal savings goals management
 */
contract PersonalSavingsV1 is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Version ============
    uint256 public constant VERSION = 1;

    // ============ Enums ============
    enum Frequency {
        DAILY,
        WEEKLY,
        MONTHLY
    }

    // ============ Structs ============
    struct PersonalGoal {
        address owner;
        string name;
        uint256 targetAmount;
        uint256 currentAmount;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 deadline;
        uint256 createdAt;
        bool isActive;
        uint256 lastContributionAt;
    }

    struct CreateGoalParams {
        string name;
        uint256 targetAmount;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 deadline;
    }

    // ============ Storage ============
    address public cUSDToken;
    IReputation public reputationContract;

    uint256 public goalCounter;

    mapping(uint256 => PersonalGoal) public personalGoals;
    mapping(address => uint256[]) public userGoals; // ============ Events ============
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event PersonalGoalCreated(
        uint256 indexed goalId,
        address indexed owner,
        string name,
        uint256 indexed amount
    );
    event GoalCompleted(uint256 indexed goalId, address indexed owner);
    event GoalContribution(
        uint256 indexed goalId,
        address indexed owner,
        uint256 amount
    );
    event GoalWithdrawn(
        uint256 indexed goalId,
        address indexed owner,
        uint256 _amount,
        uint256 penalty
    );

    // ============ Errors ============
    error InvalidTreasuryAddress();
    error InvalidContributionAmount();
    error AddressZeroNotAllowed();
    error InvalidGoalAmount();
    error InvalidDeadline();
    error InvalidSavingGoal();
    error NotGoalOwner();
    error GoalNotActive();
    error InsufficientBalance();
    error AlreadyContributed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with initial parameters
     * @param _cUSDToken Address of the cUSD token contract
     * @param initialOwner Address of the initial owner (if zero, msg.sender remains owner)
     */
    function initialize(
        address _cUSDToken,
        address _reputationContract,
        address initialOwner
    ) public initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_cUSDToken == address(0)) revert InvalidTreasuryAddress();
        if (_reputationContract == address(0)) revert AddressZeroNotAllowed();

        cUSDToken = _cUSDToken;
        reputationContract = IReputation(_reputationContract);
        goalCounter = 1;

        // transfer ownership if a different initialOwner was provided
        if (initialOwner != address(0) && initialOwner != owner()) {
            _transferOwnership(initialOwner);
        }
    }

    /**
     * @dev Function for upgrading the contract to a new version (reinitializer)
     * @param _cUSDToken Address of cUSD token (if changed)
     * @param _version Reinitializer version number
     */
    function upgrade(
        address _cUSDToken,
        address _reputationContract,
        uint8 _version
    ) public reinitializer(_version) onlyOwner {
        if (_cUSDToken != address(0)) {
            cUSDToken = _cUSDToken;
        }
        if (_reputationContract != address(0)) {
            reputationContract = IReputation(_reputationContract);
        }
    }

    /**
     * @dev Authorizes upgrade to new implementation
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        emit ContractUpgraded(newImplementation, VERSION);
    }

    // ============ Personal Saving Goals Functions ============
    /**
     * @dev Create a personal savings goal
     * @param params Goal creation parameters
     * @return goalId The ID of the newly created goal
     */
    function createPersonalGoal(
        CreateGoalParams calldata params
    ) external returns (uint256) {
        if (params.targetAmount < 10e18 || params.targetAmount > 50000e18)
            revert InvalidGoalAmount();
        if (params.contributionAmount == 0) revert InvalidContributionAmount();
        if (params.deadline <= block.timestamp) revert InvalidDeadline();

        uint256 gid = goalCounter++;

        personalGoals[gid] = PersonalGoal({
            owner: msg.sender,
            name: params.name,
            targetAmount: params.targetAmount,
            currentAmount: 0,
            contributionAmount: params.contributionAmount,
            frequency: params.frequency,
            deadline: params.deadline,
            createdAt: block.timestamp,
            isActive: true,
            lastContributionAt: 0
        });

        userGoals[msg.sender].push(gid);

        emit PersonalGoalCreated(
            gid,
            msg.sender,
            params.name,
            params.targetAmount
        );

        return gid;
    }

    /**
     * @dev Contribute to a personal goal
     * @param _goalId Goal ID
     */
    function ContributeToGoal(uint256 _goalId) external nonReentrant {
        if (_goalId == 0 || _goalId >= goalCounter) revert InvalidSavingGoal();

        PersonalGoal storage g = personalGoals[_goalId];
        if (g.owner != msg.sender) revert NotGoalOwner();
        if (!g.isActive) revert GoalNotActive();

        if (g.lastContributionAt > 0) {
            uint256 interval = _freqSeconds(g.frequency);
            // Revert if insufficient time has passed since last contribution
            if (block.timestamp < g.lastContributionAt + interval) {
                revert AlreadyContributed();
            }
        }

        IERC20(cUSDToken).safeTransferFrom(
            msg.sender,
            address(this),
            g.contributionAmount
        );

        g.currentAmount += g.contributionAmount;
        g.lastContributionAt = block.timestamp;

        emit GoalContribution(_goalId, msg.sender, g.contributionAmount);

        if (g.currentAmount >= g.targetAmount) {
            reputationContract.increaseReputation(
                msg.sender,
                10,
                "Goal target reached"
            );
            emit GoalCompleted(_goalId, msg.sender);
        }
    }

    /**
     * @dev Withdraw from a personal goal (with penalty)
     * @param _goalId Goal ID
     * @param _amount Amount to withdraw
     */
    function withdrawFromGoal(
        uint256 _goalId,
        uint256 _amount
    ) external nonReentrant {
        if (_goalId == 0 || _goalId >= goalCounter) revert InvalidSavingGoal();

        PersonalGoal storage g = personalGoals[_goalId];
        if (g.owner != msg.sender) revert NotGoalOwner();
        if (!g.isActive) revert GoalNotActive();
        if (_amount > g.currentAmount) revert InsufficientBalance();

        uint256 progress = (g.currentAmount * 10000) / g.targetAmount; // progress in percent
        uint256 penaltyBps = _penaltyBps(progress);
        uint256 penalty = (_amount * penaltyBps) / 10000;
        uint256 net = _amount - penalty;

        g.currentAmount -= _amount;

        if (penalty > 0) {
            IERC20(cUSDToken).safeTransfer(msg.sender, net);
        } else {
            IERC20(cUSDToken).safeTransfer(msg.sender, _amount);
        }

        reputationContract.decreaseReputation(
            msg.sender,
            5,
            "Early withdrawal"
        );

        emit GoalWithdrawn(_goalId, msg.sender, _amount, penalty);

        if (g.currentAmount == 0) g.isActive = false;
    }

    /**
     * @dev Complete a goal and withdraw full amount
     * @param _goalId Goal ID
     */
    function CompleteGoal(uint256 _goalId) external nonReentrant {
        if (_goalId == 0 || _goalId >= goalCounter) revert InvalidSavingGoal();

        PersonalGoal storage g = personalGoals[_goalId];
        if (g.owner != msg.sender) revert NotGoalOwner();
        if (!g.isActive) revert GoalNotActive();
        if (g.currentAmount < g.targetAmount) revert InsufficientBalance();

        uint256 amt = g.currentAmount;
        g.isActive = false;
        g.currentAmount = 0;

        IERC20(cUSDToken).safeTransfer(msg.sender, amt);
        reputationContract.increaseReputation(msg.sender, 10, "Goal completed");

        emit GoalCompleted(_goalId, msg.sender);
    }

    // ============ Helper Functions ============
    /**
     * @dev Convert frequency to seconds
     */
    function _freqSeconds(Frequency f) private pure returns (uint256) {
        if (f == Frequency.DAILY) return 1 days;
        if (f == Frequency.WEEKLY) return 7 days;
        return 30 days;
    }

    /**
     * @dev Calculate penalty basis points based on progress percentage
     */
    function _penaltyBps(uint256 prog) private pure returns (uint256) {
        if (prog < 2500) return 100; // 1.0%
        if (prog < 5000) return 60; // 0.6%
        if (prog < 7500) return 30; // 0.3%
        if (prog < 10000) return 10; // 0.1%
        return 0;
    }

    // ============ View Functions ============
    /**
     * @dev Returns all goals for a user
     */
    function getUserGoals(
        address _user
    ) external view returns (uint256[] memory) {
        return userGoals[_user];
    }

    /**
     * @dev Returns user's reputation from the reputation contract
     */
    function getUserReputation(address _user) external view returns (uint256) {
        return reputationContract.getReputation(_user);
    }

    /**
     * @dev returns contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
