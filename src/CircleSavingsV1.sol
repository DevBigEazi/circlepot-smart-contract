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
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title CircleSavingsV1
 * @dev On-chain savings circles with centralized reputation management
 * @notice Implements community savings circles with collateral-backed commitments, voting, and invitations
 */
contract CircleSavingsV1 is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Version ============
    uint256 public constant VERSION = 1;

    // ============ Constants ============
    uint256 public constant PLATFORM_FEE_BPS = 100; // 1% for payouts ≤ $1000
    uint256 public constant FIXED_FEE_THRESHOLD = 1000e18; // $1000 threshold
    uint256 public constant FIXED_FEE_AMOUNT = 10e18; // $10 fixed fee for payouts
    uint256 public constant LATE_FEE_BPS = 100; // 1%
    uint256 public constant MAX_CONTRIBUTION = 5000e18;
    uint256 public constant MIN_CONTRIBUTION = 1e18;
    uint256 public constant MIN_MEMBERS = 5;
    uint256 public constant MAX_MEMBERS = 20;
    uint256 public constant VISIBILITY_UPDATE_FEE = 0.5e18; // $0.50
    uint256 public constant VOTING_PERIOD = 2 days;
    uint256 public constant START_VOTE_THRESHOLD = 5100; //51% IN BASIS POINTS
    uint256 public constant PRIVATE_CIRCLE_DEAD_FEE = 1e18; // $1 fee for dead private circles
    uint256 public constant PUBLIC_CIRCLE_DEAD_FEE = 0.5e18; // $0.50 fee for dead public circles

    // ============ Enums ============
    enum CircleState {
        PENDING,
        CREATED,
        VOTING,
        ACTIVE,
        COMPLETED,
        DEAD
    }
    enum Frequency {
        DAILY,
        WEEKLY,
        MONTHLY
    }
    enum Visibility {
        PRIVATE,
        PUBLIC
    }
    enum VoteChoice {
        NONE,
        START,
        WITHDRAW
    }

    // ============ Structs ============
    struct CircleConfig {
        uint256 circleId;
        string title; // max of 32 characters
        string description; // IPFS hash
        address creator;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 maxMembers;
        Visibility visibility;
        uint256 createdAt;
        bool isYieldEnabled; // true = yield circle, false = standard (no DeFi risk)
    }

    struct CircleStatus {
        CircleState state;
        uint256 currentMembers;
        uint256 currentRound;
        uint256 totalRounds;
        uint256 startedAt;
        uint256 totalPot;
        uint256 contributionsThisRound; // Track contributions
    }

    struct Member {
        uint256 position;
        uint256 totalContributed;
        bool hasReceivedPayout;
        bool isActive;
        uint256 collateralLocked;
        uint256 joinedAt;
        uint256 performancePoints;
    }

    struct CreateCircleParams {
        string title;
        string description;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 maxMembers;
        Visibility visibility;
        bool enableYield; // User choice - true for yield, false for standard
    }

    struct Vote {
        uint256 votingStartTime;
        uint256 votingEndTime;
        uint256 startVoteCount;
        uint256 withdrawVoteCount;
        bool votingActive;
        bool voteExecuted;
        uint256 totalEligibleVoters; // Track total members for early execution
    }

    // ============ Storage ============
    address public USDmToken;
    address public treasury;
    address public reputationContract;

    uint256 public circleCounter;

    // Circle related storage
    mapping(uint256 => CircleConfig) public circleConfigs;
    mapping(uint256 => CircleStatus) public circleStatus;
    mapping(uint256 => mapping(address => Member)) public circleMembers;
    mapping(uint256 => address[]) public circleMemberList;
    mapping(uint256 => mapping(uint256 => mapping(address => bool)))
        public roundContributions;
    mapping(uint256 => mapping(uint256 => uint256)) public circleRoundDeadlines;

    // Voting storage
    mapping(uint256 => Vote) public circleVotes;
    mapping(uint256 => mapping(address => VoteChoice)) public memberVotes;

    // Invitation storage for private circles
    mapping(uint256 => mapping(address => bool)) public circleInvitations;

    uint256 public totalPlatformFees;
    uint256 public platformFeeBps;
    uint256 public fixedFeeThreshold;

    // Yield and Performance storage
    address public vault;
    mapping(uint256 => uint256) public circleShares;
    mapping(uint256 => uint256) public circleLateFeePool;
    mapping(uint256 => uint256) public totalCirclePoints;
    uint256 public constant PLATFORM_YIELD_SHARE_BPS = 1000; // 10%

    // ============ Events ============
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event VisibilityUpdated(
        uint256 indexed circleId,
        address indexed creator,
        Visibility newVisibility
    );
    event CircleCreated(
        uint256 indexed circleId,
        string title,
        string description,
        address indexed creator,
        uint256 indexed contributionAmount,
        Frequency frequency,
        uint256 maxMembers,
        Visibility visibility,
        uint256 createdAt,
        uint256 collateralLocked
    );
    event CircleJoined(
        uint256 indexed circleId,
        address indexed member,
        uint256 indexed currentMembers,
        CircleState state
    );
    event CircleStarted(
        uint256 indexed circleId,
        uint256 startedAt,
        CircleState state
    );
    event PayoutDistributed(
        uint256 indexed circleId,
        uint256 indexed round,
        address indexed recipient,
        uint256 amount
    );
    event PositionAssigned(
        uint256 indexed circleId,
        address indexed member,
        uint256 position
    );
    event CollateralWithdrawn(
        uint256 indexed circleId,
        address indexed member,
        uint256 amount
    );
    event VotingInitiated(
        uint256 indexed circleId,
        uint256 indexed votingStartTime,
        uint256 indexed votingEndTime
    );
    event VoteCast(
        uint256 indexed circleId,
        address indexed voter,
        VoteChoice choice
    );
    event MemberInvited(
        uint256 indexed circleId,
        address indexed creator,
        address indexed invitee,
        uint256 invitedAt
    );
    event VoteExecuted(
        uint256 indexed circleId,
        bool circleStarted,
        uint256 startVoteCount,
        uint256 withdrawVoteCount
    );
    event ContributionMade(
        uint256 indexed circleId,
        uint256 round,
        address member,
        uint256 indexed amount
    );
    event MemberForfeited(
        uint256 indexed circleId,
        uint256 round,
        address member,
        uint256 indexed deduction,
        address indexed forfeiter
    );
    event CollateralReturned(
        uint256 indexed circleId,
        address indexed member,
        uint256 indexed amount
    );
    event DeadCircleFeeDeducted(
        uint256 indexed circleId,
        address indexed creator,
        uint256 indexed amount
    );
    event ReputationContractUpdated(address indexed newContract);
    event PointsAwarded(
        uint256 indexed circleId,
        address indexed member,
        uint256 points,
        string reason
    );
    event YieldDistributed(
        uint256 indexed circleId,
        uint256 totalSurplus,
        uint256 platformShare,
        uint256 communityShare
    );
    event LateFeeAddedToPool(
        uint256 indexed circleId,
        address indexed member,
        uint256 amount
    );
    event MemberRewardClaimed(
        uint256 indexed circleId,
        address indexed member,
        uint256 rewardAmount
    );
    event VaultUpdated(address indexed newVault);

    // ============ Errors ============
    error InvalidContributionAmount();
    error InvalidMemberCount();
    error AddressZeroNotAllowed();
    error TitleTooShortOrLong();
    error InvalidCircle();
    error OnlyCreator();
    error CircleNotExist();
    error SameVisibility();
    error CircleNotOpen();
    error AlreadyJoined();
    error MinMembersNotReached();
    error UltimatumNotReached();
    error UltimatumNotPassed();
    error NotActiveMember();
    error VotingStillActive();
    error VotingAlreadyExecuted();
    error InvalidVoteChoice();
    error VotingNotActive();
    error VotingPeriodEnded();
    error AlreadyVoted();
    error VoteAlreadyExecuted();
    error CircleNotPrivate();
    error NotInvited();
    error CircleNotActive();
    error AlreadyContributed();
    error InsufficientCollateral();
    error GracePeriodNotExpired();
    error NotNextRecipient();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with initial parameters
     * @param _USDmToken Address of the USDm token contract
     * @param _treasury Address of the treasury for platform fees
     * @param _reputationContract Address of the reputation contract
     * @param initialOwner Address of the initial owner (if zero, msg.sender remains owner)
     */
    function initialize(
        address _USDmToken,
        address _treasury,
        address _reputationContract,
        address _vault,
        address initialOwner
    ) public initializer {
        __Ownable_init(initialOwner);

        if (
            _USDmToken == address(0) ||
            _treasury == address(0) ||
            _reputationContract == address(0)
        ) {
            revert AddressZeroNotAllowed();
        }

        USDmToken = _USDmToken;
        treasury = _treasury;
        reputationContract = _reputationContract;
        vault = _vault;
        circleCounter = 1;
        platformFeeBps = PLATFORM_FEE_BPS;
        fixedFeeThreshold = FIXED_FEE_THRESHOLD;

        if (initialOwner != address(0) && initialOwner != owner()) {
            _transferOwnership(initialOwner);
        }
    }

    /**
     * @dev Function for upgrading the contract to a new version (reinitializer)
     * @param _USDmToken Address of USDm token (if changed)
     * @param _treasury Address of treasury (if changed)
     * @param _reputationContract Address of reputation contract (if changed)
     * @param _version Reinitializer version number
     */
    function upgrade(
        address _USDmToken,
        address _treasury,
        address _reputationContract,
        uint8 _version
    ) public reinitializer(_version) onlyOwner {
        if (_USDmToken != address(0)) {
            USDmToken = _USDmToken;
        }
        if (_treasury != address(0)) {
            treasury = _treasury;
        }
        if (_reputationContract != address(0)) {
            reputationContract = _reputationContract;
        }
        // Vault is handled separately or in next upgrade
    }

    /**
     * @dev Update the vault address (admin only)
     * @param _newVault New vault address
     */
    function updateVault(address _newVault) external onlyOwner {
        if (_newVault == address(0)) revert AddressZeroNotAllowed();
        vault = _newVault;
        emit VaultUpdated(_newVault);
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

    /**
     * @dev Update reputation contract address (admin only)
     * @param _newReputationContract New reputation contract address
     */
    function updateReputationContract(
        address _newReputationContract
    ) external onlyOwner {
        if (_newReputationContract == address(0)) {
            revert AddressZeroNotAllowed();
        }
        reputationContract = _newReputationContract;
        emit ReputationContractUpdated(_newReputationContract);
    }

    // ============ Circle Functions ============
    /**
     * @dev Create a new saving circle
     * @param params Circle creation parameters
     * @return Return new saving circle id created
     */
    function createCircle(
        CreateCircleParams calldata params
    ) external nonReentrant returns (uint256) {
        if (msg.sender == address(0)) revert AddressZeroNotAllowed();
        if (
            params.contributionAmount < MIN_CONTRIBUTION ||
            params.contributionAmount > MAX_CONTRIBUTION
        ) {
            revert InvalidContributionAmount();
        }
        if (
            params.maxMembers < MIN_MEMBERS || params.maxMembers > MAX_MEMBERS
        ) {
            revert InvalidMemberCount();
        }

        if (
            bytes(params.title).length == 0 || bytes(params.title).length > 32
        ) {
            revert TitleTooShortOrLong();
        }

        uint256 circleId = circleCounter++;
        uint256 collateral;

        {
            collateral = _calcCollateral(
                params.contributionAmount,
                params.maxMembers
            );
            uint256 totalRequired = collateral;

            // Only public circles pay visibility fee at creation
            if (params.visibility == Visibility.PUBLIC) {
                totalRequired += VISIBILITY_UPDATE_FEE;
                totalPlatformFees += VISIBILITY_UPDATE_FEE;
                emit VisibilityUpdated(circleId, msg.sender, params.visibility);
            }

            IERC20(USDmToken).safeTransferFrom(
                msg.sender,
                address(this),
                totalRequired
            );
        }

        // Initialize Config using storage pointer to save stack
        {
            CircleConfig storage conf = circleConfigs[circleId];
            conf.circleId = circleId;
            conf.title = params.title;
            conf.description = params.description;
            conf.creator = msg.sender;
            conf.contributionAmount = params.contributionAmount;
            conf.frequency = params.frequency;
            conf.maxMembers = params.maxMembers;
            conf.visibility = params.visibility;
            conf.createdAt = block.timestamp;
            conf.isYieldEnabled = params.enableYield;
        }

        // Initialize Status using storage pointer
        {
            CircleStatus storage stat = circleStatus[circleId];
            stat.state = CircleState.CREATED;
            stat.currentMembers = 1;
            stat.currentRound = 0;
            stat.totalRounds = 1;
            stat.startedAt = 0;
            stat.totalPot = 0;
            stat.contributionsThisRound = 0;
        }

        // Only deposit to vault if yield is enabled
        if (params.enableYield && vault != address(0) && collateral > 0) {
            IERC20(USDmToken).approve(vault, collateral);
            circleShares[circleId] = IERC4626(vault).deposit(
                collateral,
                address(this)
            );
        }

        // Initialize Member
        {
            Member storage m = circleMembers[circleId][msg.sender];
            m.position = 0;
            m.totalContributed = 0;
            m.hasReceivedPayout = false;
            m.isActive = true;
            m.collateralLocked = collateral;
            m.joinedAt = block.timestamp;
            m.performancePoints = 0;
        }

        circleMemberList[circleId].push(msg.sender);

        emit CircleCreated(
            circleId,
            params.title,
            params.description,
            msg.sender,
            params.contributionAmount,
            params.frequency,
            params.maxMembers,
            params.visibility,
            block.timestamp,
            collateral // Use local variable to avoid mapping lookup on stack
        );
        emit CircleJoined(circleId, msg.sender, 1, CircleState.CREATED);

        return circleId;
    }

    /**
     * @dev Update the circle visibility (private/public)
     * @param _circleId Circle ID
     * @param _newVisibility New visibility setting
     */
    function updateCircleVisibility(
        uint256 _circleId,
        Visibility _newVisibility
    ) external nonReentrant {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        CircleConfig storage conf = circleConfigs[_circleId];
        CircleStatus storage stat = circleStatus[_circleId];

        if (conf.creator != msg.sender) revert OnlyCreator();
        if (stat.state != CircleState.CREATED) revert CircleNotExist();
        if (conf.visibility == _newVisibility) revert SameVisibility();

        IERC20(USDmToken).safeTransferFrom(
            msg.sender,
            address(this),
            VISIBILITY_UPDATE_FEE
        );
        totalPlatformFees += VISIBILITY_UPDATE_FEE;

        conf.visibility = _newVisibility;

        emit VisibilityUpdated(_circleId, msg.sender, conf.visibility);
    }

    /**
     * @dev Invite members to a private circle (only creator)
     * @param _circleId Circle ID
     * @param _invitees Array of addresses to invite
     */
    function inviteMembers(
        uint256 _circleId,
        address[] calldata _invitees
    ) external {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        CircleConfig storage conf = circleConfigs[_circleId];
        CircleStatus storage stat = circleStatus[_circleId];

        if (conf.creator != msg.sender) revert OnlyCreator();
        if (conf.visibility != Visibility.PRIVATE) revert CircleNotPrivate();
        if (
            stat.state != CircleState.CREATED &&
            stat.state != CircleState.VOTING
        ) revert InvalidCircle();

        for (uint256 i = 0; i < _invitees.length; i++) {
            circleInvitations[_circleId][_invitees[i]] = true;
            emit MemberInvited(
                _circleId,
                msg.sender,
                _invitees[i],
                block.timestamp
            );
        }
    }

    function joinCircle(uint256 _circleId) external nonReentrant {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        CircleConfig storage conf = circleConfigs[_circleId];
        CircleStatus storage stat = circleStatus[_circleId];

        if (stat.currentMembers == conf.maxMembers) revert CircleNotOpen();
        if (circleMembers[_circleId][msg.sender].isActive) {
            revert AlreadyJoined();
        }
        if (
            stat.state != CircleState.CREATED &&
            stat.state != CircleState.VOTING
        ) revert InvalidCircle();

        if (conf.visibility == Visibility.PRIVATE) {
            if (!circleInvitations[_circleId][msg.sender]) revert NotInvited();
        }

        uint256 collateral = _calcCollateral(
            conf.contributionAmount,
            conf.maxMembers
        );

        IERC20(USDmToken).safeTransferFrom(
            msg.sender,
            address(this),
            collateral
        );

        // Initialize Member using storage pointer to save stack
        {
            Member storage m = circleMembers[_circleId][msg.sender];
            m.position = 0;
            m.totalContributed = 0;
            m.hasReceivedPayout = false;
            m.isActive = true;
            m.collateralLocked = collateral;
            m.joinedAt = block.timestamp;
            m.performancePoints = 0;
        }

        // Only deposit to vault if this circle has yield enabled
        if (conf.isYieldEnabled && vault != address(0) && collateral > 0) {
            IERC20(USDmToken).approve(vault, collateral);
            circleShares[_circleId] += IERC4626(vault).deposit(
                collateral,
                address(this)
            );
        }

        circleMemberList[_circleId].push(msg.sender);

        stat.currentMembers++;
        stat.totalRounds = stat.currentMembers;

        emit CircleJoined(
            _circleId,
            msg.sender,
            stat.currentMembers,
            stat.state
        );

        if (stat.currentMembers == conf.maxMembers) {
            _startCircleInternal(_circleId);
            emit CircleStarted(_circleId, block.timestamp, stat.state);
        }
    }

    /**
     * @dev Initiates voting to decide if circle should start after ultimatum period
     * @param _circleId Circle ID
     */
    function initiateVoting(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        CircleConfig storage conf = circleConfigs[_circleId];
        CircleStatus storage stat = circleStatus[_circleId];

        if (stat.state != CircleState.CREATED) revert InvalidCircle();

        if (stat.currentMembers < (conf.maxMembers * 60) / 100) {
            revert MinMembersNotReached();
        }

        uint256 ultimatumPeriod = _ultimatum(conf.frequency);
        if (block.timestamp < conf.createdAt + ultimatumPeriod) {
            revert UltimatumNotReached();
        }

        Vote storage vote = circleVotes[_circleId];
        if (vote.votingActive) revert VotingStillActive();
        if (vote.voteExecuted) revert VotingAlreadyExecuted();

        vote.votingStartTime = block.timestamp;
        vote.votingEndTime = block.timestamp + VOTING_PERIOD;
        vote.startVoteCount = 0;
        vote.withdrawVoteCount = 0;
        vote.votingActive = true;
        vote.voteExecuted = false;
        vote.totalEligibleVoters = stat.currentMembers; // Track total for early execution

        stat.state = CircleState.VOTING;

        emit VotingInitiated(
            _circleId,
            vote.votingStartTime,
            vote.votingEndTime
        );
    }

    /**
     * @dev Cast vote to decide if circle should start
     * @param _circleId Circle ID
     * @param _choice Vote choice for the members (START or WITHDRAW)
     */
    function castVote(uint256 _circleId, VoteChoice _choice) external {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }
        if (_choice == VoteChoice.NONE) revert InvalidVoteChoice();

        CircleStatus storage stat = circleStatus[_circleId];
        if (stat.state != CircleState.VOTING) revert VotingNotActive();

        Member storage m = circleMembers[_circleId][msg.sender];
        if (!m.isActive) revert NotActiveMember();

        Vote storage vote = circleVotes[_circleId];
        if (!vote.votingActive) revert VotingNotActive();
        if (block.timestamp > vote.votingEndTime) revert VotingPeriodEnded();

        VoteChoice previousVote = memberVotes[_circleId][msg.sender];
        if (previousVote != VoteChoice.NONE) revert AlreadyVoted();

        memberVotes[_circleId][msg.sender] = _choice;

        if (_choice == VoteChoice.START) {
            vote.startVoteCount++;
        } else {
            vote.withdrawVoteCount++;
        }

        emit VoteCast(_circleId, msg.sender, _choice);

        // Check if all members have voted for early execution
        uint256 totalVotes = vote.startVoteCount + vote.withdrawVoteCount;
        if (totalVotes == vote.totalEligibleVoters) {
            // All members voted - execute immediately
            _executeVoteInternal(_circleId);
        }
    }

    /**
     * @dev execute vote result after voting period ends
     * @param _circleId Circle ID
     */
    function executeVote(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        CircleStatus storage stat = circleStatus[_circleId];
        if (stat.state != CircleState.VOTING) revert VotingNotActive();

        Vote storage vote = circleVotes[_circleId];
        if (!vote.votingActive) revert VotingNotActive();
        if (block.timestamp <= vote.votingEndTime) revert VotingStillActive();
        if (vote.voteExecuted) revert VoteAlreadyExecuted();

        _executeVoteInternal(_circleId);
    }

    /**
     * @dev Each member can withdraw their collateral if after the ultimatum, circle did not start
     * @param _circleId Circle ID to withdraw from
     * @notice Withdrawal is allowed in these scenarios:
     *   1. After voting completes and withdraw votes won (canWithdrawAfterVote)
     *   2. After ultimatum period AND below 60% threshold (no voting needed)
     *      - This includes solo creator (1 member < 60% of maxMembers)
     *      - Or any circle that didn't reach minimum membership
     */
    function WithdrawCollateral(uint256 _circleId) external nonReentrant {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        CircleConfig storage conf = circleConfigs[_circleId];
        CircleStatus storage stat = circleStatus[_circleId];

        if (stat.state != CircleState.CREATED && stat.state != CircleState.DEAD)
            revert InvalidCircle();

        Member storage m = circleMembers[_circleId][msg.sender];
        if (!m.isActive) revert NotActiveMember();

        Vote storage vote = circleVotes[_circleId];

        bool canTriggerBulkWithdraw = false;

        // Scenario 1: Voting happened and withdraw side won
        if (vote.voteExecuted && canWithdrawAfterVote(_circleId)) {
            canTriggerBulkWithdraw = true;
        }
        // Scenario 2: Ultimatum passed AND below 60% threshold (no voting needed)
        else {
            uint256 period = _ultimatum(conf.frequency);
            if (block.timestamp > conf.createdAt + period) {
                if (stat.currentMembers < (conf.maxMembers * 60) / 100) {
                    canTriggerBulkWithdraw = true;
                }
            }
        }

        if (!canTriggerBulkWithdraw) revert UltimatumNotPassed();

        // One trigger releases for everyone and marks circle as DEAD
        _releaseDeadCircleCollateral(_circleId);
    }

    /**
     * @dev Member contribute to the current round
     * @param _circleId Circle ID
     */
    function contribute(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();

        CircleConfig storage conf = circleConfigs[_circleId];
        CircleStatus storage stat = circleStatus[_circleId];

        if (stat.state != CircleState.ACTIVE) revert CircleNotActive();

        Member storage m = circleMembers[_circleId][msg.sender];
        if (!m.isActive) revert NotActiveMember();

        uint256 round = stat.currentRound;

        if (roundContributions[_circleId][round][msg.sender])
            revert AlreadyContributed();

        uint256 deadline = circleRoundDeadlines[_circleId][round];
        uint256 gracePeriod = _getGracePeriod(conf.frequency);
        uint256 graceDeadline = deadline + gracePeriod;

        bool afterGrace = block.timestamp > graceDeadline;

        if (afterGrace) {
            _handleLate(_circleId, round, conf.contributionAmount);
        } else {
            IERC20(USDmToken).safeTransferFrom(
                msg.sender,
                address(this),
                conf.contributionAmount
            );

            stat.totalPot += conf.contributionAmount;
            m.totalContributed += conf.contributionAmount;

            // Award performance points for on-time payment (not after grace), if yield is enabled
            if (conf.isYieldEnabled && vault != address(0)) {
                m.performancePoints += 10;
                totalCirclePoints[_circleId] += 10;
                emit PointsAwarded(
                    _circleId,
                    msg.sender,
                    10,
                    "On-Time Payment"
                );
            }
        }

        roundContributions[_circleId][round][msg.sender] = true;
        stat.contributionsThisRound++; // Increment contribution counter
        emit ContributionMade(
            _circleId,
            round,
            msg.sender,
            conf.contributionAmount
        );

        _checkComplete(_circleId);
    }

    /*
     * @dev Forfeit specified members who haven't contributed after grace period
     * @param _circleId Circle ID
     * @param _membersToForfeit Array of member addresses to forfeit
     * @notice Can be called by any active member after grace period expires
     * @notice The current round's recipient is exempt from forfeiture
     * @notice Processes specified late members in a single transaction
     */
    function forfeitMember(
        uint256 _circleId,
        address[] calldata _membersToForfeit
    ) external nonReentrant {
        CircleConfig storage conf = circleConfigs[_circleId];
        CircleStatus storage stat = circleStatus[_circleId];

        if (stat.state != CircleState.ACTIVE) revert CircleNotActive();

        uint256 round = stat.currentRound;

        // CHECK 1: Caller must be an active member
        if (!circleMembers[_circleId][msg.sender].isActive)
            revert NotActiveMember();

        // CHECK 2: Grace period must have expired
        {
            uint256 deadline = circleRoundDeadlines[_circleId][round];
            uint256 gracePeriod = _getGracePeriod(conf.frequency);
            if (block.timestamp <= deadline + gracePeriod)
                revert GracePeriodNotExpired();
        }

        // Get the current round's recipient
        address recipient = _getByPos(_circleId, round);
        bool anyForfeited = false;

        // Process each member
        for (uint256 i = 0; i < _membersToForfeit.length; i++) {
            address memberAddr = _membersToForfeit[i];

            // Primary filters
            if (memberAddr == recipient) continue;
            if (roundContributions[_circleId][round][memberAddr]) continue;

            Member storage m = circleMembers[_circleId][memberAddr];
            if (!m.isActive) continue;

            // Perform forfeiture logic in a separate internal call to clear stack
            _forfeitSingleMember(_circleId, memberAddr, round, conf, stat);
            anyForfeited = true;
        }

        if (anyForfeited) {
            _checkComplete(_circleId);
        }
    }

    // ============ Internal Functions ============
    /**
     * @dev Internal function to execute vote (called by executeVote or early execution)
     * @param _circleId Circle ID
     */
    function _executeVoteInternal(uint256 _circleId) private {
        Vote storage vote = circleVotes[_circleId];

        if (vote.voteExecuted) return; // Already executed

        vote.votingActive = false;
        vote.voteExecuted = true;

        // Tie-breaking: Status quo wins (circle continues)
        // Only end circle if WITHDRAW has STRICT majority
        bool shouldWithdraw = vote.withdrawVoteCount > vote.startVoteCount;

        if (shouldWithdraw) {
            // Majority wants to end circle - release everything immediately
            _releaseDeadCircleCollateral(_circleId);
            emit VoteExecuted(
                _circleId,
                false, // false = circle ended
                vote.startVoteCount,
                vote.withdrawVoteCount
            );
        } else {
            // Tie or majority wants to start - start the circle
            _startCircleInternal(_circleId);
            emit VoteExecuted(
                _circleId,
                true, // true = circle started
                vote.startVoteCount,
                vote.withdrawVoteCount
            );
        }
    }

    /**
     * @dev Internal helper for forfeiture to keep stack clear
     */
    function _forfeitSingleMember(
        uint256 _circleId,
        address _memberAddr,
        uint256 _round,
        CircleConfig storage _conf,
        CircleStatus storage _stat
    ) internal {
        Member storage m = circleMembers[_circleId][_memberAddr];
        uint256 deduction;
        uint256 fee;

        {
            fee = (_conf.contributionAmount * LATE_FEE_BPS) / 10000;
            deduction = _conf.contributionAmount + fee;

            if (m.collateralLocked < deduction) {
                deduction = m.collateralLocked;
            }
        }

        m.collateralLocked -= deduction;

        {
            uint256 toPot = deduction > _conf.contributionAmount
                ? _conf.contributionAmount
                : deduction;
            uint256 toFees = deduction - toPot;

            _stat.totalPot += toPot;

            if (_conf.isYieldEnabled) {
                circleLateFeePool[_circleId] += toFees;
                emit LateFeeAddedToPool(_circleId, _memberAddr, toFees);
            } else {
                totalPlatformFees += toFees;
            }
        }

        roundContributions[_circleId][_round][_memberAddr] = true;
        _stat.contributionsThisRound++;

        _decreaseReputation(_memberAddr, 5, "Late Payment");
        _recordLatePayment(_memberAddr, _circleId, _round, fee);

        emit MemberForfeited(
            _circleId,
            _round,
            _memberAddr,
            deduction,
            msg.sender
        );
    }

    // ============ Helper Functions ============
    /**
     * @dev Calculate required collateral for a circle
     */
    function _calcCollateral(
        uint256 amount,
        uint256 members
    ) private pure returns (uint256) {
        uint256 totalCommitment = amount * members;
        uint256 lateBuffer = (totalCommitment * LATE_FEE_BPS) / 10000;
        return totalCommitment + lateBuffer;
    }

    /**
     * @dev Internal function to start a circle
     */
    function _startCircleInternal(uint256 _circleId) private {
        CircleConfig storage conf = circleConfigs[_circleId];
        CircleStatus storage stat = circleStatus[_circleId];

        _assignPosition(_circleId);

        stat.state = CircleState.ACTIVE;
        stat.startedAt = block.timestamp;
        stat.currentRound = 1;

        circleRoundDeadlines[_circleId][1] = _nextDeadline(
            conf.frequency,
            block.timestamp
        );

        emit CircleStarted(_circleId, block.timestamp, stat.state);
    }

    /**
     * @dev Assign positions to all members based on reputation when circle starts
     */
    function _assignPosition(uint256 cid) internal {
        CircleConfig storage conf = circleConfigs[cid];
        address[] storage mlist = circleMemberList[cid];

        // Creator always gets position 1
        circleMembers[cid][conf.creator].position = 1;
        emit PositionAssigned(cid, conf.creator, 1);

        uint256 memberCount = mlist.length - 1;
        address[] memory members = new address[](memberCount);
        uint256[] memory reputationScores = new uint256[](memberCount);

        // Step 1: Build arrays excluding creator
        uint256 idxCounter = 0;
        for (uint256 i = 0; i < mlist.length; i++) {
            if (mlist[i] != conf.creator) {
                members[idxCounter] = mlist[i];
                reputationScores[idxCounter] = _getReputationScore(mlist[i]);
                idxCounter++;
            }
        }

        // Step 2: Sort using insertion sort (more gas efficient than bubble sort)
        // Insertion sort is O(n²) worst case but O(n) best case for nearly sorted data
        // and has better cache locality than bubble sort
        for (uint256 i = 1; i < memberCount; i++) {
            uint256 keyScore = reputationScores[i];
            address keyAddr = members[i];
            uint256 j = i;

            // Shift elements with lower reputation scores to the right
            while (j > 0 && reputationScores[j - 1] < keyScore) {
                reputationScores[j] = reputationScores[j - 1];
                members[j] = members[j - 1];
                j--;
            }

            reputationScores[j] = keyScore;
            members[j] = keyAddr;
        }

        // Step 3: Assign positions (position 2 onwards for sorted members)
        for (uint256 i = 0; i < memberCount; i++) {
            uint256 position = i + 2;
            circleMembers[cid][members[i]].position = position;
            emit PositionAssigned(cid, members[i], position);
        }
    }

    /**
     * @dev Calculate platform fee based on payout amount
     * @param payoutAmount The total payout amount before fees
     * @return fee The calculated platform fee
     */
    function _calculatePlatformFee(
        uint256 payoutAmount
    ) private pure returns (uint256) {
        if (payoutAmount <= FIXED_FEE_THRESHOLD) {
            // For payouts ≤ $1000, charge 1%
            return (payoutAmount * PLATFORM_FEE_BPS) / 10000;
        } else {
            // For payouts > $1000, charge fixed $10
            return FIXED_FEE_AMOUNT;
        }
    }

    /**
     * @dev Get reputation score from reputation contract
     */
    function _getReputationScore(
        address _user
    ) internal view returns (uint256) {
        try
            IReputation(reputationContract).getUserReputationData(_user)
        returns (uint256, uint256, uint256, uint256 score) {
            return score;
        } catch {
            return 0;
        }
    }

    /**
     * @dev Increase reputation via reputation contract
     */
    function _increaseReputation(
        address _user,
        uint256 _amount,
        string memory _source
    ) internal {
        try
            IReputation(reputationContract).increaseReputation(
                _user,
                _amount,
                _source
            )
        {
            // Success
        } catch {
            // Fail silently - reputation is not critical
        }
    }

    /**
     * @dev Decrease reputation via reputation contract
     */
    function _decreaseReputation(
        address _user,
        uint256 _amount,
        string memory _source
    ) internal {
        try
            IReputation(reputationContract).decreaseReputation(
                _user,
                _amount,
                _source
            )
        {
            // Success
        } catch {
            // Fail silently
        }
    }

    /**
     * @dev Record circle completion via reputation contract
     */
    function _recordCircleCompleted(address _user, uint256 _cid) internal {
        try IReputation(reputationContract).recordCircleCompleted(_user, _cid) {
            // Success
        } catch {
            // Fail silently
        }
    }

    /**
     * @dev Record circle completion for all active members
     */
    function _recordCircleCompletedForAll(uint256 _cid) internal {
        address[] storage mlist = circleMemberList[_cid];
        for (uint256 i = 0; i < mlist.length; i++) {
            if (circleMembers[_cid][mlist[i]].isActive) {
                _recordCircleCompleted(mlist[i], _cid);
            }
        }
    }

    /**
     * @dev Record late payment via reputation contract
     */
    function _recordLatePayment(
        address _user,
        uint256 _cid,
        uint256 _round,
        uint256 _fee
    ) internal {
        try
            IReputation(reputationContract).recordLatePayment(
                _user,
                _cid,
                _round,
                _fee
            )
        {
            // Success
        } catch {
            // Fail silently
        }
    }

    /**
     * @dev calculate next deadline base on frequency
     */
    function _nextDeadline(
        Frequency f,
        uint256 from
    ) private pure returns (uint256) {
        if (f == Frequency.DAILY) return from + 1 days;
        if (f == Frequency.WEEKLY) return from + 7 days;
        return from + 30 days;
    }

    /**
     * @dev Processes payout for a round with tiered fee structure
     */
    function _payoutRound(uint256 cid, uint256 round) private {
        CircleConfig storage conf = circleConfigs[cid];
        CircleStatus storage stat = circleStatus[cid];
        address recip = _getByPos(cid, round);

        if (recip == address(0)) return;

        Member storage m = circleMembers[cid][recip];
        if (m.hasReceivedPayout) return;

        uint256 totalAmount = stat.totalPot;
        uint256 amt = totalAmount;

        if (recip != conf.creator) {
            // Use tiered fee calculation
            uint256 fee = _calculatePlatformFee(totalAmount);
            amt -= fee;
            totalPlatformFees += fee;
        }

        // Vault Integration: If contract balance is low (due to forfeitures covered by collateral), withdraw from vault
        uint256 currentBalance = IERC20(USDmToken).balanceOf(address(this));
        if (
            currentBalance < totalAmount &&
            vault != address(0) &&
            circleShares[cid] > 0
        ) {
            uint256 needed = totalAmount - currentBalance;
            // Ensure we don't try to withdraw more than available shares represent
            uint256 maxWithdraw = IERC4626(vault).previewRedeem(
                circleShares[cid]
            );
            uint256 toWithdraw = needed > maxWithdraw ? maxWithdraw : needed;

            if (toWithdraw > 0) {
                uint256 sharesToBurn = IERC4626(vault).withdraw(
                    toWithdraw,
                    address(this),
                    address(this)
                );
                circleShares[cid] -= sharesToBurn;
            }
        }

        IERC20(USDmToken).safeTransfer(recip, amt);
        m.hasReceivedPayout = true;
        stat.totalPot = 0;

        // Update reputation via reputation contract
        _increaseReputation(recip, 5, "Circle Payout Received");

        emit PayoutDistributed(cid, round, recip, amt);

        _progressNextRound(cid, round);
    }

    /**
     * @dev Advance round or finalize the circle
     */
    function _progressNextRound(uint256 cid, uint256 round) private {
        CircleConfig storage conf = circleConfigs[cid];
        CircleStatus storage stat = circleStatus[cid];

        if (round < stat.totalRounds) {
            stat.currentRound = round + 1;
            stat.contributionsThisRound = 0; // Reset counter for new round
            circleRoundDeadlines[cid][round + 1] = _nextDeadline(
                conf.frequency,
                block.timestamp
            );
        } else {
            stat.state = CircleState.COMPLETED;
            _releaseAllCollateral(cid);
            _recordCircleCompletedForAll(cid);
        }
    }

    /**
     * @dev Release all collateral at circle completion
     */
    function _releaseAllCollateral(uint256 cid) private {
        CircleConfig storage conf = circleConfigs[cid];
        address[] storage mlist = circleMemberList[cid];
        uint256 totalPrincipal = 0;

        // Loop 1: Calculate total principal (Simplified)
        for (uint256 i = 0; i < mlist.length; i++) {
            totalPrincipal += circleMembers[cid][mlist[i]].collateralLocked;
        }

        uint256 communityShare;
        {
            uint256 totalSurplus = _processVaultRedemption(
                cid,
                conf,
                totalPrincipal
            );
            if (totalSurplus > 0) {
                uint256 platformShare = (totalSurplus *
                    PLATFORM_YIELD_SHARE_BPS) / 10000;
                communityShare = totalSurplus - platformShare;
                totalPlatformFees += platformShare;
                emit YieldDistributed(
                    cid,
                    totalSurplus,
                    platformShare,
                    communityShare
                );
            }
        }

        uint256 tPoints = totalCirclePoints[cid];

        // Loop 2: Distribute to members via helper
        for (uint256 i = 0; i < mlist.length; i++) {
            _returnMemberCollateral(cid, mlist[i], communityShare, tPoints);
        }
    }

    /**
     * @dev Helper to handle vault logic and calculate surplus interest
     */
    function _processVaultRedemption(
        uint256 cid,
        CircleConfig storage conf,
        uint256 totalPrincipal
    ) internal returns (uint256 surplus) {
        uint256 shares = circleShares[cid];
        if (conf.isYieldEnabled && vault != address(0) && shares > 0) {
            uint256 balanceBefore = IERC20(USDmToken).balanceOf(address(this));
            IERC4626(vault).redeem(shares, address(this), address(this));
            uint256 balanceAfter = IERC20(USDmToken).balanceOf(address(this));

            uint256 totalWithdrawn = balanceAfter - balanceBefore;
            uint256 interest = totalWithdrawn > totalPrincipal
                ? totalWithdrawn - totalPrincipal
                : 0;
            return interest + circleLateFeePool[cid];
        }
        return 0;
    }

    /**
     * @dev Helper to return collateral and rewards to a single member
     */
    function _returnMemberCollateral(
        uint256 cid,
        address memberAddr,
        uint256 communityShare,
        uint256 tPoints
    ) internal {
        Member storage m = circleMembers[cid][memberAddr];
        if (!m.isActive) return;

        uint256 amt = m.collateralLocked;
        uint256 reward = 0;

        if (tPoints > 0 && communityShare > 0 && m.performancePoints > 0) {
            reward = (m.performancePoints * communityShare) / tPoints;
        }

        if (amt > 0 || reward > 0) {
            m.collateralLocked = 0;
            IERC20(USDmToken).safeTransfer(memberAddr, amt + reward);
            if (reward > 0) {
                emit MemberRewardClaimed(cid, memberAddr, reward);
            }
            emit CollateralReturned(cid, memberAddr, amt);
        }
    }

    /**
     * @dev Release all collateral for a DEAD or failed circle to all members at once
     * @param cid Circle ID
     */
    function _releaseDeadCircleCollateral(uint256 cid) internal {
        CircleConfig storage conf = circleConfigs[cid];
        CircleStatus storage stat = circleStatus[cid];

        // Prevent duplicate execution
        if (stat.state == CircleState.COMPLETED) return;
        stat.state = CircleState.DEAD;

        uint256 withdrawnFromVault = 0;
        if (
            conf.isYieldEnabled && vault != address(0) && circleShares[cid] > 0
        ) {
            uint256 shares = circleShares[cid];
            circleShares[cid] = 0;

            uint256 balanceBefore = IERC20(USDmToken).balanceOf(address(this));
            IERC4626(vault).redeem(shares, address(this), address(this));
            uint256 balanceAfter = IERC20(USDmToken).balanceOf(address(this));
            withdrawnFromVault = balanceAfter - balanceBefore;
        }

        address[] storage mlist = circleMemberList[cid];
        uint256 totalPrincipalReturned = 0;

        for (uint256 i = 0; i < mlist.length; i++) {
            address memberAddr = mlist[i];
            Member storage m = circleMembers[cid][memberAddr];

            if (!m.isActive || m.collateralLocked == 0) continue;

            uint256 amt = m.collateralLocked;
            m.collateralLocked = 0;
            m.isActive = false;

            if (memberAddr == conf.creator) {
                uint256 deadFee = (conf.visibility == Visibility.PRIVATE)
                    ? PRIVATE_CIRCLE_DEAD_FEE
                    : PUBLIC_CIRCLE_DEAD_FEE;

                if (amt >= deadFee) {
                    amt -= deadFee;
                    totalPlatformFees += deadFee;
                    emit DeadCircleFeeDeducted(cid, conf.creator, deadFee);
                }
            }

            if (amt > 0) {
                totalPrincipalReturned += amt;
                IERC20(USDmToken).safeTransfer(memberAddr, amt);
                emit CollateralWithdrawn(cid, memberAddr, amt);
            }
        }

        // Yield Sweep: If we got more back from the vault than the principal we owed everyone, platform takes the profit
        if (withdrawnFromVault > totalPrincipalReturned) {
            totalPlatformFees += (withdrawnFromVault - totalPrincipalReturned);
        }
    }

    /**
     * @dev Returns ultimatum period based on frequency
     */
    function _ultimatum(Frequency f) private pure returns (uint256) {
        if (f == Frequency.DAILY || f == Frequency.WEEKLY) return 7 days;
        return 14 days;
    }

    /**
     * @dev Checks if round is complete and trigger payout
     * @notice Uses contributionsThisRound counter to avoid looping through all members
     */
    function _checkComplete(uint256 cid) private {
        CircleStatus storage stat = circleStatus[cid];

        // Check if all active members have contributed using the counter
        if (stat.contributionsThisRound == stat.currentMembers) {
            _payoutRound(cid, stat.currentRound);
        }
    }

    /**
     * @dev Return grace period by frequency
     */
    function _getGracePeriod(Frequency f) public pure returns (uint256) {
        if (f == Frequency.DAILY) return 12 hours;
        return 48 hours;
    }

    /**
     * @dev Handles late payment with collateral deduction
     * @notice Called when user has insufficient balance OR after grace period
     */
    function _handleLate(uint256 cid, uint256 round, uint256 amt) internal {
        uint256 fee = (amt * LATE_FEE_BPS) / 10000;
        uint256 deduction = amt + fee;
        Member storage m = circleMembers[cid][msg.sender];

        if (m.collateralLocked < deduction) {
            revert InsufficientCollateral();
        }

        CircleConfig storage conf = circleConfigs[cid];
        CircleStatus storage stat = circleStatus[cid];

        m.collateralLocked -= deduction;
        stat.totalPot += amt;

        // Late fee routing based on circle mode
        if (conf.isYieldEnabled) {
            // Yield circles: late fees go to community reward pool
            circleLateFeePool[cid] += fee;
            emit LateFeeAddedToPool(cid, msg.sender, fee);
        } else {
            // No-yield circles: late fees go to platform
            totalPlatformFees += fee;
        }

        // Update reputation via reputation contract
        _decreaseReputation(msg.sender, 5, "Late Payment");
        _recordLatePayment(msg.sender, cid, round, fee);
    }

    // ============ Admin Functions ============
    /**
     * @dev Withdraw accumulated platform fees to treasury
     */
    function withdrawPlatformFees() external onlyOwner {
        uint256 amt = totalPlatformFees;
        totalPlatformFees = 0;
        IERC20(USDmToken).safeTransfer(treasury, amt);
    }

    /**
     * @dev Update treasury address
     */
    function updateTreasury(address _new) external onlyOwner {
        if (_new == address(0)) revert AddressZeroNotAllowed();
        treasury = _new;
    }

    /**
     * @dev Updates platform fee in basis points (max is 1% = 100pts)
     */
    function setPlatformFeeBps(uint256 _newBps) external onlyOwner {
        require(_newBps <= 100, "fee too high");
        platformFeeBps = _newBps;
    }

    /**
     * @dev Updates the fixed fee threshold (admin only)
     * @notice This changes the threshold at which fixed fee applies
     */
    function updateFeeThreshold(uint256 _newThreshold) external onlyOwner {
        require(_newThreshold > 0, "threshold must be positive");
        fixedFeeThreshold = _newThreshold;
    }

    // ============ View Functions ============
    /**
     * @dev Gets member address by position
     */
    function _getByPos(
        uint256 cid,
        uint256 pos
    ) private view returns (address) {
        address[] storage mlist = circleMemberList[cid];

        for (uint256 i = 0; i < mlist.length; i++) {
            if (circleMembers[cid][mlist[i]].position == pos) return mlist[i];
        }

        return address(0);
    }

    /**
     * @dev Check if member can withdraw after failed vote
     * @param _circleId circle ID
     * @return canWithdraw True if member can withraw
     */
    function canWithdrawAfterVote(
        uint256 _circleId
    ) public view returns (bool) {
        CircleStatus storage stat = circleStatus[_circleId];
        Vote storage vote = circleVotes[_circleId];

        if (!vote.voteExecuted) return false;
        if (stat.state == CircleState.ACTIVE) return false;

        uint256 totalVotes = vote.startVoteCount + vote.withdrawVoteCount;
        uint256 startPercentage = totalVotes > 0
            ? (vote.startVoteCount * 10000) / totalVotes
            : 0;

        return startPercentage < START_VOTE_THRESHOLD;
    }

    /**
     * @dev Return voting info for a circle
     */
    function getVoteInfo(
        uint256 _circleId
    )
        public
        view
        returns (
            uint256 votingEndTime,
            uint256 startVoteCount,
            uint256 withdrawVoteCount,
            bool votingActive,
            bool voteExecuted,
            VoteChoice userVote
        )
    {
        Vote storage vote = circleVotes[_circleId];

        return (
            vote.votingEndTime,
            vote.startVoteCount,
            vote.withdrawVoteCount,
            vote.votingActive,
            vote.voteExecuted,
            memberVotes[_circleId][msg.sender]
        );
    }

    /**
     * @dev Check if address is invited to a private circle
     */
    function isInvited(
        uint256 _circleId,
        address _user
    ) external view returns (bool) {
        return circleInvitations[_circleId][_user];
    }

    /**
     * @dev Return detailed circle information
     */
    function getCircleDetails(
        uint256 _circleId
    )
        external
        view
        returns (
            CircleConfig memory config,
            CircleStatus memory status,
            uint256 currentDeadline,
            bool canStart
        )
    {
        config = circleConfigs[_circleId];
        status = circleStatus[_circleId];

        if (status.state == CircleState.ACTIVE) {
            currentDeadline = circleRoundDeadlines[_circleId][
                status.currentRound
            ];
        }

        canStart = status.currentMembers >= (config.maxMembers * 60) / 100;

        return (config, status, currentDeadline, canStart);
    }

    /**
     * @dev Get member info for a specific circle
     */
    function getMemberInfo(
        uint256 _circleId,
        address _member
    )
        external
        view
        returns (
            Member memory memberInfo,
            bool hasContributedThisRound,
            uint256 nextDeadline
        )
    {
        memberInfo = circleMembers[_circleId][_member];
        CircleStatus storage stat = circleStatus[_circleId];

        if (stat.state == CircleState.ACTIVE) {
            hasContributedThisRound = roundContributions[_circleId][
                stat.currentRound
            ][_member];
            nextDeadline = circleRoundDeadlines[_circleId][stat.currentRound];
        }

        return (memberInfo, hasContributedThisRound, nextDeadline);
    }

    /**
     * @dev Return progress info for a circle
     */
    function getCircleProgress(
        uint256 _circleId
    )
        external
        view
        returns (
            uint256 currentRound,
            uint256 totalRounds,
            uint256 contributionsThisRound,
            uint256 totalMembers,
            uint256 lateFeePool,
            uint256 totalPoints
        )
    {
        CircleStatus storage stat = circleStatus[_circleId];
        currentRound = stat.currentRound;
        totalRounds = stat.totalRounds;
        totalMembers = stat.currentMembers;
        lateFeePool = circleLateFeePool[_circleId];
        totalPoints = totalCirclePoints[_circleId];
        contributionsThisRound = stat.contributionsThisRound;

        return (
            currentRound,
            totalRounds,
            contributionsThisRound,
            totalMembers,
            lateFeePool,
            totalPoints
        );
    }

    /**
     * @dev Returns all members of a circle
     */
    function getCircleMembers(
        uint256 _circleId
    ) external view returns (address[] memory) {
        return circleMemberList[_circleId];
    }

    /**
     * @dev returns contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
