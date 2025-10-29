// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title ReputationV1
 * @dev Centralized reputation management system for all platform contracts
 * @notice Manages user reputation scores across PersonalSavings, CircleSavings, and other contracts
 */
contract ReputationV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // ============ Version ============
    uint256 public constant VERSION = 1;

    // ============ Storage ============
    mapping(address => uint256) public userReputation;
    mapping(address => uint256) public completedCircles;
    mapping(address => uint256) public latePayments;
    mapping(address => bool) public authorizedContracts;

    // Track reputation sources for transparency
    mapping(address => string) public contractNames;
    address[] public authorizedContractsList;

    // ============ Events ============
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event ReputationIncreased(
        address indexed user,
        uint256 amount,
        uint256 newTotal,
        string source
    );
    event ReputationDecreased(
        address indexed user,
        uint256 amount,
        uint256 newTotal,
        string source
    );
    event CircleCompleted(address indexed user, uint256 totalCompleted);
    event LatePaymentRecorded(address indexed user, uint256 totalLatePayments);
    event ContractAuthorized(address indexed contractAddress, string name);
    event ContractDeauthorized(address indexed contractAddress);

    // ============ Errors ============
    error NotAuthorized();
    error ContractAlreadyAuthorized();
    error ContractNotAuthorized();
    error InvalidAddress();
    error InvalidAmount();

    // ============ Modifiers ============
    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized();
        }
        _;
    }

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

    // ============ Admin Functions ============
    /**
     * @dev Authorize a contract to update reputation
     * @param _contract Address of the contract to authorize
     * @param _name Name of the contract (e.g., "PersonalSavings", "CircleSavings")
     */
    function authorizeContract(
        address _contract,
        string calldata _name
    ) external onlyOwner {
        if (_contract == address(0)) revert InvalidAddress();
        if (authorizedContracts[_contract]) revert ContractAlreadyAuthorized();

        authorizedContracts[_contract] = true;
        contractNames[_contract] = _name;
        authorizedContractsList.push(_contract);

        emit ContractAuthorized(_contract, _name);
    }

    /**
     * @dev Deauthorize a contract from updating reputation
     * @param _contract Address of the contract to deauthorize
     */
    function deauthorizeContract(address _contract) external onlyOwner {
        if (!authorizedContracts[_contract]) revert ContractNotAuthorized();

        authorizedContracts[_contract] = false;

        emit ContractDeauthorized(_contract);
    }

    // ============ Reputation Management Functions ============
    /**
     * @dev Increase user's reputation
     * @param _user User address
     * @param _amount Amount to increase
     * @param _source Source description (e.g., "Goal Completed")
     */
    function increaseReputation(
        address _user,
        uint256 _amount,
        string calldata _source
    ) external onlyAuthorized {
        if (_user == address(0)) revert InvalidAddress();
        if (_amount == 0) revert InvalidAmount();

        userReputation[_user] += _amount;

        emit ReputationIncreased(
            _user,
            _amount,
            userReputation[_user],
            _source
        );
    }

    /**
     * @dev Decrease user's reputation
     * @param _user User address
     * @param _amount Amount to decrease
     * @param _source Source description (e.g., "Early Withdrawal")
     */
    function decreaseReputation(
        address _user,
        uint256 _amount,
        string calldata _source
    ) external onlyAuthorized {
        if (_user == address(0)) revert InvalidAddress();
        if (_amount == 0) revert InvalidAmount();

        if (userReputation[_user] > _amount) {
            userReputation[_user] -= _amount;
        } else {
            userReputation[_user] = 0;
        }

        emit ReputationDecreased(
            _user,
            _amount,
            userReputation[_user],
            _source
        );
    }

    /**
     * @dev Record a completed circle for a user
     * @param _user User address
     */
    function recordCircleCompleted(address _user) external onlyAuthorized {
        if (_user == address(0)) revert InvalidAddress();

        completedCircles[_user]++;

        emit CircleCompleted(_user, completedCircles[_user]);
    }

    /**
     * @dev Record a late payment for a user
     * @param _user User address
     */
    function recordLatePayment(address _user) external onlyAuthorized {
        if (_user == address(0)) revert InvalidAddress();

        latePayments[_user]++;

        emit LatePaymentRecorded(_user, latePayments[_user]);
    }

    /**
     * @dev Batch update reputation for multiple users (gas efficient)
     * @param _users Array of user addresses
     * @param _amounts Array of amounts (positive for increase, negative for decrease)
     * @param _source Source description
     */
    function batchUpdateReputation(
        address[] calldata _users,
        int256[] calldata _amounts,
        string calldata _source
    ) external onlyAuthorized {
        require(_users.length == _amounts.length, "Length mismatch");

        for (uint256 i = 0; i < _users.length; i++) {
            if (_users[i] == address(0)) continue;
            if (_amounts[i] == 0) continue;

            if (_amounts[i] > 0) {
                uint256 amount = uint256(_amounts[i]);
                userReputation[_users[i]] += amount;
                emit ReputationIncreased(
                    _users[i],
                    amount,
                    userReputation[_users[i]],
                    _source
                );
            } else {
                uint256 amount = uint256(-_amounts[i]);
                if (userReputation[_users[i]] > amount) {
                    userReputation[_users[i]] -= amount;
                } else {
                    userReputation[_users[i]] = 0;
                }
                emit ReputationDecreased(
                    _users[i],
                    amount,
                    userReputation[_users[i]],
                    _source
                );
            }
        }
    }

    // ============ View Functions ============
    /**
     * @dev Get user's reputation score
     * @param _user User address
     * @return Reputation score
     */
    function getReputation(address _user) external view returns (uint256) {
        return userReputation[_user];
    }

    /**
     * @dev Get comprehensive reputation data for a user
     * @param _user User address
     * @return reputation Total reputation score
     * @return circlesCompleted Number of circles completed
     * @return latePaymentsCount Number of late payments
     * @return reputationScore Calculated score (reputation + circles bonus)
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
        )
    {
        reputation = userReputation[_user];
        circlesCompleted = completedCircles[_user];
        latePaymentsCount = latePayments[_user];
        // Calculate weighted score (circles worth 10x more)
        reputationScore = reputation + (circlesCompleted * 10);

        return (
            reputation,
            circlesCompleted,
            latePaymentsCount,
            reputationScore
        );
    }

    /**
     * @dev Check if a contract is authorized
     * @param _contract Contract address
     * @return True if authorized
     */
    function isAuthorized(address _contract) external view returns (bool) {
        return authorizedContracts[_contract];
    }

    /**
     * @dev Get all authorized contracts
     * @return Array of authorized contract addresses
     */
    function getAuthorizedContracts() external view returns (address[] memory) {
        return authorizedContractsList;
    }

    /**
     * @dev Get name of an authorized contract
     * @param _contract Contract address
     * @return Contract name
     */
    function getContractName(
        address _contract
    ) external view returns (string memory) {
        return contractNames[_contract];
    }

    /**
     * @dev Returns contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
