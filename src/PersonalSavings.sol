// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.27;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReputation} from "./interfaces/IReputation.sol";
import {IReferralRewards} from "./interfaces/IReferralRewards.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title PersonalSavings
 * @dev Personal savings goals management with referral integration
 */
contract PersonalSavings is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuard,
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
        bool isYieldEnabled; // true = yield goal, false = standard (no DeFi risk)
        uint256 contributionCount;
    }

    struct CreateGoalParams {
        string name;
        uint256 targetAmount;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 deadline;
        bool enableYield; // User choice - true for yield, false for standard
        address token; // The ERC20 token to use for this savings goal
        uint256 yieldAPY; // The current yield APY (in basis points, e.g., 500 = 5%)
    }

    // ============ Storage ============
    IReputation public reputationContract;
    IReferralRewards public referralRewardsContract; // ReferralRewards contract reference

    address public treasury;
    uint256 public goalCounter;

    // platformFeesByToken tracks fees for each token
    mapping(address => uint256) public platformFeesByToken;

    mapping(uint256 => PersonalGoal) public personalGoals;
    mapping(address => uint256[]) public userGoals;

    // tokenVaults maps token address to its ERC4626 vault address
    mapping(address => address) public tokenVaults;
    // Supported tokens whitelist
    mapping(address => bool) public supportedTokens;
    address[] public supportedTokenList;

    // goalToken maps goalId to the token used for that goal
    mapping(uint256 => address) public goalToken;

    // goalShares maps goalId to vault shares
    mapping(uint256 => uint256) public goalShares;

    bool public personalGoalCreationPaused;

    uint256 public constant PLATFORM_YIELD_SHARE_BPS = 1000; // 10%
    uint256 public constant COMPLETION_FEE_BPS = 10; // 0.1%

    //   ============ Events ============
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event PersonalGoalCreated(
        uint256 indexed goalId,
        address indexed owner,
        string name,
        uint256 indexed amount,
        uint256 currentAmount,
        Frequency frequency,
        uint256 deadline,
        bool isActive,
        address token,
        uint256 yieldAPY
    );
    event GoalContribution(
        uint256 indexed goalId,
        address indexed owner,
        uint256 amount,
        uint256 currentAmount,
        address token
    );
    event GoalWithdrawn(
        uint256 indexed goalId,
        address indexed owner,
        uint256 amount,
        uint256 penalty,
        address token
    );
    event VaultUpdated(
        address indexed token,
        address indexed newVault,
        string project
    );
    event YieldDistributed(
        uint256 indexed goalId,
        address indexed owner,
        uint256 yieldAmount,
        uint256 platformShare,
        address token
    );
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event PersonalGoalCreationPausedUpdated(bool paused);

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
    error UnsupportedToken();
    error TokenAlreadySupported();
    error TokenNotSupported();
    error PersonalGoalCreationPaused();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with initial parameters
     * @param _supportedTokens Array of supported ERC20 token addresses
     * @param _treasury Address for platform fees
     * @param _reputationContract Address of the reputation contract
     * @param initialOwner Address of the initial owner (if zero, msg.sender remains owner)
     */
    function initialize(
        address[] calldata _supportedTokens,
        address _treasury,
        address _reputationContract,
        address initialOwner
    ) public initializer {
        __Ownable_init(initialOwner);

        if (_treasury == address(0) || _reputationContract == address(0)) {
            revert AddressZeroNotAllowed();
        }

        if (_supportedTokens.length == 0) {
            revert AddressZeroNotAllowed();
        }

        // Initialize supported tokens
        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            address token = _supportedTokens[i];
            if (token == address(0)) revert AddressZeroNotAllowed();
            if (!supportedTokens[token]) {
                supportedTokens[token] = true;
                supportedTokenList.push(token);
            }
        }

        reputationContract = IReputation(_reputationContract);
        treasury = _treasury;
        goalCounter = 1;

        // transfer ownership if a different initialOwner was provided
        if (initialOwner != address(0) && initialOwner != owner()) {
            _transferOwnership(initialOwner);
        }
    }

    /**
     * @dev Sets the ReferralRewards contract address (admin only)
     * @param _referralRewardsContract Address of the ReferralRewards contract
     */
    function setReferralRewardsContract(
        address _referralRewardsContract
    ) external onlyOwner {
        if (_referralRewardsContract == address(0))
            revert AddressZeroNotAllowed();
        referralRewardsContract = IReferralRewards(_referralRewardsContract);
    }

    /**
     * @dev Add a supported token (admin only)
     * @param _token Token address
     */
    function addSupportedToken(address _token) external onlyOwner {
        if (_token == address(0)) revert AddressZeroNotAllowed();
        if (supportedTokens[_token]) revert TokenAlreadySupported();
        supportedTokens[_token] = true;
        supportedTokenList.push(_token);
        emit TokenAdded(_token);
    }

    /**
     * @dev Remove a supported token (admin only)
     * @param _token Token address
     */
    function removeSupportedToken(address _token) external onlyOwner {
        if (!supportedTokens[_token]) revert TokenNotSupported();
        supportedTokens[_token] = false;
        // Remove from array
        for (uint256 i = 0; i < supportedTokenList.length; i++) {
            if (supportedTokenList[i] == _token) {
                supportedTokenList[i] = supportedTokenList[
                    supportedTokenList.length - 1
                ];
                supportedTokenList.pop();
                break;
            }
        }
        emit TokenRemoved(_token);
    }

    /**
     * @dev Set the vault address for a specific token (admin only)
     * @param _token Token address
     * @param _vault Vault address for this token
     * @param _project pool project name for this vault
     */
    function setTokenVault(
        address _token,
        address _vault,
        string memory _project
    ) external onlyOwner {
        if (_token == address(0)) revert AddressZeroNotAllowed();
        if (!supportedTokens[_token]) revert UnsupportedToken();
        tokenVaults[_token] = _vault; // Allow setting to address(0) to disable yield for a token
        emit VaultUpdated(_token, _vault, _project);
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
     * @dev Create a personal savings goal with initial contribution
     * @param params Goal creation parameters
     * @return goalId The ID of the newly created goal
     */
    function createPersonalGoal(
        CreateGoalParams calldata params
    ) external nonReentrant returns (uint256) {
        if (personalGoalCreationPaused) revert PersonalGoalCreationPaused();
        if (params.targetAmount < 10e6 || params.targetAmount > 50000e6) {
            revert InvalidGoalAmount();
        }
        if (params.contributionAmount == 0) revert InvalidContributionAmount();
        if (params.deadline <= block.timestamp) revert InvalidDeadline();

        // Validate token
        if (params.token == address(0)) revert AddressZeroNotAllowed();
        if (!supportedTokens[params.token]) revert UnsupportedToken();

        uint256 gid = goalCounter++;
        address token = params.token;
        goalToken[gid] = token;

        // Transfer the first contribution immediately
        IERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            params.contributionAmount
        );

        emit GoalContribution(
            gid,
            msg.sender,
            params.contributionAmount,
            params.contributionAmount,
            token
        );

        // Deposit to vault if yield is enabled
        address vault = tokenVaults[token];
        if (
            params.enableYield &&
            vault != address(0) &&
            params.contributionAmount > 0
        ) {
            IERC20(token).approve(vault, params.contributionAmount);
            goalShares[gid] = IERC4626(vault).deposit(
                params.contributionAmount,
                address(this)
            );
        }

        personalGoals[gid] = PersonalGoal({
            owner: msg.sender,
            name: params.name,
            targetAmount: params.targetAmount,
            currentAmount: params.contributionAmount,
            contributionAmount: params.contributionAmount,
            frequency: params.frequency,
            deadline: params.deadline,
            createdAt: block.timestamp,
            isActive: true,
            lastContributionAt: block.timestamp,
            isYieldEnabled: params.enableYield,
            contributionCount: 1
        });

        userGoals[msg.sender].push(gid);

        emit PersonalGoalCreated(
            gid,
            msg.sender,
            params.name,
            params.targetAmount,
            params.contributionAmount,
            params.frequency,
            params.deadline,
            true,
            token,
            params.enableYield ? params.yieldAPY : 0
        );

        // ============ Trigger Referral Reward ============
        // Check if this is user's FIRST goal
        if (userGoals[msg.sender].length == 1) {
            // Call ReferralRewards to pay referral reward
            // This is safe even if it reverts - won't affect goal creation
            try referralRewardsContract.payReferralReward(msg.sender, token) {
                // Success - referrer was paid (if user was referred)
            } catch {
                // Failed - but goal creation still succeeds
                // Could be: not referred, already rewarded, rewards disabled, unsupported token, or insufficient funds
            }
        }
        // ============ END Referral Logic ============

        return gid;
    }

    /**
     * @dev Contribute to a personal goal
     * @param _goalId Goal ID
     * @param _amount Optional contribution amount (if 0, uses goal's contributionAmount)
     */
    function contributeToGoal(
        uint256 _goalId,
        uint256 _amount
    ) external nonReentrant {
        if (_goalId == 0 || _goalId >= goalCounter) revert InvalidSavingGoal();

        PersonalGoal storage g = personalGoals[_goalId];
        if (g.owner != msg.sender) revert NotGoalOwner();
        if (!g.isActive) revert GoalNotActive();
        if (_amount > g.contributionAmount) revert InvalidContributionAmount();

        if (g.lastContributionAt > 0) {
            uint256 interval = _freqSeconds(g.frequency);
            // Revert if insufficient time has passed since last contribution
            if (block.timestamp < g.lastContributionAt + interval) {
                revert AlreadyContributed();
            }
        }

        uint256 contributionAmt = _amount > 0 ? _amount : g.contributionAmount;
        if (contributionAmt == 0) revert InvalidContributionAmount();

        address token = goalToken[_goalId];
        IERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            contributionAmt
        );

        // Deposit to vault if yield is enabled for this goal
        address vault = tokenVaults[token];
        if (g.isYieldEnabled && vault != address(0) && contributionAmt > 0) {
            IERC20(token).approve(vault, contributionAmt);
            goalShares[_goalId] += IERC4626(vault).deposit(
                contributionAmt,
                address(this)
            );
        }

        g.currentAmount += contributionAmt;
        g.lastContributionAt = block.timestamp;
        g.contributionCount++;

        emit GoalContribution(
            _goalId,
            msg.sender,
            contributionAmt,
            g.currentAmount,
            token
        );
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

        address token = goalToken[_goalId];
        uint256 actualAmountReceived = _amount;
        uint256 yieldEarned = 0;

        // Handle vault redemption for yield-enabled goals
        {
            address vault = tokenVaults[token];
            uint256 shares = goalShares[_goalId];
            if (g.isYieldEnabled && vault != address(0) && shares > 0) {
                // Calculate proportional shares to redeem
                uint256 sharesToRedeem = (shares * _amount) / g.currentAmount;

                if (sharesToRedeem > 0) {
                    uint256 balanceBefore = IERC20(token).balanceOf(
                        address(this)
                    );
                    IERC4626(vault).redeem(
                        sharesToRedeem,
                        address(this),
                        address(this)
                    );
                    uint256 balanceAfter = IERC20(token).balanceOf(
                        address(this)
                    );

                    actualAmountReceived = balanceAfter - balanceBefore;
                    goalShares[_goalId] -= sharesToRedeem;

                    // Calculate yield (any excess over principal)
                    if (actualAmountReceived > _amount) {
                        uint256 totalYield = actualAmountReceived - _amount;
                        // Platform takes 10% of yield
                        uint256 platformYield = (totalYield *
                            PLATFORM_YIELD_SHARE_BPS) / 10000;
                        platformFeesByToken[token] += platformYield;
                        yieldEarned = totalYield - platformYield;
                        actualAmountReceived = _amount; // Cap the base amount at requested principal

                        emit YieldDistributed(
                            _goalId,
                            msg.sender,
                            yieldEarned,
                            platformYield,
                            token
                        );
                    }
                }
            }
        }

        // Calculate penalty based on the actual amount returned from vault (capped at requested)
        uint256 progress = (g.currentAmount * 10000) / g.targetAmount;
        uint256 penaltyBps = _penaltyBps(progress);
        uint256 penalty = (actualAmountReceived * penaltyBps) / 10000;
        uint256 net = actualAmountReceived - penalty;

        g.currentAmount -= _amount;

        if (penalty > 0) {
            platformFeesByToken[token] += penalty;
        }

        IERC20(token).safeTransfer(msg.sender, net + yieldEarned);

        uint256 pointsToDecrease = g.currentAmount == 0 ? 5 : 2;
        reputationContract.decreaseReputation(
            msg.sender,
            pointsToDecrease,
            "Early withdrawal"
        );

        emit GoalWithdrawn(_goalId, msg.sender, _amount, penalty, token);

        if (g.currentAmount == 0) {
            g.isActive = false;
            goalShares[_goalId] = 0; // Clear any remaining shares
        }
    }

    /**
     * @dev Complete a goal and withdraw full amount plus any yield earned
     * @param _goalId Goal ID
     */
    function completeGoal(uint256 _goalId) external nonReentrant {
        if (_goalId == 0 || _goalId >= goalCounter) revert InvalidSavingGoal();

        PersonalGoal storage g = personalGoals[_goalId];
        if (g.owner != msg.sender) revert NotGoalOwner();
        if (!g.isActive) revert GoalNotActive();
        if (g.currentAmount < g.targetAmount) revert InsufficientBalance();

        uint256 principal = g.currentAmount;
        address token = goalToken[_goalId];
        uint256 actualAmountReceived = principal;
        uint256 yieldEarned = 0;

        // Handle vault redemption for yield-enabled goals
        {
            address vault = tokenVaults[token];
            if (
                g.isYieldEnabled &&
                vault != address(0) &&
                goalShares[_goalId] > 0
            ) {
                uint256 shares = goalShares[_goalId];
                goalShares[_goalId] = 0;

                uint256 balanceBefore = IERC20(token).balanceOf(address(this));
                IERC4626(vault).redeem(shares, address(this), address(this));
                uint256 balanceAfter = IERC20(token).balanceOf(address(this));

                actualAmountReceived = balanceAfter - balanceBefore;

                // Calculate yield (any excess over principal)
                if (actualAmountReceived > principal) {
                    uint256 totalYield = actualAmountReceived - principal;
                    // Platform takes 10% of yield
                    uint256 platformYield = (totalYield *
                        PLATFORM_YIELD_SHARE_BPS) / 10000;
                    platformFeesByToken[token] += platformYield;
                    yieldEarned = totalYield - platformYield;
                    actualAmountReceived = principal; // Base for completion fee is capped at principal

                    emit YieldDistributed(
                        _goalId,
                        msg.sender,
                        yieldEarned,
                        platformYield,
                        token
                    );
                }
            }
        }

        uint256 penaltyBps = _penaltyBps(10000); // gets the 10 BPS
        uint256 fee = (actualAmountReceived * penaltyBps) / 10000;
        uint256 amountToUser = actualAmountReceived - fee;

        g.isActive = false;
        g.currentAmount = 0;

        IERC20(token).safeTransfer(msg.sender, amountToUser + yieldEarned);
        platformFeesByToken[token] += fee;

        uint256 reputationPoints = g.contributionCount < 4 ? 1 : 10;
        reputationContract.increaseReputation(
            msg.sender,
            reputationPoints,
            "Goal completed"
        );

        // Record goal completion in reputation contract
        _recordGoalCompleted(msg.sender, _goalId);
        emit GoalWithdrawn(
            _goalId,
            msg.sender,
            amountToUser + yieldEarned,
            fee,
            token
        );
    }

    // ============ Admin Functions ============
    /**
     * @dev Withdraw accumulated platform fees for a specific token to treasury
     * @param _token The address of the token to withdraw fees for
     */
    function withdrawPlatformFees(address _token) external onlyOwner {
        uint256 amt = platformFeesByToken[_token];
        if (amt == 0) revert InsufficientBalance();
        platformFeesByToken[_token] = 0;
        IERC20(_token).safeTransfer(treasury, amt);
    }

    /**
     * @dev Update treasury address
     */
    function updateTreasury(address _new) external onlyOwner {
        if (_new == address(0)) revert InvalidTreasuryAddress();
        treasury = _new;
    }

    /**
     * @dev Toggle the pause state for goal creation (admin only)
     * @param _paused True to pause, false to unpause
     */
    function setPersonalGoalCreationPaused(bool _paused) external onlyOwner {
        personalGoalCreationPaused = _paused;
        emit PersonalGoalCreationPausedUpdated(_paused);
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
        if (prog < 10000) return 25; // 0.25%
        return COMPLETION_FEE_BPS;
    }

    /**
     * @dev Record goal completion via reputation contract
     */
    function _recordGoalCompleted(address _user, uint256 _goalId) internal {
        try
            IReputation(reputationContract).recordGoalCompleted(_user, _goalId)
        {
            // Success
        } catch {
            // Fail silently
        }
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
     * @dev Returns the token address for a specific goal
     */
    function getGoalToken(uint256 _goalId) external view returns (address) {
        return goalToken[_goalId];
    }

    /**
     * @dev Returns the list of all supported tokens
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokenList;
    }

    /**
     * @dev Checks if a token is supported
     */
    function isSupportedToken(address _token) external view returns (bool) {
        return supportedTokens[_token];
    }

    /**
     * @dev Returns platform fees for a specific token
     */
    function getPlatformFees(address _token) external view returns (uint256) {
        return platformFeesByToken[_token];
    }

    /**
     * @dev returns contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
