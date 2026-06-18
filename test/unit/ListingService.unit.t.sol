// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/TestSetup.sol";
import "../../contracts/ListingService.sol";

/**
 * @title ListingServiceTests
 * @notice Unit tests for the ListingService curated wrapper (current API)
 * @dev Covers: initialize (+ re-init / zero-address reverts), owner-only access
 *      control on admin setters, collateral & loan-token whitelisting (including
 *      the per-token minBidStep rules and zero-address reverts), batch setters,
 *      view getters, pause/unpause, and the curated createListedAuction path
 *      (operator approval + bidStep resolution).
 *
 * API NOTES (verified against contracts/ListingService.sol):
 *   - initialize(address _loanProtocol)                       // no treasury / no fee
 *   - setCollateralWhitelist(address token, bool whitelisted)
 *   - setLoanTokenWhitelist(address token, bool whitelisted, uint256 minBidStep)
 *   - batchSetCollateralWhitelist(address[] tokens, bool whitelisted)
 *   - batchSetLoanTokenWhitelist(address[] tokens, uint256[] minBidSteps, bool whitelisted)
 *   - createListedAuction(collateralToken, collateralAmount, loanToken, loanAmount,
 *                         maxRepayment, loanDuration, auctionDuration, bidStep)
 *   - isCollateralWhitelisted / isLoanTokenWhitelisted / isListedAuction
 *   - public mappings: collateralWhitelist, loanTokenWhitelist, loanTokenMinBidSteps
 *
 * Removed vs old test: ALL treasury/fee logic (treasury, setTreasury, auctionFeeBps,
 *   setAuctionFee, marketplaceListingFee, setMarketplaceListingFee, listPositionWithFee,
 *   withdrawFees, calculateAuctionFee, getFeeConfiguration, getAccumulatedFees) — those
 *   functions no longer exist on the contract.
 * Added: per-token minBidStep behaviour (MinBidStepRequired, BidStepBelowTokenMinimum,
 *   bidStep==0 substitution), ArrayLengthMismatch on batch loan-token setter,
 *   re-initialization revert.
 */

// ============================================================================
// LISTING SERVICE TEST SETUP
// ============================================================================

/**
 * @dev Extends TestSetup by deploying ListingService via proxy, whitelisting
 *      both tokens (loan token with a non-zero minBidStep), and granting the
 *      service operator approval on the protocol from the relevant actors.
 */
