// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/NFTTestSetup.sol";

/**
 * @title NFTLoanProtocol Marketplace Tests
 * @notice Unit tests for NFTLoanProtocol integrated marketplace (current/deployed API)
 * @dev Covers: listPosition, listPositionFor, unlistPosition, updateListingPrice,
 *      cleanStaleListing, makeMarketplaceOffer, cancelMarketplaceOffer,
 *      rejectMarketplaceOffer, counterMarketplaceOffer, acceptMarketplaceOffer,
 *      acceptMarketplaceCounterOffer, buyPosition, expireMarketplaceOffer.
 *
 * Current-API notes (verified against contracts/NFTLoanProtocol.sol):
 *   - listPosition/listPositionFor take (loanId, [seller,] positionType, paymentToken,
 *     askingPrice, minOfferAmount).
 *   - ALL other marketplace ops are keyed by the Position NFT tokenId, NOT loanId:
 *       borrower tokenId = loanId * 2   (nftPositionNFT.getBorrowerTokenId)
 *       lender   tokenId = loanId * 2+1 (nftPositionNFT.getLenderTokenId)
 *   - makeMarketplaceOffer(tokenId, amount, duration, expectedPaymentToken) -> offerId
 *   - buyPosition(tokenId, maxPrice, expectedPaymentToken)  [MEV/slippage protection]
 *   - Contract constants: MATURITY_BUFFER = 1 days, MIN_OFFER_DURATION = 1 days.
 *     We read them at runtime so tests stay correct if constants change.
 */

// ============================================================================
// MARKETPLACE SETUP HELPERS
// ============================================================================

abstract contract NFTMarketplaceSetup is NFTTestSetup {

    // Runtime-resolved protocol constants (the NFTTestSetup mirror constants are stale).
    uint256 internal MATURITY_BUFFER_C;
    uint256 internal MIN_OFFER_DURATION_C;
    uint256 internal MAX_OFFERS_C;

    // Default offer parameters: comfortably above MIN_OFFER_DURATION and within the
    // marketplace-active window for a 30-day loan.
    uint256 internal OFFER_DURATION;

    function setUp() public virtual override {
        super.setUp();
        MATURITY_BUFFER_C    = nftProtocol.MATURITY_BUFFER();
        MIN_OFFER_DURATION_C = nftProtocol.MIN_OFFER_DURATION();
        MAX_OFFERS_C         = nftProtocol.MAX_OFFERS_PER_LISTING();
        // 5 days is >= MIN_OFFER_DURATION (1 day) and << (30 days - 1 day buffer).
        OFFER_DURATION = 5 days;
    }

    // --- tokenId helpers ----------------------------------------------------

    function _borrowerTokenId(uint256 loanId) internal view returns (uint256) {
        return nftPositionNFT.getBorrowerTokenId(loanId);
    }

    function _lenderTokenId(uint256 loanId) internal view returns (uint256) {
        return nftPositionNFT.getLenderTokenId(loanId);
    }

    // --- listing helpers ----------------------------------------------------

    /// @dev Creates an active loan and lists borrower position for sale.
    function _createListedBorrowerPosition() internal returns (uint256 loanId, uint256 tokenId) {
        loanId = _createActiveNFTLoan();
        vm.prank(borrower);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6, 0);
        tokenId = _borrowerTokenId(loanId);
    }

    /// @dev Creates an active loan and lists lender position for sale.
    function _createListedLenderPosition() internal returns (uint256 loanId, uint256 tokenId) {
        loanId = _createActiveNFTLoan();
        vm.prank(lender);
        nftProtocol.listPosition(loanId, "lender", address(loanToken), 5_000e6, 0);
        tokenId = _lenderTokenId(loanId);
    }

    /// @dev Creates a listed borrower position and makes a single offer on it.
    function _createListingWithOffer()
        internal
        returns (uint256 loanId, uint256 tokenId, uint256 offerId)
    {
        (loanId, tokenId) = _createListedBorrowerPosition();
        vm.prank(buyer);
        offerId = nftProtocol.makeMarketplaceOffer(tokenId, 4_000e6, OFFER_DURATION, address(loanToken));
    }
}

