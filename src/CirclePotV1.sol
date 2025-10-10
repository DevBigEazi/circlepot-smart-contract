// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CirclePotV1
 * @dev On-chain savings circles
 * @notice Implements community savings circles with collateral-backed commitments 
 */
contract CirclePotV1 is 
    Initializable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable, 
    UUPSUpgradeable 
{
    using SafeERC20 for IERC20;

    // ============ Version ============
    uint8 public constant VERSION = 1;

    // ============ Constants ============
    uint256 public constant PLATFORM_FEE_BPS = 20; // 0.2%
    uint256 public constant LATE_FEE_BPS = 100; // 1%
    uint256 public constant MAX_CONTRIBUTION = 5000e18;
    uint256 public constant MIN_CONTRIBUTION = 1e18;
    uint256 public constant MIN_MEMBERS = 5;
    uint256 public constant MAX_MEMBERS = 20;
    uint256 public constant FEATURED_CIRCLE_FEE = 1e18; // $1
    uint256 public constant VISIBILITY_UPDATE_FEE = 0.1e18; // $0.10

    // ============ Enums ============
    // Default state should be PENDING
    enum CircleState { PENDING, CREATED, ACTIVE, COMPLETED }
    enum Frequency { DAILY, WEEKLY, MONTHLY }
    enum Visibility { PUBLIC, PRIVATE }

    // ============ Structs ============
    struct Circle {
        uint256 circleId;
        address creator;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 maxMembers;
        uint256 currentMembers;
        uint256 currentRound;
        uint256 totalRounds;
        CircleState state;
        Visibility visibility;
        uint256 createdAt;
        uint256 startedAt;
        uint256 totalPot;
        bool isFeatured;
    }

    struct Member {
        uint256 position;
        uint256 totalContributed;
        bool hasReceivedPayout;
        bool isActive;
        uint256 collateralLocked;
        uint256 joinedAt;
    }

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

    struct CreateCircleParams {
        uint256 contributionAmount;
        Frequency frequency;
        uint256 maxMembers;
        Visibility visibility;
        bool isFeatured;
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
    address public treasury;
    
    uint256 public circleCounter;
    uint256 public goalCounter;
    
    mapping(uint256 => Circle) public circles;
    mapping(uint256 => mapping(address => Member)) public circleMembers;
    mapping(uint256 => address[]) public circleMemberList;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public roundContributions;
    mapping(uint256 => mapping(uint256 => uint256)) public circleRoundDeadlines;
    
    mapping(uint256 => PersonalGoal) public personalGoals;
    mapping(address => uint256[]) public userGoals;
    
    mapping(address => uint256) public userReputation;
    mapping(address => uint256) public completedCircles;
    mapping(address => uint256) public latePayments;
    
    uint256 public totalPlatformFees;
    uint256 public platformFeeBps;

    // ============ Events ============
    event ContractUpgraded(address indexed newImplementation, uint8 version);

    // ============ Errors ============
    error InvalidTreasuryAddress();


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with initial parameters
     * @param _cUSDToken Address of the cUSD token contract
     * @param _treasury Address of the treasury for platform fees
     * @param initialOwner Address of the initial owner (if zero, msg.sender remains owner)
     */
    function initialize(
        address _cUSDToken, 
        address _treasury, 
        address initialOwner
    ) 
        public 
        initializer 
    {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        if (_cUSDToken == address(0) || _treasury == address(0)) revert InvalidTreasuryAddress();
        
        cUSDToken = _cUSDToken;
        treasury = _treasury;
        circleCounter = 1;
        goalCounter = 1;
        platformFeeBps = PLATFORM_FEE_BPS;
        
        // transfer ownership if a different initialOwner was provided
        if (initialOwner != address(0) && initialOwner != owner()) {
            _transferOwnership(initialOwner);
        }
    }

    /**
     * @dev Function for upgrading the contract to a new version (reinitializer)
     * @param _cUSDToken Address of cUSD token (if changed)
     * @param _treasury Address of treasury (if changed)
     * @param _version Reinitializer version number
     */
    function upgrade(
        address _cUSDToken,
        address _treasury,
        uint8 _version
    ) public reinitializer(_version) onlyOwner {
        if (_cUSDToken != address(0)) {
            cUSDToken = _cUSDToken;
        }
        if (_treasury != address(0)) {
            treasury = _treasury;
        }
    }

    /**
     * @dev Authorizes upgrade to new implementation
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        emit ContractUpgraded(newImplementation, VERSION);
    }

    // ============ Circle Functions ============
}