abstract contract ListingServiceSetup is TestSetup {

    ListingService public listingService;

    /// @dev Per-token minimum bid step used when whitelisting the loan token.
    uint256 public constant LOAN_MIN_BID_STEP = 50e6; // 50 USDC

    function setUp() public virtual override {
        super.setUp();

        // Deploy ListingService implementation
        ListingService lsImpl = new ListingService();

        // Deploy ListingService proxy — initialize takes ONLY the protocol address
        ERC1967Proxy lsProxy = new ERC1967Proxy(
            address(lsImpl),
            abi.encodeCall(ListingService.initialize, (address(protocol)))
        );
        listingService = ListingService(address(lsProxy));

        // Whitelist both tokens (loan token requires a non-zero minBidStep)
        listingService.setCollateralWhitelist(address(collateralToken), true);
        listingService.setLoanTokenWhitelist(address(loanToken), true, LOAN_MIN_BID_STEP);

        // Grant ListingService operator approval from borrower so it can call
        // createAuctionFor on the borrower's behalf.
        vm.prank(borrower);
        protocol.setOperatorApproval(address(listingService), true);
    }

    /// @dev Borrower deposits collateral and creates a curated (listed) auction.
    function _createListedAuction() internal returns (uint256 auctionId) {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        auctionId = listingService.createListedAuction(
            address(collateralToken),
            DEFAULT_COLLATERAL,
            address(loanToken),
            DEFAULT_LOAN_AMOUNT,
            DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION,
            DEFAULT_AUCTION_DURATION,
            DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
}

// ============================================================================
// INITIALIZATION
// ============================================================================

contract ListingServiceInitTest is ListingServiceSetup {

    function test_initialize_setsCorrectState() public {
        assertEq(address(listingService.loanProtocol()), address(protocol));
        assertEq(listingService.owner(), address(this));
        assertEq(listingService.MAX_BATCH_SIZE(), 50);
    }

    function test_initialize_zeroProtocol_reverts() public {
        ListingService impl = new ListingService();
        vm.expectRevert(); // ZeroAddress (bubbled through proxy init)
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(ListingService.initialize, (address(0)))
        );
    }

    function test_initialize_reinit_reverts() public {
        // Already initialized in setUp — a second call must revert.
        vm.expectRevert(); // InvalidInitialization
        listingService.initialize(address(protocol));
    }
}

// ============================================================================
// TOKEN WHITELISTING
// ============================================================================

contract WhitelistTest is ListingServiceSetup {

    // ---- collateral ----

    function test_setCollateralWhitelist_add() public {
        address newToken = makeAddr("newToken");
        listingService.setCollateralWhitelist(newToken, true);
        assertTrue(listingService.isCollateralWhitelisted(newToken));
        assertTrue(listingService.collateralWhitelist(newToken));
    }

    function test_setCollateralWhitelist_remove() public {
        listingService.setCollateralWhitelist(address(collateralToken), false);
        assertFalse(listingService.isCollateralWhitelisted(address(collateralToken)));
    }

    function test_setCollateralWhitelist_zeroAddress_reverts() public {
        vm.expectRevert(ListingService.InvalidToken.selector);
        listingService.setCollateralWhitelist(address(0), true);
    }

    function test_setCollateralWhitelist_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        listingService.setCollateralWhitelist(makeAddr("token"), true);
    }

    // ---- loan token (+ minBidStep rules) ----

    function test_setLoanTokenWhitelist_add() public {
        address newToken = makeAddr("DAI");
        listingService.setLoanTokenWhitelist(newToken, true, 1e18);
        assertTrue(listingService.isLoanTokenWhitelisted(newToken));
        assertEq(listingService.loanTokenMinBidSteps(newToken), 1e18);
    }

    function test_setLoanTokenWhitelist_remove_clearsMinBidStep() public {
        // loanToken was whitelisted with LOAN_MIN_BID_STEP in setUp.
        assertEq(listingService.loanTokenMinBidSteps(address(loanToken)), LOAN_MIN_BID_STEP);

        // Unwhitelisting ignores minBidStep and clears the stored floor.
        listingService.setLoanTokenWhitelist(address(loanToken), false, 0);
        assertFalse(listingService.isLoanTokenWhitelisted(address(loanToken)));
        assertEq(listingService.loanTokenMinBidSteps(address(loanToken)), 0);
    }

    function test_setLoanTokenWhitelist_zeroMinBidStep_reverts() public {
        address newToken = makeAddr("USDT");
        vm.expectRevert(ListingService.MinBidStepRequired.selector);
        listingService.setLoanTokenWhitelist(newToken, true, 0);
    }

    function test_setLoanTokenWhitelist_zeroAddress_reverts() public {
        vm.expectRevert(ListingService.InvalidToken.selector);
        listingService.setLoanTokenWhitelist(address(0), true, 1e6);
    }

    function test_setLoanTokenWhitelist_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        listingService.setLoanTokenWhitelist(makeAddr("DAI"), true, 1e18);
    }
}