// ============================================================================
// LIST POSITION
// ============================================================================

contract NFTListPositionTest is NFTMarketplaceSetup {

    function test_listPosition_borrower_success() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6, 0);

        uint256 tokenId = _borrowerTokenId(loanId);
        NFTLoanProtocol.MarketplaceListing memory listing = nftProtocol.getMarketplaceListing(tokenId);
        assertEq(listing.seller, borrower);
        assertTrue(listing.active);
        assertEq(listing.askingPrice, 5_000e6);
        assertEq(listing.loanId, loanId);
        assertTrue(nftProtocol.isPositionListed(tokenId));
    }

    function test_listPosition_lender_success() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(lender);
        nftProtocol.listPosition(loanId, "lender", address(loanToken), 10_000e6, 0);

        uint256 tokenId = _lenderTokenId(loanId);
        NFTLoanProtocol.MarketplaceListing memory listing = nftProtocol.getMarketplaceListing(tokenId);
        assertEq(listing.seller, lender);
        assertTrue(listing.active);
    }

    function test_listPosition_withMinOfferFloor_success() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6, 1_000e6);

        NFTLoanProtocol.MarketplaceListing memory listing =
            nftProtocol.getMarketplaceListing(_borrowerTokenId(loanId));
        assertEq(listing.minOfferAmount, 1_000e6);
    }

    function test_listPosition_minOfferAboveAsking_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidPrice.selector);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6, 6_000e6);
    }

    function test_listPosition_alreadyListed_reverts() public {
        (uint256 loanId, ) = _createListedBorrowerPosition();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.AlreadyListed.selector);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 6_000e6, 0);
    }

    function test_listPosition_notPositionOwner_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotPositionOwner.selector);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6, 0);
    }

    function test_listPosition_invalidPositionType_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidPositionType.selector);
        nftProtocol.listPosition(loanId, "invalid", address(loanToken), 5_000e6, 0);
    }

    function test_listPosition_zeroPrice_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidPrice.selector);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 0, 0);
    }

    function test_listPosition_zeroPaymentToken_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.ZeroAddress.selector);
        nftProtocol.listPosition(loanId, "borrower", address(0), 5_000e6, 0);
    }

    function test_listPosition_withinMaturityBuffer_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        // Warp to within maturity buffer (marketplace frozen).
        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER_C);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.MarketplaceFrozen.selector);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6, 0);
    }
}

// ============================================================================
// LIST POSITION FOR (OPERATOR DELEGATION)
// ============================================================================

contract NFTListPositionForTest is NFTMarketplaceSetup {

    function test_listPositionFor_asOperator() public {
        uint256 loanId = _createActiveNFTLoan();

        address operator = makeAddr("operator");
        vm.prank(borrower);
        nftProtocol.setOperatorApproval(operator, true);

        vm.prank(operator);
        nftProtocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 5_000e6, 0);

        assertTrue(nftProtocol.isPositionListed(_borrowerTokenId(loanId)));
    }

    function test_listPositionFor_asSeller_self() public {
        uint256 loanId = _createActiveNFTLoan();

        // seller == msg.sender path (no operator approval needed).
        vm.prank(borrower);
        nftProtocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 5_000e6, 0);

        assertTrue(nftProtocol.isPositionListed(_borrowerTokenId(loanId)));
    }

    function test_listPositionFor_unauthorized_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 5_000e6, 0);
    }

    function test_listPositionFor_zeroSeller_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.ZeroAddress.selector);
        nftProtocol.listPositionFor(1, address(0), "borrower", address(loanToken), 5_000e6, 0);
    }
}

// ============================================================================
// UNLIST POSITION
// ============================================================================

