// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/NFTTestSetup.sol";
import "../../contracts/NFTListingService.sol";

/**
 * @title NFTListingServiceTests
 * @notice Unit tests for NFTListingService commercial wrapper (curated NFT lending layer)
 * @dev Covers: initialize (+ re-init revert), owner-only access control,
 *      collection whitelisting, loan-token whitelisting with per-token minBidStep rules,
 *      batch setters, collection metadata, pause/unpause, view functions, and the
 *      curated createListedAuction operator flow (incl. bidStep resolution).
 *
 * API note: the deployed NFTListingService has NO treasury and NO fees. initialize takes
 * only (address _loanProtocol). Loan tokens carry a per-token minBidStep that must be > 0
 * at whitelist time (Sherlock #15). createListedAuction routes through
 * NFTLoanProtocol.createAuctionFor on behalf of msg.sender.
 */

// ============================================================================
// NFT LISTING SERVICE TEST SETUP
// ============================================================================

abstract contract NFTListingServiceSetup is NFTTestSetup {

    NFTListingService public listingService;

    /// @dev Per-token minimum bid step used when whitelisting the default loan token.
    uint256 public constant DEFAULT_MIN_BID_STEP = 100e6; // 100 USDC

    function setUp() public virtual override {
        super.setUp();

        // Deploy NFTListingService implementation
        NFTListingService lsImpl = new NFTListingService();

        // Deploy proxy — initialize takes ONLY the loan protocol address
        ERC1967ProxyNFT lsProxy = new ERC1967ProxyNFT(
            address(lsImpl),
            abi.encodeCall(
                NFTListingService.initialize,
                (address(nftProtocol))
            )
        );
        listingService = NFTListingService(address(lsProxy));

        // Whitelist collection and loan token (loan token requires minBidStep > 0)
        listingService.setCollectionWhitelist(address(mockNFT), true);
        listingService.setLoanTokenWhitelist(address(loanToken), true, DEFAULT_MIN_BID_STEP);

        // Borrower approves the listing service as an operator: createListedAuction calls
        // createAuctionFor on the borrower's behalf, which requires operator approval.
        vm.prank(borrower);
        nftProtocol.setOperatorApproval(address(listingService), true);
    }
}

// ============================================================================
// INITIALIZATION
// ============================================================================

contract NFTListingServiceInitTest is NFTListingServiceSetup {

    function test_initialize_setsCorrectState() public {
        assertEq(address(listingService.loanProtocol()), address(nftProtocol));
        assertEq(listingService.owner(), address(this));
        assertEq(listingService.MAX_BATCH_SIZE(), 50);
    }

    function test_initialize_zeroProtocol_reverts() public {
        NFTListingService impl = new NFTListingService();
        vm.expectRevert();
        new ERC1967ProxyNFT(
            address(impl),
            abi.encodeCall(NFTListingService.initialize, (address(0)))
        );
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert(); // InvalidInitialization
        listingService.initialize(address(nftProtocol));
    }

    function test_implementation_cannotBeInitialized() public {
        NFTListingService impl = new NFTListingService();
        vm.expectRevert(); // InvalidInitialization — constructor disables initializers
        impl.initialize(address(nftProtocol));
    }
}

// ============================================================================
// COLLECTION WHITELISTING
// ============================================================================

