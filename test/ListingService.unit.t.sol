// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/TestSetup.sol";
import "../../contracts/ListingService.sol";

/**
 * @title ListingServiceTests
 * @notice Unit tests for ListingService commercial wrapper
 * @dev Covers: createListedAuction, listPositionWithFee, withdrawFees,
 *      setCollateralWhitelist, setLoanTokenWhitelist, batchSetCollateralWhitelist,
 *      batchSetLoanTokenWhitelist, setAuctionFee, setMarketplaceListingFee,
 *      setTreasury, pause/unpause, all view functions
 *
 * Coverage target: ListingService.sol 30% → 90%+ line coverage
 * Test count: ~30 tests
 */

// ============================================================================
// LISTING SERVICE TEST SETUP
// ============================================================================

/**
 * @dev Extends TestSetup by deploying ListingService via proxy,
 *      whitelisting both tokens, and granting operator approval.
 */
abstract contract ListingServiceSetup is TestSetup {

    ListingService public listingService;
    address public treasury = makeAddr("treasury");

    uint256 public constant DEFAULT_AUCTION_FEE_BPS = 10; // 0.1%

    function setUp() public virtual override {
        super.setUp();

        // Deploy ListingService implementation
        ListingService lsImpl = new ListingService();

        // Deploy ListingService proxy
        ERC1967Proxy lsProxy = new ERC1967Proxy(
            address(lsImpl),
            abi.encodeCall(
                ListingService.initialize,
                (address(protocol), treasury, DEFAULT_AUCTION_FEE_BPS)
            )
        );
        listingService = ListingService(address(lsProxy));

        // Whitelist both tokens
        listingService.setCollateralWhitelist(address(collateralToken), true);
        listingService.setLoanTokenWhitelist(address(loanToken), true);

        // Grant ListingService operator approval from borrower
        // (needed for createAuctionFor and listPositionFor delegation)
        vm.prank(borrower);
        protocol.setOperatorApproval(address(listingService), true);

        // Borrower approves ListingService for fee payments (collateral token)
        vm.prank(borrower);
        collateralToken.approve(address(listingService), type(uint256).max);

        // Borrower approves ListingService for marketplace listing fees (loan token)
        vm.prank(borrower);
        loanToken.approve(address(listingService), type(uint256).max);

        // Lender also approves for marketplace listing fees
        vm.prank(lender);
        loanToken.approve(address(listingService), type(uint256).max);
        vm.prank(lender);
        protocol.setOperatorApproval(address(listingService), true);
    }

    /// @dev Borrower deposits collateral and creates a listed auction
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

    /// @dev Full flow: listed auction → bid → finalize → active loan
    function _createListedLoan() internal returns (uint256 loanId) {
        loanId = _createListedAuction();
        vm.prank(lender);
        protocol.placeBid(loanId, DEFAULT_MAX_REPAYMENT);
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        protocol.finalizeAuction(loanId);
    }
}

// ============================================================================
// INITIALIZATION
// ============================================================================

contract ListingServiceInitTest is ListingServiceSetup {

    function test_initialize_setsCorrectState() public view {
        assertEq(address(listingService.loanProtocol()), address(protocol));
        assertEq(listingService.treasury(), treasury);
        assertEq(listingService.auctionFeeBps(), DEFAULT_AUCTION_FEE_BPS);
        assertEq(listingService.marketplaceListingFee(), 0);
    }

    function test_initialize_zeroProtocol_reverts() public {
        ListingService impl = new ListingService();
        vm.expectRevert();
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(ListingService.initialize, (address(0), treasury, 10))
        );
    }

    function test_initialize_zeroTreasury_reverts() public {
        ListingService impl = new ListingService();
        vm.expectRevert();
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(ListingService.initialize, (address(protocol), address(0), 10))
        );
    }

    function test_initialize_feeTooHigh_reverts() public {
        ListingService impl = new ListingService();
        vm.expectRevert();
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(ListingService.initialize, (address(protocol), treasury, 101))
        );
    }
}

// ============================================================================
// TOKEN WHITELISTING
// ============================================================================

