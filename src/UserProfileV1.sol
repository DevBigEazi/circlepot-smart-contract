// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title UserProfileV1
 * @dev User profile management contract
 * @notice Manages user profile data including email, username, address, and profile photo
 */
contract UserProfileV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // ============ Version ============
    uint256 public constant VERSION = 1;

    // ============ Constants ============
    uint256 public constant USERNAME_UPDATE_COOLDOWN = 30 days; // 1 month

    // ============ Structs ============
    struct UserProfile {
        address userAddress;
        string email;
        string username;
        string profilePhoto; // IPFS hash or URL
        uint256 lastUsernameUpdate;
        uint256 lastPhotoUpdate;
        uint256 createdAt;
    }

    // ============ Storage ============
    mapping(address => UserProfile) public profiles;
    mapping(string => address) public usernameToAddress; // Track usernames to ensure uniqueness
    mapping(address => bool) public hasProfile;

    address[] public allUsers;

    // ============ Events ============
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event ProfileCreated(address indexed user, string email, string username);
    event UsernameUpdated(
        address indexed user,
        string oldUsername,
        string newUsername
    );
    event PhotoUpdated(address indexed user, string photo);

    // ============ Errors ============
    error ProfileAlreadyExists();
    error ProfileDoesNotExist();
    error UsernameAlreadyTaken();
    error UsernameUpdateCooldownNotMet();
    error OnlyProfileOwner();
    error EmptyUsername();
    error EmptyEmail();
    error EmptyPhoto();

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
        __UUPSUpgradeable_init();

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
        // Add any upgrade logic here if needed
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
     * @dev Create a new user profile
     * @param _email User's email address
     * @param _username Unique username
     * @param _profilePhoto Profile photo IPFS hash or URL
     */
    function createProfile(
        string calldata _email,
        string calldata _username,
        string calldata _profilePhoto
    ) external {
        if (hasProfile[msg.sender]) revert ProfileAlreadyExists();
        if (bytes(_username).length == 0) revert EmptyUsername();
        if (bytes(_email).length == 0) revert EmptyEmail();
        if (bytes(_profilePhoto).length == 0) revert EmptyPhoto();

        // Check if username is already taken
        if (usernameToAddress[_username] != address(0)) {
            revert UsernameAlreadyTaken();
        }

        profiles[msg.sender] = UserProfile({
            userAddress: msg.sender,
            email: _email,
            username: _username,
            profilePhoto: _profilePhoto,
            lastUsernameUpdate: 0,
            lastPhotoUpdate: 0,
            createdAt: block.timestamp
        });

        usernameToAddress[_username] = msg.sender;
        hasProfile[msg.sender] = true;
        allUsers.push(msg.sender);

        emit ProfileCreated(msg.sender, _email, _username);
    }

    /**
     * @dev Update profile photo only (email is permanent, cannot be changed)
     * Note: Photo updates are restricted to once per month
     * @param _profilePhoto New profile photo IPFS hash or URL
     */
    function updatePhoto(string calldata _profilePhoto) external {
        if (!hasProfile[msg.sender]) revert ProfileDoesNotExist();
        if (bytes(_profilePhoto).length == 0) revert EmptyPhoto();

        UserProfile storage profile = profiles[msg.sender];

        // Check cooldown period
        uint256 timeSinceLastUpdate = block.timestamp - profile.lastPhotoUpdate;
        if (timeSinceLastUpdate < USERNAME_UPDATE_COOLDOWN) {
            revert UsernameUpdateCooldownNotMet();
        }

        profile.profilePhoto = _profilePhoto;
        profile.lastPhotoUpdate = block.timestamp;

        emit PhotoUpdated(msg.sender, _profilePhoto);
    }

    /**
     * @dev Update username (can only be done once per month)
     * @param _newUsername New username
     */
    function updateUsername(string calldata _newUsername) external {
        if (!hasProfile[msg.sender]) revert ProfileDoesNotExist();
        if (bytes(_newUsername).length == 0) revert EmptyUsername();

        // Check if username is already taken
        if (
            usernameToAddress[_newUsername] != address(0) &&
            usernameToAddress[_newUsername] != msg.sender
        ) {
            revert UsernameAlreadyTaken();
        }

        UserProfile storage profile = profiles[msg.sender];

        // Check cooldown period (skip if this is first update)
        if (profile.lastUsernameUpdate != 0) {
            uint256 timeSinceLastUpdate = block.timestamp -
                profile.lastUsernameUpdate;
            if (timeSinceLastUpdate < USERNAME_UPDATE_COOLDOWN) {
                revert UsernameUpdateCooldownNotMet();
            }
        }

        string memory oldUsername = profile.username;

        // Free the old username
        usernameToAddress[oldUsername] = address(0);

        // Set the new username
        profile.username = _newUsername;
        usernameToAddress[_newUsername] = msg.sender;
        profile.lastUsernameUpdate = block.timestamp;

        emit UsernameUpdated(msg.sender, oldUsername, _newUsername);
    }

    /**
     * @dev Update both username and profile photo at once. At least one must be provided.
     * @param _newUsername New username (optional, pass empty string to skip)
     * @param _newPhoto New profile photo IPFS hash or URL (optional, pass empty string to skip)
     */
    function updateProfile(
        string calldata _newUsername,
        string calldata _newPhoto
    ) external {
        if (!hasProfile[msg.sender]) revert ProfileDoesNotExist();
        if (bytes(_newUsername).length == 0 && bytes(_newPhoto).length == 0)
            revert EmptyUsername();

        UserProfile storage profile = profiles[msg.sender];

        // Handle username update if provided
        if (bytes(_newUsername).length > 0) {
            // Check if username is already taken
            if (
                usernameToAddress[_newUsername] != address(0) &&
                usernameToAddress[_newUsername] != msg.sender
            ) {
                revert UsernameAlreadyTaken();
            }

            // Check username cooldown period
            uint256 timeSinceLastUsernameUpdate = block.timestamp -
                profile.lastUsernameUpdate;
            if (timeSinceLastUsernameUpdate < USERNAME_UPDATE_COOLDOWN) {
                revert UsernameUpdateCooldownNotMet();
            }

            string memory oldUsername = profile.username;

            // Free the old username
            usernameToAddress[oldUsername] = address(0);

            // Set the new username
            profile.username = _newUsername;
            usernameToAddress[_newUsername] = msg.sender;
            profile.lastUsernameUpdate = block.timestamp;

            emit UsernameUpdated(msg.sender, oldUsername, _newUsername);
        }

        // Handle photo update if provided
        if (bytes(_newPhoto).length > 0) {
            // Check photo cooldown period
            uint256 timeSinceLastPhotoUpdate = block.timestamp -
                profile.lastPhotoUpdate;
            if (timeSinceLastPhotoUpdate < USERNAME_UPDATE_COOLDOWN) {
                revert UsernameUpdateCooldownNotMet();
            }

            profile.profilePhoto = _newPhoto;
            profile.lastPhotoUpdate = block.timestamp;

            emit PhotoUpdated(msg.sender, _newPhoto);
        }
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
     * @dev Check if address has a profile
     * @param _user User address
     * @return True if profile exists
     */
    function hasUserProfile(address _user) external view returns (bool) {
        return hasProfile[_user];
    }

    /**
     * @dev Get time until user can update username again
     * @param _user User address
     * @return Time in seconds until next update allowed
     */
    function getUsernameUpdateCooldownRemaining(
        address _user
    ) external view returns (uint256) {
        if (!hasProfile[_user]) revert ProfileDoesNotExist();

        UserProfile storage profile = profiles[_user];
        uint256 timeSinceLastUpdate = block.timestamp -
            profile.lastUsernameUpdate;

        if (timeSinceLastUpdate >= USERNAME_UPDATE_COOLDOWN) {
            return 0;
        }

        return USERNAME_UPDATE_COOLDOWN - timeSinceLastUpdate;
    }

    /**
     * @dev Get total number of profiles
     * @return Total number of profiles
     */
    function getTotalProfiles() external view returns (uint256) {
        return allUsers.length;
    }

    /**
     * @dev returns contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