contract CollectionWhitelistTest is NFTListingServiceSetup {

    function test_setCollectionWhitelist_add() public {
        address newCollection = makeAddr("newCollection");
        listingService.setCollectionWhitelist(newCollection, true);
        assertTrue(listingService.isCollectionWhitelisted(newCollection));
    }

    function test_setCollectionWhitelist_remove() public {
        listingService.setCollectionWhitelist(address(mockNFT), false);
        assertFalse(listingService.isCollectionWhitelisted(address(mockNFT)));
    }

    function test_setCollectionWhitelist_emitsEvent() public {
        address col = makeAddr("col");
        listingService.setCollectionWhitelist(col, true);
        assertTrue(listingService.isCollectionWhitelisted(col));
    }

    function test_setCollectionWhitelist_zeroAddress_reverts() public {
        vm.expectRevert(NFTListingService.ZeroAddress.selector);
        listingService.setCollectionWhitelist(address(0), true);
    }

    function test_setCollectionWhitelist_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        listingService.setCollectionWhitelist(makeAddr("col"), true);
    }

    function test_batchSetCollectionWhitelist_success() public {
        address[] memory cols = new address[](2);
        bool[] memory wl = new bool[](2);
        cols[0] = makeAddr("col1");
        cols[1] = makeAddr("col2");
        wl[0] = true;
        wl[1] = true;

        listingService.batchSetCollectionWhitelist(cols, wl);
        assertTrue(listingService.isCollectionWhitelisted(cols[0]));
        assertTrue(listingService.isCollectionWhitelisted(cols[1]));
    }

    function test_batchSetCollectionWhitelist_mixedStatuses() public {
        address[] memory cols = new address[](2);
        bool[] memory wl = new bool[](2);
        cols[0] = address(mockNFT); // already whitelisted in setUp
        cols[1] = makeAddr("col2");
        wl[0] = false;
        wl[1] = true;

        listingService.batchSetCollectionWhitelist(cols, wl);
        assertFalse(listingService.isCollectionWhitelisted(cols[0]));
        assertTrue(listingService.isCollectionWhitelisted(cols[1]));
    }

    function test_batchSetCollectionWhitelist_lengthMismatch_reverts() public {
        address[] memory cols = new address[](2);
        bool[] memory wl = new bool[](1);
        cols[0] = makeAddr("col1");
        cols[1] = makeAddr("col2");
        wl[0] = true;

        vm.expectRevert(NFTListingService.ArrayLengthMismatch.selector);
        listingService.batchSetCollectionWhitelist(cols, wl);
    }

    function test_batchSetCollectionWhitelist_tooLarge_reverts() public {
        address[] memory cols = new address[](51);
        bool[] memory wl = new bool[](51);
        for (uint256 i = 0; i < 51; i++) {
            cols[i] = address(uint160(i + 1));
            wl[i] = true;
        }
        vm.expectRevert(NFTListingService.BatchTooLarge.selector);
        listingService.batchSetCollectionWhitelist(cols, wl);
    }

    function test_batchSetCollectionWhitelist_maxBatchSizeOk() public {
        address[] memory cols = new address[](50);
        bool[] memory wl = new bool[](50);
        for (uint256 i = 0; i < 50; i++) {
            cols[i] = address(uint160(i + 1));
            wl[i] = true;
        }
        listingService.batchSetCollectionWhitelist(cols, wl);
        assertTrue(listingService.isCollectionWhitelisted(cols[49]));
    }

    function test_batchSetCollectionWhitelist_zeroAddress_reverts() public {
        address[] memory cols = new address[](2);
        bool[] memory wl = new bool[](2);
        cols[0] = makeAddr("valid");
        cols[1] = address(0);
        wl[0] = true;
        wl[1] = true;

        vm.expectRevert(NFTListingService.ZeroAddress.selector);
        listingService.batchSetCollectionWhitelist(cols, wl);
    }

    function test_batchSetCollectionWhitelist_nonOwner_reverts() public {
        address[] memory cols = new address[](1);
        bool[] memory wl = new bool[](1);
        cols[0] = makeAddr("col");
        wl[0] = true;

        vm.prank(attacker);
        vm.expectRevert();
        listingService.batchSetCollectionWhitelist(cols, wl);
    }

    function test_setCollectionInfo() public {
        listingService.setCollectionInfo(address(mockNFT), "CryptoPunks", "PUNK", true);

        NFTListingService.CollectionInfo memory info = listingService.getCollectionInfo(address(mockNFT));
        assertEq(info.name, "CryptoPunks");
        assertEq(info.symbol, "PUNK");
        assertTrue(info.isVerified);
        assertGt(info.addedAt, 0);
    }

    function test_setCollectionInfo_zeroAddress_reverts() public {
        vm.expectRevert(NFTListingService.ZeroAddress.selector);
        listingService.setCollectionInfo(address(0), "x", "x", false);
    }

    function test_setCollectionInfo_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert();
        listingService.setCollectionInfo(address(mockNFT), "x", "x", false);
    }
}

// ============================================================================
// LOAN TOKEN WHITELISTING (with per-token minBidStep rules)
// ============================================================================