contract BatchWhitelistTest is ListingServiceSetup {

    // ---- collateral batch ----

    function test_batchSetCollateralWhitelist_success() public {
        address[] memory tokens = new address[](3);
        tokens[0] = makeAddr("token1");
        tokens[1] = makeAddr("token2");
        tokens[2] = makeAddr("token3");

        listingService.batchSetCollateralWhitelist(tokens, true);

        assertTrue(listingService.isCollateralWhitelisted(tokens[0]));
        assertTrue(listingService.isCollateralWhitelisted(tokens[1]));
        assertTrue(listingService.isCollateralWhitelisted(tokens[2]));
    }

    function test_batchSetCollateralWhitelist_remove() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(collateralToken);

        listingService.batchSetCollateralWhitelist(tokens, false);
        assertFalse(listingService.isCollateralWhitelisted(address(collateralToken)));
    }

    function test_batchSetCollateralWhitelist_tooLarge_reverts() public {
        address[] memory tokens = new address[](51);
        for (uint256 i = 0; i < 51; i++) {
            tokens[i] = address(uint160(i + 1));
        }
        vm.expectRevert(ListingService.BatchTooLarge.selector);
        listingService.batchSetCollateralWhitelist(tokens, true);
    }

    function test_batchSetCollateralWhitelist_containsZero_reverts() public {
        address[] memory tokens = new address[](2);
        tokens[0] = makeAddr("valid");
        tokens[1] = address(0);

        vm.expectRevert(ListingService.InvalidToken.selector);
        listingService.batchSetCollateralWhitelist(tokens, true);
    }

    function test_batchSetCollateralWhitelist_nonOwner_reverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("token");

        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        listingService.batchSetCollateralWhitelist(tokens, true);
    }

    // ---- loan-token batch (parallel minBidSteps array) ----

    function test_batchSetLoanTokenWhitelist_success() public {
        address[] memory tokens = new address[](2);
        tokens[0] = makeAddr("DAI");
        tokens[1] = makeAddr("USDT");

        uint256[] memory steps = new uint256[](2);
        steps[0] = 1e18;
        steps[1] = 25e6;

        listingService.batchSetLoanTokenWhitelist(tokens, steps, true);

        assertTrue(listingService.isLoanTokenWhitelisted(tokens[0]));
        assertTrue(listingService.isLoanTokenWhitelisted(tokens[1]));
        assertEq(listingService.loanTokenMinBidSteps(tokens[0]), 1e18);
        assertEq(listingService.loanTokenMinBidSteps(tokens[1]), 25e6);
    }

    function test_batchSetLoanTokenWhitelist_remove_clearsSteps() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(loanToken);
        uint256[] memory steps = new uint256[](1);
        steps[0] = 0; // ignored on removal

        listingService.batchSetLoanTokenWhitelist(tokens, steps, false);
        assertFalse(listingService.isLoanTokenWhitelisted(address(loanToken)));
        assertEq(listingService.loanTokenMinBidSteps(address(loanToken)), 0);
    }

    function test_batchSetLoanTokenWhitelist_tooLarge_reverts() public {
        address[] memory tokens = new address[](51);
        uint256[] memory steps = new uint256[](51);
        for (uint256 i = 0; i < 51; i++) {
            tokens[i] = address(uint160(i + 1));
            steps[i] = 1e6;
        }
        vm.expectRevert(ListingService.BatchTooLarge.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, steps, true);
    }

    function test_batchSetLoanTokenWhitelist_lengthMismatch_reverts() public {
        address[] memory tokens = new address[](2);
        tokens[0] = makeAddr("DAI");
        tokens[1] = makeAddr("USDT");
        uint256[] memory steps = new uint256[](1);
        steps[0] = 1e6;

        vm.expectRevert(ListingService.ArrayLengthMismatch.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, steps, true);
    }

    function test_batchSetLoanTokenWhitelist_zeroStep_reverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("DAI");
        uint256[] memory steps = new uint256[](1);
        steps[0] = 0;

        vm.expectRevert(ListingService.MinBidStepRequired.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, steps, true);
    }

    function test_batchSetLoanTokenWhitelist_containsZero_reverts() public {
        address[] memory tokens = new address[](2);
        tokens[0] = makeAddr("valid");
        tokens[1] = address(0);
        uint256[] memory steps = new uint256[](2);
        steps[0] = 1e6;
        steps[1] = 1e6;

        vm.expectRevert(ListingService.InvalidToken.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, steps, true);
    }

    function test_batchSetLoanTokenWhitelist_nonOwner_reverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("DAI");
        uint256[] memory steps = new uint256[](1);
        steps[0] = 1e18;

        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        listingService.batchSetLoanTokenWhitelist(tokens, steps, true);
    }
}

// ============================================================================
// PAUSE / UNPAUSE
// ============================================================================

contract ListingServicePauseTest is ListingServiceSetup {

    function test_pause_unpause() public {
        listingService.pause();

        // Cannot create listed auction while paused
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        vm.expectRevert(); // EnforcedPause
        listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();

        // Unpause restores functionality
        listingService.unpause();

        uint256 auctionId = _createListedAuction();
        assertGt(auctionId, 0);
    }

    function test_pause_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        listingService.pause();
    }

    function test_unpause_nonOwner_reverts() public {
        listingService.pause();
        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        listingService.unpause();
    }
}

// ============================================================================
// CREATE LISTED AUCTION (curated path + bidStep resolution)
// ============================================================================