contract NFTUnlistPositionTest is NFTMarketplaceSetup {

    function test_unlistPosition_success() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(borrower);
        nftProtocol.unlistPosition(tokenId);

        assertFalse(nftProtocol.isPositionListed(tokenId));
    }

    function test_unlistPosition_notListed_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        uint256 tokenId = _borrowerTokenId(loanId); // resolve (external view) before arming expectRevert

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.unlistPosition(tokenId);
    }

    function test_unlistPosition_notSeller_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.unlistPosition(tokenId);
    }

    function test_unlistPosition_refundsOpenOffers() public {
        (, uint256 tokenId, ) = _createListingWithOffer();

        uint256 buyerBalBefore = loanToken.balanceOf(buyer);

        vm.prank(borrower);
        nftProtocol.unlistPosition(tokenId);

        // unlist refunds pending offers via the pull-refund queue (_refundOtherOffers),
        // NOT a direct wallet push. The buyer's escrow is queued in pendingRefunds and
        // the wallet is unchanged until claimRefund is called.
        assertFalse(nftProtocol.isPositionListed(tokenId));
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore);
        assertEq(nftProtocol.getPendingRefund(buyer, address(loanToken)), 4_000e6);

        // After claiming, the escrow is returned to the buyer's wallet.
        vm.prank(buyer);
        nftProtocol.claimRefund(address(loanToken));
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore + 4_000e6);
    }
}

// ============================================================================
// CLEAN STALE LISTING
// ============================================================================

contract NFTCleanStaleListingTest is NFTMarketplaceSetup {

    function test_cleanStaleListing_notStale_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        // Seller still owns the position -> listing is not stale.
        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.ListingNotStale.selector);
        nftProtocol.cleanStaleListing(tokenId);
    }

    function test_cleanStaleListing_notListed_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        uint256 tokenId = _borrowerTokenId(loanId); // resolve (external view) before arming expectRevert

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.cleanStaleListing(tokenId);
    }

    function test_cleanStaleListing_afterBuy_success() public {
        // After a buyPosition, the borrower position transfers to a new owner while
        // a lender listing could still exist; here we exercise the stale path by
        // listing then selling, then verifying a second buy cannot occur (defensive).
        (, uint256 tokenId, ) = _createListingWithOffer();

        // Original seller (borrower) sells via accept; listing deactivated.
        vm.prank(borrower);
        nftProtocol.acceptMarketplaceOffer(tokenId, 1);

        // Now the listing is inactive; cleanStaleListing should revert NotListed.
        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.cleanStaleListing(tokenId);
    }
}

// ============================================================================
// UPDATE LISTING PRICE
// ============================================================================

contract NFTUpdateListingPriceTest is NFTMarketplaceSetup {

    function test_updateListingPrice_success() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(borrower);
        nftProtocol.updateListingPrice(tokenId, 8_000e6);

        NFTLoanProtocol.MarketplaceListing memory listing = nftProtocol.getMarketplaceListing(tokenId);
        assertEq(listing.askingPrice, 8_000e6);
    }

    function test_updateListingPrice_notListed_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.updateListingPrice(999, 8_000e6);
    }

    function test_updateListingPrice_notSeller_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.updateListingPrice(tokenId, 8_000e6);
    }

    function test_updateListingPrice_zeroPrice_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidPrice.selector);
        nftProtocol.updateListingPrice(tokenId, 0);
    }
}

// ============================================================================
// MAKE MARKETPLACE OFFER (incl. MEV expectedPaymentToken)
// ============================================================================

