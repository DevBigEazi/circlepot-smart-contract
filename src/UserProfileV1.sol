// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title UserProfileV1
 * @dev User profile management contract with unique account id (account number)
 * @notice Manages user profile data including email, username, address, profile photo, and unique account number
 */
contract UserProfileV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // ============ Version ============
    uint256 public constant VERSION = 1;

    // ============ Constants ============
    uint256 public constant PHOTO_UPDATE_COOLDOWN = 30 days; // 1 month

    // Account ID generation constants
    uint256 private constant ACCOUNT_ID_START = 1000000000; // First 10-digit id
    uint256 private constant ACCOUNT_ID_MAX = 9999999999; // Last 10-digit id

    // ============ Structs ============
    struct UserProfile {
        address userAddress; // user address
        string email; // unique email
        string username; // unique username
        string fullName; // full name field
        string profilePhoto; // IPFS hash or URL
        uint256 accountId; // unique account id
        uint256 lastPhotoUpdate;
        uint256 createdAt;
    }

    // ============ Storage ============
    mapping(address => UserProfile) public profiles;
    mapping(string => address) public usernameToAddress; // Track usernames to ensure uniqueness
    mapping(string => address) public emailToAddress; // Track emails for lookup
    mapping(uint256 => address) public accountIdToAddress; // Track account numbers for lookup
    mapping(address => bool) public hasProfile;

    uint256 private accountIdCounter; // Counter for generating unique account numbers
    address[] public allUsers;

    // ============ Events ============
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event ProfileCreated(
        address indexed user,
        string indexed email,
        string indexed username,
        string fullName,
        uint256 accountId
    );
    event PhotoUpdated(address indexed user, string indexed photo);

    // ============ Errors ============
    error ProfileAlreadyExists();
    error ProfileDoesNotExist();
    error UsernameAlreadyTaken();
    error EmailAlreadyTaken();
    error PhotoUpdateCooldownNotMet();
    error OnlyProfileOwner();
    error EmptyUsername();
    error EmptyEmail();
    error EmptyFullName();
    error EmptyPhoto();
    error NoMoreAccountIdsAvailable();
    error InvalidAccountId();

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
     * @dev Function for upgrading the contract to a new version (reinitializer)
     * @param _version Reinitializer version number
     */
    function upgrade(uint8 _version) public reinitializer(_version) onlyOwner {
        // Version 1 - no upgrade logic needed yet
        // Future versions will add initialization logic here
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
     * @param _email User's email address
     * @param _username Unique username
     * @param _fullName User's full name
     * @param _profilePhoto Profile photo IPFS hash or URL (optional)
     */
    function createProfile(
        string calldata _email,
        string calldata _username,
        string calldata _fullName,
        string calldata _profilePhoto
    ) external {
        if (hasProfile[msg.sender]) revert ProfileAlreadyExists();
        if (bytes(_username).length == 0) revert EmptyUsername();
        if (bytes(_email).length == 0) revert EmptyEmail();
        if (bytes(_fullName).length == 0) revert EmptyFullName();

        // Check if username is already taken
        if (usernameToAddress[_username] != address(0)) {
            revert UsernameAlreadyTaken();
        }

        // Check if email is already taken
        if (emailToAddress[_email] != address(0)) {
            revert EmailAlreadyTaken();
        }

        // Generate unique account number
        if (accountIdCounter >= (ACCOUNT_ID_MAX - ACCOUNT_ID_START + 1)) {
            revert NoMoreAccountIdsAvailable();
        }

        uint256 accountId = _generateAccountId();

        profiles[msg.sender] = UserProfile({
            userAddress: msg.sender,
            email: _email,
            username: _username,
            fullName: _fullName,
            profilePhoto: _profilePhoto,
            accountId: accountId,
            lastPhotoUpdate: 0,
            createdAt: block.timestamp
        });

        usernameToAddress[_username] = msg.sender;
        emailToAddress[_email] = msg.sender;
        accountIdToAddress[accountId] = msg.sender;
        hasProfile[msg.sender] = true;
        allUsers.push(msg.sender);

        emit ProfileCreated(
            msg.sender,
            _email,
            _username,
            _fullName,
            accountId
        );
    }

    /**
     * @dev Update profile photo only (email, username, and full name are permanent, cannot be changed)
     * Note: Photo updates are restricted to once per month
     * @param _profilePhoto New profile photo IPFS hash or URL
     */
    function updatePhoto(string calldata _profilePhoto) external {
        if (!hasProfile[msg.sender]) revert ProfileDoesNotExist();
        if (bytes(_profilePhoto).length == 0) revert EmptyPhoto();

        UserProfile storage profile = profiles[msg.sender];

        // Check cooldown period
        uint256 timeSinceLastUpdate = block.timestamp - profile.lastPhotoUpdate;
        if (timeSinceLastUpdate < PHOTO_UPDATE_COOLDOWN) {
            revert PhotoUpdateCooldownNotMet();
        }

        profile.profilePhoto = _profilePhoto;
        profile.lastPhotoUpdate = block.timestamp;

        emit PhotoUpdated(msg.sender, _profilePhoto);
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
            uint256 accountId = (randomHash % (ACCOUNT_ID_MAX - ACCOUNT_ID_START + 1)) + ACCOUNT_ID_START;

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
     * @dev Get full user details by any identifier (username, email, or account number)
     * @param _identifier The identifier (username or email as string)
     * @return userAddress User's wallet address
     * @return fullName User's full name
     * @return accountId User's unique account number
     * @return email User's email
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

        // If still not found, revert
        if (userAddr == address(0)) {
            revert ProfileDoesNotExist();
        }

        UserProfile memory profile = profiles[userAddr];
        return (
            profile.userAddress,
            profile.fullName,
            profile.accountId,
            profile.email,
            profile.username
        );
    }

    /**
     * @dev Get full user details by account number
     * @param _accountId The account number
     * @return userAddress User's wallet address
     * @return fullName User's full name
     * @return email User's email
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

        UserProfile memory profile = profiles[userAddr];
        return (
            profile.userAddress,
            profile.fullName,
            profile.email,
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