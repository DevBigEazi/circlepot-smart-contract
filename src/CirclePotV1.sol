// SPDX-License-Identifier: SEE LICENSE IN LICENSE
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
 * @notice Implements individual savings and community savings circles with collateral-backed commitments, voting,and invitations
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
    uint8 public constant MIN_MEMBERS = 5;
    uint8 public constant MAX_MEMBERS = 20;
    uint256 public constant VISIBILITY_UPDATE_FEE = 0.5e18; // $0.50
    uint256 public constant VOTING_PERIOD = 2 days; // VOTING LAST 3 DAYS
    uint256 public constant START_VOTE_THRESHOLD = 5100; //51% IN BASIS POINTS

    // ============ Enums ============
    // Default state should be PENDING
    enum CircleState {
        PENDING,
        CREATED,
        VOTING,
        ACTIVE,
        COMPLETED
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
        address creator;
        uint256 contributionAmount;
        Frequency frequency;
        uint8 maxMembers;
        uint8 currentMembers;
        uint8 currentRound;
        uint8 totalRounds;
        CircleState state;
        Visibility visibility;
        uint256 createdAt;
        uint256 startedAt;
        uint256 totalPot;
    }

    struct Member {
        uint8 position;
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
        uint8 maxMembers;
        Visibility visibility;
    }

    struct CreateGoalParams {
        string name;
        uint256 targetAmount;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 deadline;
    }

    struct Vote {
        uint256 votingStartTime;
        uint256 votingEndTime;
        uint8 startVoteCount;
        uint8 withdrawVoteCount;
        bool votingActive;
        bool voteExecuted;
    }

    // ============ Storage ============
    address public cUSDToken;
    address public treasury;

    uint256 public circleCounter;
    uint256 public goalCounter;

    // Circle related storage
    mapping(uint256 => Circle) public circles;
    mapping(uint256 => mapping(address => Member)) public circleMembers;
    mapping(uint256 => address[]) public circleMemberList;
    mapping(uint256 => mapping(uint8 => mapping(address => bool)))
        public roundContributions;
    mapping(uint256 => mapping(uint256 => uint256)) public circleRoundDeadlines;

    // Voting storage
    mapping(uint256 => Vote) public circleVotes;
    mapping(uint256 => mapping(address => VoteChoice)) public memberVotes;

    // Invitation storage for private circles
    mapping(uint256 => mapping(address => bool)) public circleInvitations;

    // Personal goals related storage
    mapping(uint256 => PersonalGoal) public personalGoals;
    mapping(address => uint256[]) public userGoals;

    // Reputations related storage
    mapping(address => uint256) public userReputation;
    mapping(address => uint256) public completedCircles;
    mapping(address => uint256) public latePayments;

    uint256 public totalPlatformFees;
    uint256 public platformFeeBps;

    // ============ Events ============
    event ContractUpgraded(address indexed newImplementation, uint8 version);
    event VisibilityUpdated(uint256 indexed circleId, address indexed creator);
    event CircleCreated(
        uint256 circleId,
        address creator,
        uint256 contributionAmount
    );
    event CircleJoined(uint256 indexed circleId, address indexed member);
    event CircleStarted(uint256 indexed circleId, uint256 startedAt);
    event PayoutDistributed(
        uint256 indexed circleId,
        uint256 indexed round,
        address indexed recipient,
        uint256 amount
    );
    event CircleCompleted(uint256 indexed circleId);
    event PositionAssigned(
        uint256 indexed circledId,
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
        uint256 indexed votingEndTime
    );
    event VoteCast(
        uint256 indexed circleId,
        address indexed voter,
        VoteChoice choice
    );
    event MemberInvited(uint256 indexed circleId, address indexed _invitee);
    event VoteExecuted(
        uint256 indexed circleId,
        bool circleStarted,
        uint256 startVoteCount,
        uint256 withdrawVoteCount
    );
    event ContributionMade(
        uint256 indexed circleId,
        uint8 round,
        address member,
        uint256 indexed amount
    );
    event LatePayment(
        uint256 indexed circleId,
        uint8 round,
        address member,
        uint256 indexed fee
    );
    event PersonalGoalCreated(uint256 indexed goalId, address indexed owner, string name, uint256 indexed targetAmount);

    // ============ Errors ============
    error InvalidTreasuryAddress();
    error InvalidContributionAmount();
    error InvalidMemberCount();
    error AddressZeroNotAllowed();
    error InvalidCircle();
    error OnlyCreator();
    error CircleNotExist();
    error SameVisibility();
    error CircleNotOpen();
    error CircleFull();
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
    error InvalidGoalAmount();
    error InvalidDeadline();

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
    ) public initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_cUSDToken == address(0) || _treasury == address(0))
            revert InvalidTreasuryAddress();

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
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        emit ContractUpgraded(newImplementation, VERSION);
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
        ) revert InvalidContributionAmount();
        if (params.maxMembers < MIN_MEMBERS || params.maxMembers > MAX_MEMBERS)
            revert InvalidMemberCount();

        uint256 circleId = circleCounter++;
        uint256 collateral = _calcCollateral(
            params.contributionAmount,
            params.maxMembers
        );
        uint256 totalRequired = collateral;

        // // if applicable, add visibilty fee( by default, the visibility is private but user can create a circle with public visibility by paying $0.5 one time fee)
        if (params.visibility == Visibility.PUBLIC) {
            totalRequired + VISIBILITY_UPDATE_FEE;
            totalPlatformFees + VISIBILITY_UPDATE_FEE;
            emit VisibilityUpdated(circleId, msg.sender);
        }

        //deposit collateral + buffer
        IERC20(cUSDToken).safeTransferFrom(
            msg.sender,
            address(this),
            totalRequired
        );

        //update circle
        circles[circleId] = Circle({
            circleId: circleId,
            creator: msg.sender,
            contributionAmount: params.contributionAmount,
            frequency: params.frequency,
            maxMembers: params.maxMembers,
            currentMembers: 1,
            currentRound: 0,
            totalRounds: params.maxMembers,
            state: CircleState.CREATED,
            visibility: params.visibility,
            createdAt: block.timestamp,
            startedAt: 0,
            totalPot: 0
        });

        // update circle Membership data
        circleMembers[circleId][msg.sender] = Member({
            position: 0, // will be assigned no 1 when circle starts
            totalContributed: 0,
            hasReceivedPayout: false,
            isActive: true,
            collateralLocked: collateral,
            joinedAt: block.timestamp
        });

        // add creator to Circle Member list
        circleMemberList[circleId].push(msg.sender);

        emit CircleCreated(circleId, msg.sender, params.contributionAmount);

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
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();

        Circle storage c = circles[_circleId];
        if (c.creator != msg.sender) revert OnlyCreator();
        if (c.state != CircleState.CREATED) revert CircleNotExist();
        if (c.visibility == _newVisibility) revert SameVisibility();

        // charge $0.50 visibility update fee
        IERC20(cUSDToken).safeTransferFrom(
            msg.sender,
            address(this),
            VISIBILITY_UPDATE_FEE
        );
        totalPlatformFees += VISIBILITY_UPDATE_FEE;

        c.visibility = _newVisibility;

        emit VisibilityUpdated(_circleId, msg.sender);
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
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();

        Circle storage c = circles[_circleId];
        if (c.creator != msg.sender) revert OnlyCreator();
        if (c.visibility != Visibility.PRIVATE) revert CircleNotPrivate();
        if (c.state != CircleState.CREATED) revert CircleNotOpen();

        for (uint256 i = 0; i < _invitees.length; i++) {
            circleInvitations[_circleId][_invitees[i]] = true;

            emit MemberInvited(_circleId, _invitees[i]);
        }
    }

    /**
     * @dev Allow a user to join an existing circle
     * @param _circleId Circle ID to join
     */
    function joinCircle(uint256 _circleId) external nonReentrant {
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();

        Circle storage c = circles[_circleId];
        // allow to join only created circle
        if (c.state != CircleState.CREATED) revert CircleNotOpen();
        if (c.currentMembers == c.maxMembers) revert CircleFull();
        if (circleMembers[_circleId][msg.sender].isActive)
            revert AlreadyJoined();

        // check invitation for private circles
        if (c.visibility == Visibility.PRIVATE) {
            if (!circleInvitations[_circleId][msg.sender]) revert NotInvited();
        }

        uint256 collateral = _calcCollateral(
            c.contributionAmount,
            c.maxMembers
        );

        // Desposit collateral and join the circle
        IERC20(cUSDToken).safeTransferFrom(
            msg.sender,
            address(this),
            collateral
        );

        // update circle Membership data
        circleMembers[_circleId][msg.sender] = Member({
            position: 0, // will be assigned when circle starts
            totalContributed: 0,
            hasReceivedPayout: false,
            isActive: true,
            collateralLocked: collateral,
            joinedAt: block.timestamp
        });

        circleMemberList[_circleId].push(msg.sender);

        c.currentMembers++;

        emit CircleJoined(_circleId, msg.sender);

        // if max mebers reached, auto start the circle
        if (c.currentMembers == c.maxMembers) {
            _startCircleInternal(_circleId);
            emit CircleStarted(_circleId, block.timestamp);
        }
    }

    /**
     * @dev Initiates voting to decide if circle should start after ultimatum period
     * @param _circleId Circle ID
     */
    function initiateVoting(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();

        Circle storage c = circles[_circleId];
        if (c.state != CircleState.CREATED) revert CircleNotOpen();

        // chect the 60% min threshold
        if (c.currentMembers < (c.maxMembers * 60) / 100)
            revert MinMembersNotReached();

        // check ultimatum period if it has passed
        uint256 ultimatumPeriod = _ultimatum(c.frequency);
        if (block.timestamp >= c.createdAt + ultimatumPeriod)
            revert UltimatumNotReached();

        // check if voting is already initiated
        Vote storage vote = circleVotes[_circleId];
        if (vote.votingActive) revert VotingStillActive();
        if (vote.voteExecuted) revert VotingAlreadyExecuted();

        // initialize voting
        vote.votingStartTime = block.timestamp;
        vote.votingEndTime = block.timestamp + VOTING_PERIOD;
        vote.startVoteCount = 0;
        vote.withdrawVoteCount = 0;
        vote.votingActive = true;
        vote.voteExecuted = false;

        c.state = CircleState.VOTING;

        emit VotingInitiated(_circleId, vote.votingEndTime);
    }

    /**
     * @dev Cast vote to decide if circle should start
     * @param _circleId Circle ID
     * @param _choice Vote choice for the members (START or WITHDRAW)
     */
    function castVote(uint256 _circleId, VoteChoice _choice) external {
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();
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
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();

        Circle storage c = circles[_circleId];
        if (c.state != CircleState.VOTING) revert VotingNotActive();

        Vote storage vote = circleVotes[_circleId];
        if (!vote.votingActive) revert VotingNotActive();
        if (block.timestamp <= vote.votingEndTime) revert VotingStillActive();
        if (vote.voteExecuted) revert VoteAlreadyExecuted();

        vote.votingActive = false;
        vote.voteExecuted = true;

        uint8 totalVotes = vote.startVoteCount + vote.withdrawVoteCount;
        uint256 startPercentage = totalVotes > 0
            ? (vote.startVoteCount * 10000) / totalVotes
            : 0;

        bool shouldStart = startPercentage >= START_VOTE_THRESHOLD;

        if (shouldStart) {
            // 51% voted to start - initiate circle
            c.state = CircleState.CREATED; // Reset to created b4 starting
            _startCircleInternal(_circleId);

            emit VoteExecuted(
                _circleId,
                true,
                vote.startVoteCount,
                vote.withdrawVoteCount
            );
        } else {
            // Less than 51% voted to start - allow withdrawals
            c.state = CircleState.CREATED;
            emit VoteExecuted(
                _circleId,
                true,
                vote.startVoteCount,
                vote.withdrawVoteCount
            );
        }
    }

    /**
     * @dev Each member can withdraw their collateral if after the ultimum, circle did not start
     * @param _circleId Circle ID to withdraw from
     */
    function WithdrawCollateral(uint256 _circleId) external nonReentrant {
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();

        Circle storage c = circles[_circleId];
        if (c.state != CircleState.CREATED) revert CircleNotOpen();

        Member storage m = circleMembers[_circleId][msg.sender];
        if (!m.isActive) revert NotActiveMember();

        Vote storage vote = circleVotes[_circleId];

        // check if withdrawal is allowed (two consitions)
        bool canWithdraw = false;
        // case 1: vote executed and failed (if less than 51% voted to start)
        if (vote.voteExecuted && canWithdrawAfterVote(_circleId)) {
            canWithdraw = true;
        } else {
            // case 2: Ultimatum passed and 60% threshold is not met(no voting will be initiated)
            uint256 period = _ultimatum(c.frequency);
            if (block.timestamp <= c.createdAt + period) {
                if (c.currentMembers < (c.maxMembers * 60) / 100) {
                    canWithdraw = true;
                }
            }
        }

        if (!canWithdraw) revert UltimatumNotPassed();

        uint256 amt = m.collateralLocked;
        m.collateralLocked = 0;
        m.isActive = false;

        IERC20(cUSDToken).safeTransfer(msg.sender, amt);

        emit CollateralWithdrawn(_circleId, msg.sender, amt);
    }

    /**
     * @dev Start circle mannually by only the creator after ultimatum and 60% threshold reached
     * @param _circleId Circle ID to start
     */
    function startCircle(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();

        Circle storage c = circles[_circleId];
        if (c.creator != msg.sender) revert OnlyCreator();
        if (c.state != CircleState.CREATED) revert CircleNotOpen();

        // check 60% min threshold
        if (c.currentMembers < ((c.maxMembers * 60) / 100))
            revert MinMembersNotReached();

        // check if ultimatum period has passed
        uint256 ultimatumPeriod = _ultimatum(c.frequency);
        if (block.timestamp <= c.createdAt + ultimatumPeriod)
            revert UltimatumNotReached();

        _startCircleInternal(_circleId);
    }

    /**
     * @dev Member contribute to the current round
     * @param _circleId Circle ID
     */
    function contribute(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter)
            revert InvalidCircle();

        Circle storage c = circles[_circleId];
        if (c.state != CircleState.ACTIVE) revert CircleNotActive();

        Member storage m = circleMembers[_circleId][msg.sender];
        if (!m.isActive) revert NotActiveMember();

        uint8 round = c.currentRound;
        if (roundContributions[_circleId][round][msg.sender])
            revert AlreadyContributed();

        IERC20(cUSDToken).safeTransferFrom(
            msg.sender,
            address(this),
            c.contributionAmount
        );

        uint256 deadline = circleRoundDeadlines[_circleId][round];
        uint256 gracePeriod = _getGracePeriod(c.frequency);
        uint256 graceDeadline = deadline + gracePeriod;

        bool afterGrace = block.timestamp > graceDeadline;

        if (afterGrace) {
            _handleLate(_circleId, round, c.contributionAmount);
        } else {
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

    // helper functions
    /**
     * @dev Calculate required collateral for a circle
     * @param amount Contribution amount per round
     * @param members Maximum number of members
     * @return Total required collateral amount
     */
    function _calcCollateral(
        uint256 amount,
        uint256 members
    ) private pure returns (uint256) {
        uint256 totalCommitment = amount * members;

        // Buffer cover all potential late fees (1% of the contributions amount per round)
        uint256 lateBuffer = (totalCommitment * LATE_FEE_BPS) / 10000;

        return totalCommitment + lateBuffer;
    }

    /**
     * @dev Internal function to start a circle( to be called by both manual and auto-start)
     * @param _circleId Circle ID to start
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

        emit CircleStarted(_circleId, block.timestamp);

        _payoutRound(_circleId, 1);
    }

    /**
     * @dev Assign positions to all members base on reputation when circle starts
     * @param cid Circle ID
     */
    function _assignPosition(uint256 cid) private {
        Circle storage c = circles[cid];
        address[] storage mlist = circleMemberList[cid];

        // creator always get first position
        circleMembers[cid][c.creator].position = 1;
        emit PositionAssigned(cid, c.creator, 1);

        // array of non-creator members with thier reputation score
        uint256 memberCount = mlist.length - 1; // exclude the creator
        address[] memory members = new address[](memberCount);
        uint256[] memory reputationScores = new uint256[](memberCount);

        uint256 idxCounter = 0;

        for (uint8 i = 0; i < mlist.length; i++) {
            if (mlist[i] != c.creator) {
                members[idxCounter] = mlist[i];
                // calculate the reputation score(number of completed ccirle worth more)
                reputationScores[idxCounter] =
                    userReputation[mlist[i]] +
                    (completedCircles[mlist[i]] * 10);
                idxCounter++;
            }
        }

        // Sort members by reputation (descending) using bubble sort (Higher rep gets more advantages)
        for (uint8 i = 0; i < memberCount; i++) {
            for (uint8 j = i + 1; j < memberCount; j++) {
                if (reputationScores[j] > reputationScores[i]) {
                    // swap reputation scores
                    uint256 tempScore = reputationScores[i];
                    reputationScores[i] = reputationScores[j];
                    reputationScores[j] = tempScore;
                }
            }
        }

        // Assign position through N based on sorted reputation
        for (uint8 i = 0; i < memberCount; i++) {
            uint8 position = i + 2; // positions start at 2 (creator has 1)
            circleMembers[cid][members[i]].position = position;

            emit PositionAssigned(cid, members[i], position);
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
     * @dev Processes payout for a round
     */
    function _payoutRound(uint256 cid, uint8 round) private {
        Circle storage c = circles[cid];
        address recip = _getByPos(cid, round);

        if (recip == address(0)) return;

        Member storage m = circleMembers[cid][recip];
        if (m.hasReceivedPayout) return;

        uint amt = c.totalPot;

        if (recip != c.creator) {
            uint256 fee = (amt * platformFeeBps) / 10000;
            amt -= fee;
            totalPlatformFees += fee;
        }

        IERC20(cUSDToken).safeTransfer(recip, amt);
        m.hasReceivedPayout = true;
        c.totalPot = 0;

        userReputation[recip] += 5;
        completedCircles[recip]++;

        emit PayoutDistributed(cid, round, recip, amt);

        _progressNextRound(c, cid, round);
    }

    /**
     * @dev Advance round or finalize the circle
     */
    function _progressNextRound(
        Circle storage c,
        uint256 cid,
        uint8 round
    ) private {
        if (round < c.totalRounds) {
            c.currentRound = round + 1;
            circleRoundDeadlines[cid][round] = _nextDeadline(
                c.frequency,
                block.timestamp
            );
        } else {
            c.state = CircleState.COMPLETED;
            _releaseAllCollateral(cid);
            emit CircleCompleted(cid);
        }
    }

    /**
     * @dev Release all collateral at circle completion
     */
    function _releaseAllCollateral(uint256 cid) private {
        address[] storage mlist = circleMemberList[cid];

        for (uint8 i = 0; i < mlist.length; i++) {
            Member storage m = circleMembers[cid][mlist[i]];

            if (m.isActive && m.collateralLocked > 0) {
                uint256 amt = m.collateralLocked;
                m.collateralLocked = 0;
                IERC20(cUSDToken).safeTransfer(mlist[i], amt);
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
     * @dev Handles late payment with collateral deduction
     */
    function _handleLate(uint256 cid, uint8 round, uint256 amt) private {
        uint256 fee = (amt * LATE_FEE_BPS) / 10000;

        Member storage m = circleMembers[cid][msg.sender];
        uint256 deduction = amt + fee;
        if (m.collateralLocked > deduction) {
            m.collateralLocked -= deduction;
        } else {
            m.collateralLocked = 0;
        }

        circles[cid].totalPot += amt;
        totalPlatformFees += fee;

        userReputation[msg.sender] = userReputation[msg.sender] > 5
            ? userReputation[msg.sender] - 5
            : 0;
        latePayments[msg.sender]++;

        emit LatePayment(cid, round, msg.sender, fee);
    }

    /**
     * @dev Checks if round is complete and trigger payout
     */
    function _checkComplete(uint256 cid) private {
        Circle storage c = circles[cid];
        address[] storage mlist = circleMemberList[cid];
        uint80 payCount = 0;

        for (uint8 i = 0; i < mlist.length; i++) {
            address addr = mlist[i];
            //only count active members who have paid
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
        if (f == Frequency.DAILY) return 0;
        return 48 hours;
    }

    // ============ Personal Saving Goals Functions ============
    /**
     * @dev Create a personal savings goal
     * @param params Goal creation parameters
     * @return goalId The ID of the newly created goal
     */
    function createPersonalGoal(
        CreateGoalParams calldata params
    ) external returns (uint256) {
        if (params.targetAmount < 10e18 || params.targetAmount > 50000e18)
            revert InvalidGoalAmount();
        if (params.contributionAmount == 0) revert InvalidContributionAmount();
        if (params.deadline <= block.timestamp) revert InvalidDeadline();

        uint256 gid = goalCounter++;

        personalGoals[gid] = PersonalGoal({
            owner: msg.sender,
            name: params.name,
            targetAmount: params.targetAmount,
            currentAmount: 0,
            contributionAmount: params.contributionAmount,
            frequency: params.frequency,
            deadline: params.deadline,
            createdAt: block.timestamp,
            isActive: true,
            lastContributionAt: 0
        });

        userGoals[msg.sender].push(gid);

        emit PersonalGoalCreated(gid, msg.sender, params.name, params.targetAmount);

        return gid;
    }

    // ============ Getter/View Functions ============
    /**
     * @dev Gets member address by position
     */
    function _getByPos(
        uint256 cid,
        uint256 pos
    ) private view returns (address) {
        address[] storage mlist = circleMemberList[cid];

        for (uint8 i = 0; i < mlist.length; i++) {
            if (circleMembers[cid][mlist[i]].position == pos) return mlist[i];
        }

        return address(0);
    }

    /**
     * @dev Checki if member can withdraw after failed vote
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

        uint8 totalVotes = vote.startVoteCount + vote.withdrawVoteCount;
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
            uint8 startVoteCount,
            uint8 withdrawVoteCount,
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
     * @dev Retunrs all circles a user is part of
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
                userCircles[idx] = 1;

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
            uint8 currentRound,
            uint8 totalRounds,
            uint256 contributionsThisRound,
            uint8 totalMembers
        )
    {
        Circle storage c = circles[_circleId];
        currentRound = c.currentRound;
        totalRounds = c.totalRounds;
        totalMembers = c.currentMembers;

        if (c.state == CircleState.ACTIVE) {
            address[] storage mlist = circleMemberList[_circleId];
            for (uint8 i = 0; i < mlist.length; i++) {
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
     * @dev Returns user's reputation data
     */
    function getUserReputation(
        address _user
    )
        external
        view
        returns (
            uint256 reputation,
            uint256 circlesCompleted,
            uint256 latePaymentsCount
        )
    {
        return (
            userReputation[_user],
            completedCircles[_user],
            latePayments[_user]
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