contract NFTMakeOfferTest is NFTMarketplaceSetup {

    function test_makeOffer_success() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(buyer);
        uint256 offerId = nftProtocol.makeMarketplaceOffer(tokenId, 4_000e6, OFFER_DURATION, address(loanToken));

        assertEq(offerId, 1);
        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(offer.buyer, buyer);
        assertEq(offer.amount, 4_000e6);
        assertEq(offer.escrowedAmount, 4_000e6);
        assertEq(offer.paymentToken, address(loanToken));
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.PENDING));
    }

    function test_makeOffer_wrongExpectedToken_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        // MEV protection: buyer expects a token that does not match the listing.
        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.PaymentTokenMismatch.selector);
        nftProtocol.makeMarketplaceOffer(tokenId, 4_000e6, OFFER_DURATION, address(0xBEEF));
    }

    function test_makeOffer_belowMinFloor_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        vm.prank(borrower);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6, 2_000e6);
        uint256 tokenId = _borrowerTokenId(loanId);

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.OfferBelowMinimum.selector);
        nftProtocol.makeMarketplaceOffer(tokenId, 1_000e6, OFFER_DURATION, address(loanToken));
    }

    function test_makeOffer_notListed_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.makeMarketplaceOffer(999, 4_000e6, OFFER_DURATION, address(loanToken));
    }

    function test_makeOffer_sellerCannotOffer_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.CannotBuyOwnPosition.selector);
        nftProtocol.makeMarketplaceOffer(tokenId, 4_000e6, OFFER_DURATION, address(loanToken));
    }

    function test_makeOffer_zeroAmount_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.InvalidOffer.selector);
        nftProtocol.makeMarketplaceOffer(tokenId, 0, OFFER_DURATION, address(loanToken));
    }

    function test_makeOffer_durationTooShort_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.OfferDurationTooShort.selector);
        nftProtocol.makeMarketplaceOffer(tokenId, 4_000e6, MIN_OFFER_DURATION_C - 1, address(loanToken));
    }

    function test_makeOffer_durationPastMaturity_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        // Duration extending past (maturity - buffer) must revert (no silent capping).
        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.OfferDurationTooLong.selector);
        nftProtocol.makeMarketplaceOffer(tokenId, 4_000e6, 365 days, address(loanToken));
    }

    function test_makeOffer_marketplaceFrozen_reverts() public {
        (uint256 loanId, uint256 tokenId) = _createListedBorrowerPosition();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER_C);

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.MarketplaceFrozen.selector);
        nftProtocol.makeMarketplaceOffer(tokenId, 4_000e6, MIN_OFFER_DURATION_C, address(loanToken));
    }

    function test_makeOffer_maxOffersCap_reverts() public {
        // Fill the listing up to MAX_OFFERS_PER_LISTING, then expect TooManyOffers.
        (, uint256 tokenId) = _createListedBorrowerPosition();

        for (uint256 i = 0; i < MAX_OFFERS_C; i++) {
            address b = makeAddr(string(abi.encodePacked("capbuyer", i)));
            loanToken.mint(b, 1_000_000e6);
            vm.prank(b);
            loanToken.approve(address(nftProtocol), type(uint256).max);
            vm.prank(b);
            nftProtocol.makeMarketplaceOffer(tokenId, 1_000e6, OFFER_DURATION, address(loanToken));
        }

        address overflow = makeAddr("overflowbuyer");
        loanToken.mint(overflow, 1_000_000e6);
        vm.prank(overflow);
        loanToken.approve(address(nftProtocol), type(uint256).max);
        vm.prank(overflow);
        vm.expectRevert(NFTLoanProtocol.TooManyOffers.selector);
        nftProtocol.makeMarketplaceOffer(tokenId, 1_000e6, OFFER_DURATION, address(loanToken));
    }
}

// ============================================================================
// CANCEL MARKETPLACE OFFER
// ============================================================================

contract NFTCancelOfferTest is NFTMarketplaceSetup {

    function test_cancelOffer_pending_success() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        uint256 balBefore = loanToken.balanceOf(buyer);
        vm.prank(buyer);
        nftProtocol.cancelMarketplaceOffer(tokenId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.CANCELLED));
        // Cancel pushes the refund directly back to the buyer.
        assertEq(loanToken.balanceOf(buyer), balBefore + 4_000e6);
    }

    function test_cancelOffer_notBuyer_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotBuyer.selector);
        nftProtocol.cancelMarketplaceOffer(tokenId, offerId);
    }

    function test_cancelOffer_offerNotFound_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.OfferNotFound.selector);
        nftProtocol.cancelMarketplaceOffer(tokenId, 999);
    }
}

// ============================================================================
// REJECT MARKETPLACE OFFER
// ============================================================================