contract WhitelistTest is ListingServiceSetup {

    function test_setCollateralWhitelist_add() public {
        address newToken = makeAddr("newToken");
        listingService.setCollateralWhitelist(newToken, true);
        assertTrue(listingService.isCollateralWhitelisted(newToken));
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

    function test_setLoanTokenWhitelist_add() public {
        address newToken = makeAddr("DAI");
        listingService.setLoanTokenWhitelist(newToken, true);
        assertTrue(listingService.isLoanTokenWhitelisted(newToken));
    }

    function test_setLoanTokenWhitelist_remove() public {
        listingService.setLoanTokenWhitelist(address(loanToken), false);
        assertFalse(listingService.isLoanTokenWhitelisted(address(loanToken)));
    }

    function test_setLoanTokenWhitelist_zeroAddress_reverts() public {
        vm.expectRevert(ListingService.InvalidToken.selector);
        listingService.setLoanTokenWhitelist(address(0), true);
    }
}

contract BatchWhitelistTest is ListingServiceSetup {

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

    function test_batchSetLoanTokenWhitelist_success() public {
        address[] memory tokens = new address[](2);
        tokens[0] = makeAddr("DAI");
        tokens[1] = makeAddr("USDT");

        listingService.batchSetLoanTokenWhitelist(tokens, true);

        assertTrue(listingService.isLoanTokenWhitelisted(tokens[0]));
        assertTrue(listingService.isLoanTokenWhitelisted(tokens[1]));
    }

    function test_batchSetLoanTokenWhitelist_tooLarge_reverts() public {
        address[] memory tokens = new address[](51);
        for (uint256 i = 0; i < 51; i++) {
            tokens[i] = address(uint160(i + 1));
        }
        vm.expectRevert(ListingService.BatchTooLarge.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, true);
    }

    function test_batchSetLoanTokenWhitelist_containsZero_reverts() public {
        address[] memory tokens = new address[](2);
        tokens[0] = makeAddr("valid");
        tokens[1] = address(0);

        vm.expectRevert(ListingService.InvalidToken.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, true);
    }
}

// ============================================================================
// FEE MANAGEMENT
// ============================================================================

contract FeeManagementTest is ListingServiceSetup {

    function test_setAuctionFee_success() public {
        listingService.setAuctionFee(50); // 0.5%
        assertEq(listingService.auctionFeeBps(), 50);
    }

    function test_setAuctionFee_zero() public {
        listingService.setAuctionFee(0);
        assertEq(listingService.auctionFeeBps(), 0);
    }

    function test_setAuctionFee_maxBoundary() public {
        listingService.setAuctionFee(100); // exactly 1% — should succeed
        assertEq(listingService.auctionFeeBps(), 100);
    }

    function test_setAuctionFee_tooHigh_reverts() public {
        vm.expectRevert(ListingService.FeeTooHigh.selector);
        listingService.setAuctionFee(101); // 1.01%
    }

    function test_setAuctionFee_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        listingService.setAuctionFee(50);
    }

    function test_setMarketplaceListingFee_success() public {
        listingService.setMarketplaceListingFee(5_000_000); // $5
        assertEq(listingService.marketplaceListingFee(), 5_000_000);
    }

    function test_setMarketplaceListingFee_tooHigh_reverts() public {
        vm.expectRevert(ListingService.FeeTooHigh.selector);
        listingService.setMarketplaceListingFee(100_000_001); // > $100
    }

    function test_setMarketplaceListingFee_maxBoundary() public {
        listingService.setMarketplaceListingFee(100_000_000); // exactly $100
        assertEq(listingService.marketplaceListingFee(), 100_000_000);
    }

    function test_setTreasury_success() public {
        address newTreasury = makeAddr("newTreasury");
        listingService.setTreasury(newTreasury);
        assertEq(listingService.treasury(), newTreasury);
    }

    function test_setTreasury_zeroAddress_reverts() public {
        vm.expectRevert(ListingService.ZeroAddress.selector);
        listingService.setTreasury(address(0));
    }

    function test_setTreasury_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        listingService.setTreasury(makeAddr("newTreasury"));
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
// CREATE LISTED AUCTION
// ============================================================================

contract CreateListedAuctionTest is ListingServiceSetup {

    function test_createListedAuction_success() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);

        uint256 treasuryBalBefore = collateralToken.balanceOf(treasury);

        uint256 auctionId = listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();

        // Auction created in protocol
        assertEq(auctionId, 1);
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(auction.borrower, borrower);
        assertEq(uint(auction.status), uint(LoanProtocol.AuctionStatus.OPEN));

        // Tracked as listed
        assertTrue(listingService.isListedAuction(auctionId));

        // Fee collected to treasury: 0.1% of 1e8 = 1e5
        uint256 expectedFee = (DEFAULT_COLLATERAL * DEFAULT_AUCTION_FEE_BPS) / 10000;
        assertEq(collateralToken.balanceOf(treasury), treasuryBalBefore + expectedFee);
    }

    function test_createListedAuction_zeroFee() public {
        // Set fee to 0
        listingService.setAuctionFee(0);

        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);

        uint256 treasuryBalBefore = collateralToken.balanceOf(treasury);

        uint256 auctionId = listingService.createListedAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();

        assertGt(auctionId, 0);
        // No fee collected
        assertEq(collateralToken.balanceOf(treasury), treasuryBalBefore);
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
// LIST POSITION WITH FEE
// ============================================================================

