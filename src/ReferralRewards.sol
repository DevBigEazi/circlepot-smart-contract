// SPDX-License-Identifier: SEE LICENSE IN LICENSE
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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ReferralRewards
 * @dev Minimal referral and rewards tracking contract migrated from UserProfile.sol
 */
contract ReferralRewards is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    // ============ Constants ============
    uint256 public constant VERSION = 1;

    // ============ Storage ============
    mapping(address => address) public referredBy; // referee => referrer
    mapping(address => uint256) public referralCount; // referrer => count
    mapping(address => bool) public hasFirstGoalReward; // referee => processed?
    mapping(address => mapping(address => uint256)) public pendingRewards; // user => token => debt
    mapping(address => address[]) public tokenPendingUsers; // token => list of debtors
    mapping(address => mapping(address => bool)) public isUserPendingForToken; // token => user => exists?

    mapping(address => bool) public authorizedRelayers;
    mapping(address => uint256) public referralBonusAmount; // token => amount
    mapping(address => uint256) public totalRewardsPaidByToken; // token => total
    mapping(address => mapping(address => uint256)) public userTotalPaidRewards; // user => token => total

    bool public referralRewardsEnabled;
    address public personalSavingsContract;
    mapping(address => bool) public supportedTokens;

    // Campaign mode
    bool public campaignMode;
    uint256 public campaignStartTime;
    uint256 public campaignEndTime;
    mapping(address => uint256) public campaignBonusAmount; // token => amount

    // ============ Events ============
    event UserReferred(
        address indexed newUser,
        address indexed referrer,
        uint256 timestamp
    );
    event ReferralRewardsEnabledUpdated(bool enabled);
    event ReferralBonusUpdated(address indexed token, uint256 amount);
    event TokenSupportUpdated(address indexed token, bool status);
    event ReferralRewardPaid(
        address indexed referrer,
        address indexed referee,
        address indexed token,
        uint256 amount
    );
    event ReferralRewardPending(
        address indexed referrer,
        address indexed referee,
        address indexed token,
        uint256 amount
    );
    event RelayerStatusUpdated(address indexed relayer, bool status);
    event PersonalSavingsUpdated(address indexed newContract);
    event CampaignStarted(uint256 startTime, uint256 endTime);
    event CampaignEnded(uint256 timestamp);
    event CampaignBonusUpdated(address indexed token, uint256 bonusAmount);

    // ============ Errors ============
    error OnlyRelayer();
    error OnlyPersonalSavings();
    error AlreadyReferred();
    error CannotReferSelf();
    error RewardTransferFailed();
    error InvalidAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        referralRewardsEnabled = true;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    modifier onlyRelayer() {
        if (!authorizedRelayers[msg.sender] && msg.sender != owner())
            revert OnlyRelayer();
        _;
    }

    // ============ Relayer Functions ============

    function setRelayerStatus(address relayer, bool status) external onlyOwner {
        authorizedRelayers[relayer] = status;
        emit RelayerStatusUpdated(relayer, status);
    }

    /**
     * @dev Records a referral relationship. Called by API via relayer during profile creation.
     */
    function recordReferral(
        address _referee,
        address _referrer
    ) external onlyRelayer {
        if (_referee == _referrer) revert CannotReferSelf();
        if (referredBy[_referee] != address(0)) revert AlreadyReferred();
        if (_referrer == address(0)) return;

        referredBy[_referee] = _referrer;
        emit UserReferred(_referee, _referrer, block.timestamp);
    }

    // ============ Reward Functions ============

    function setPersonalSavingsContract(address _contract) external onlyOwner {
        personalSavingsContract = _contract;
        emit PersonalSavingsUpdated(_contract);
    }

    function setTokenSupport(address _token, bool _status) external onlyOwner {
        supportedTokens[_token] = _status;
        emit TokenSupportUpdated(_token, _status);
    }

    function setBonusAmount(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        referralBonusAmount[_token] = _amount;
        emit ReferralBonusUpdated(_token, _amount);
    }

    /**
     * @dev Toggle referral rewards on/off (Admin only)
     */
    function setReferralRewardsEnabled(bool _enabled) external onlyOwner {
        referralRewardsEnabled = _enabled;
        emit ReferralRewardsEnabledUpdated(_enabled);
    }

    /**
     * @dev Called by PersonalSavings when a user completes their first deposit/goal.
     */
    function payReferralReward(
        address _referee,
        address _token
    ) external nonReentrant {
        if (msg.sender != personalSavingsContract) revert OnlyPersonalSavings();

        address referrer = referredBy[_referee];
        if (referrer == address(0) || hasFirstGoalReward[_referee]) return;

        hasFirstGoalReward[_referee] = true;
        referralCount[referrer]++;

        if (!referralRewardsEnabled || !supportedTokens[_token]) return;

        uint256 currentBonus = _calculateReward(_token);
        uint256 amount = currentBonus + pendingRewards[referrer][_token];
        if (amount == 0) return;

        uint256 balance = IERC20(_token).balanceOf(address(this));

        if (balance >= amount) {
            IERC20(_token).safeTransfer(referrer, amount);
            pendingRewards[referrer][_token] = 0;
            totalRewardsPaidByToken[_token] += amount;
            userTotalPaidRewards[referrer][_token] += amount;
            _removeFromPendingList(_token, referrer);
            emit ReferralRewardPaid(referrer, _referee, _token, amount);
        } else {
            // Partial payment or just add to debt
            if (balance > 0) {
                IERC20(_token).safeTransfer(referrer, balance);
                uint256 paid = balance;
                uint256 remaining = amount - paid;
                pendingRewards[referrer][_token] = remaining;
                totalRewardsPaidByToken[_token] += paid;
                userTotalPaidRewards[referrer][_token] += paid;
                _addToPendingList(_token, referrer, 0, address(0)); // Just ensure in list
                emit ReferralRewardPaid(referrer, _referee, _token, paid);
                emit ReferralRewardPending(
                    referrer,
                    _referee,
                    _token,
                    remaining
                );
            } else {
                pendingRewards[referrer][_token] = amount;
                _addToPendingList(_token, referrer, 0, address(0));
                emit ReferralRewardPending(referrer, _referee, _token, amount);
            }
        }
    }

    function _addToPendingList(
        address _token,
        address _user,
        uint256 _amount,
        address _referee
    ) internal {
        if (_amount > 0) {
            pendingRewards[_user][_token] = _amount;
            emit ReferralRewardPending(_user, _referee, _token, _amount);
        }

        if (!isUserPendingForToken[_token][_user]) {
            tokenPendingUsers[_token].push(_user);
            isUserPendingForToken[_token][_user] = true;
        }
    }

    function _removeFromPendingList(address _token, address _user) internal {
        if (!isUserPendingForToken[_token][_user]) return;

        address[] storage users = tokenPendingUsers[_token];
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == _user) {
                users[i] = users[users.length - 1];
                users.pop();
                isUserPendingForToken[_token][_user] = false;
                break;
            }
        }
    }

    function processPendingRewards(
        address _token,
        uint256 _count
    ) external onlyOwner nonReentrant {
        address[] storage users = tokenPendingUsers[_token];
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) return;

        uint256 iterations = _count > users.length ? users.length : _count;

        for (uint256 i = 0; i < iterations; i++) {
            if (users.length == 0) break;
            address user = users[users.length - 1]; // Process from end for safe pop
            uint256 amount = pendingRewards[user][_token];

            if (amount == 0) {
                _removeFromPendingList(_token, user);
                continue;
            }

            uint256 toPay = amount > balance ? balance : amount;
            IERC20(_token).safeTransfer(user, toPay);
            balance -= toPay;
            pendingRewards[user][_token] -= toPay;
            totalRewardsPaidByToken[_token] += toPay;
            userTotalPaidRewards[user][_token] += toPay;

            emit ReferralRewardPaid(user, address(0), _token, toPay);

            if (pendingRewards[user][_token] == 0) {
                _removeFromPendingList(_token, user);
            }
            if (balance == 0) break;
        }
    }

    function withdrawFunds(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    function getPendingUserCount(
        address _token
    ) external view returns (uint256) {
        return tokenPendingUsers[_token].length;
    }

    /**
     * @dev Returns comprehensive referral settings for a specific token
     */
    function getReferralSettings(
        address _token
    )
        external
        view
        returns (
            bool enabled,
            uint256 standardBonus,
            bool inCampaign,
            uint256 campaignBonus,
            uint256 campaignEndsAt
        )
    {
        return (
            referralRewardsEnabled,
            referralBonusAmount[_token],
            campaignMode && block.timestamp <= campaignEndTime,
            campaignBonusAmount[_token],
            campaignEndTime
        );
    }

    // ============ Internal Functions ============

    function _calculateReward(address _token) internal view returns (uint256) {
        if (
            campaignMode &&
            block.timestamp >= campaignStartTime &&
            block.timestamp <= campaignEndTime
        ) {
            return campaignBonusAmount[_token];
        }
        return referralBonusAmount[_token];
    }

    // ============ Admin Campaign Functions ============

    function startReferralCampaign(uint256 _durationInDays) external onlyOwner {
        require(!campaignMode, "CampaignAlreadyActive");
        campaignMode = true;
        campaignStartTime = block.timestamp;
        campaignEndTime = block.timestamp + (_durationInDays * 1 days);
        emit CampaignStarted(campaignStartTime, campaignEndTime);
    }

    function setCampaignBonusAmount(
        address _token,
        uint256 _bonus
    ) external onlyOwner {
        campaignBonusAmount[_token] = _bonus;
        emit CampaignBonusUpdated(_token, _bonus);
    }

    function endReferralCampaign() external onlyOwner {
        require(campaignMode, "NoCampaignActive");
        campaignMode = false;
        campaignEndTime = block.timestamp;
        emit CampaignEnded(block.timestamp);
    }
}
