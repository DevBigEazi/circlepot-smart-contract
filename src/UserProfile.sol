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

/**
 * @title UserProfile
 * @dev User profile management contract with referral rewards system
 * @notice Manages user profile data and automatic referral rewards
 */
contract UserProfile is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard
{
    // ============ Version ============
    uint256 public constant VERSION = 1;

    // ============ Constants ============
    uint256 public constant PROFILE_UPDATE_COOLDOWN = 30 days;
    uint256 public constant MIN_USERNAME_LENGTH = 3;
    uint256 public constant MAX_USERNAME_LENGTH = 20;
    uint256 public constant MIN_FULLNAME_LENGTH = 6;
    uint256 public constant MAX_FULLNAME_LENGTH = 50;

    // Account ID generation constants
    uint256 private constant ACCOUNT_ID_START = 1000000000;
    uint256 private constant ACCOUNT_ID_MAX = 9999999999;

    // ============ Structs ============
    struct UserProfileData {
        address userAddress;
        string email;
        string phoneNumber;
        string username;
        string fullName;
        string profilePhoto;
        uint256 accountId;
        bool emailIsOriginal;
        bool phoneIsOriginal;
        uint256 lastProfileUpdate;
        uint256 createdAt;
    }

    // ============ Profile Storage ============
    mapping(address => UserProfileData) public profiles;
    mapping(string => address) public usernameToAddress;
    mapping(string => address) public emailToAddress;
    mapping(string => address) public phoneNumberToAddress;
    mapping(uint256 => address) public accountIdToAddress;
    mapping(address => bool) public hasProfile;

    uint256 private accountIdCounter;
    address[] public allUsers;

    // ============ Referral Storage ============
    mapping(address => address) public referredBy; // Who referred this user
    mapping(address => uint256) public referralCount; // Successful referrals count
    mapping(address => bool) public hasFirstGoalReward; // Track if referee triggered reward

    // Admin controls
    bool public referralRewardsEnabled;
    mapping(address => uint256) public referralBonusAmount; // token => amount
    mapping(address => uint256) public totalRewardsPaidByToken; // token => amount

    // Campaign mode
    bool public campaignMode;
    uint256 public campaignStartTime;
    uint256 public campaignEndTime;
    mapping(address => uint256) public campaignBonusAmount; // token => amount

    // Contract references
    mapping(address => bool) public supportedTokens;
    address[] public supportedTokenList;
    address public personalSavingsContract;

    // ============ Profile Events ============
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event ProfileCreated(
        address indexed user,
        string email,
        string phoneNumber,
        string username,
        string fullName,
        uint256 accountId,
        string profilePhoto,
        uint256 createdAt,
        bool hasProfile
    );
    event ProfileUpdated(address indexed user, string fullName, string photo);
    event ContactInfoUpdated(
        address indexed user,
        string email,
        string phoneNumber
    );

    // ============ Referral Events ============
    event UserReferred(
        address indexed newUser,
        address indexed referrer,
        uint256 timestamp
    );
    event ReferralRewardPaid(
        address indexed referrer,
        address indexed referee,
        address indexed token,
        uint256 rewardAmount,
        uint256 timestamp
    );
    event ReferralRewardsToggled(bool enabled, uint256 timestamp);
    event ReferralBonusUpdated(
        address indexed token,
        uint256 oldAmount,
        uint256 newAmount,
        uint256 timestamp
    );
    event CampaignStarted(uint256 startTime, uint256 endTime);
    event CampaignBonusUpdated(
        address indexed token,
        uint256 bonusAmount,
        uint256 timestamp
    );
    event CampaignEnded(uint256 timestamp);
    event RewardFundsDeposited(
        address indexed from,
        address indexed token,
        uint256 amount
    );
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event PersonalSavingsContractUpdated(address indexed newContract);

    // ============ Profile Errors ============
    error ProfileAlreadyExists();
    error ProfileDoesNotExist();
    error UsernameAlreadyTaken();
    error EmailAlreadyTaken();
    error PhoneNumberAlreadyTaken();
    error ProfileUpdateCooldownNotMet();
    error OnlyProfileOwner();
    error EmptyUsername();
    error EmptyFullName();
    error NoMoreAccountIdsAvailable();
    error InvalidAccountId();
    error EmailOrPhoneRequired();
    error CannotChangeOriginalContactInfo();
    error UsernameTooShort();
    error UsernameTooLong();
    error FullNameTooShort();
    error FullNameTooLong();
    error NoFieldsToUpdate();

    // ============ Referral Errors ============
    error CannotReferSelf();
    error ReferrerMustHaveProfile();
    error InsufficientRewardFunds();
    error RewardTransferFailed();
    error TokenAlreadySupported();
    error TokenNotSupported();
    error UnsupportedToken();
    error InvalidUSDmTokenAddress();
    error AlreadyReceivedFirstGoalReward();
    error OnlyPersonalSavingsContract();
    error InvalidContractAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param initialOwner Address of the initial owner
     */
    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);

        // Initialize account id counter
        accountIdCounter = 0;

        // Initialize referral settings
        referralRewardsEnabled = false; // Start disabled
        campaignMode = false;

        // Transfer ownership if different initialOwner provided
        if (initialOwner != address(0) && initialOwner != owner()) {
            _transferOwnership(initialOwner);
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

    // ============ Profile Functions ============

    /**
     * @dev Create a new user profile with full name and unique account number
     * @param _email User's email address (optional if phone provided)
     * @param _phoneNumber User's phone number (optional if email provided)
     * @param _username Unique username (minimum 3 characters)
     * @param _fullName User's full name (minimum 6 characters)
     * @param _profilePhoto Profile photo IPFS hash or URL (optional)
     * @param _referrer Address of the user who referred this person (address(0) if none)
     * @notice At least one of email or phone number must be provided
     */
    function createProfile(
        string calldata _email,
        string calldata _phoneNumber,
        string calldata _username,
        string calldata _fullName,
        string calldata _profilePhoto,
        address _referrer
    ) external {
        if (hasProfile[msg.sender]) revert ProfileAlreadyExists();

        // Validate required fields
        if (bytes(_username).length == 0) revert EmptyUsername();
        if (bytes(_username).length < MIN_USERNAME_LENGTH)
            revert UsernameTooShort();
        if (bytes(_username).length > MAX_USERNAME_LENGTH)
            revert UsernameTooLong();
        if (bytes(_fullName).length == 0) revert EmptyFullName();
        if (bytes(_fullName).length < MIN_FULLNAME_LENGTH)
            revert FullNameTooShort();
        if (bytes(_fullName).length > MAX_FULLNAME_LENGTH)
            revert FullNameTooLong();

        // At least one contact method (email or phone) must be provided
        bool hasEmail = bytes(_email).length > 0;
        bool hasPhone = bytes(_phoneNumber).length > 0;
        if (!hasEmail && !hasPhone) revert EmailOrPhoneRequired();

        // Check if username is already taken
        if (usernameToAddress[_username] != address(0)) {
            revert UsernameAlreadyTaken();
        }

        // Check if email is already taken (if provided)
        if (hasEmail && emailToAddress[_email] != address(0)) {
            revert EmailAlreadyTaken();
        }

        // Check if phone number is already taken (if provided)
        if (hasPhone && phoneNumberToAddress[_phoneNumber] != address(0)) {
            revert PhoneNumberAlreadyTaken();
        }

        // Generate unique account number
        if (accountIdCounter >= (ACCOUNT_ID_MAX - ACCOUNT_ID_START + 1)) {
            revert NoMoreAccountIdsAvailable();
        }

        uint256 accountId = _generateAccountId();

        {
            UserProfileData storage profile = profiles[msg.sender];
            profile.userAddress = msg.sender;
            profile.email = _email;
            profile.phoneNumber = _phoneNumber;
            profile.username = _username;
            profile.fullName = _fullName;
            profile.profilePhoto = _profilePhoto;
            profile.accountId = accountId;
            profile.emailIsOriginal = bytes(_email).length > 0;
            profile.phoneIsOriginal = bytes(_phoneNumber).length > 0;
            profile.lastProfileUpdate = 0;
            profile.createdAt = block.timestamp;
        }

        usernameToAddress[_username] = msg.sender;
        if (bytes(_email).length > 0) {
            emailToAddress[_email] = msg.sender;
        }
        if (bytes(_phoneNumber).length > 0) {
            phoneNumberToAddress[_phoneNumber] = msg.sender;
        }
        accountIdToAddress[accountId] = msg.sender;
        hasProfile[msg.sender] = true;
        allUsers.push(msg.sender);

        // ============ Referral Logic ============
        if (_referrer != address(0)) {
            // Validate referrer
            if (_referrer == msg.sender) revert CannotReferSelf();
            if (!hasProfile[_referrer]) revert ReferrerMustHaveProfile();

            // Record referral relationship (NO payment yet!)
            referredBy[msg.sender] = _referrer;

            emit UserReferred(msg.sender, _referrer, block.timestamp);

            // NOTE: referralCount is NOT incremented here!
            // It will be incremented when referee creates first goal
        }
        // ============ END Referral Logic ============

        _emitProfileCreated(msg.sender, accountId);
    }

    function _emitProfileCreated(address user, uint256 accountId) internal {
        UserProfileData storage p = profiles[user];
        emit ProfileCreated(
            user,
            p.email,
            p.phoneNumber,
            p.username,
            p.fullName,
            accountId,
            p.profilePhoto,
            p.createdAt,
            true
        );
    }

    /**
     * @dev Update or add contact information (email or phone number)
     * @param _email Email address to add/update (empty string to skip)
     * @param _phoneNumber Phone number to add/update (empty string to skip)
     * @notice Can only update contact info that was added later (not original)
     * @notice Phone number authenticity is validated offline
     * @notice 30-day cooldown applies when updating existing contact info
     */
    function updateContactInfo(
        string calldata _email,
        string calldata _phoneNumber
    ) external {
        if (!hasProfile[msg.sender]) revert ProfileDoesNotExist();

        UserProfileData storage profile = profiles[msg.sender];
        bool hasEmail = bytes(_email).length > 0;
        bool hasPhone = bytes(_phoneNumber).length > 0;

        // Must provide at least one field to update
        if (!hasEmail && !hasPhone) revert NoFieldsToUpdate();

        bool isAdding = false;
        bool isUpdating = false;

        // Process email update/add
        if (hasEmail) {
            if (bytes(profile.email).length > 0) {
                // Trying to update existing email
                if (profile.emailIsOriginal) {
                    revert CannotChangeOriginalContactInfo();
                }
                isUpdating = true;
                delete emailToAddress[profile.email];
            } else {
                isAdding = true;
            }

            if (emailToAddress[_email] != address(0)) {
                revert EmailAlreadyTaken();
            }

            profile.email = _email;
            emailToAddress[_email] = msg.sender;
        }

        // Process phone number update/add
        if (hasPhone) {
            if (bytes(profile.phoneNumber).length > 0) {
                // Trying to update existing phone
                if (profile.phoneIsOriginal) {
                    revert CannotChangeOriginalContactInfo();
                }
                isUpdating = true;
                delete phoneNumberToAddress[profile.phoneNumber];
            } else {
                isAdding = true;
            }

            if (phoneNumberToAddress[_phoneNumber] != address(0)) {
                revert PhoneNumberAlreadyTaken();
            }

            profile.phoneNumber = _phoneNumber;
            phoneNumberToAddress[_phoneNumber] = msg.sender;
        }

        // Apply cooldown only if updating (not adding for first time)
        if (isUpdating) {
            uint256 timeSinceLastUpdate = block.timestamp -
                profile.lastProfileUpdate;
            if (timeSinceLastUpdate < PROFILE_UPDATE_COOLDOWN) {
                revert ProfileUpdateCooldownNotMet();
            }
            profile.lastProfileUpdate = block.timestamp;
        }

        emit ContactInfoUpdated(msg.sender, profile.email, profile.phoneNumber);
    }

    /**
     * @dev Update profile information (username, full name, and/or profile photo)
     * @param _fullName New full name (empty string to skip, minimum 6 characters if provided)
     * @param _profilePhoto New profile photo IPFS hash or URL (empty string to skip)
     * @notice All profile updates share a 30-day cooldown period
     */
    function updateProfile(
        string calldata _fullName,
        string calldata _profilePhoto
    ) external {
        if (!hasProfile[msg.sender]) revert ProfileDoesNotExist();

        UserProfileData storage profile = profiles[msg.sender];

        bool hasFullName = bytes(_fullName).length > 0;
        bool hasPhoto = bytes(_profilePhoto).length > 0;

        // Must update at least one field
        if (!hasFullName && !hasPhoto) {
            revert NoFieldsToUpdate();
        }

        // Check cooldown period
        uint256 timeSinceLastUpdate = block.timestamp -
            profile.lastProfileUpdate;
        if (timeSinceLastUpdate < PROFILE_UPDATE_COOLDOWN) {
            revert ProfileUpdateCooldownNotMet();
        }

        // Update full name if provided
        if (hasFullName) {
            if (bytes(_fullName).length < MIN_FULLNAME_LENGTH) {
                revert FullNameTooShort();
            }
            if (bytes(_fullName).length > MAX_FULLNAME_LENGTH) {
                revert FullNameTooLong();
            }
            profile.fullName = _fullName;
        }

        // Update profile photo if provided
        if (hasPhoto) {
            profile.profilePhoto = _profilePhoto;
        }

        profile.lastProfileUpdate = block.timestamp;

        emit ProfileUpdated(msg.sender, profile.fullName, profile.profilePhoto);
    }

    // ============ Referral Functions ============

    /**
     * @dev Called by PersonalSavings contract when user creates first goal
     * @param _referee The user who created their first goal
     * @param _token The token used for the goal
     * @notice Automatically pays referral reward to the referrer
     * @notice Can only be called by PersonalSavings contract
     */
    function payReferralReward(
        address _referee,
        address _token
    ) external nonReentrant {
        // Only PersonalSavings contract can call this
        if (msg.sender != personalSavingsContract)
            revert OnlyPersonalSavingsContract();

        // Check if token is supported
        if (!supportedTokens[_token]) return;

        // Check if user was referred
        address referrer = referredBy[_referee];
        if (referrer == address(0)) return; // Not referred, exit silently

        // Check if already rewarded
        if (hasFirstGoalReward[_referee]) return;

        // Check if rewards are enabled
        if (!referralRewardsEnabled) return; // Silently skip if disabled

        // Calculate reward amount for this token
        uint256 rewardAmount = _calculateReward(_token);
        if (rewardAmount == 0) return;

        // Check contract has sufficient funds
        uint256 contractBalance = IERC20(_token).balanceOf(address(this));
        if (contractBalance < rewardAmount) {
            // Insufficient funds - skip silently to not block goal creation
            return;
        }

        // Mark as rewarded (BEFORE transfer for reentrancy protection)
        hasFirstGoalReward[_referee] = true;

        // Increment referrer's successful referral count
        referralCount[referrer]++;

        // Pay reward directly to referrer
        bool success = IERC20(_token).transfer(referrer, rewardAmount);

        if (success) {
            totalRewardsPaidByToken[_token] += rewardAmount;
            emit ReferralRewardPaid(
                referrer,
                _referee,
                _token,
                rewardAmount,
                block.timestamp
            );
        } else {
            // Transfer failed - revert the state changes
            hasFirstGoalReward[_referee] = false;
            referralCount[referrer]--;
            revert RewardTransferFailed();
        }
    }

    /**
     * @dev Calculate reward amount based on current settings for a specific token
     * @param _token Address of the token
     * @return Reward amount to give
     */
    function _calculateReward(address _token) internal view returns (uint256) {
        // If campaign is active and not expired, use campaign bonus
        if (
            campaignMode &&
            block.timestamp >= campaignStartTime &&
            block.timestamp <= campaignEndTime
        ) {
            return campaignBonusAmount[_token];
        }

        // Otherwise use standard bonus
        return referralBonusAmount[_token];
    }

    // ============ Admin Functions ============

    /**
     * @dev Toggle referral rewards on/off
     */
    function setReferralRewardsEnabled(bool _enabled) external onlyOwner {
        referralRewardsEnabled = _enabled;
        emit ReferralRewardsToggled(_enabled, block.timestamp);
    }

    /**
     * @dev Update the referral bonus amount for a specific token
     * @param _token Address of the token
     * @param _newAmount New bonus amount
     */
    function setReferralBonusAmount(
        address _token,
        uint256 _newAmount
    ) external onlyOwner {
        if (!supportedTokens[_token]) revert TokenNotSupported();
        uint256 oldAmount = referralBonusAmount[_token];
        referralBonusAmount[_token] = _newAmount;
        emit ReferralBonusUpdated(
            _token,
            oldAmount,
            _newAmount,
            block.timestamp
        );
    }

    /**
     * @dev Start a time-limited referral campaign for all supported tokens
     * @param _durationInDays Duration of the campaign in days
     */
    function startReferralCampaign(uint256 _durationInDays) external onlyOwner {
        require(!campaignMode, "CampaignAlreadyActive");

        campaignMode = true;
        campaignStartTime = block.timestamp;
        campaignEndTime = block.timestamp + (_durationInDays * 1 days);

        emit CampaignStarted(campaignStartTime, campaignEndTime);
    }

    /**
     * @dev Update campaign bonus amount for a specific token
     * @param _token Address of the token
     * @param _bonus Campaign bonus amount
     */
    function setCampaignBonusAmount(
        address _token,
        uint256 _bonus
    ) external onlyOwner {
        if (!supportedTokens[_token]) revert TokenNotSupported();
        campaignBonusAmount[_token] = _bonus;
        emit CampaignBonusUpdated(_token, _bonus, block.timestamp);
    }

    /**
     * @dev End the current campaign early
     */
    function endReferralCampaign() external onlyOwner {
        require(campaignMode, "NoCampaignActive");

        campaignMode = false;
        campaignEndTime = block.timestamp;

        emit CampaignEnded(block.timestamp);
    }

    /**
     * @dev Fund the contract with rewards for a specific token
     * @param _token Address of the token
     * @param _amount Amount to deposit
     */
    function fundReferralRewards(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        if (!supportedTokens[_token]) revert TokenNotSupported();
        bool success = IERC20(_token).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        require(success, "TransferFailed");

        emit RewardFundsDeposited(msg.sender, _token, _amount);
    }

    /**
     * @dev Withdraw unused reward funds for a specific token (emergency)
     * @param _token Address of the token
     * @param _amount Amount to withdraw
     */
    function withdrawReferralFunds(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        bool success = IERC20(_token).transfer(owner(), _amount);
        require(success, "TransferFailed");
    }

    /**
     * @dev Update PersonalSavings contract address
     */
    function setPersonalSavingsContract(
        address _newContract
    ) external onlyOwner {
        if (_newContract == address(0)) revert InvalidContractAddress();
        personalSavingsContract = _newContract;
        emit PersonalSavingsContractUpdated(_newContract);
    }

    /**
     * @dev Add a supported token for referral rewards
     * @param _token Token address
     */
    function addSupportedToken(address _token) external onlyOwner {
        if (_token == address(0)) revert InvalidContractAddress();
        if (supportedTokens[_token]) revert TokenAlreadySupported();
        supportedTokens[_token] = true;
        supportedTokenList.push(_token);
        emit TokenAdded(_token);
    }

    /**
     * @dev Remove a supported token
     * @param _token Token address
     */
    function removeSupportedToken(address _token) external onlyOwner {
        if (!supportedTokens[_token]) revert TokenNotSupported();
        supportedTokens[_token] = false;

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

    // ============ Helper Functions ============

    /**
     * @dev Generate obfuscated unique account number using pseudo-random hash
     */
    function _generateAccountId() private returns (uint256) {
        uint256 maxAttempts = 100;

        for (uint256 attempt = 0; attempt < maxAttempts; attempt++) {
            uint256 randomHash = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        msg.sender,
                        accountIdCounter,
                        attempt,
                        allUsers.length
                    )
                )
            );

            uint256 accountId = (randomHash %
                (ACCOUNT_ID_MAX - ACCOUNT_ID_START + 1)) + ACCOUNT_ID_START;

            if (accountIdToAddress[accountId] == address(0)) {
                accountIdCounter++;
                return accountId;
            }
        }

        for (uint256 id = ACCOUNT_ID_START; id <= ACCOUNT_ID_MAX; id++) {
            if (accountIdToAddress[id] == address(0)) {
                accountIdCounter++;
                return id;
            }
        }

        revert NoMoreAccountIdsAvailable();
    }

    // ============ Profile View Functions ============

    function getProfile(
        address _user
    ) external view returns (UserProfileData memory) {
        if (!hasProfile[_user]) revert ProfileDoesNotExist();
        return profiles[_user];
    }

    function getAddressByUsername(
        string calldata _username
    ) external view returns (address) {
        address userAddr = usernameToAddress[_username];
        if (userAddr == address(0)) revert ProfileDoesNotExist();
        return userAddr;
    }

    function getAddressByEmail(
        string calldata _email
    ) external view returns (address) {
        address userAddr = emailToAddress[_email];
        if (userAddr == address(0)) revert ProfileDoesNotExist();
        return userAddr;
    }

    function getAddressByPhoneNumber(
        string calldata _phoneNumber
    ) external view returns (address) {
        address userAddr = phoneNumberToAddress[_phoneNumber];
        if (userAddr == address(0)) revert ProfileDoesNotExist();
        return userAddr;
    }

    function getAddressByAccountId(
        uint256 _accountId
    ) external view returns (address) {
        if (_accountId < ACCOUNT_ID_START || _accountId > ACCOUNT_ID_MAX) {
            revert InvalidAccountId();
        }
        address userAddr = accountIdToAddress[_accountId];
        if (userAddr == address(0)) revert ProfileDoesNotExist();
        return userAddr;
    }

    function getUserDetailsByIdentifier(
        string calldata _identifier
    )
        external
        view
        returns (
            address userAddress,
            string memory fullName,
            uint256 accountId,
            string memory email,
            string memory phoneNumber,
            string memory username
        )
    {
        address userAddr;

        userAddr = usernameToAddress[_identifier];

        if (userAddr == address(0)) {
            userAddr = emailToAddress[_identifier];
        }

        if (userAddr == address(0)) {
            userAddr = phoneNumberToAddress[_identifier];
        }

        if (userAddr == address(0)) {
            revert ProfileDoesNotExist();
        }

        UserProfileData storage profile = profiles[userAddr];
        return (
            profile.userAddress,
            profile.fullName,
            profile.accountId,
            profile.email,
            profile.phoneNumber,
            profile.username
        );
    }

    function getUserDetailsByAccountId(
        uint256 _accountId
    )
        external
        view
        returns (
            address userAddress,
            string memory fullName,
            string memory email,
            string memory phoneNumber,
            string memory username
        )
    {
        if (_accountId < ACCOUNT_ID_START || _accountId > ACCOUNT_ID_MAX) {
            revert InvalidAccountId();
        }

        address userAddr = accountIdToAddress[_accountId];
        if (userAddr == address(0)) {
            revert ProfileDoesNotExist();
        }

        UserProfileData storage profile = profiles[userAddr];
        return (
            profile.userAddress,
            profile.fullName,
            profile.email,
            profile.phoneNumber,
            profile.username
        );
    }

    function isUsernameAvailable(
        string calldata _username
    ) external view returns (bool) {
        return usernameToAddress[_username] == address(0);
    }

    function isEmailAvailable(
        string calldata _email
    ) external view returns (bool) {
        return emailToAddress[_email] == address(0);
    }

    function isPhoneNumberAvailable(
        string calldata _phoneNumber
    ) external view returns (bool) {
        return phoneNumberToAddress[_phoneNumber] == address(0);
    }

    function hasUserProfile(address _user) external view returns (bool) {
        return hasProfile[_user];
    }

    function getTotalProfiles() external view returns (uint256) {
        return allUsers.length;
    }

    function getRemainingAccountIds() external view returns (uint256) {
        uint256 totalAvailable = ACCOUNT_ID_MAX - ACCOUNT_ID_START + 1;
        if (accountIdCounter >= totalAvailable) return 0;
        return totalAvailable - accountIdCounter;
    }

    // ============ Referral View Functions ============

    function getReferrer(address _user) external view returns (address) {
        return referredBy[_user];
    }

    function getReferralCount(address _user) external view returns (uint256) {
        return referralCount[_user];
    }

    function wasReferred(address _user) external view returns (bool) {
        return referredBy[_user] != address(0);
    }

    function hasReceivedFirstGoalReward(
        address _user
    ) external view returns (bool) {
        return hasFirstGoalReward[_user];
    }

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

    function getRewardFundBalance(
        address _token
    ) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function getTotalRewardsPaid(
        address _token
    ) external view returns (uint256) {
        return totalRewardsPaidByToken[_token];
    }

    /**
     * @dev Get comprehensive referral stats for a user for a specific token
     */
    function getUserReferralStats(
        address _user,
        address _token
    )
        external
        view
        returns (
            uint256 successfulReferrals,
            address referredByAddress,
            uint256 totalEarned
        )
    {
        return (
            referralCount[_user],
            referredBy[_user],
            referralCount[_user] * referralBonusAmount[_token]
        );
    }

    /**
     * @dev Returns list of all supported tokens
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokenList;
    }

    /**
     * @dev Returns contract version
     */
    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}