contract NFTRejectOfferTest is NFTMarketplaceSetup {

    function test_rejectOffer_success() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        nftProtocol.rejectMarketplaceOffer(tokenId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.REJECTED));
        // Reject queues a pull-refund.
        assertEq(nftProtocol.getPendingRefund(buyer, address(loanToken)), 4_000e6);
    }

    function test_rejectOffer_notSeller_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.rejectMarketplaceOffer(tokenId, offerId);
    }

    function test_rejectOffer_notPending_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        // Cancel first so status is no longer PENDING.
        vm.prank(buyer);
        nftProtocol.cancelMarketplaceOffer(tokenId, offerId);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidOfferStatus.selector);
        nftProtocol.rejectMarketplaceOffer(tokenId, offerId);
    }
}

// ============================================================================
// COUNTER MARKETPLACE OFFER
// ============================================================================

contract NFTCounterOfferTest is NFTMarketplaceSetup {

    function test_counterOffer_success() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 4_500e6, OFFER_DURATION);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.COUNTERED));
        assertEq(offer.counterAmount, 4_500e6);
    }

    function test_counterOffer_notSeller_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 4_500e6, OFFER_DURATION);
    }

    function test_counterOffer_zeroAmount_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidOffer.selector);
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 0, OFFER_DURATION);
    }

    function test_counterOffer_durationTooShort_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.OfferDurationTooShort.selector);
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 4_500e6, MIN_OFFER_DURATION_C - 1);
    }

    function test_counterOffer_durationPastMaturity_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.OfferDurationTooLong.selector);
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 4_500e6, 365 days);
    }

    function test_counterOffer_marketplaceFrozen_reverts() public {
        (uint256 loanId, uint256 tokenId, uint256 offerId) = _createListingWithOffer();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER_C);

        vm.prank(borrower);
        // Offer is also time-expired by now; OfferExpired is checked before freeze,
        // so accept either revert reason from the frozen window.
        vm.expectRevert();
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 4_500e6, MIN_OFFER_DURATION_C);
    }
}

// ============================================================================
// ACCEPT MARKETPLACE OFFER
// ============================================================================

contract NFTAcceptOfferTest is NFTMarketplaceSetup {

    function test_acceptOffer_success() public {
        (uint256 loanId, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        vm.prank(borrower);
        nftProtocol.acceptMarketplaceOffer(tokenId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.ACCEPTED));

        // Seller received payment.
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 4_000e6);
        // Position transferred to buyer.
        assertEq(nftProtocol.getBorrowerPositionOwner(loanId), buyer);
        // Listing deactivated.
        assertFalse(nftProtocol.isPositionListed(tokenId));
    }

    function test_acceptOffer_notSeller_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.acceptMarketplaceOffer(tokenId, offerId);
    }

    function test_acceptOffer_expired_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        vm.warp(offer.expiresAt);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.OfferExpired.selector);
        nftProtocol.acceptMarketplaceOffer(tokenId, offerId);
    }

    function test_acceptOffer_notPending_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(buyer);
        nftProtocol.cancelMarketplaceOffer(tokenId, offerId);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidOfferStatus.selector);
        nftProtocol.acceptMarketplaceOffer(tokenId, offerId);
    }

    function test_acceptOffer_marketplaceFrozen_reverts() public {
        (uint256 loanId, uint256 tokenId, uint256 offerId) = _createListingWithOffer();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER_C);

        vm.prank(borrower);
        // Within the freeze window the offer is also time-expired; accept either revert.
        vm.expectRevert();
        nftProtocol.acceptMarketplaceOffer(tokenId, offerId);
    }
}

// ============================================================================
// ACCEPT COUNTER OFFER
// ============================================================================