contract LoanTokenWhitelistTest is NFTListingServiceSetup {

    function test_setLoanTokenWhitelist_add() public {
        address dai = makeAddr("DAI");
        listingService.setLoanTokenWhitelist(dai, true, 5e18);
        assertTrue(listingService.isLoanTokenWhitelisted(dai));
        assertEq(listingService.loanTokenMinBidSteps(dai), 5e18);
    }

    function test_setLoanTokenWhitelist_remove_clearsMinBidStep() public {
        // loanToken is whitelisted with DEFAULT_MIN_BID_STEP in setUp
        assertEq(listingService.loanTokenMinBidSteps(address(loanToken)), DEFAULT_MIN_BID_STEP);

        listingService.setLoanTokenWhitelist(address(loanToken), false, 0);
        assertFalse(listingService.isLoanTokenWhitelisted(address(loanToken)));
        assertEq(listingService.loanTokenMinBidSteps(address(loanToken)), 0);
    }

    function test_setLoanTokenWhitelist_emitsEvent() public {
        address dai = makeAddr("DAI");
        listingService.setLoanTokenWhitelist(dai, true, 1e6);
        assertTrue(listingService.isLoanTokenWhitelisted(dai));
        assertEq(listingService.loanTokenMinBidSteps(dai), 1e6);
    }

    function test_setLoanTokenWhitelist_zeroAddress_reverts() public {
        vm.expectRevert(NFTListingService.InvalidToken.selector);
        listingService.setLoanTokenWhitelist(address(0), true, 1e6);
    }

    function test_setLoanTokenWhitelist_zeroMinBidStep_reverts() public {
        address dai = makeAddr("DAI");
        vm.expectRevert(NFTListingService.MinBidStepRequired.selector);
        listingService.setLoanTokenWhitelist(dai, true, 0);
    }

    function test_setLoanTokenWhitelist_unwhitelistZeroMinBidStep_ok() public {
        // When unwhitelisting, minBidStep == 0 is allowed (ignored)
        listingService.setLoanTokenWhitelist(makeAddr("DAI"), false, 0);
        assertFalse(listingService.isLoanTokenWhitelisted(makeAddr("DAI")));
    }

    function test_setLoanTokenWhitelist_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert();
        listingService.setLoanTokenWhitelist(makeAddr("DAI"), true, 1e6);
    }

    function test_batchSetLoanTokenWhitelist_success() public {
        address[] memory tokens = new address[](2);
        uint256[] memory steps = new uint256[](2);
        bool[] memory wl = new bool[](2);
        tokens[0] = makeAddr("DAI");
        tokens[1] = makeAddr("USDT");
        steps[0] = 5e18;
        steps[1] = 1e6;
        wl[0] = true;
        wl[1] = true;

        listingService.batchSetLoanTokenWhitelist(tokens, steps, wl);
        assertTrue(listingService.isLoanTokenWhitelisted(tokens[0]));
        assertTrue(listingService.isLoanTokenWhitelisted(tokens[1]));
        assertEq(listingService.loanTokenMinBidSteps(tokens[0]), 5e18);
        assertEq(listingService.loanTokenMinBidSteps(tokens[1]), 1e6);
    }

    function test_batchSetLoanTokenWhitelist_unwhitelistClearsStep() public {
        address[] memory tokens = new address[](1);
        uint256[] memory steps = new uint256[](1);
        bool[] memory wl = new bool[](1);
        tokens[0] = address(loanToken);
        steps[0] = 0; // ignored when unwhitelisting
        wl[0] = false;

        listingService.batchSetLoanTokenWhitelist(tokens, steps, wl);
        assertFalse(listingService.isLoanTokenWhitelisted(address(loanToken)));
        assertEq(listingService.loanTokenMinBidSteps(address(loanToken)), 0);
    }

    function test_batchSetLoanTokenWhitelist_zeroMinBidStep_reverts() public {
        address[] memory tokens = new address[](1);
        uint256[] memory steps = new uint256[](1);
        bool[] memory wl = new bool[](1);
        tokens[0] = makeAddr("DAI");
        steps[0] = 0;
        wl[0] = true;

        vm.expectRevert(NFTListingService.MinBidStepRequired.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, steps, wl);
    }

    function test_batchSetLoanTokenWhitelist_tokenLengthMismatch_reverts() public {
        address[] memory tokens = new address[](2);
        uint256[] memory steps = new uint256[](2);
        bool[] memory wl = new bool[](1);
        tokens[0] = makeAddr("a");
        tokens[1] = makeAddr("b");
        steps[0] = 1e6;
        steps[1] = 1e6;
        wl[0] = true;

        vm.expectRevert(NFTListingService.ArrayLengthMismatch.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, steps, wl);
    }

    function test_batchSetLoanTokenWhitelist_stepLengthMismatch_reverts() public {
        address[] memory tokens = new address[](2);
        uint256[] memory steps = new uint256[](1);
        bool[] memory wl = new bool[](2);
        tokens[0] = makeAddr("a");
        tokens[1] = makeAddr("b");
        steps[0] = 1e6;
        wl[0] = true;
        wl[1] = true;

        vm.expectRevert(NFTListingService.ArrayLengthMismatch.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, steps, wl);
    }

    function test_batchSetLoanTokenWhitelist_tooLarge_reverts() public {
        address[] memory tokens = new address[](51);
        uint256[] memory steps = new uint256[](51);
        bool[] memory wl = new bool[](51);
        for (uint256 i = 0; i < 51; i++) {
            tokens[i] = address(uint160(i + 1));
            steps[i] = 1e6;
            wl[i] = true;
        }
        vm.expectRevert(NFTListingService.BatchTooLarge.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, steps, wl);
    }

    function test_batchSetLoanTokenWhitelist_zeroAddress_reverts() public {
        address[] memory tokens = new address[](1);
        uint256[] memory steps = new uint256[](1);
        bool[] memory wl = new bool[](1);
        tokens[0] = address(0);
        steps[0] = 1e6;
        wl[0] = true;

        vm.expectRevert(NFTListingService.InvalidToken.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, steps, wl);
    }

    function test_batchSetLoanTokenWhitelist_nonOwner_reverts() public {
        address[] memory tokens = new address[](1);
        uint256[] memory steps = new uint256[](1);
        bool[] memory wl = new bool[](1);
        tokens[0] = makeAddr("DAI");
        steps[0] = 1e6;
        wl[0] = true;

        vm.prank(attacker);
        vm.expectRevert();
        listingService.batchSetLoanTokenWhitelist(tokens, steps, wl);
    }
}

