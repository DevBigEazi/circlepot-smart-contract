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
    uint256 public constant VISIBILITY_UPDATE_FEE = 0.5e18; // $0.50

    // ============ Enums ============
    // Default state should be PENDING
    enum CircleState {
        PENDING,
        CREATED,
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
    mapping(uint256 => mapping(uint256 => mapping(address => bool)))
        public roundContributions;
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
    event PositionAssigned(uint256 circledId, address member, uint256 position);

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
     * @dev Start circle mannually by only the creator after ultimatum and 60% threshold reached
     * @param _circleId Circle ID to start
     */
     function startCircle(uint256 _circleId) external {
        if (_circleId == 0 || _circleId >= circleCounter) revert InvalidCircle();

        Circle storage c = circles[_circleId];
        if (c.creator != msg.sender) revert OnlyCreator();
        if (c.state != CircleState.CREATED) revert CircleNotOpen();

        // check 60% min threshold
        if (c.currentMembers < (c.maxMembers * 60 / 100)) revert MinMembersNotReached();

        // check if ultimatum period has passed
        uint256 ultimatumPeriod = _ultimatum(c.frequency);
        if (block.timestamp <= c.createdAt + ultimatumPeriod) revert UltimatumNotReached();

        _startCircleInternal(_circleId);
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
     * @dev Internal function start a circle( to be called by both manual and auto-start)
     * @param _circleId Circle ID to start
     */
    function _startCircleInternal(uint256 _circleId) private {
        Circle storage c = circles[_circleId];

        _assignPosition(_circleId);

        c.state = CircleState.ACTIVE;
        c.startedAt = block.timestamp;
        c.currentRound = 1;

        circleRoundDeadlines[_circleId][1] = _nextDeadline(c.frequency, block.timestamp);

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
        uint256 memberCount = mlist.length -1; // exclude the creator
        address[] memory members = new address[](memberCount);
        uint256[] memory reputationScores = new uint256[](memberCount);

        uint256 idxCounter = 0;

        for (uint256 i = 0; i < mlist.length; i++) {
            if (mlist[i] != c.creator) {
                members[idxCounter] = mlist[i];
                // calculate the reputation score(number of completed ccirle worth more)
                reputationScores[idxCounter] = userReputation[mlist[i]] + (completedCircles[mlist[i]] * 10);
                idxCounter++;
            }
        }

        // Sort members by reputation (descending) using bubble sort (Higher rep gets more advantages)
        for (uint256 i = 0; i < memberCount; i++) {
            for (uint256 j = i + 1; j < memberCount; j++) {
                if (reputationScores[j] > reputationScores[i]) {
                    // swap reputation scores
                    uint256 tempScore = reputationScores[i];
                    reputationScores[i] = reputationScores[j];
                    reputationScores[j] = tempScore;
                }
            }
        }

        // Assign position through N based on sorted reputation
        for (uint256 i = 0; i < memberCount; i++) {
            uint256 position = i + 2; // positions start at 2 (creator has 1)
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

    function _payoutRound(uint256 cid, uint256 round) private {
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
        uint256 round
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

        for (uint256 i = 0; i < mlist.length; i++) {
            Member storage m = circleMembers[cid][mlist[i]];

            if (m.isActive && m.collateralLocked > 0) {
                uint256 amt = m.collateralLocked;
                m.collateralLocked = 0;
                IERC20(cUSDToken).safeTransfer(mlist[i], amt);
            }
        }
    }

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
     * @dev Returns ultimatum period based on frequency
     */
    function _ultimatum(Frequency f) private pure returns(uint256) {
        if (f == Frequency.DAILY || f == Frequency.WEEKLY) return 7 days;
        return 14 days;
    }
}