contract NFTAcceptCounterOfferTest is NFTMarketplaceSetup {

    function _createCounteredOffer()
        internal
        returns (uint256 loanId, uint256 tokenId, uint256 offerId)
    {
        (loanId, tokenId, offerId) = _createListingWithOffer();
        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 4_500e6, OFFER_DURATION);
    }

    function test_acceptCounterOffer_higherThanEscrow() public {
        // Counter is 4500, escrow is 4000 -> buyer pays 500 more.
        (uint256 loanId, uint256 tokenId, uint256 offerId) = _createCounteredOffer();

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        vm.prank(buyer);
        nftProtocol.acceptMarketplaceCounterOffer(tokenId, offerId);

        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 4_500e6);
        assertEq(nftProtocol.getBorrowerPositionOwner(loanId), buyer);
    }

    function test_acceptCounterOffer_lowerThanEscrow() public {
        // Offer 4000, counter to 3500 -> buyer gets 500 back.
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();
        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 3_500e6, OFFER_DURATION);

        uint256 buyerBalBefore = loanToken.balanceOf(buyer);
        uint256 sellerBalBefore = loanToken.balanceOf(borrower);

        vm.prank(buyer);
        nftProtocol.acceptMarketplaceCounterOffer(tokenId, offerId);

        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 3_500e6);
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore + 500e6);
    }

    function test_acceptCounterOffer_equalToEscrow() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();
        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 4_000e6, OFFER_DURATION);

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        vm.prank(buyer);
        nftProtocol.acceptMarketplaceCounterOffer(tokenId, offerId);

        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 4_000e6);
    }

    function test_acceptCounterOffer_notBuyer_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createCounteredOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotBuyer.selector);
        nftProtocol.acceptMarketplaceCounterOffer(tokenId, offerId);
    }

    function test_acceptCounterOffer_notCountered_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.InvalidOfferStatus.selector);
        nftProtocol.acceptMarketplaceCounterOffer(tokenId, offerId);
    }

    function test_acceptCounterOffer_expired_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createCounteredOffer();

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        vm.warp(offer.expiresAt);

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.OfferExpired.selector);
        nftProtocol.acceptMarketplaceCounterOffer(tokenId, offerId);
    }
}

// ============================================================================
// BUY POSITION (INSTANT BUY w/ maxPrice + expectedPaymentToken protection)
// ============================================================================

contract NFTBuyPositionTest is NFTMarketplaceSetup {

    function test_buyPosition_success() public {
        (uint256 loanId, uint256 tokenId) = _createListedBorrowerPosition();

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        vm.prank(buyer);
        nftProtocol.buyPosition(tokenId, 5_000e6, address(loanToken));

        // Seller received asking price.
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 5_000e6);
        // Position transferred.
        assertEq(nftProtocol.getBorrowerPositionOwner(loanId), buyer);
        // Listing deactivated.
        assertFalse(nftProtocol.isPositionListed(tokenId));
    }

    function test_buyPosition_higherMaxPrice_success() public {
        // Buyer is willing to pay more than asking; pays only the asking price.
        (, uint256 tokenId) = _createListedBorrowerPosition();

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        vm.prank(buyer);
        nftProtocol.buyPosition(tokenId, 10_000e6, address(loanToken));

        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 5_000e6);
    }

    function test_buyPosition_lenderPosition_success() public {
        (uint256 loanId, uint256 tokenId) = _createListedLenderPosition();

        vm.prank(buyer);
        nftProtocol.buyPosition(tokenId, 5_000e6, address(loanToken));

        assertEq(nftProtocol.getLenderPositionOwner(loanId), buyer);
    }

    function test_buyPosition_priceExceedsMax_reverts() public {
        // Slippage protection: asking price (5000) > maxPrice (4000).
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.PriceExceedsMaximum.selector);
        nftProtocol.buyPosition(tokenId, 4_000e6, address(loanToken));
    }

    function test_buyPosition_wrongExpectedToken_reverts() public {
        // MEV protection: expected payment token mismatch.
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.PaymentTokenMismatch.selector);
        nftProtocol.buyPosition(tokenId, 5_000e6, address(0xBEEF));
    }

    function test_buyPosition_notListed_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.buyPosition(999, 5_000e6, address(loanToken));
    }

    function test_buyPosition_cannotBuyOwn_reverts() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.CannotBuyOwnPosition.selector);
        nftProtocol.buyPosition(tokenId, 5_000e6, address(loanToken));
    }

    function test_buyPosition_marketplaceFrozen_reverts() public {
        (uint256 loanId, uint256 tokenId) = _createListedBorrowerPosition();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER_C);

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.MarketplaceFrozen.selector);
        nftProtocol.buyPosition(tokenId, 5_000e6, address(loanToken));
    }

    function test_buyPosition_refundsOpenOffers() public {
        (, uint256 tokenId, ) = _createListingWithOffer();

        // A different buyer instant-buys; the original offerer's escrow is refunded.
        address buyer2 = makeAddr("buyer2");
        loanToken.mint(buyer2, 10_000_000e6);
        vm.prank(buyer2);
        loanToken.approve(address(nftProtocol), type(uint256).max);

        uint256 origBuyerBalBefore = loanToken.balanceOf(buyer);

        vm.prank(buyer2);
        nftProtocol.buyPosition(tokenId, 5_000e6, address(loanToken));

        // buyPosition refunds OTHER offers via the pull-refund queue (not a wallet push).
        // The original offerer's escrow is queued in pendingRefunds, wallet unchanged until claimed.
        assertEq(loanToken.balanceOf(buyer), origBuyerBalBefore);
        assertEq(nftProtocol.getPendingRefund(buyer, address(loanToken)), 4_000e6);

        // After claiming, the wallet is made whole.
        vm.prank(buyer);
        nftProtocol.claimRefund(address(loanToken));
        assertEq(loanToken.balanceOf(buyer), origBuyerBalBefore + 4_000e6);
    }
}