contract CreateListedAuctionTest is ListingServiceSetup {

    function test_createListedAuction_success() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);

        uint256 auctionId = listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();

        // First auction id is 1 (++loanNonce)
        assertEq(auctionId, 1);

        // Auction created in protocol with correct borrower / status
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(auction.borrower, borrower);
        assertEq(uint(auction.status), uint(LoanProtocol.AuctionStatus.OPEN));

        // bidStep recorded as supplied (>= token minimum)
        assertEq(auction.bidStep, DEFAULT_BID_STEP);

        // Tracked as a listed auction
        assertTrue(listingService.isListedAuction(auctionId));
        assertTrue(listingService.listedAuctions(auctionId));
    }

    function test_createListedAuction_bidStepZero_usesTokenDefault() public {
        // bidStep == 0 substitutes the configured per-token minimum.
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        uint256 auctionId = listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, 0
        );
        vm.stopPrank();

        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(auction.bidStep, LOAN_MIN_BID_STEP);
    }

    function test_createListedAuction_bidStepBelowMinimum_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);

        vm.expectRevert(ListingService.BidStepBelowTokenMinimum.selector);
        listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION,
            LOAN_MIN_BID_STEP - 1
        );
        vm.stopPrank();
    }

    function test_createListedAuction_bidStepAtMinimum_succeeds() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        uint256 auctionId = listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION,
            LOAN_MIN_BID_STEP
        );
        vm.stopPrank();

        assertEq(protocol.getAuction(auctionId).bidStep, LOAN_MIN_BID_STEP);
    }

    function test_createListedAuction_collateralNotWhitelisted_reverts() public {
        TestMockERC20 rando = new TestMockERC20("Rando", "RND", 18);
        rando.mint(borrower, 1000e18);

        vm.startPrank(borrower);
        rando.approve(address(protocol), type(uint256).max);
        protocol.depositCollateral(address(rando), 100e18);

        vm.expectRevert(ListingService.TokenNotWhitelisted.selector);
        listingService.createListedAuction(
            address(rando), 100e18, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }

    function test_createListedAuction_loanTokenNotWhitelisted_reverts() public {
        TestMockERC20 rando = new TestMockERC20("Rando", "RND", 6);

        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);

        vm.expectRevert(ListingService.TokenNotWhitelisted.selector);
        listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(rando),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }

    function test_createListedAuction_insufficientCollateral_reverts() public {
        // Don't deposit any collateral
        vm.prank(borrower);
        vm.expectRevert(ListingService.InsufficientCollateral.selector);
        listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_createListedAuction_partialCollateral_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL - 1);

        vm.expectRevert(ListingService.InsufficientCollateral.selector);
        listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }

    function test_createListedAuction_withoutOperatorApproval_reverts() public {
        // lender2 never granted the service operator approval, so createAuctionFor
        // on their behalf must revert in the underlying protocol.
        vm.startPrank(lender2);
        // lender2 has no collateral token / no deposit; the whitelist + balance
        // checks pass only after a deposit, so deposit a fresh collateral first.
        // Mint + approve some collateral for lender2.
        collateralToken.mint(lender2, DEFAULT_COLLATERAL);
        collateralToken.approve(address(protocol), type(uint256).max);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);

        vm.expectRevert(); // OperatorNotApproved in LoanProtocol.createAuctionFor
        listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }

    function test_createListedAuction_whenPaused_reverts() public {
        listingService.pause();

        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);

        vm.expectRevert(); // EnforcedPause
        listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
}

// ============================================================================
// VIEW FUNCTIONS
// ============================================================================

contract ListingServiceViewTest is ListingServiceSetup {

    function test_isCollateralWhitelisted_reflectsState() public {
        assertTrue(listingService.isCollateralWhitelisted(address(collateralToken)));
        assertFalse(listingService.isCollateralWhitelisted(makeAddr("unknown")));
    }

    function test_isLoanTokenWhitelisted_reflectsState() public {
        assertTrue(listingService.isLoanTokenWhitelisted(address(loanToken)));
        assertFalse(listingService.isLoanTokenWhitelisted(makeAddr("unknown")));
    }

    function test_loanTokenMinBidSteps_view() public {
        assertEq(listingService.loanTokenMinBidSteps(address(loanToken)), LOAN_MIN_BID_STEP);
    }

    function test_isListedAuction_true() public {
        uint256 id = _createListedAuction();
        assertTrue(listingService.isListedAuction(id));
    }

    function test_isListedAuction_false() public {
        assertFalse(listingService.isListedAuction(999));
    }
}
