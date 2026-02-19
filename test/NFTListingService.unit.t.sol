// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/NFTTestSetup.sol";
import "../../contracts/NFTListingService.sol";

/**
 * @title NFTListingServiceTests
 * @notice Unit tests for NFTListingService commercial wrapper
 * @dev Covers: createListedAuction, listPositionWithFee, whitelisting (collection + loan token),
 *      batch operations, fee management, pause/unpause, view functions
 *
 * Coverage target: NFTListingService.sol 20% → 85%+ line coverage
 * Test count: ~30 tests
 */

// ============================================================================
// NFT LISTING SERVICE TEST SETUP
// ============================================================================

abstract contract NFTListingServiceSetup is NFTTestSetup {

    NFTListingService public listingService;
    address public treasury = makeAddr("treasury");

    uint256 public constant DEFAULT_AUCTION_LISTING_FEE = 10_000_000; // $10

    function setUp() public virtual override {
        super.setUp();

        // Deploy NFTListingService implementation
        NFTListingService lsImpl = new NFTListingService();

        // Deploy proxy
        ERC1967ProxyNFT lsProxy = new ERC1967ProxyNFT(
            address(lsImpl),
            abi.encodeCall(
                NFTListingService.initialize,
                (address(nftProtocol), treasury, DEFAULT_AUCTION_LISTING_FEE)
            )
        );
        listingService = NFTListingService(address(lsProxy));

        // Whitelist collection and loan token
        listingService.setCollectionWhitelist(address(mockNFT), true);
        listingService.setLoanTokenWhitelist(address(loanToken), true);

        // Borrower approves listing service for fee payments
        vm.prank(borrower);
        loanToken.approve(address(listingService), type(uint256).max);

        // Borrower grants operator approval to listing service
        vm.prank(borrower);
        nftProtocol.setOperatorApproval(address(listingService), true);

        // Lender approvals
        vm.prank(lender);
        loanToken.approve(address(listingService), type(uint256).max);
        vm.prank(lender);
        nftProtocol.setOperatorApproval(address(listingService), true);
    }
}

// ============================================================================
// INITIALIZATION
// ============================================================================

contract NFTListingServiceInitTest is NFTListingServiceSetup {

    function test_initialize_setsCorrectState() public view {
        assertEq(address(listingService.loanProtocol()), address(nftProtocol));
        assertEq(listingService.treasury(), treasury);
        assertEq(listingService.auctionListingFee(), DEFAULT_AUCTION_LISTING_FEE);
        assertEq(listingService.marketplaceListingFee(), 0);
    }

    function test_initialize_zeroProtocol_reverts() public {
        NFTListingService impl = new NFTListingService();
        vm.expectRevert();
        new ERC1967ProxyNFT(
            address(impl),
            abi.encodeCall(NFTListingService.initialize, (address(0), treasury, 10e6))
        );
    }

    function test_initialize_zeroTreasury_reverts() public {
        NFTListingService impl = new NFTListingService();
        vm.expectRevert();
        new ERC1967ProxyNFT(
            address(impl),
            abi.encodeCall(NFTListingService.initialize, (address(nftProtocol), address(0), 10e6))
        );
    }

    function test_initialize_feeTooHigh_reverts() public {
        NFTListingService impl = new NFTListingService();
        vm.expectRevert();
        new ERC1967ProxyNFT(
            address(impl),
            abi.encodeCall(NFTListingService.initialize, (address(nftProtocol), treasury, 1000_000_001))
        );
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
}

// ============================================================================
// LOAN TOKEN WHITELISTING
// ============================================================================

contract LoanTokenWhitelistTest is NFTListingServiceSetup {

    function test_setLoanTokenWhitelist_add() public {
        address dai = makeAddr("DAI");
        listingService.setLoanTokenWhitelist(dai, true);
        assertTrue(listingService.isLoanTokenWhitelisted(dai));
    }

    function test_setLoanTokenWhitelist_zeroAddress_reverts() public {
        vm.expectRevert(NFTListingService.InvalidToken.selector);
        listingService.setLoanTokenWhitelist(address(0), true);
    }

    function test_batchSetLoanTokenWhitelist_success() public {
        address[] memory tokens = new address[](2);
        bool[] memory wl = new bool[](2);
        tokens[0] = makeAddr("DAI");
        tokens[1] = makeAddr("USDT");
        wl[0] = true;
        wl[1] = true;

        listingService.batchSetLoanTokenWhitelist(tokens, wl);
        assertTrue(listingService.isLoanTokenWhitelisted(tokens[0]));
        assertTrue(listingService.isLoanTokenWhitelisted(tokens[1]));
    }

    function test_batchSetLoanTokenWhitelist_lengthMismatch_reverts() public {
        address[] memory tokens = new address[](2);
        bool[] memory wl = new bool[](1);
        tokens[0] = makeAddr("a");
        tokens[1] = makeAddr("b");
        wl[0] = true;

        vm.expectRevert(NFTListingService.ArrayLengthMismatch.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, wl);
    }

    function test_batchSetLoanTokenWhitelist_tooLarge_reverts() public {
        address[] memory tokens = new address[](51);
        bool[] memory wl = new bool[](51);
        for (uint256 i = 0; i < 51; i++) {
            tokens[i] = address(uint160(i + 1));
            wl[i] = true;
        }
        vm.expectRevert(NFTListingService.BatchTooLarge.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, wl);
    }

    function test_batchSetLoanTokenWhitelist_zeroAddress_reverts() public {
        address[] memory tokens = new address[](1);
        bool[] memory wl = new bool[](1);
        tokens[0] = address(0);
        wl[0] = true;

        vm.expectRevert(NFTListingService.InvalidToken.selector);
        listingService.batchSetLoanTokenWhitelist(tokens, wl);
    }
}

// ============================================================================
// FEE MANAGEMENT
// ============================================================================

contract NFTFeeManagementTest is NFTListingServiceSetup {

    function test_setAuctionListingFee_success() public {
        listingService.setAuctionListingFee(20_000_000); // $20
        assertEq(listingService.auctionListingFee(), 20_000_000);
    }

    function test_setAuctionListingFee_zero() public {
        listingService.setAuctionListingFee(0);
        assertEq(listingService.auctionListingFee(), 0);
    }

    function test_setAuctionListingFee_tooHigh_reverts() public {
        vm.expectRevert(NFTListingService.FeeTooHigh.selector);
        listingService.setAuctionListingFee(1000_000_001);
    }

    function test_setAuctionListingFee_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert();
        listingService.setAuctionListingFee(1);
    }

    function test_setMarketplaceListingFee_success() public {
        listingService.setMarketplaceListingFee(5_000_000); // $5
        assertEq(listingService.marketplaceListingFee(), 5_000_000);
    }

    function test_setMarketplaceListingFee_tooHigh_reverts() public {
        vm.expectRevert(NFTListingService.FeeTooHigh.selector);
        listingService.setMarketplaceListingFee(100_000_001);
    }

    function test_setTreasury_success() public {
        address newTreasury = makeAddr("newTreasury");
        listingService.setTreasury(newTreasury);
        assertEq(listingService.treasury(), newTreasury);
    }

    function test_setTreasury_zeroAddress_reverts() public {
        vm.expectRevert(NFTListingService.ZeroAddress.selector);
        listingService.setTreasury(address(0));
    }

    function test_getFeeConfiguration() public view {
        (uint256 aFee, uint256 mFee) = listingService.getFeeConfiguration();
        assertEq(aFee, DEFAULT_AUCTION_LISTING_FEE);
        assertEq(mFee, 0);
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
        assertGt(id, 0);
    }

    function test_pause_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert();
        listingService.pause();
    }
}

