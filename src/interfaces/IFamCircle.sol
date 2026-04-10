// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IFamCircle {
    enum CircleState { PENDING, CREATED, ACTIVE, COMPLETED, DEAD }
    enum Frequency { DAILY, WEEKLY, MONTHLY }
    enum FeeType { CREATION, MAINTENANCE, LATE }

    // ============ Custom Errors ============
    error UserIsBlacklisted();
    error MaxActiveCirclesReached();
    error ReputationTooLow();
    error InsufficientCreatorBalance(uint256 current, uint256 required);
    error OnlyCreatorAllowed();
    error CircleNotActive();
    error AlreadyContributedThisRound();
    error MemberNotFlagged();
    error NotInvitedToCircle();
    error InsufficientVouches(uint256 current, uint256 required);
    error MinMembersNotMet(uint256 current, uint256 required);
    error CircleIsFull();
    error AlreadyAMember();
    error CannotVouchForSelf();
    error MaxVouchLimitReached();
    error AlreadyVouchedForMember();
    error InvalidCircleState();
    error NotACircleMember();
    error MaxMembersExceeded(uint256 current, uint256 limit);
    error TokenNotSupported();
    error AlreadyInvited();
    error ContributionTooLow(uint256 current, uint256 min);
    error ContributionTooHigh(uint256 current, uint256 max);
    error GracePeriodNotExpired();
    error BadRecord();

    struct FamCircleConfig {
        uint256 circleId;
        string title;
        string description;
        address creator;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 maxMembers;
        uint256 createdAt;
        address token;
    }

    struct FamCircleStatus {
        CircleState state;
        uint256 currentMembers;
        uint256 currentRound;
        uint256 totalRounds;
        uint256 startedAt;
        uint256 totalPot;
        uint256 totalDebtOwed;
        uint256 contributionsThisRound;
    }

    struct FamMember {
        uint256 position;
        uint256 totalContributed;
        bool hasReceivedPayout;
        bool isActive;
        bool isFlagged;
        uint256 debtOwed;
        uint256 pendingDebt;
        uint256 roundsDefaulted;
    }

    struct CreateParams {
        string title;
        string description;
        address token;
        uint256 contributionAmount;
        Frequency frequency;
        uint256 maxMembers;
        address[] initialInvitees;
    }

    event FamCircleCreated(uint256 indexed circleId, address indexed creator, uint256 contributionAmount, address token, Frequency frequency);
    event MemberInvited(uint256 indexed circleId, address indexed inviter, address indexed invitee);
    event MemberVouched(uint256 indexed circleId, address indexed voucher, address indexed member);
    event MemberJoined(uint256 indexed circleId, address indexed member);
    event MemberKicked(uint256 indexed circleId, address indexed member);
    event PayoutDistributed(uint256 indexed circleId, address indexed recipient, uint256 immediatePayout, uint256 creatorFeeReward);
    event MemberFlagged(uint256 indexed circleId, address indexed member, uint256 debtAdded);
    event DebtRepaid(uint256 indexed circleId, address indexed debtor, address indexed recipient, uint256 amount);
    event PayoutDiverted(uint256 indexed circleId, address indexed member, address indexed recipient, uint256 amount);
    event PositionSwapped(uint256 indexed circleId, address indexed member, address currentRecipient, uint256 oldPosition, uint256 newPosition);
    event FeeCollected(uint256 indexed circleId, address indexed member, FeeType feeType, uint256 amount);

    function createCircle(CreateParams calldata params) external returns (uint256);
    function inviteMembers(uint256 circleId, address[] calldata invitees) external;
    function vouchForMember(uint256 circleId, address member) external;
    function joinCircle(uint256 circleId) external;
    function contribute(uint256 circleId) external;
    function cancelCircle(uint256 circleId) external;
    function processForfeits(uint256 circleId, address[] calldata membersToForfeit) external;
    function repayCircleDebt(uint256 circleId, uint256 amount) external;
}