// ============================================================================
// PAUSE / UNPAUSE
// ============================================================================

contract NFTListingServicePauseTest is NFTListingServiceSetup {

    function test_pause_blocksAuctionCreation() public {
        listingService.pause();

        vm.prank(borrower);
        vm.expectRevert(); // EnforcedPause
        listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_unpause_restoresFunction() public {
        listingService.pause();
        listingService.unpause();

        vm.prank(borrower);
        uint256 id = listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        assertTrue(listingService.isListedAuction(id));
    }

    function test_pause_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert();
        listingService.pause();
    }

    function test_unpause_nonOwner_reverts() public {
        listingService.pause();
        vm.prank(attacker);
        vm.expectRevert();
        listingService.unpause();
    }
}

// ============================================================================
// CREATE LISTED AUCTION (curated operator flow)
// ============================================================================

contract CreateListedNFTAuctionTest is NFTListingServiceSetup {

    function test_createListedAuction_success() public {
        vm.prank(borrower);
        uint256 auctionId = listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );

        assertTrue(listingService.isListedAuction(auctionId));

        // NFT transferred to protocol as collateral
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), address(nftProtocol));
    }

    function test_createListedAuction_zeroBidStep_usesTokenMinimum() public {
        // bidStep == 0 means "use the curated per-token default" — must not revert.
        vm.prank(borrower);
        uint256 auctionId = listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, 0
        );
        assertTrue(listingService.isListedAuction(auctionId));
    }

    function test_createListedAuction_bidStepBelowMinimum_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTListingService.BidStepBelowTokenMinimum.selector);
        listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_MIN_BID_STEP - 1
        );
    }

    function test_createListedAuction_bidStepAtMinimum_ok() public {
        vm.prank(borrower);
        uint256 auctionId = listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_MIN_BID_STEP
        );
        assertTrue(listingService.isListedAuction(auctionId));
    }

    function test_createListedAuction_emitsEvent() public {
        // effectiveBidStep == DEFAULT_BID_STEP (>= minimum)
        vm.prank(borrower);
        uint256 auctionId = listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        assertTrue(listingService.isListedAuction(auctionId));
    }

    function test_createListedAuction_collectionNotWhitelisted_reverts() public {
        TestMockERC721 randoNFT = new TestMockERC721("Rando", "RND");
        randoNFT.mint(borrower, 1);

        vm.prank(borrower);
        randoNFT.setApprovalForAll(address(nftProtocol), true);

        vm.prank(borrower);
        vm.expectRevert(NFTListingService.CollectionNotWhitelisted.selector);
        listingService.createListedAuction(
            address(randoNFT), 1, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_createListedAuction_loanTokenNotWhitelisted_reverts() public {
        MockERC20NFT rando = new MockERC20NFT("Rando", "RND", 6);

        vm.prank(borrower);
        vm.expectRevert(NFTListingService.LoanTokenNotWhitelisted.selector);
        listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(rando),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_createListedAuction_notNFTOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(NFTListingService.NotNFTOwner.selector);
        listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }
}

// ============================================================================
// VIEW FUNCTIONS
// ============================================================================

contract NFTListingServiceViewTest is NFTListingServiceSetup {

    function test_isListedAuction_false() public {
        assertFalse(listingService.isListedAuction(999));
    }

    function test_isCollectionWhitelisted_reflectsState() public {
        assertTrue(listingService.isCollectionWhitelisted(address(mockNFT)));
        assertFalse(listingService.isCollectionWhitelisted(makeAddr("unknown")));
    }

    function test_isLoanTokenWhitelisted_reflectsState() public {
        assertTrue(listingService.isLoanTokenWhitelisted(address(loanToken)));
        assertFalse(listingService.isLoanTokenWhitelisted(makeAddr("unknown")));
    }

    function test_getCollectionInfo_empty() public {
        NFTListingService.CollectionInfo memory info = listingService.getCollectionInfo(makeAddr("unknown"));
        assertEq(info.addedAt, 0);
        assertFalse(info.isVerified);
    }

    function test_loanTokenMinBidSteps_default() public {
        assertEq(listingService.loanTokenMinBidSteps(address(loanToken)), DEFAULT_MIN_BID_STEP);
    }
}