// ============================================================================
// CREATE LISTED AUCTION
// ============================================================================

contract CreateListedNFTAuctionTest is NFTListingServiceSetup {

    function test_createListedAuction_success() public {
        uint256 treasuryBalBefore = loanToken.balanceOf(treasury);

        vm.prank(borrower);
        uint256 auctionId = listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );

        assertEq(auctionId, 1);
        assertTrue(listingService.isListedAuction(auctionId));

        // Fee collected to treasury
        assertEq(loanToken.balanceOf(treasury), treasuryBalBefore + DEFAULT_AUCTION_LISTING_FEE);

        // NFT transferred to protocol
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), address(nftProtocol));
    }

    function test_createListedAuction_zeroFee() public {
        listingService.setAuctionListingFee(0);

        uint256 treasuryBalBefore = loanToken.balanceOf(treasury);

        vm.prank(borrower);
        uint256 auctionId = listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );

        assertGt(auctionId, 0);
        assertEq(loanToken.balanceOf(treasury), treasuryBalBefore); // No fee
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

    function test_createListedAuction_whenPaused_reverts() public {
        listingService.pause();

        vm.prank(borrower);
        vm.expectRevert(); // EnforcedPause
        listingService.createListedAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }
}

// ============================================================================
// LIST POSITION WITH FEE
// ============================================================================

contract NFTListPositionWithFeeTest is NFTListingServiceSetup {

    function test_listPositionWithFee_withFee() public {
        // Create a loan first
        uint256 loanId = _createActiveNFTLoan();

        // Enable fee
        listingService.setMarketplaceListingFee(5_000_000); // $5

        uint256 treasuryBalBefore = loanToken.balanceOf(treasury);

        vm.prank(borrower);
        listingService.listPositionWithFee(loanId, "borrower", address(loanToken), 1000e6);

        assertEq(loanToken.balanceOf(treasury), treasuryBalBefore + 5_000_000);
        assertTrue(nftProtocol.isPositionListed(loanId));
    }

    function test_listPositionWithFee_freeListing() public {
        uint256 loanId = _createActiveNFTLoan();
        assertEq(listingService.marketplaceListingFee(), 0);

        uint256 treasuryBalBefore = loanToken.balanceOf(treasury);

        vm.prank(borrower);
        listingService.listPositionWithFee(loanId, "borrower", address(loanToken), 1000e6);

        assertEq(loanToken.balanceOf(treasury), treasuryBalBefore);
        assertTrue(nftProtocol.isPositionListed(loanId));
    }

    function test_listPositionWithFee_whenPaused_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        listingService.pause();

        vm.prank(borrower);
        vm.expectRevert(); // EnforcedPause
        listingService.listPositionWithFee(loanId, "borrower", address(loanToken), 1000e6);
    }
}

// ============================================================================
// VIEW FUNCTIONS
// ============================================================================

contract NFTListingServiceViewTest is NFTListingServiceSetup {

    function test_isListedAuction_false() public view {
        assertFalse(listingService.isListedAuction(999));
    }

    function test_getFeeConfiguration_afterUpdates() public {
        listingService.setAuctionListingFee(25_000_000);
        listingService.setMarketplaceListingFee(10_000_000);

        (uint256 aFee, uint256 mFee) = listingService.getFeeConfiguration();
        assertEq(aFee, 25_000_000);
        assertEq(mFee, 10_000_000);
    }
}