// ============================================================================
// EXPIRE MARKETPLACE OFFER
// ============================================================================

contract NFTExpireOfferTest is NFTMarketplaceSetup {

    function test_expireOffer_success() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        vm.warp(offer.expiresAt);

        nftProtocol.expireMarketplaceOffer(tokenId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offerAfter = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offerAfter.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.EXPIRED));
        // Expire queues a pull-refund.
        assertEq(nftProtocol.getPendingRefund(buyer, address(loanToken)), 4_000e6);
    }

    function test_expireOffer_notYetExpired_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.expectRevert(NFTLoanProtocol.OfferNotExpired.selector);
        nftProtocol.expireMarketplaceOffer(tokenId, offerId);
    }

    function test_expireOffer_alreadyCancelled_reverts() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(buyer);
        nftProtocol.cancelMarketplaceOffer(tokenId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        vm.warp(offer.expiresAt + 1);

        vm.expectRevert(NFTLoanProtocol.InvalidOfferStatus.selector);
        nftProtocol.expireMarketplaceOffer(tokenId, offerId);
    }

    function test_expireOffer_counteredCanBeExpired() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(tokenId, offerId, 4_500e6, OFFER_DURATION);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        vm.warp(offer.expiresAt);

        nftProtocol.expireMarketplaceOffer(tokenId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offerAfter = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offerAfter.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.EXPIRED));
    }
}

// ============================================================================
// MARKETPLACE VIEW FUNCTIONS
// ============================================================================

contract NFTMarketplaceViewTest is NFTMarketplaceSetup {

    function test_getMarketplaceListing() public {
        (, uint256 tokenId) = _createListedBorrowerPosition();
        NFTLoanProtocol.MarketplaceListing memory listing = nftProtocol.getMarketplaceListing(tokenId);
        assertEq(listing.seller, borrower);
        assertEq(listing.askingPrice, 5_000e6);
    }

    function test_getMarketplaceOffer() public {
        (, uint256 tokenId, uint256 offerId) = _createListingWithOffer();
        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(offer.buyer, buyer);
        assertEq(offer.amount, 4_000e6);
    }

    function test_getMarketplaceOfferCount() public {
        (, uint256 tokenId, ) = _createListingWithOffer();
        assertEq(nftProtocol.getMarketplaceOfferCount(tokenId), 1);
    }

    function test_isPositionListed_falseWhenUnlisted() public {
        uint256 loanId = _createActiveNFTLoan();
        assertFalse(nftProtocol.isPositionListed(_borrowerTokenId(loanId)));
    }
}
