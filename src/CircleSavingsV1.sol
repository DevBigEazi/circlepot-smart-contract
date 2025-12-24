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
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IReputation} from "./interfaces/IReputation.sol";

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
    struct Circle {
        uint256 circleId;
        string title; // max of 32 characters
        string description; // IPFS hash
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
    }

    struct Member {
        uint256 position;
        uint256 totalContributed;
        bool hasReceivedPayout;
        bool isActive;
        uint256 collateralLocked;
        uint256 joinedAt;
    }

    struct CreateCircleParams {
        string title;
        string description;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 maxMembers;
        Visibility visibility;
    }

    struct Vote {
        uint256 votingStartTime;
        uint256 votingEndTime;
        uint256 startVoteCount;
        uint256 withdrawVoteCount;
        bool votingActive;
        bool voteExecuted;
    }

    // ============ Storage ============
    address public cUSDToken;
    address public treasury;
    address public reputationContract;

    uint256 public circleCounter;

    // Circle related storage
    mapping(uint256 => Circle) public circles;
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
     * @param _cUSDToken Address of the cUSD token contract
     * @param _treasury Address of the treasury for platform fees
     * @param _reputationContract Address of the reputation contract
     * @param initialOwner Address of the initial owner (if zero, msg.sender remains owner)
     */
    function initialize(
        address _cUSDToken,
        address _treasury,
        address _reputationContract,
        address initialOwner
    ) public initializer {
        __Ownable_init(initialOwner);

        if (
            _cUSDToken == address(0) ||
            _treasury == address(0) ||
            _reputationContract == address(0)
        ) {
            revert AddressZeroNotAllowed();
        }

        cUSDToken = _cUSDToken;
        treasury = _treasury;
        reputationContract = _reputationContract;
        circleCounter = 1;
        platformFeeBps = PLATFORM_FEE_BPS;
        fixedFeeThreshold = FIXED_FEE_THRESHOLD;

        if (initialOwner != address(0) && initialOwner != owner()) {
            _transferOwnership(initialOwner);
        }
    }

    /**
     * @dev Function for upgrading the contract to a new version (reinitializer)
     * @param _cUSDToken Address of cUSD token (if changed)
     * @param _treasury Address of treasury (if changed)
     * @param _reputationContract Address of reputation contract (if changed)
     * @param _version Reinitializer version number
     */
    function upgrade(
        address _cUSDToken,
        address _treasury,
        address _reputationContract,
        uint8 _version
    ) public reinitializer(_version) onlyOwner {
        if (_cUSDToken != address(0)) {
            cUSDToken = _cUSDToken;
        }
        if (_treasury != address(0)) {
            treasury = _treasury;
        }
        if (_reputationContract != address(0)) {
            reputationContract = _reputationContract;
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
        uint256 collateral = _calcCollateral(
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

        IERC20(cUSDToken).safeTransferFrom(
            msg.sender,
            address(this),
            totalRequired
        );

        circles[circleId] = Circle({
            circleId: circleId,
            title: params.title,
            description: params.description,
            creator: msg.sender,
            contributionAmount: params.contributionAmount,
            frequency: params.frequency,
            maxMembers: params.maxMembers,
            currentMembers: 1,
            currentRound: 0,
            totalRounds: 1,
            state: CircleState.CREATED,
            visibility: params.visibility,
            createdAt: block.timestamp,
            startedAt: 0,
            totalPot: 0
        });

        circleMembers[circleId][msg.sender] = Member({
            position: 0,
            totalContributed: 0,
            hasReceivedPayout: false,
            isActive: true,
            collateralLocked: collateral,
            joinedAt: block.timestamp
        });

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
            circleMembers[circleId][msg.sender].collateralLocked
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

        Circle storage c = circles[_circleId];
        if (c.creator != msg.sender) revert OnlyCreator();
        if (c.state != CircleState.CREATED) revert CircleNotExist();
        if (c.visibility == _newVisibility) revert SameVisibility();

        IERC20(cUSDToken).safeTransferFrom(
            msg.sender,
            address(this),
            VISIBILITY_UPDATE_FEE
        );
        totalPlatformFees += VISIBILITY_UPDATE_FEE;

        c.visibility = _newVisibility;

        emit VisibilityUpdated(_circleId, msg.sender, c.visibility);
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

        Circle storage c = circles[_circleId];
        if (c.creator != msg.sender) revert OnlyCreator();
        if (c.visibility != Visibility.PRIVATE) revert CircleNotPrivate();
        if (c.state != CircleState.CREATED) revert InvalidCircle();

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

    /**
     * @dev Allow a user to join an existing circle
     * @param _circleId Circle ID to join
     */
    function joinCircle(uint256 _circleId) external nonReentrant {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        Circle storage c = circles[_circleId];
        if (c.currentMembers == c.maxMembers) revert CircleNotOpen();
        if (circleMembers[_circleId][msg.sender].isActive) {
            revert AlreadyJoined();
        }
        if (c.state != CircleState.CREATED && c.state != CircleState.VOTING)
            revert InvalidCircle();

        if (c.visibility == Visibility.PRIVATE) {
            if (!circleInvitations[_circleId][msg.sender]) revert NotInvited();
        }

        uint256 collateral = _calcCollateral(
            c.contributionAmount,
            c.maxMembers
        );

        IERC20(cUSDToken).safeTransferFrom(
            msg.sender,
            address(this),
            collateral
        );

        circleMembers[_circleId][msg.sender] = Member({
            position: 0,
            totalContributed: 0,
            hasReceivedPayout: false,
            isActive: true,
            collateralLocked: collateral,
            joinedAt: block.timestamp
        });

        circleMemberList[_circleId].push(msg.sender);

        c.currentMembers++;
        c.totalRounds = c.currentMembers;

        emit CircleJoined(_circleId, msg.sender, c.currentMembers, c.state);

        if (c.currentMembers == c.maxMembers) {
            _startCircleInternal(_circleId);
            emit CircleStarted(_circleId, block.timestamp, c.state);
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

        Circle storage c = circles[_circleId];
        if (c.state != CircleState.CREATED) revert InvalidCircle();

        if (c.currentMembers < (c.maxMembers * 60) / 100) {
            revert MinMembersNotReached();
        }

        uint256 ultimatumPeriod = _ultimatum(c.frequency);
        if (block.timestamp < c.createdAt + ultimatumPeriod) {
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

        c.state = CircleState.VOTING;

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

        Circle storage c = circles[_circleId];
        if (c.state != CircleState.VOTING) revert VotingNotActive();

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
    }

    /**
     * @dev execute vote result after voting period ends
     * @param _circleId Circle ID
     */
    function executeVote(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        Circle storage c = circles[_circleId];
        if (c.state != CircleState.VOTING) revert VotingNotActive();

        Vote storage vote = circleVotes[_circleId];
        if (!vote.votingActive) revert VotingNotActive();
        if (block.timestamp <= vote.votingEndTime) revert VotingStillActive();
        if (vote.voteExecuted) revert VoteAlreadyExecuted();

        vote.votingActive = false;
        vote.voteExecuted = true;

        uint256 totalVotes = vote.startVoteCount + vote.withdrawVoteCount;
        uint256 startPercentage = totalVotes > 0
            ? (vote.startVoteCount * 10000) / totalVotes
            : 0;

        bool shouldStart = startPercentage >= START_VOTE_THRESHOLD;

        if (shouldStart) {
            c.state = CircleState.CREATED;
            _startCircleInternal(_circleId);

            emit VoteExecuted(
                _circleId,
                true,
                vote.startVoteCount,
                vote.withdrawVoteCount
            );
        } else {
            c.state = CircleState.CREATED;
            emit VoteExecuted(
                _circleId,
                false,
                vote.startVoteCount,
                vote.withdrawVoteCount
            );
        }
    }

    /**
     * @dev Each member can withdraw their collateral if after the ultimatum, circle did not start
     * @param _circleId Circle ID to withdraw from
     */
    function WithdrawCollateral(uint256 _circleId) external nonReentrant {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        Circle storage c = circles[_circleId];
        if (c.state != CircleState.CREATED && c.state != CircleState.DEAD)
            revert InvalidCircle();

        Member storage m = circleMembers[_circleId][msg.sender];
        if (!m.isActive) revert NotActiveMember();

        Vote storage vote = circleVotes[_circleId];

        bool canWithdraw = false;
        if (vote.voteExecuted && canWithdrawAfterVote(_circleId)) {
            canWithdraw = true;
        } else {
            uint256 period = _ultimatum(c.frequency);
            if (block.timestamp > c.createdAt + period) {
                if (c.currentMembers < (c.maxMembers * 60) / 100) {
                    canWithdraw = true;
                }
            }
        }

        if (!canWithdraw) revert UltimatumNotPassed();

        uint256 amt = m.collateralLocked;

        // Check if this is the creator withdrawing from a dead circle
        bool isCreator = c.creator == msg.sender;
        uint256 deadFee = 0;

        if (isCreator) {
            if (c.visibility == Visibility.PRIVATE) {
                deadFee = PRIVATE_CIRCLE_DEAD_FEE;
            } else {
                deadFee = PUBLIC_CIRCLE_DEAD_FEE;
            }

            // Deduct fee from creator's collateral if sufficient
            if (amt >= deadFee) {
                amt -= deadFee;
                totalPlatformFees += deadFee;
            }

            emit DeadCircleFeeDeducted(_circleId, c.creator, deadFee);
        }

        m.collateralLocked = 0;
        m.isActive = false;
        c.state = CircleState.DEAD;

        IERC20(cUSDToken).safeTransfer(msg.sender, amt);

        emit CollateralWithdrawn(_circleId, msg.sender, amt);
    }

    /**
     * @dev Start circle manually by only the creator after ultimatum and 60% threshold reached
     * @param _circleId Circle ID to start
     */
    function startCircle(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        Circle storage c = circles[_circleId];
        if (c.creator != msg.sender) revert OnlyCreator();
        if (c.state != CircleState.CREATED) revert InvalidCircle();

        if (c.currentMembers < ((c.maxMembers * 60) / 100)) {
            revert MinMembersNotReached();
        }

        uint256 ultimatumPeriod = _ultimatum(c.frequency);
        if (block.timestamp <= c.createdAt + ultimatumPeriod) {
            revert UltimatumNotReached();
        }

        _startCircleInternal(_circleId);
    }

    /**
     * @dev Member contribute to the current round
     * @param _circleId Circle ID
     */
    function contribute(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter) {
            revert InvalidCircle();
        }

        Circle storage c = circles[_circleId];
        if (c.state != CircleState.ACTIVE) revert CircleNotActive();

        Member storage m = circleMembers[_circleId][msg.sender];
        if (!m.isActive) revert NotActiveMember();

        uint256 round = c.currentRound;

        // CHECK 0: Caller must be an active member
        if (!circleMembers[_circleId][msg.sender].isActive)
            revert NotActiveMember();
        if (roundContributions[_circleId][round][msg.sender]) {
            revert AlreadyContributed();
        }

        uint256 deadline = circleRoundDeadlines[_circleId][round];
        uint256 gracePeriod = _getGracePeriod(c.frequency);
        uint256 graceDeadline = deadline + gracePeriod;

        bool afterGrace = block.timestamp > graceDeadline;

        if (afterGrace) {
            _handleLate(_circleId, round, c.contributionAmount);
        } else {
            IERC20(cUSDToken).safeTransferFrom(
                msg.sender,
                address(this),
                c.contributionAmount
            );

            c.totalPot += c.contributionAmount;
            m.totalContributed += c.contributionAmount;
        }

        roundContributions[_circleId][round][msg.sender] = true;
        emit ContributionMade(
            _circleId,
            round,
            msg.sender,
            c.contributionAmount
        );

        _checkComplete(_circleId);
    }

    /*
     * @dev Forfeit all members who haven't contributed after grace period
     * @param _circleId Circle ID
     * @notice Can ONLY be called by the next payout recipient
     * @notice Can ONLY be called AFTER grace period expires
     * @notice This incentivizes the next recipient to keep the circle moving
     * @notice Processes all late members in a single transaction
     */
    function forfeitMember(uint256 _circleId) external nonReentrant {
        Circle storage c = circles[_circleId];
        if (c.state != CircleState.ACTIVE) revert CircleNotActive();

        uint256 round = c.currentRound;

        // CHECK 1: Caller must be an active member
        if (!circleMembers[_circleId][msg.sender].isActive)
            revert NotActiveMember();

        // CHECK 2: Grace period must have expired
        uint256 deadline = circleRoundDeadlines[_circleId][round];
        uint256 gracePeriod = _getGracePeriod(c.frequency);
        uint256 graceDeadline = deadline + gracePeriod;

        if (block.timestamp <= graceDeadline) revert GracePeriodNotExpired();

        // Process all members who haven't contributed yet
        address[] storage mlist = circleMemberList[_circleId];
        bool anyForfeited = false;

        for (uint256 i = 0; i < mlist.length; i++) {
            address memberAddr = mlist[i];

            // Skip members who already contributed or are not active
            if (
                !roundContributions[_circleId][round][memberAddr] &&
                circleMembers[_circleId][memberAddr].isActive
            ) {
                Member storage m = circleMembers[_circleId][memberAddr];

                // Deduct from collateral
                uint256 fee = (c.contributionAmount * LATE_FEE_BPS) / 10000;
                uint256 deduction = c.contributionAmount + fee;

                if (m.collateralLocked < deduction) {
                    // Not enough collateral - take what's left
                    deduction = m.collateralLocked;
                }

                m.collateralLocked -= deduction;

                // Split forfeited amount
                uint256 toPot = deduction > c.contributionAmount
                    ? c.contributionAmount
                    : deduction;
                uint256 toFees = deduction - toPot;

                c.totalPot += toPot;
                totalPlatformFees += toFees;

                // Mark as contributed (forfeited counts as contributed)
                roundContributions[_circleId][round][memberAddr] = true;

                // Update reputation via reputation contract
                _decreaseReputation(memberAddr, 5, "Late Payment");
                _recordLatePayment(memberAddr, _circleId, round, fee);

                emit MemberForfeited(
                    _circleId,
                    round,
                    memberAddr,
                    deduction,
                    msg.sender
                );
                anyForfeited = true;
            }
        }

        // Only check for round completion if at least one member was forfeited
        if (anyForfeited) {
            _checkComplete(_circleId);
        }
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
        Circle storage c = circles[_circleId];

        _assignPosition(_circleId);

        c.state = CircleState.ACTIVE;
        c.startedAt = block.timestamp;
        c.currentRound = 1;

        circleRoundDeadlines[_circleId][1] = _nextDeadline(
            c.frequency,
            block.timestamp
        );

        emit CircleStarted(_circleId, block.timestamp, c.state);
    }

    /**
     * @dev Assign positions to all members based on reputation when circle starts
     */
    function _assignPosition(uint256 cid) internal {
        Circle storage c = circles[cid];
        address[] storage mlist = circleMemberList[cid];

        circleMembers[cid][c.creator].position = 1;
        emit PositionAssigned(cid, c.creator, 1);

        uint256 memberCount = mlist.length - 1;
        address[] memory members = new address[](memberCount);
        uint256[] memory reputationScores = new uint256[](memberCount);

        uint256 idxCounter = 0;

        for (uint256 i = 0; i < mlist.length; i++) {
            if (mlist[i] != c.creator) {
                members[idxCounter] = mlist[i];
                reputationScores[idxCounter] = _getReputationScore(mlist[i]);
                idxCounter++;
            }
        }

        for (uint256 i = 0; i < memberCount; i++) {
            for (uint256 j = i + 1; j < memberCount; j++) {
                if (reputationScores[j] > reputationScores[i]) {
                    uint256 tempScore = reputationScores[i];
                    reputationScores[i] = reputationScores[j];
                    reputationScores[j] = tempScore;

                    address tempAddr = members[i];
                    members[i] = members[j];
                    members[j] = tempAddr;
                }
            }
        }

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
        Circle storage c = circles[cid];
        address recip = _getByPos(cid, round);

        if (recip == address(0)) return;

        Member storage m = circleMembers[cid][recip];
        if (m.hasReceivedPayout) return;

        uint256 totalAmount = c.totalPot;
        uint256 amt = totalAmount;

        if (recip != c.creator) {
            // Use tiered fee calculation
            uint256 fee = _calculatePlatformFee(totalAmount);
            amt -= fee;
            totalPlatformFees += fee;
        }

        IERC20(cUSDToken).safeTransfer(recip, amt);
        m.hasReceivedPayout = true;
        c.totalPot = 0;

        // Update reputation via reputation contract
        _increaseReputation(recip, 5, "Circle Payout Received");

        emit PayoutDistributed(cid, round, recip, amt);

        _progressNextRound(c, cid, round);
    }

    /**
     * @dev Advance round or finalize the circle
     */
    function _progressNextRound(
        Circle storage c,
        uint256 cid,
        uint256 round
    ) private {
        if (round < c.totalRounds) {
            c.currentRound = round + 1;
            circleRoundDeadlines[cid][round + 1] = _nextDeadline(
                c.frequency,
                block.timestamp
            );
        } else {
            c.state = CircleState.COMPLETED;
            _releaseAllCollateral(cid);
            _recordCircleCompletedForAll(cid);
        }
    }

    /**
     * @dev Release all collateral at circle completion
     */
    function _releaseAllCollateral(uint256 cid) private {
        address[] storage mlist = circleMemberList[cid];

        for (uint256 i = 0; i < mlist.length; i++) {
            Member storage m = circleMembers[cid][mlist[i]];

            if (m.isActive && m.collateralLocked > 0) {
                uint256 amt = m.collateralLocked;
                m.collateralLocked = 0;
                IERC20(cUSDToken).safeTransfer(mlist[i], amt);
                emit CollateralReturned(cid, mlist[i], amt);
            }
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
     */
    function _checkComplete(uint256 cid) private {
        Circle storage c = circles[cid];
        address[] storage mlist = circleMemberList[cid];
        uint256 payCount = 0;

        for (uint256 i = 0; i < mlist.length; i++) {
            address addr = mlist[i];
            if (
                circleMembers[cid][addr].isActive &&
                roundContributions[cid][c.currentRound][addr]
            ) {
                payCount++;
            }
        }

        if (payCount == c.currentMembers) _payoutRound(cid, c.currentRound);
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

        m.collateralLocked -= deduction;
        circles[cid].totalPot += amt;
        totalPlatformFees += fee;

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
        IERC20(cUSDToken).safeTransfer(treasury, amt);
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
        Circle storage c = circles[_circleId];
        Vote storage vote = circleVotes[_circleId];

        if (!vote.voteExecuted) return false;
        if (c.state == CircleState.ACTIVE) return false;

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
            Circle memory circle,
            uint256 membersJoined,
            uint256 currentDeadline,
            bool canStart
        )
    {
        circle = circles[_circleId];
        membersJoined = circle.currentMembers;

        if (circle.state == CircleState.ACTIVE) {
            currentDeadline = circleRoundDeadlines[_circleId][
                circle.currentRound
            ];
        }

        canStart = circle.currentMembers >= (circle.maxMembers * 60) / 100;

        return (circle, membersJoined, currentDeadline, canStart);
    }

    /**
     * @dev Returns all circles a user is part of
     */
    function getUserCircles(
        address _user
    ) external view returns (uint256[] memory) {
        uint256 count = 0;

        for (uint256 i = 1; i < circleCounter; i++) {
            if (circleMembers[i][_user].isActive) {
                count++;
            }
        }

        uint256[] memory userCircles = new uint256[](count);
        uint256 idx = 0;

        for (uint256 i = 1; i < circleCounter; i++) {
            if (circleMembers[i][_user].isActive) {
                userCircles[idx] = i;
                idx++;
            }
        }

        return userCircles;
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
        Circle storage c = circles[_circleId];

        if (c.state == CircleState.ACTIVE) {
            hasContributedThisRound = roundContributions[_circleId][
                c.currentRound
            ][_member];
            nextDeadline = circleRoundDeadlines[_circleId][c.currentRound];
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
            uint256 totalMembers
        )
    {
        Circle storage c = circles[_circleId];
        currentRound = c.currentRound;
        totalRounds = c.totalRounds;
        totalMembers = c.currentMembers;

        if (c.state == CircleState.ACTIVE) {
            address[] storage mlist = circleMemberList[_circleId];
            for (uint256 i = 0; i < mlist.length; i++) {
                if (roundContributions[_circleId][c.currentRound][mlist[i]]) {
                    contributionsThisRound++;
                }
            }
        }
        return (
            currentRound,
            totalRounds,
            contributionsThisRound,
            totalMembers
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