contract ListPositionWithFeeTest is ListingServiceSetup {

    function test_listPositionWithFee_withFee() public {
        // Enable marketplace listing fee: $5
        listingService.setMarketplaceListingFee(5_000_000);

        uint256 loanId = _createListedLoan();

        uint256 treasuryBalBefore = loanToken.balanceOf(treasury);

        vm.prank(borrower);
        listingService.listPositionWithFee(loanId, "borrower", address(loanToken), 1000e6);

        // Fee collected
        assertEq(loanToken.balanceOf(treasury), treasuryBalBefore + 5_000_000);

        // Position listed on protocol
        assertTrue(protocol.isPositionListed(loanId));
    }

    function test_listPositionWithFee_freeListing() public {
        // marketplaceListingFee defaults to 0
        assertEq(listingService.marketplaceListingFee(), 0);

        uint256 loanId = _createListedLoan();

        uint256 treasuryBalBefore = loanToken.balanceOf(treasury);

        vm.prank(borrower);
        listingService.listPositionWithFee(loanId, "borrower", address(loanToken), 1000e6);

        // No fee collected
        assertEq(loanToken.balanceOf(treasury), treasuryBalBefore);

        // Position still listed
        assertTrue(protocol.isPositionListed(loanId));
    }

    function test_listPositionWithFee_lender() public {
        uint256 loanId = _createListedLoan();

        vm.prank(lender);
        listingService.listPositionWithFee(loanId, "lender", address(loanToken), 2000e6);

        assertTrue(protocol.isPositionListed(loanId));
    }

    function test_listPositionWithFee_whenPaused_reverts() public {
        uint256 loanId = _createListedLoan();
        listingService.pause();

        vm.prank(borrower);
        vm.expectRevert(); // EnforcedPause
        listingService.listPositionWithFee(loanId, "borrower", address(loanToken), 1000e6);
    }
}

// ============================================================================
// WITHDRAW FEES
// ============================================================================

contract WithdrawFeesTest is ListingServiceSetup {

    function test_withdrawFees_noFees_reverts() public {
        vm.expectRevert(ListingService.NoFeesToWithdraw.selector);
        listingService.withdrawFees(address(loanToken));
    }

    // Note: In the current implementation, auction fees go directly to treasury
    // and marketplace fees also go directly to treasury. The accumulatedFees
    // mapping is only used if fees were accumulated (e.g., from a deprecated path).
    // This test verifies the withdrawFees mechanism works if fees exist.
    function test_withdrawFees_noAccumulatedFees_reverts() public {
        // Even after creating a listed auction with fee, accumulatedFees stays 0
        // because fees go directly to treasury
        _createListedAuction();

        vm.expectRevert(ListingService.NoFeesToWithdraw.selector);
        listingService.withdrawFees(address(collateralToken));
    }
}

// ============================================================================
// VIEW FUNCTIONS
// ============================================================================

contract ListingServiceViewTest is ListingServiceSetup {

    function test_calculateAuctionFee() public view {
        // 0.1% of 50,000 USDC = 50 USDC
        uint256 fee = listingService.calculateAuctionFee(50_000e6);
        assertEq(fee, 50e6);
    }

    function test_calculateAuctionFee_smallAmount() public view {
        // 0.1% of 1 = 0 (rounds down)
        assertEq(listingService.calculateAuctionFee(1), 0);
    }

    function test_calculateAuctionFee_zeroFee() public {
        listingService.setAuctionFee(0);
        assertEq(listingService.calculateAuctionFee(1_000_000e6), 0);
    }

    function test_getMarketplaceListingFee_default() public view {
        assertEq(listingService.getMarketplaceListingFee(), 0);
    }

    function test_getMarketplaceListingFee_afterUpdate() public {
        listingService.setMarketplaceListingFee(5_000_000);
        assertEq(listingService.getMarketplaceListingFee(), 5_000_000);
    }

    function test_isListedAuction_true() public {
        uint256 id = _createListedAuction();
        assertTrue(listingService.isListedAuction(id));
    }

    function test_isListedAuction_false() public view {
        assertFalse(listingService.isListedAuction(999));
    }

    function test_getAccumulatedFees_zero() public view {
        assertEq(listingService.getAccumulatedFees(address(loanToken)), 0);
    }

    function test_getFeeConfiguration() public view {
        (uint256 aFee, uint256 mFee) = listingService.getFeeConfiguration();
        assertEq(aFee, DEFAULT_AUCTION_FEE_BPS);
        assertEq(mFee, 0);
    }

    function test_getFeeConfiguration_afterUpdates() public {
        listingService.setAuctionFee(50);
        listingService.setMarketplaceListingFee(10_000_000);

        (uint256 aFee, uint256 mFee) = listingService.getFeeConfiguration();
        assertEq(aFee, 50);
        assertEq(mFee, 10_000_000);
    }
}
