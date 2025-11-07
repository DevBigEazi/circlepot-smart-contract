// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.27;

import {ReputationSetup} from "./ReputationSetup.t.sol";
import {ReputationV1} from "../../src/ReputationV1.sol";

/**
 * @title ReputationBasic
 * @dev Basic test cases for Reputation contract with credit score system (300-850)
 */
contract ReputationBasic is ReputationSetup {
    // ============ Initialization Tests ============

    function test_initializer() public view {
        assertEq(reputation.owner(), owner);
        assertEq(reputation.VERSION(), 1);
        assertEq(reputation.MIN_SCORE(), 300);
        assertEq(reputation.MAX_SCORE(), 850);
        assertEq(reputation.DEFAULT_SCORE(), 300);
    }

    // ============ Authorization Tests ============

    function test_contractAuthorization() public {
        address mockContract = makeAddr("mockContract");

        vm.prank(owner);
        reputation.authorizeContract(mockContract);

        assertTrue(reputation.authorizedContracts(mockContract));
    }

    function test_contractDeauthorization() public {
        address mockContract = makeAddr("mockContract");

        vm.startPrank(owner);
        reputation.authorizeContract(mockContract);
        assertTrue(reputation.authorizedContracts(mockContract));

        reputation.revokeContract(mockContract);
        assertFalse(reputation.authorizedContracts(mockContract));
        vm.stopPrank();
    }

    function test_revertNotAuthorized() public {
        vm.expectRevert(ReputationV1.UnauthorizedContract.selector);
        reputation.increaseReputation(user1, 10, "Test");
    }

    function test_onlyOwnerCanAuthorize() public {
        address mockContract = makeAddr("mockContract");

        vm.prank(user1);
        vm.expectRevert();
        reputation.authorizeContract(mockContract);
    }

    function test_onlyOwnerCanRevoke() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(user1);
        vm.expectRevert();
        reputation.revokeContract(mockContract);
    }

    // ============ Score Initialization Tests ============

    function test_newUserHasDefaultScore() public view {
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 300, "New user should have default score of 300");
    }

    function test_getUserReputationData_NewUser() public view {
        (uint256 positiveActions, uint256 negativeActions, uint256 circlesCompleted, uint256 score) =
            reputation.getUserReputationData(user1);

        assertEq(positiveActions, 0);
        assertEq(negativeActions, 0);
        assertEq(circlesCompleted, 0);
        assertEq(score, 300); // Default score
    }

    // ============ Reputation Increase Tests ============

    function test_reputationIncrease_PoorScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 10, "Test Increase");

        // Poor score (300): 10 × 5 = 50 point increase
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 350, "Poor score should get 5X multiplier");
    }

    function test_reputationIncrease_FairScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        // Get user to Fair score (600)
        reputation.increaseReputation(user1, 60, "Setup"); // 300 + (60×5) = 600

        // Now increase from Fair
        reputation.increaseReputation(user1, 10, "Test");
        vm.stopPrank();

        // Fair score (600): 10 × 4 = 40 point increase
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 640, "Fair score should get 4X multiplier");
    }

    function test_reputationIncrease_GoodScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        // Get to Good score (700)
        reputation.increaseReputation(user1, 80, "Setup"); // 300 + (80×5) = 700

        reputation.increaseReputation(user1, 10, "Test");
        vm.stopPrank();

        // Good score (700): 10 × 3 = 30 point increase
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 730, "Good score should get 3X multiplier");
    }

    function test_reputationIncrease_VeryGoodScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        // Get to Very Good score (750)
        reputation.increaseReputation(user1, 90, "Setup"); // 300 + (90×5) = 750

        reputation.increaseReputation(user1, 10, "Test");
        vm.stopPrank();

        // Very Good score (750): 10 × 2 = 20 point increase
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 770, "Very Good score should get 2X multiplier");
    }

    function test_reputationIncrease_ExceptionalScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        // Get to Exceptional score (820)
        reputation.increaseReputation(user1, 104, "Setup"); // 300 + (104×5) = 820

        reputation.increaseReputation(user1, 10, "Test");
        vm.stopPrank();

        // Exceptional score (820): 10 × 1 = 10 point increase
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 830, "Exceptional score should get 1X multiplier");
    }

    function test_reputationIncrease_CappedAtMaxScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        // Get close to max
        reputation.increaseReputation(user1, 110, "Setup"); // 300 + (110×5) = 850 (capped)

        // Try to increase more
        reputation.increaseReputation(user1, 10, "Test");
        vm.stopPrank();

        uint256 score = reputation.getReputation(user1);
        assertEq(score, 850, "Score should be capped at 850");
    }

    function test_reputationIncrease_TracksPositiveActions() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 10, "Action 1");
        reputation.increaseReputation(user1, 10, "Action 2");
        vm.stopPrank();

        (uint256 positiveActions,,,) = reputation.getUserReputationData(user1);
        assertEq(positiveActions, 2, "Should track positive actions");
    }

    function test_reputationIncrease_GoalCompletion_TracksGoals() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 10, "Goal completed");

        ReputationV1.UserReputation memory userRep = _getUserReputation(user1);
        assertEq(userRep.goalsCompleted, 1, "Should track goal completion");
    }

    function test_reputationIncrease_GoalTarget_TracksStreak() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 10, "Goal target reached");

        ReputationV1.UserReputation memory userRep = _getUserReputation(user1);
        assertEq(userRep.consecutiveOnTimePayments, 1, "Should track payment streak");
    }

    // ============ Reputation Decrease Tests ============

    function test_reputationDecrease_PoorScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 10, "Setup"); // Score: 350
        reputation.decreaseReputation(user1, 5, "Test Decrease");
        vm.stopPrank();

        // Poor score (350): 5 × 3 = 15 point decrease
        // 350 - 15 = 335
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 335, "Poor score should get 3X penalty");
    }

    function test_reputationDecrease_FairScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 60, "Setup"); // Score: 600
        reputation.decreaseReputation(user1, 5, "Test");
        vm.stopPrank();

        // Fair score (600): 5 × 4 = 20 point decrease
        // 600 - 20 = 580
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 580, "Fair score should get 4X penalty");
    }

    function test_reputationDecrease_GoodScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 80, "Setup"); // Score: 700
        reputation.decreaseReputation(user1, 5, "Test");
        vm.stopPrank();

        // Good score (700): 5 × 5 = 25 point decrease
        // 700 - 25 = 675
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 675, "Good score should get 5X penalty");
    }

    function test_reputationDecrease_VeryGoodScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 90, "Setup"); // Score: 750
        reputation.decreaseReputation(user1, 5, "Test");
        vm.stopPrank();

        // Very Good score (750): 5 × 6 = 30 point decrease
        // 750 - 30 = 720
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 720, "Very Good score should get 6X penalty");
    }

    function test_reputationDecrease_ExceptionalScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 104, "Setup"); // Score: 820
        reputation.decreaseReputation(user1, 5, "Test");
        vm.stopPrank();

        // Exceptional score (820): 5 × 8 = 40 point decrease
        // 820 - 40 = 780
        uint256 score = reputation.getReputation(user1);
        assertEq(score, 780, "Exceptional score should get 8X penalty");
    }

    function test_reputationDecrease_FlooredAtMinScore() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.decreaseReputation(user1, 100, "Large decrease");

        uint256 score = reputation.getReputation(user1);
        assertEq(score, 300, "Score should be floored at 300");
    }

    function test_reputationDecrease_ResetsStreak() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 10, "Goal completed"); // Sets streak
        reputation.decreaseReputation(user1, 5, "Penalty");
        vm.stopPrank();

        ReputationV1.UserReputation memory userRep = _getUserReputation(user1);
        assertEq(userRep.consecutiveOnTimePayments, 0, "Should reset payment streak");
    }

    function test_reputationDecrease_TracksNegativeActions() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.decreaseReputation(user1, 5, "Action 1");
        reputation.decreaseReputation(user1, 5, "Action 2");
        vm.stopPrank();

        (, uint256 negativeActions,,) = reputation.getUserReputationData(user1);
        assertEq(negativeActions, 2, "Should track negative actions");
    }

    function test_reputationDecrease_LatePayment_TracksLatePayments() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.decreaseReputation(user1, 5, "Late Payment");
        // Explicitly call recordLatePayment since we removed the automatic tracking in decreaseReputation
        reputation.recordLatePayment(user1, 1, 1, 1);
        vm.stopPrank();

        ReputationV1.UserReputation memory userRep = _getUserReputation(user1);
        assertEq(userRep.latePayments, 1, "Should track late payments");
    }

    // ============ Circle Completion Tests ============

    function test_recordCircleCompletion() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.recordCircleCompleted(user1, 1);

        (,, uint256 circles,) = reputation.getUserReputationData(user1);
        assertEq(circles, 1, "Should record circle completion");
    }

    function test_recordCircleCompletion_Multiple() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.recordCircleCompleted(user1, 1);
        reputation.recordCircleCompleted(user1, 2);
        reputation.recordCircleCompleted(user1, 3);
        vm.stopPrank();

        (,, uint256 circles,) = reputation.getUserReputationData(user1);
        assertEq(circles, 3, "Should track multiple circle completions");
    }

    // ============ Late Payment Tests ============

    function test_recordLatePayment() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.recordLatePayment(user1, 1, 1, 1);

        ReputationV1.UserReputation memory userRep = _getUserReputation(user1);
        assertEq(userRep.latePayments, 1, "Should record late payment");
    }

    function test_recordLatePayment_Multiple() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.recordLatePayment(user1, 1, 1, 1);
        reputation.recordLatePayment(user1, 1, 1, 1);
        vm.stopPrank();

        ReputationV1.UserReputation memory userRep = _getUserReputation(user1);
        assertEq(userRep.latePayments, 2, "Should track multiple late payments");
    }

    // ============ Score Category Tests ============

    function test_getScoreCategory_Poor() public view {
        // Default score is 300 (Poor)
        ReputationV1.ScoreCategory category = reputation.getScoreCategory(user1);
        assertEq(uint256(category), uint256(ReputationV1.ScoreCategory.POOR));
    }

    function test_getScoreCategory_Fair() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 60, "Setup"); // 300 + (60×5) = 600

        ReputationV1.ScoreCategory category = reputation.getScoreCategory(user1);
        assertEq(uint256(category), uint256(ReputationV1.ScoreCategory.FAIR));
    }

    function test_getScoreCategory_Good() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 80, "Setup"); // 300 + (80×5) = 700

        ReputationV1.ScoreCategory category = reputation.getScoreCategory(user1);
        assertEq(uint256(category), uint256(ReputationV1.ScoreCategory.GOOD));
    }

    function test_getScoreCategory_VeryGood() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 90, "Setup"); // 300 + (90×5) = 750

        ReputationV1.ScoreCategory category = reputation.getScoreCategory(user1);
        assertEq(uint256(category), uint256(ReputationV1.ScoreCategory.VERY_GOOD));
    }

    function test_getScoreCategory_Exceptional() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 110, "Setup"); // 300 + (110×5) = 850 (capped)

        ReputationV1.ScoreCategory category = reputation.getScoreCategory(user1);
        assertEq(uint256(category), uint256(ReputationV1.ScoreCategory.EXCEPTIONAL));
    }

    function test_getScoreCategoryString_AllCategories() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        // Poor (default 300)
        string memory cat = reputation.getScoreCategoryString(user1);
        assertEq(cat, "Poor (300-579)");

        vm.startPrank(mockContract);

        // Fair (600) - Need to increase by 60 points * 5 multiplier = 300 points
        reputation.increaseReputation(user1, 60, "Setup");
        cat = reputation.getScoreCategoryString(user1);
        assertEq(cat, "Fair (580-669)");

        // Good (700) - From 600 to 700 = 100 points needed
        // At Fair (600), multiplier is 4X, so need 25 base points: 25 * 4 = 100
        reputation.increaseReputation(user1, 25, "Setup");
        cat = reputation.getScoreCategoryString(user1);
        assertEq(cat, "Good (670-739)");

        // Very Good (750) - From 700 to 750 = 50 points needed
        // At Good (700), multiplier is 3X, so need 17 base points: 17 * 3 = 51
        reputation.increaseReputation(user1, 17, "Setup");
        cat = reputation.getScoreCategoryString(user1);
        assertEq(cat, "Very Good (740-799)");

        // Exceptional (820) - From 751 to 820 = 69 points needed
        // At Very Good (751), multiplier is 2X, so need 35 base points: 35 * 2 = 70
        reputation.increaseReputation(user1, 35, "Setup");
        cat = reputation.getScoreCategoryString(user1);
        assertEq(cat, "Exceptional (800-850)");

        vm.stopPrank();
    }

    // ============ Feature Gating Tests ============
    function test_meetsScoreRequirement() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        // Default score 300
        assertFalse(reputation.meetsScoreRequirement(user1, 600));

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 60, "Setup"); // Score: 600

        assertTrue(reputation.meetsScoreRequirement(user1, 600));
    }

    function test_canCreateLargeGoal() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        // Default score 300
        assertFalse(reputation.canCreateLargeGoal(user1));

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 60, "Setup"); // Score: 600

        assertTrue(reputation.canCreateLargeGoal(user1));
    }

    function test_canCreateCircle() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        // Default score 300
        assertFalse(reputation.canCreateCircle(user1));

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 56, "Setup"); // Score: 580

        assertTrue(reputation.canCreateCircle(user1));
    }

    function test_hasPremiumAccess() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        // Default score 300
        assertFalse(reputation.hasPremiumAccess(user1));

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 88, "Setup"); // Score: 740

        assertTrue(reputation.hasPremiumAccess(user1));
    }

    // ============ Penalty Multiplier Tests ============

    function test_getPenaltyMultiplier_Poor() public view {
        uint256 multiplier = reputation.getPenaltyMultiplier(user1); // Score: 300
        assertEq(multiplier, 10000, "Poor score: no reduction (100%)");
    }

    function test_getPenaltyMultiplier_Fair() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 60, "Setup"); // Score: 600

        uint256 multiplier = reputation.getPenaltyMultiplier(user1);
        assertEq(multiplier, 9500, "Fair score: 5% reduction");
    }

    function test_getPenaltyMultiplier_Good() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 80, "Setup"); // Score: 700

        uint256 multiplier = reputation.getPenaltyMultiplier(user1);
        assertEq(multiplier, 8500, "Good score: 15% reduction");
    }

    function test_getPenaltyMultiplier_VeryGood() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 90, "Setup"); // Score: 750

        uint256 multiplier = reputation.getPenaltyMultiplier(user1);
        assertEq(multiplier, 7000, "Very Good score: 30% reduction");
    }

    function test_getPenaltyMultiplier_Exceptional() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 110, "Setup"); // Score: 850

        uint256 multiplier = reputation.getPenaltyMultiplier(user1);
        assertEq(multiplier, 5000, "Exceptional score: 50% reduction");
    }

    // ============ Collateral Multiplier Tests ============
    function test_getCollateralMultiplier_AllScores() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        // Poor (300): 100%
        uint256 mult = reputation.getCollateralMultiplier(user1);
        assertEq(mult, 10000);

        vm.startPrank(mockContract);

        // Fair (600): 95%
        reputation.increaseReputation(user1, 60, "Setup");
        mult = reputation.getCollateralMultiplier(user1);
        assertEq(mult, 9500);

        // Good (700): 90%
        reputation.increaseReputation(user1, 25, "Setup");
        mult = reputation.getCollateralMultiplier(user1);
        assertEq(mult, 9000);

        // Very Good (750): 85%
        reputation.increaseReputation(user1, 17, "Setup");
        mult = reputation.getCollateralMultiplier(user1);
        assertEq(mult, 8500);

        // Exceptional (820): 80%
        reputation.increaseReputation(user1, 35, "Setup");
        mult = reputation.getCollateralMultiplier(user1);
        assertEq(mult, 8000);

        vm.stopPrank();
    }

    // ============ Reputation Details Tests ============

    function test_getUserReputationDetails_Complete() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 20, "Goal completed");
        reputation.increaseReputation(user1, 10, "Contribution");
        reputation.recordCircleCompleted(user1, 1);
        reputation.recordLatePayment(user1, 1, 1, 1);
        reputation.decreaseReputation(user1, 5, "Late Payment");
        vm.stopPrank();

        (
            uint256 score,
            ReputationV1.ScoreCategory category,
            uint256 positiveActions,
            uint256 negativeActions,
            uint256 consecutivePayments,
            uint256 circlesCompleted,
            uint256 goalsCompleted,
            uint256 latePayments,
            uint256 lastUpdated
        ) = reputation.getUserReputationDetails(user1);

        assertGt(score, 300);
        assertEq(uint256(category), uint256(ReputationV1.ScoreCategory.POOR)); // Still poor after penalties
        assertEq(positiveActions, 2);
        assertEq(negativeActions, 1);
        assertEq(consecutivePayments, 0); // Reset by decrease
        assertEq(circlesCompleted, 1);
        assertEq(goalsCompleted, 1);
        assertEq(latePayments, 1); // Only one from recordLatePayment, since we removed tracking from decreaseReputation
        assertGt(lastUpdated, 0);
    }

    // ============ Reputation History Tests ============

    function test_getReputationHistory() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 10, "Action 1");
        reputation.increaseReputation(user1, 5, "Action 2");
        reputation.decreaseReputation(user1, 3, "Penalty");
        vm.stopPrank();

        ReputationV1.ReputationHistory[] memory history = reputation.getReputationHistory(user1);

        assertEq(history.length, 3);
        assertEq(history[0].reason, "Action 1");
        assertEq(history[1].reason, "Action 2");
        assertEq(history[2].reason, "Penalty");
        assertGt(history[0].scoreChange, 0); // Increase
        assertLt(history[2].scoreChange, 0); // Decrease
    }

    // ============ Event Tests ============

    function test_emitsReputationIncreasedEvent() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.expectEmit(true, true, true, true);
        emit ReputationV1.ReputationIncreased(user1, 50, "Test", 350);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 10, "Test");
    }

    function test_emitsReputationDecreasedEvent() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.startPrank(mockContract);
        reputation.increaseReputation(user1, 20, "Setup");

        vm.expectEmit(true, true, true, true);
        emit ReputationV1.ReputationDecreased(user1, 15, "Test", 385);

        reputation.decreaseReputation(user1, 5, "Test");
        vm.stopPrank();
    }

    function test_emitsScoreCategoryChangedEvent() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.expectEmit(true, true, true, true);
        emit ReputationV1.ScoreCategoryChanged(user1, ReputationV1.ScoreCategory.POOR, ReputationV1.ScoreCategory.FAIR);

        vm.prank(mockContract);
        reputation.increaseReputation(user1, 60, "Upgrade"); // 300 -> 600 (Poor -> Fair)
    }

    function test_emitsContractAuthorizedEvent() public {
        address mockContract = makeAddr("mockContract");

        vm.expectEmit(true, true, true, true);
        emit ReputationV1.ContractAuthorized(mockContract);

        vm.prank(owner);
        reputation.authorizeContract(mockContract);
    }

    function test_emitsContractRevokedEvent() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.expectEmit(true, true, true, true);
        emit ReputationV1.ContractRevoked(mockContract);

        vm.prank(owner);
        reputation.revokeContract(mockContract);
    }

    function test_emitsCircleCompletedEvent() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.expectEmit(true, true, true, true);
        emit ReputationV1.CircleCompleted(user1, 1, 1);

        vm.prank(mockContract);
        reputation.recordCircleCompleted(user1, 1);
    }

    function test_emitsLatePaymentRecordedEvent() public {
        address mockContract = makeAddr("mockContract");
        _authorizeContract(mockContract);

        vm.expectEmit(true, true, true, true);
        emit ReputationV1.LatePaymentRecorded(user1, 1, 1, 1, 1);

        vm.prank(mockContract);
        reputation.recordLatePayment(user1, 1, 1, 1);
    }

    // ============ Helper Function ============
    function _getUserReputation(address _user) internal view returns (ReputationV1.UserReputation memory) {
        (
            uint256 score,
            ,
            uint256 positiveActions,
            uint256 negativeActions,
            uint256 consecutivePayments,
            uint256 circlesCompleted,
            uint256 goalsCompleted,
            uint256 latePayments,
            uint256 lastUpdated
        ) = reputation.getUserReputationDetails(_user);

        return ReputationV1.UserReputation({
            score: score,
            totalPositiveActions: positiveActions,
            totalNegativeActions: negativeActions,
            consecutiveOnTimePayments: consecutivePayments,
            circlesCompleted: circlesCompleted,
            goalsCompleted: goalsCompleted,
            latePayments: latePayments,
            lastUpdated: lastUpdated,
            isInitialized: true
        });
    }

    function _authorizeContract(address _contract) internal override {
        vm.prank(owner);
        reputation.authorizeContract(_contract);
    }
}
