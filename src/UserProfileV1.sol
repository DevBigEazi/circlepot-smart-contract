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

/**
 * @title UserProfileV1
 * @dev User profile management contract with unique account id (account number)
 * @notice Manages user profile data including email, username, address, profile photo, and unique account number
 */
contract UserProfileV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // ============ Version ============
    uint256 public constant VERSION = 1;

    // ============ Constants ============
    uint256 public constant PROFILE_UPDATE_COOLDOWN = 30 days; // 1 month for all profile updates
    uint256 public constant MIN_USERNAME_LENGTH = 3; // Minimum username length
    uint256 public constant MAX_USERNAME_LENGTH = 20; // Maximum username length
    uint256 public constant MIN_FULLNAME_LENGTH = 6; // Minimum full name length
    uint256 public constant MAX_FULLNAME_LENGTH = 50; // Maximum full name length

    // Account ID generation constants
    uint256 private constant ACCOUNT_ID_START = 1000000000; // First 10-digit id
    uint256 private constant ACCOUNT_ID_MAX = 9999999999; // Last 10-digit id

    // ============ Structs ============
    struct UserProfile {
        address userAddress; // user address
        string email; // unique email (optional if phone provided)
        string phoneNumber; // unique phone number (optional if email provided)
        string username; // unique username
        string fullName; // full name field
        string profilePhoto; // IPFS hash or URL
        uint256 accountId; // unique account id
        bool emailIsOriginal; // true if email was provided at creation (immutable)
        bool phoneIsOriginal; // true if phone was provided at creation (immutable)
        uint256 lastProfileUpdate; // timestamp of last profile update
        uint256 createdAt;
    }

    // ============ Storage ============
    mapping(address => UserProfile) public profiles;
    mapping(string => address) public usernameToAddress; // Track usernames to ensure uniqueness
    mapping(string => address) public emailToAddress; // Track emails for lookup
    mapping(string => address) public phoneNumberToAddress; // Track phone numbers for lookup
    mapping(uint256 => address) public accountIdToAddress; // Track account numbers for lookup
    mapping(address => bool) public hasProfile;

    uint256 private accountIdCounter; // Counter for generating unique account numbers
    address[] public allUsers;

    // ============ Events ============
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
    event ProfileUpdated(
        address indexed user,
        string fullName,
        string photo
    );
    event ContactInfoUpdated(
        address indexed user,
        string email,
        string phoneNumber
    );

    // ============ Errors ============
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
    error EmailOrPhoneRequired(); // At least one contact method required
    error CannotChangeOriginalContactInfo(); // Cannot change contact info provided at creation
    error UsernameTooShort(); // Username must be at least 3 characters
    error UsernameTooLong(); // Username must be at most 20 characters
    error FullNameTooShort(); // Full name must be at least 6 characters
    error FullNameTooLong(); // Full name must be at most 50 characters
    error NoFieldsToUpdate(); // At least one field must be provided for update

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

        // transfer ownership if a different initialOwner was provided
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
     * @notice At least one of email or phone number must be provided
     */
    function createProfile(
        string calldata _email,
        string calldata _phoneNumber,
        string calldata _username,
        string calldata _fullName,
        string calldata _profilePhoto
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
            UserProfile storage profile = profiles[msg.sender];
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

        _emitProfileCreated(msg.sender, accountId);
    }

    function _emitProfileCreated(address user, uint256 accountId) internal {
        UserProfile storage p = profiles[user];
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

        UserProfile storage profile = profiles[msg.sender];
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

        UserProfile storage profile = profiles[msg.sender];

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

        emit ProfileUpdated(
            msg.sender,
            profile.fullName,
            profile.profilePhoto
        );
    }

    // ============ Helper Functions ============
    /**
     * @dev Generate obfuscated unique account number using pseudo-random hash
     */
    function _generateAccountId() private returns (uint256) {
        uint256 maxAttempts = 100; // Prevent infinite loop

        for (uint256 attempt = 0; attempt < maxAttempts; attempt++) {
            // Create pseudo-random hash using multiple sources
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

            // Map to 10-digit range
            uint256 accountId = (randomHash %
                (ACCOUNT_ID_MAX - ACCOUNT_ID_START + 1)) + ACCOUNT_ID_START;

            // Check if this account ID is available
            if (accountIdToAddress[accountId] == address(0)) {
                accountIdCounter++;
                return accountId;
            }
        }

        // Fallback: if we couldn't find a random ID, use sequential search
        // This should be extremely rare
        for (uint256 id = ACCOUNT_ID_START; id <= ACCOUNT_ID_MAX; id++) {
            if (accountIdToAddress[id] == address(0)) {
                accountIdCounter++;
                return id;
            }
        }

        revert NoMoreAccountIdsAvailable();
    }

    // ============ View Functions ============

    /**
     * @dev Get user profile by address
     * @param _user User address
     * @return User profile struct
     */
    function getProfile(
        address _user
    ) external view returns (UserProfile memory) {
        if (!hasProfile[_user]) revert ProfileDoesNotExist();
        return profiles[_user];
    }

    /**
     * @dev Get user address by username
     * @param _username Username to lookup
     * @return User address
     */
    function getAddressByUsername(
        string calldata _username
    ) external view returns (address) {
        address userAddr = usernameToAddress[_username];
        if (userAddr == address(0)) revert ProfileDoesNotExist();
        return userAddr;
    }

    /**
     * @dev Get user address by email
     * @param _email Email to lookup
     * @return User address
     */
    function getAddressByEmail(
        string calldata _email
    ) external view returns (address) {
        address userAddr = emailToAddress[_email];
        if (userAddr == address(0)) revert ProfileDoesNotExist();
        return userAddr;
    }

    /**
     * @dev Get user address by phone number
     * @param _phoneNumber Phone number to lookup
     * @return User address
     */
    function getAddressByPhoneNumber(
        string calldata _phoneNumber
    ) external view returns (address) {
        address userAddr = phoneNumberToAddress[_phoneNumber];
        if (userAddr == address(0)) revert ProfileDoesNotExist();
        return userAddr;
    }

    /**
     * @dev Get user address by account number
     * @param _accountId Account number to lookup
     * @return User address
     */
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

    /**
     * @dev Get full user details by any identifier (username, email, or phone number)
     * @param _identifier The identifier (username, email, or phone number as string)
     * @return userAddress User's wallet address
     * @return fullName User's full name
     * @return accountId User's unique account number
     * @return email User's email
     * @return phoneNumber User's phone number
     * @return username User's username
     */
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

        // First, try to find by username
        userAddr = usernameToAddress[_identifier];

        // If not found, try by email
        if (userAddr == address(0)) {
            userAddr = emailToAddress[_identifier];
        }

        // If not found, try by phone number
        if (userAddr == address(0)) {
            userAddr = phoneNumberToAddress[_identifier];
        }

        // If still not found, revert
        if (userAddr == address(0)) {
            revert ProfileDoesNotExist();
        }

        UserProfile storage profile = profiles[userAddr];
        return (
            profile.userAddress,
            profile.fullName,
            profile.accountId,
            profile.email,
            profile.phoneNumber,
            profile.username
        );
    }

    /**
     * @dev Get full user details by account number
     * @param _accountId The account number
     * @return userAddress User's wallet address
     * @return fullName User's full name
     * @return email User's email
     * @return phoneNumber User's phone number
     * @return username User's username
     */
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

        UserProfile storage profile = profiles[userAddr];
        return (
            profile.userAddress,
            profile.fullName,
            profile.email,
            profile.phoneNumber,
            profile.username
        );
    }

    /**
     * @dev Check if username is available
     * @param _username Username to check
     * @return True if available
     */
    function isUsernameAvailable(
        string calldata _username
    ) external view returns (bool) {
        return usernameToAddress[_username] == address(0);
    }

    /**
     * @dev Check if email is available
     * @param _email Email to check
     * @return True if available
     */
    function isEmailAvailable(
        string calldata _email
    ) external view returns (bool) {
        return emailToAddress[_email] == address(0);
    }

    /**
     * @dev Check if phone number is available
     * @param _phoneNumber Phone number to check
     * @return True if available
     */
    function isPhoneNumberAvailable(
        string calldata _phoneNumber
    ) external view returns (bool) {
        return phoneNumberToAddress[_phoneNumber] == address(0);
    }

    /**
     * @dev Check if address has a profile
     * @param _user User address
     * @return True if profile exists
     */
    function hasUserProfile(address _user) external view returns (bool) {
        return hasProfile[_user];
    }

    /**
     * @dev Get total number of profiles
     * @return Total number of profiles
     */
    function getTotalProfiles() external view returns (uint256) {
        return allUsers.length;
    }

    /**
     * @dev Get remaining account numbers available
     * @return Number of account numbers remaining
     */
    function getRemainingAccountIds() external view returns (uint256) {
        uint256 totalAvailable = ACCOUNT_ID_MAX - ACCOUNT_ID_START + 1;
        if (accountIdCounter >= totalAvailable) return 0;
        return totalAvailable - accountIdCounter;
    }

    /**
     * @dev returns contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
