// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IReputation.sol";
import "./interfaces/IFamCircle.sol";

/**
 * @title FamCircle
 * @notice Collateral-free savings circles based on social trust, reputation, and progressive escrow.
 */
contract FamCircle is 
    Initializable, 
    OwnableUpgradeable, 
    ReentrancyGuard, 
    UUPSUpgradeable,
    IFamCircle 
{
    using SafeERC20 for IERC20;

    // ============ Constants ============
    uint256 public constant VERSION = 1;
    uint256 public constant CREATION_FEE = 2e6;             // $2.00
    uint256 public constant MIN_CONTRIBUTION = 1e6;         // $1.00
    uint256 public constant MAX_CONTRIBUTION = 2500e6;      // $2500.00
    uint256 public constant MIN_CREATOR_BALANCE = 100e6;    // $100.00
    uint256 public constant MIN_REPUTATION_JOIN = 580;
    uint256 public constant MIN_REPUTATION_CREATE = 670;
    uint256 public constant MIN_MEMBERS = 5;
    uint256 public constant MAX_ACTIVE_FAM_CIRCLES = 2;
    uint256 public constant REQUIRED_VOUCHES = 2;
    uint256 public constant MAX_VOUCH_LIMIT = 3;
    uint256 public constant CREATOR_REWARD_BPS = 4000;      // 40%
    uint256 public constant LATE_FEE_BPS = 100;             // 1%
    uint256 public constant LATE_FEE_THRESHOLD = 500e6;
    uint256 public constant LATE_FEE_FIXED = 5e6;
    
    // Fee Tiers
    uint256 public constant FIXED_FEE_THRESHOLD = 1000e6;   // $1000 threshold
    uint256 public constant FIXED_FEE_AMOUNT = 10e6;        // $10 fixed fee
    uint256 public constant MAINT_FEE_BPS = 100;            // 1%

    // ============ Storage ============
    address public treasury;
    address public reputationContract;
    uint256 public circleCounter;
    mapping(address => uint256) public platformFeesByToken;

    mapping(address => uint256) public globalOutstandingDebt;
    mapping(address => uint256) public globalDivertedFunds; // Escrow for victims
    mapping(address => uint256) public activeFamCircleCount;
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public hasEverDefaulted;
    mapping(address => uint256) public goodStandingStreak;
    mapping(address => uint256) public kickedTime;
    mapping(address => uint256[]) public userCircles;
    mapping(address => uint256) public activeVouchCount;

    bool public circleCreationPaused;

    // Multi-token support
    mapping(address => bool) public supportedTokens;
    address[] public supportedTokenList;

    mapping(uint256 => FamCircleConfig) public configs;
    mapping(uint256 => FamCircleStatus) public statuses;
    mapping(uint256 => mapping(address => FamMember)) public members;
    mapping(uint256 => address[]) public circleMemberList;
    
    // Debt Restitution: circleId -> defaulter -> round -> recipientOwed
    mapping(uint256 => mapping(address => mapping(uint256 => address))) public debtRecipient;
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) public debtRemaining;
    mapping(uint256 => mapping(address => uint256[])) public memberDefaultedRounds;
    mapping(uint256 => mapping(address => address[])) public memberVouchers;
    mapping(uint256 => mapping(address => bool)) public invitations;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public roundContributions;
    mapping(uint256 => mapping(uint256 => uint256)) public circleRoundDeadlines;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============
    function initialize(
        address _treasury, 
        address _reputation, 
        address _initialOwner,
        address[] memory _initialTokens
    ) public initializer {
        __Ownable_init(_initialOwner);
        treasury = _treasury;
        reputationContract = _reputation;

        for (uint256 i = 0; i < _initialTokens.length; i++) {
            _addToken(_initialTokens[i]);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


    // ============ Admin Functions ============

    function addSupportedToken(address token) external onlyOwner {
        _addToken(token);
    }

    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        // keep it in the list but mark as false
    }

    function _addToken(address token) internal {
        if (!supportedTokens[token]) {
            supportedTokens[token] = true;
            supportedTokenList.push(token);
        }
    }

    function setCircleCreationPaused(bool _paused) external onlyOwner {
        circleCreationPaused = _paused;
        emit CircleCreationPausedUpdated(_paused);
    }

    // ============ Core Lifecycle ============

    function createCircle(CreateParams calldata params) external override nonReentrant returns (uint256) {
        if (circleCreationPaused) revert CircleCreationPaused();
        if (!supportedTokens[params.token]) revert TokenNotSupported();
        if (isBlacklisted[msg.sender]) revert UserIsBlacklisted();
        if (activeFamCircleCount[msg.sender] >= MAX_ACTIVE_FAM_CIRCLES) revert MaxActiveCirclesReached();
        if (params.maxMembers < MIN_MEMBERS) revert MinMembersNotMet(params.maxMembers, MIN_MEMBERS);
        if (params.contributionAmount < MIN_CONTRIBUTION) revert ContributionTooLow(params.contributionAmount, MIN_CONTRIBUTION);
        if (params.contributionAmount > MAX_CONTRIBUTION) revert ContributionTooHigh(params.contributionAmount, MAX_CONTRIBUTION);
        
        // Layer 1: Reputation & Balance Check
        uint256 score = IReputation(reputationContract).userReputations(msg.sender);
        if (score < MIN_REPUTATION_CREATE) revert ReputationTooLow();
        
        if (hasEverDefaulted[msg.sender] && goodStandingStreak[msg.sender] < 15) {
            revert BadRecord(); 
        }

        if (block.timestamp < kickedTime[msg.sender] + 365 days) {
            revert BadRecord(); // 1 year ban on creation
        }
        
        uint256 creatorBalance = IERC20(params.token).balanceOf(msg.sender);
        if (creatorBalance < MIN_CREATOR_BALANCE) revert InsufficientCreatorBalance(creatorBalance, MIN_CREATOR_BALANCE);

        // Frequency Limits Check
        uint256 limit = _getMaxMembersForFrequency(params.frequency);
        if (params.maxMembers > limit) revert MaxMembersExceeded(params.maxMembers, limit);

        // Creation Fee & Counter
        circleCounter++;
        uint256 circleId = circleCounter;
        IERC20(params.token).safeTransferFrom(msg.sender, treasury, CREATION_FEE);
        platformFeesByToken[params.token] += CREATION_FEE;
        
        emit FeeCollected(circleId, msg.sender, FeeType.CREATION, CREATION_FEE);
        emit FamCircleCreated(circleId, msg.sender, params.contributionAmount, params.token, params.frequency);

        configs[circleId] = FamCircleConfig({
            circleId: circleId,
            title: params.title,
            description: params.description,
            creator: msg.sender,
            contributionAmount: params.contributionAmount,
            frequency: params.frequency,
            maxMembers: params.maxMembers,
            createdAt: block.timestamp,
            token: params.token 
        });

        statuses[circleId].state = CircleState.CREATED;
        
        // Auto-join creator
        _join(circleId, msg.sender);

        if (params.initialInvitees.length > 0) {
            _invite(circleId, msg.sender, params.initialInvitees);
        }

        return circleId;
    }

    function inviteMembers(uint256 circleId, address[] calldata invitees) external override {
        if (configs[circleId].creator != msg.sender) revert OnlyCreatorAllowed();
        _invite(circleId, msg.sender, invitees);
    }

    function vouchForMember(uint256 circleId, address member) external override {
        if (statuses[circleId].state != CircleState.CREATED) revert InvalidCircleState();
        if (msg.sender == configs[circleId].creator) revert AlreadyVouchedForMember(); // Creator already vouched via invitation
        if (activeVouchCount[msg.sender] >= MAX_VOUCH_LIMIT) revert MaxVouchLimitReached();
        if (!members[circleId][msg.sender].isActive) revert NotACircleMember();
        if (msg.sender == member) revert CannotVouchForSelf();
        
        // Prevent double vouching
        address[] storage vouchers = memberVouchers[circleId][member];
        for(uint i=0; i<vouchers.length; i++) {
            if (vouchers[i] == msg.sender) revert AlreadyVouchedForMember();
        }

        vouchers.push(msg.sender);
        activeVouchCount[msg.sender]++;
        
        emit MemberVouched(circleId, msg.sender, member);
    }

    function joinCircle(uint256 circleId) external override nonReentrant {
        if (statuses[circleId].state != CircleState.CREATED) revert InvalidCircleState();
        if (!invitations[circleId][msg.sender]) revert NotInvitedToCircle();
        if (isBlacklisted[msg.sender]) revert UserIsBlacklisted();
        
        uint256 maxAllowed = MAX_ACTIVE_FAM_CIRCLES;
        if (block.timestamp < kickedTime[msg.sender] + 365 days) {
            maxAllowed = 1;
        }
        if (activeFamCircleCount[msg.sender] >= maxAllowed) revert MaxActiveCirclesReached();
        
        // Check Vouch Count (Creator invite counts as 1)
        uint256 totalVouches = memberVouchers[circleId][msg.sender].length + 1;
        if (totalVouches < REQUIRED_VOUCHES) revert InsufficientVouches(totalVouches, REQUIRED_VOUCHES);

        _join(circleId, msg.sender);
    }

    // ============ Internals ============

    function _invite(uint256 circleId, address inviter, address[] calldata invitees) internal {
        bool isSingle = invitees.length == 1;
        for (uint i = 0; i < invitees.length; i++) {
            address invitee = invitees[i];
            bool alreadyIn = invitations[circleId][invitee] || members[circleId][invitee].isActive;
            
            if (alreadyIn) {
                if (isSingle) revert AlreadyInvited();
                continue;
            }
            
            invitations[circleId][invitee] = true;
            emit MemberInvited(circleId, inviter, invitee);
        }
    }

    function _join(uint256 circleId, address member) internal {
        if (statuses[circleId].currentMembers >= configs[circleId].maxMembers) revert CircleIsFull();
        if (members[circleId][member].isActive) revert AlreadyAMember();

        members[circleId][member].isActive = true;
        circleMemberList[circleId].push(member);
        userCircles[member].push(circleId);
        statuses[circleId].currentMembers++;
        activeFamCircleCount[member]++;

        emit MemberJoined(circleId, member);
    }

    function startCircle(uint256 circleId) external nonReentrant {
        if (configs[circleId].creator != msg.sender) revert OnlyCreatorAllowed();
        if (statuses[circleId].state != CircleState.CREATED) revert InvalidCircleState();
        if (statuses[circleId].currentMembers < MIN_MEMBERS) revert MinMembersNotMet(statuses[circleId].currentMembers, MIN_MEMBERS);

        statuses[circleId].state = CircleState.ACTIVE;
        statuses[circleId].startedAt = block.timestamp;
        statuses[circleId].totalRounds = statuses[circleId].currentMembers;
        statuses[circleId].currentRound = 1;

        uint256 deadline = _nextDeadline(configs[circleId].frequency, block.timestamp);
        circleRoundDeadlines[circleId][1] = deadline;

        _assignPositions(circleId);
    }

    function cancelCircle(uint256 circleId) external override nonReentrant {
        if (configs[circleId].creator != msg.sender) revert OnlyCreatorAllowed();
        if (statuses[circleId].state != CircleState.CREATED) revert InvalidCircleState();

        statuses[circleId].state = CircleState.DEAD;
        
        // Return active circle slots to all members
        address[] storage mlist = circleMemberList[circleId];
        for (uint256 i = 0; i < mlist.length; i++) {
            activeFamCircleCount[mlist[i]]--;
        }
    }

    function _assignPositions(uint256 circleId) internal {
        FamCircleConfig storage conf = configs[circleId];
        address[] storage mlist = circleMemberList[circleId];
        uint256 total = mlist.length;

        // Determine Creator Position
        uint256 creatorPos = 1;
        if (hasEverDefaulted[conf.creator] && goodStandingStreak[conf.creator] < 15) {
            creatorPos = (total / 2) + 1; // Middle position
        } else if (block.timestamp < kickedTime[conf.creator] + 365 days) {
            creatorPos = (total / 2) + 1; // Also middle if recently kicked
        }

        members[circleId][conf.creator].position = creatorPos;

        uint256 otherCount = total - 1;
        address[] memory sortedOthers = new address[](otherCount);
        uint256 count = 0;

        for (uint256 i = 0; i < total; i++) {
            address mAddr = mlist[i];
            if (mAddr == conf.creator) continue;

            bool inProbation = hasEverDefaulted[mAddr] && goodStandingStreak[mAddr] < 5;
            uint256 score = inProbation ? 0 : IReputation(reputationContract).userReputations(mAddr);

            uint256 j = count;
            while (j > 0) {
                address prev = sortedOthers[j - 1];
                bool prevInProbation = hasEverDefaulted[prev] && goodStandingStreak[prev] < 5;
                uint256 prevScore = prevInProbation ? 0 : IReputation(reputationContract).userReputations(prev);

                if (prevScore < score) {
                    sortedOthers[j] = prev;
                    j--;
                } else {
                    break;
                }
            }
            sortedOthers[j] = mAddr;
            count++;
        }

        uint256 sIdx = 0;
        for (uint256 i = 1; i <= total; i++) {
            if (i == creatorPos) continue;
            members[circleId][sortedOthers[sIdx]].position = i;
            sIdx++;
        }
    }

    function _reassignRemainingPositions(uint256 circleId) internal {
        FamCircleStatus storage status = statuses[circleId];
        uint256 currentRound = status.currentRound;
        uint256 totalMembers = status.currentMembers;
        
        uint256 remainingCount = 0;
        address[] storage mlist = circleMemberList[circleId];
        
        // Count unpaid members (excluding current round recipient)
        for (uint256 i = 0; i < mlist.length; i++) {
            address mAddr = mlist[i];
            if (!members[circleId][mAddr].hasReceivedPayout && members[circleId][mAddr].position > currentRound) {
                remainingCount++;
            }
        }
        
        if (remainingCount == 0) return;
        
        address[] memory unpaid = new address[](remainingCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < mlist.length; i++) {
            address mAddr = mlist[i];
            if (!members[circleId][mAddr].hasReceivedPayout && members[circleId][mAddr].position > currentRound) {
                unpaid[idx] = mAddr;
                idx++;
            }
        }
        
        // Sort unpaid members by reputation
        for (uint256 i = 1; i < remainingCount; i++) {
            address keyAddr = unpaid[i];
            bool keyProbation = hasEverDefaulted[keyAddr] && goodStandingStreak[keyAddr] < 5;
            uint256 keyScore = keyProbation ? 0 : IReputation(reputationContract).userReputations(keyAddr);
            
            uint256 j = i;
            while (j > 0) {
                address prev = unpaid[j-1];
                bool prevProbation = hasEverDefaulted[prev] && goodStandingStreak[prev] < 5;
                uint256 prevScore = prevProbation ? 0 : IReputation(reputationContract).userReputations(prev);
                
                if (prevScore < keyScore) {
                    unpaid[j] = prev;
                    j--;
                } else {
                    break;
                }
            }
            unpaid[j] = keyAddr;
        }
        
        // Re-assign positions starting from currentRound + 1
        for (uint256 i = 0; i < remainingCount; i++) {
             uint256 oldPos = members[circleId][unpaid[i]].position;
             uint256 newPos = currentRound + 1 + i;
             if (oldPos != newPos) {
                 members[circleId][unpaid[i]].position = newPos;
                 emit PositionSwapped(circleId, unpaid[i], address(0), oldPos, newPos);
             }
        }
    }

    function _getReputationScore(address user) internal view returns (uint256) {
        try IReputation(reputationContract).getUserReputationData(user)
        returns (uint256, uint256, uint256, uint256 score) {
            return score;
        } catch {
            return 0;
        }
    }

    function _nextDeadline(Frequency f, uint256 from) internal pure returns (uint256) {
        if (f == Frequency.DAILY) return from + 1 days;
        if (f == Frequency.WEEKLY) return from + 7 days;
        return from + 30 days;
    }

    function _getMaxMembersForFrequency(Frequency f) internal pure returns (uint256) {
        if (f == Frequency.DAILY) return 30;
        if (f == Frequency.WEEKLY) return 25;
        return 12; // Monthly
    }

    function _getGracePeriod(Frequency f) internal pure returns (uint256) {
        if (f == Frequency.DAILY) return 12 hours;
        return 48 hours;
    }

    function _handleDefault(uint256 circleId, address defaulter) internal {
        FamMember storage m = members[circleId][defaulter];
        uint256 amount = configs[circleId].contributionAmount;
        m.roundsDefaulted++;
        m.isFlagged = true;
        hasEverDefaulted[defaulter] = true;
        goodStandingStreak[defaulter] = 0;
        statuses[circleId].contributionsThisRound++;

        address currentRecipient = _getByPos(circleId, statuses[circleId].currentRound);
        debtRecipient[circleId][defaulter][statuses[circleId].currentRound] = currentRecipient;
        debtRemaining[circleId][defaulter][statuses[circleId].currentRound] = amount;
        memberDefaultedRounds[circleId][defaulter].push(statuses[circleId].currentRound);

        if (m.hasReceivedPayout) {
            m.debtOwed += amount;
            globalOutstandingDebt[defaulter] += amount;
        } else {
            m.pendingDebt += amount;
        }
        
        statuses[circleId].totalDebtOwed += amount;
        emit MemberFlagged(circleId, defaulter, amount);

        // Reputation Nuke (Layer 7)
        IReputation(reputationContract).decreaseReputation(defaulter, 30, "FamCircle Default");

        if (m.roundsDefaulted >= 3 && m.totalContributed == 0) {
            _kickMember(circleId, defaulter);
        }

        // Global Position Contagion
        uint256[] storage cids = userCircles[defaulter];
        for (uint256 i = 0; i < cids.length; i++) {
            uint256 cid = cids[i];
            if (statuses[cid].state == CircleState.ACTIVE) {
                _reassignRemainingPositions(cid);
            }
        }
    }

    function _kickMember(uint256 circleId, address member) internal {
        FamMember storage m = members[circleId][member];
        if (!m.isActive) return;

        m.isActive = false;
        statuses[circleId].currentMembers--;
        
        kickedTime[member] = block.timestamp;
        
        // Only blacklist if they have Real Debt (other offenses)
        if (m.debtOwed > 0) {
            isBlacklisted[member] = true;
        }
        
        activeFamCircleCount[member]--;
        _penalizeVouchers(circleId, member);

        IReputation(reputationContract).decreaseReputation(member, 50, "FamCircle Expulsion");
        emit MemberKicked(circleId, member);
        
        // Re-sort to close the gap
        _reassignRemainingPositions(circleId);
    }

    function _penalizeVouchers(uint256 circleId, address member) internal {
        address[] memory vouchers = memberVouchers[circleId][member];
        for (uint i = 0; i < vouchers.length; i++) {
            IReputation(reputationContract).decreaseReputation(vouchers[i], 15, "Vouched member defaulted");
        }
    }

    // ============ Financial Logic ============

    function contribute(uint256 circleId) external override nonReentrant {
        FamCircleStatus storage status = statuses[circleId];
        if (status.state != CircleState.ACTIVE) revert CircleNotActive();
        if (roundContributions[circleId][status.currentRound][msg.sender]) revert AlreadyContributedThisRound();
        
        uint256 amount = configs[circleId].contributionAmount;
        uint256 deadline = circleRoundDeadlines[circleId][status.currentRound];
        uint256 gracePeriod = _getGracePeriod(configs[circleId].frequency);
        
        uint256 totalToTransfer = amount;
        bool isLate = block.timestamp > deadline + gracePeriod;

        if (isLate) {
            uint256 lateFee = (amount * LATE_FEE_BPS) / 10000;
            totalToTransfer += lateFee;
            IERC20(configs[circleId].token).safeTransferFrom(msg.sender, treasury, lateFee);
            IReputation(reputationContract).decreaseReputation(msg.sender, 5, "Late Payment");
            emit FeeCollected(circleId, msg.sender, FeeType.LATE, lateFee);
        }

        IERC20(configs[circleId].token).safeTransferFrom(msg.sender, address(this), amount);
        
        roundContributions[circleId][status.currentRound][msg.sender] = true;
        status.totalPot += amount;
        status.contributionsThisRound++;

        _checkComplete(circleId);
    }

    function _checkComplete(uint256 circleId) internal {
        FamCircleStatus storage status = statuses[circleId];
        if (status.contributionsThisRound == status.currentMembers) {
            address recipient = _getByPos(circleId, status.currentRound);
            _processPayout(circleId, recipient);
        }
    }

    function processForfeits(uint256 circleId, address[] calldata membersToForfeit) external override nonReentrant {
        FamCircleStatus storage status = statuses[circleId];
        if (status.state != CircleState.ACTIVE) revert CircleNotActive();
        if (!members[circleId][msg.sender].isActive) revert NotACircleMember();

        uint256 deadline = circleRoundDeadlines[circleId][status.currentRound];
        uint256 gracePeriod = _getGracePeriod(configs[circleId].frequency);
        if (block.timestamp <= deadline + gracePeriod) revert GracePeriodNotExpired();

        address recipient = _getByPos(circleId, status.currentRound);
        bool recipientDefaulted = false;

        // Special Case: Check if recipient defaulted
        if (!roundContributions[circleId][status.currentRound][recipient]) {
            recipientDefaulted = true;
        }

        for (uint256 i = 0; i < membersToForfeit.length; i++) {
            address target = membersToForfeit[i];
            if (roundContributions[circleId][status.currentRound][target]) continue; // Already contributed
            if (!members[circleId][target].isActive) continue;

            if (target == recipient) {
                _handleRecipientDefault(circleId, target);
            } else {
                _handleDefault(circleId, target);
            }
        }

        // If recipient wasn't in membersToForfeit but still hasn't paid, we still force it if they defaulted
        if (recipientDefaulted && !roundContributions[circleId][status.currentRound][recipient]) {
             _handleRecipientDefault(circleId, recipient);
        }

        // Batch Re-sorting (One re-sort for all defaults)
        _reassignRemainingPositions(circleId);

        _checkComplete(circleId);
    }

    function _handleRecipientDefault(uint256 circleId, address recipient) internal {
        // 1. Mark as defaulted
        _handleDefault(circleId, recipient); // This will nuke rep and re-sort
        
        // 2. Since _handleDefault moves defaulter to the END, Position 'currentRound' is now EMPTY.
        // We need to pull the 'new' Position currentRound + 1 into Position currentRound.
        
        uint256 currentPos = statuses[circleId].currentRound;
        address nextInLine = _getByPos(circleId, currentPos + 1);
        
        if (nextInLine != address(0)) {
            members[circleId][nextInLine].position = currentPos;
            // defaulter was already moved to the end by _reassignRemainingPositions called in _handleDefault
            emit PositionSwapped(circleId, nextInLine, recipient, currentPos + 1, currentPos);
        }
    }

    function repayCircleDebt(uint256 circleId, uint256 amount) external override nonReentrant {
        FamMember storage m = members[circleId][msg.sender];
        uint256[] storage rounds = memberDefaultedRounds[circleId][msg.sender];
        if (rounds.length == 0 || amount == 0) return;

        address token = configs[circleId].token;
        uint256 remainingToPay = amount;

        for (uint256 i = 0; i < rounds.length; i++) {
            if (remainingToPay == 0) break;
            
            uint256 r = rounds[i];
            address to = debtRecipient[circleId][msg.sender][r];
            uint256 dRem = debtRemaining[circleId][msg.sender][r];

            if (to != address(0) && dRem > 0) {
                uint256 penalty = _calculateLateFee(dRem);
                uint256 totalNeeded = dRem + penalty;

                uint256 payment = amountMin(remainingToPay, totalNeeded);
                uint256 penaltyPart;
                uint256 contributionPart;

                if (payment == totalNeeded) {
                    penaltyPart = penalty;
                    contributionPart = dRem;
                } else {
                    penaltyPart = (payment * penalty) / totalNeeded;
                    contributionPart = payment - penaltyPart;
                }

                // Transfers
                IERC20(token).safeTransferFrom(msg.sender, to, contributionPart);
                IERC20(token).safeTransferFrom(msg.sender, treasury, penaltyPart);
                platformFeesByToken[token] += penaltyPart;
                
                emit FeeCollected(circleId, msg.sender, FeeType.LATE, penaltyPart);
                
                // Update Storage
                debtRemaining[circleId][msg.sender][r] -= contributionPart;
                if (m.debtOwed >= contributionPart) {
                    m.debtOwed -= contributionPart;
                    globalOutstandingDebt[msg.sender] -= contributionPart;
                    statuses[circleId].totalDebtOwed -= contributionPart;
                }

                if (debtRemaining[circleId][msg.sender][r] == 0) {
                    delete debtRecipient[circleId][msg.sender][r];
                }

                remainingToPay -= payment;
                emit DebtRepaid(circleId, msg.sender, to, contributionPart);
            }
        }

        if (m.debtOwed == 0) {
            m.isFlagged = false;
            isBlacklisted[msg.sender] = false;
        }
    }

    function _processPayout(uint256 circleId, address recipient) internal {
        uint256 fullPot = statuses[circleId].totalPot;
        uint256 immediate = fullPot;
        address token = configs[circleId].token;

        // Layer: Lazy Debt Balancing (Internal Restitution)
        FamMember storage m = members[circleId][recipient];
        if (m.pendingDebt > 0) {
            uint256 garnish = amountMin(immediate, m.pendingDebt);
            immediate -= garnish;
            m.pendingDebt -= garnish;
            
            // Distribute to victims
            uint256[] storage drs = memberDefaultedRounds[circleId][recipient];
            for (uint256 i = 0; i < drs.length; i++) {
                if (garnish == 0) break;
                
                uint256 r = drs[i];
                address victim = debtRecipient[circleId][recipient][r];
                uint256 dRem = debtRemaining[circleId][recipient][r];
                if (victim != address(0) && dRem > 0) {
                    uint256 penalty = _calculateLateFee(dRem);
                    uint256 totalNeeded = dRem + penalty;

                    uint256 repayment = amountMin(garnish, totalNeeded);
                    uint256 penaltyPart;
                    uint256 contributionPart;

                    if (repayment == totalNeeded) {
                        penaltyPart = penalty;
                        contributionPart = dRem;
                    } else {
                        penaltyPart = (repayment * penalty) / totalNeeded;
                        contributionPart = repayment - penaltyPart;
                    }

                    IERC20(token).safeTransfer(victim, contributionPart);
                    IERC20(token).safeTransfer(treasury, penaltyPart);
                    platformFeesByToken[token] += penaltyPart;
                    
                    emit FeeCollected(circleId, recipient, FeeType.LATE, penaltyPart);
                    
                    garnish -= repayment;
                    debtRemaining[circleId][recipient][r] -= contributionPart;
                    m.pendingDebt -= contributionPart;

                    if (debtRemaining[circleId][recipient][r] == 0) {
                        delete debtRecipient[circleId][recipient][r];
                    }
                    emit DebtRepaid(circleId, recipient, victim, contributionPart);
                }
            }
        }

        // Layer 6: Cross-Circle Payout Diversion
        if (globalOutstandingDebt[recipient] > 0 && immediate > 0) {
            uint256 baseDebt = globalOutstandingDebt[recipient];
            uint256 penalty = _calculateLateFee(baseDebt);
            uint256 totalDue = baseDebt + penalty;
            
            uint256 totalDiverted = amountMin(immediate, totalDue);
            
            // Simplified pro-rata division for diversion
            uint256 contributionDiverted;
            uint256 penaltyDiverted;
            
            if (totalDiverted == totalDue) {
                contributionDiverted = baseDebt;
                penaltyDiverted = penalty;
            } else {
                penaltyDiverted = (totalDiverted * penalty) / totalDue;
                contributionDiverted = totalDiverted - penaltyDiverted;
            }

            _handleDiversion(circleId, recipient, token, contributionDiverted, penaltyDiverted);
            immediate -= totalDiverted;
            
            globalOutstandingDebt[recipient] -= contributionDiverted;
        }

        // Payout Maintenance Fee (Layer 3)
        if (recipient != configs[circleId].creator) {
            uint256 mFee = amountMin(immediate, (fullPot * MAINT_FEE_BPS) / 10000);
            if (mFee > FIXED_FEE_AMOUNT) mFee = FIXED_FEE_AMOUNT;

            IERC20(token).safeTransfer(treasury, mFee);
            platformFeesByToken[token] += mFee;
            immediate -= mFee;
            
            emit FeeCollected(circleId, recipient, FeeType.MAINTENANCE, mFee);
        }

        // Transfer payout
        if (immediate > 0) {
            IERC20(token).safeTransfer(recipient, immediate);
        }

        emit PayoutDistributed(circleId, recipient, immediate);
        m.hasReceivedPayout = true;
        statuses[circleId].totalPot = 0;

        _progressNextRound(circleId, statuses[circleId].currentRound);
    }

    function _progressNextRound(uint256 circleId, uint256 round) internal {
        FamCircleStatus storage status = statuses[circleId];
        
        if (round < status.totalRounds) {
            status.currentRound = round + 1;
            status.contributionsThisRound = 0;
            circleRoundDeadlines[circleId][round + 1] = _nextDeadline(configs[circleId].frequency, block.timestamp);
        } else {
            status.state = CircleState.COMPLETED;
            
            address[] storage mlist = circleMemberList[circleId];
            for (uint256 i = 0; i < mlist.length; i++) {
                address mAddr = mlist[i];
                if (!members[circleId][mAddr].isFlagged && members[circleId][mAddr].roundsDefaulted == 0) {
                    goodStandingStreak[mAddr]++;
                }
                activeFamCircleCount[mAddr]--;
            }
        }
    }

    function _getByPos(uint256 circleId, uint256 pos) internal view returns (address) {
        address[] storage mlist = circleMemberList[circleId];
        for (uint256 i = 0; i < mlist.length; i++) {
            if (members[circleId][mlist[i]].position == pos) return mlist[i];
        }
        return address(0);
    }

    /**
     * @notice Allows a victim to claim owed funds from a debtor's global escrowpool.
     */
    function claimRestitution(address debtor, uint256 circleId, uint256 round) external nonReentrant {
        address victim = debtRecipient[circleId][debtor][round];
        uint256 baseDebt = debtRemaining[circleId][debtor][round];
        
        if (msg.sender != victim) revert OnlyRecipientAllowed();
        if (baseDebt == 0) revert MemberNotFlagged();
        
        if (globalDivertedFunds[debtor] < baseDebt) revert InsufficientFunds();

        globalDivertedFunds[debtor] -= baseDebt;
        debtRemaining[circleId][debtor][round] = 0;
        delete debtRecipient[circleId][debtor][round];
        
        address token = configs[circleId].token;
        IERC20(token).safeTransfer(victim, baseDebt);

        // Adjust debtor's profile if all debt cleared
        FamMember storage m = members[circleId][debtor];
        if (m.debtOwed >= baseDebt) {
            m.debtOwed -= baseDebt;
        }

        if (m.debtOwed == 0) {
            m.isFlagged = false;
            isBlacklisted[debtor] = false;
        }

        emit DebtRepaid(circleId, debtor, victim, baseDebt);
    }

    function _handleDiversion(uint256 circleId, address debtor, address token, uint256 amount, uint256 penalty) internal {
        // Penalty goes to platform
        IERC20(token).safeTransfer(treasury, penalty);
        platformFeesByToken[token] += penalty;

        emit FeeCollected(circleId, debtor, FeeType.LATE, penalty);

        // Principal goes to Bob's individual escrow
        globalDivertedFunds[debtor] += amount;
        
        emit PayoutDiverted(circleId, debtor, address(this), amount); 
    }

    function _calculateLateFee(uint256 amount) internal pure returns (uint256) {
        if (amount > LATE_FEE_THRESHOLD) {
            return LATE_FEE_FIXED;
        } else {
            return (amount * LATE_FEE_BPS) / 10000;
        }
    }

    function amountMin(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
