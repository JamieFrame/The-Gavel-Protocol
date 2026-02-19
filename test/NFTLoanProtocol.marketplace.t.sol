// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/NFTTestSetup.sol";

/**
 * @title NFTLoanProtocol Marketplace Tests
 * @notice Unit tests for NFTLoanProtocol integrated marketplace
 * @dev Covers: listPosition, listPositionFor, unlistPosition, updateListingPrice,
 *      makeMarketplaceOffer, cancelMarketplaceOffer, rejectMarketplaceOffer,
 *      counterMarketplaceOffer, acceptMarketplaceOffer, acceptMarketplaceCounterOffer,
 *      buyPosition, expireMarketplaceOffer
 *
 * Coverage target: Push NFTLoanProtocol.sol from 27% → 80%+ combined with core tests
 * Test count: ~55 tests
 */

// ============================================================================
// MARKETPLACE SETUP HELPERS
// ============================================================================

abstract contract NFTMarketplaceSetup is NFTTestSetup {

    address public paymentToken2;

    function setUp() public virtual override {
        super.setUp();
        // Second payment token for marketplace tests
        paymentToken2 = address(loanToken); // same token for simplicity
    }

    /// @dev Creates an active loan and lists borrower position for sale
    function _createListedBorrowerPosition() internal returns (uint256 loanId) {
        loanId = _createActiveNFTLoan();
        vm.prank(borrower);
        nftProtocol.listPosition(
            loanId, "borrower", address(loanToken), 5_000e6
        );
    }

    /// @dev Creates an active loan and lists lender position for sale
    function _createListedLenderPosition() internal returns (uint256 loanId) {
        loanId = _createActiveNFTLoan();
        vm.prank(lender);
        nftProtocol.listPosition(
            loanId, "lender", address(loanToken), 5_000e6
        );
    }

    /// @dev Creates a listed position and makes an offer on it
    function _createListingWithOffer() internal returns (uint256 loanId, uint256 offerId) {
        loanId = _createListedBorrowerPosition();
        vm.prank(buyer);
        offerId = nftProtocol.makeMarketplaceOffer(loanId, 4_000e6, 1 days);
    }
}

// ============================================================================
// LIST POSITION
// ============================================================================

contract NFTListPositionTest is NFTMarketplaceSetup {

    function test_listPosition_borrower_success() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6);

        NFTLoanProtocol.MarketplaceListing memory listing = nftProtocol.getMarketplaceListing(loanId);
        assertEq(listing.seller, borrower);
        assertTrue(listing.active);
        assertEq(listing.askingPrice, 5_000e6);
        assertTrue(nftProtocol.isPositionListed(loanId));
    }

    function test_listPosition_lender_success() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(lender);
        nftProtocol.listPosition(loanId, "lender", address(loanToken), 10_000e6);

        NFTLoanProtocol.MarketplaceListing memory listing = nftProtocol.getMarketplaceListing(loanId);
        assertEq(listing.seller, lender);
        assertTrue(listing.active);
    }

    function test_listPosition_alreadyListed_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.AlreadyListed.selector);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 6_000e6);
    }

    function test_listPosition_notPositionOwner_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotPositionOwner.selector);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6);
    }

    function test_listPosition_invalidPositionType_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidPositionType.selector);
        nftProtocol.listPosition(loanId, "invalid", address(loanToken), 5_000e6);
    }

    function test_listPosition_zeroPrice_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidPrice.selector);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 0);
    }

    function test_listPosition_zeroPaymentToken_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.ZeroAddress.selector);
        nftProtocol.listPosition(loanId, "borrower", address(0), 5_000e6);
    }

    function test_listPosition_withinMaturityBuffer_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        // Warp to within maturity buffer
        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.MarketplaceFrozen.selector);
        nftProtocol.listPosition(loanId, "borrower", address(loanToken), 5_000e6);
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
        nftProtocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 5_000e6);

        assertTrue(nftProtocol.isPositionListed(loanId));
    }

    function test_listPositionFor_unauthorized_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 5_000e6);
    }

    function test_listPositionFor_zeroSeller_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.ZeroAddress.selector);
        nftProtocol.listPositionFor(1, address(0), "borrower", address(loanToken), 5_000e6);
    }
}

// ============================================================================
// UNLIST POSITION
// ============================================================================

contract NFTUnlistPositionTest is NFTMarketplaceSetup {

    function test_unlistPosition_success() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(borrower);
        nftProtocol.unlistPosition(loanId);

        assertFalse(nftProtocol.isPositionListed(loanId));
    }

    function test_unlistPosition_notListed_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.unlistPosition(loanId);
    }

    function test_unlistPosition_notSeller_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.unlistPosition(loanId);
    }

    function test_unlistPosition_refundsOpenOffers() public {
        (uint256 loanId, ) = _createListingWithOffer();

        uint256 buyerBalBefore = loanToken.balanceOf(buyer);

        vm.prank(borrower);
        nftProtocol.unlistPosition(loanId);

        // Buyer's offer should be refunded via pendingRefunds
        uint256 refund = nftProtocol.getPendingRefund(buyer, address(loanToken));
        assertEq(refund, 4_000e6);
    }
}

// ============================================================================
// UPDATE LISTING PRICE
// ============================================================================

contract NFTUpdateListingPriceTest is NFTMarketplaceSetup {

    function test_updateListingPrice_success() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(borrower);
        nftProtocol.updateListingPrice(loanId, 8_000e6);

        NFTLoanProtocol.MarketplaceListing memory listing = nftProtocol.getMarketplaceListing(loanId);
        assertEq(listing.askingPrice, 8_000e6);
    }

    function test_updateListingPrice_notListed_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.updateListingPrice(999, 8_000e6);
    }

    function test_updateListingPrice_notSeller_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.updateListingPrice(loanId, 8_000e6);
    }

    function test_updateListingPrice_zeroPrice_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidPrice.selector);
        nftProtocol.updateListingPrice(loanId, 0);
    }
}

// ============================================================================
// MAKE MARKETPLACE OFFER
// ============================================================================

contract NFTMakeOfferTest is NFTMarketplaceSetup {

    function test_makeOffer_success() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(buyer);
        uint256 offerId = nftProtocol.makeMarketplaceOffer(loanId, 4_000e6, 1 days);

        assertEq(offerId, 1);
        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        assertEq(offer.buyer, buyer);
        assertEq(offer.amount, 4_000e6);
        assertEq(offer.escrowedAmount, 4_000e6);
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.PENDING));
    }

    function test_makeOffer_notListed_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.makeMarketplaceOffer(999, 4_000e6, 1 days);
    }

    function test_makeOffer_sellerCannotOffer_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.CannotBuyOwnPosition.selector);
        nftProtocol.makeMarketplaceOffer(loanId, 4_000e6, 1 days);
    }

    function test_makeOffer_zeroAmount_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.InvalidOffer.selector);
        nftProtocol.makeMarketplaceOffer(loanId, 0, 1 days);
    }

    function test_makeOffer_durationTooShort_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.OfferDurationTooShort.selector);
        nftProtocol.makeMarketplaceOffer(loanId, 4_000e6, 1 minutes);
    }

    function test_makeOffer_durationPastMaturity_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.OfferDurationTooLong.selector);
        nftProtocol.makeMarketplaceOffer(loanId, 4_000e6, 365 days);
    }

    function test_makeOffer_marketplaceFrozen_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER);

        vm.prank(buyer);
        vm.expectRevert();
        nftProtocol.makeMarketplaceOffer(loanId, 4_000e6, 1 minutes);
    }
}

// ============================================================================
// CANCEL MARKETPLACE OFFER
// ============================================================================

contract NFTCancelOfferTest is NFTMarketplaceSetup {

    function test_cancelOffer_pending_success() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        uint256 balBefore = loanToken.balanceOf(buyer);
        vm.prank(buyer);
        nftProtocol.cancelMarketplaceOffer(loanId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.CANCELLED));
        assertEq(loanToken.balanceOf(buyer), balBefore + 4_000e6);
    }

    function test_cancelOffer_notBuyer_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotBuyer.selector);
        nftProtocol.cancelMarketplaceOffer(loanId, offerId);
    }

    function test_cancelOffer_offerNotFound_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.OfferNotFound.selector);
        nftProtocol.cancelMarketplaceOffer(1, 999);
    }
}

// ============================================================================
// REJECT MARKETPLACE OFFER
// ============================================================================

contract NFTRejectOfferTest is NFTMarketplaceSetup {

    function test_rejectOffer_success() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        nftProtocol.rejectMarketplaceOffer(loanId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.REJECTED));
        // Refund queued via pendingRefunds
        assertEq(nftProtocol.getPendingRefund(buyer, address(loanToken)), 4_000e6);
    }

    function test_rejectOffer_notSeller_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.rejectMarketplaceOffer(loanId, offerId);
    }

    function test_rejectOffer_notPending_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        // Cancel first
        vm.prank(buyer);
        nftProtocol.cancelMarketplaceOffer(loanId, offerId);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidOfferStatus.selector);
        nftProtocol.rejectMarketplaceOffer(loanId, offerId);
    }
}

// ============================================================================
// COUNTER MARKETPLACE OFFER
// ============================================================================

contract NFTCounterOfferTest is NFTMarketplaceSetup {

    function test_counterOffer_success() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 4_500e6, 1 days);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.COUNTERED));
        assertEq(offer.counterAmount, 4_500e6);
    }

    function test_counterOffer_notSeller_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 4_500e6, 1 days);
    }

    function test_counterOffer_zeroAmount_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidOffer.selector);
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 0, 1 days);
    }

    function test_counterOffer_durationTooShort_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.OfferDurationTooShort.selector);
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 4_500e6, 1 minutes);
    }

    function test_counterOffer_durationPastMaturity_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.OfferDurationTooLong.selector);
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 4_500e6, 365 days);
    }

    function test_counterOffer_marketplaceFrozen_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER);

        vm.prank(borrower);
        vm.expectRevert();
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 4_500e6, 1 minutes);
    }
}

// ============================================================================
// ACCEPT MARKETPLACE OFFER
// ============================================================================

contract NFTAcceptOfferTest is NFTMarketplaceSetup {

    function test_acceptOffer_success() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        vm.prank(borrower);
        nftProtocol.acceptMarketplaceOffer(loanId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offer.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.ACCEPTED));

        // Seller received payment
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 4_000e6);

        // Position transferred
        assertEq(nftProtocol.getBorrowerPositionOwner(loanId), buyer);

        // Listing deactivated
        assertFalse(nftProtocol.isPositionListed(loanId));
    }

    function test_acceptOffer_notSeller_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotSeller.selector);
        nftProtocol.acceptMarketplaceOffer(loanId, offerId);
    }

    function test_acceptOffer_expired_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        vm.warp(offer.expiresAt);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.OfferExpired.selector);
        nftProtocol.acceptMarketplaceOffer(loanId, offerId);
    }

    function test_acceptOffer_notPending_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        // Cancel first
        vm.prank(buyer);
        nftProtocol.cancelMarketplaceOffer(loanId, offerId);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidOfferStatus.selector);
        nftProtocol.acceptMarketplaceOffer(loanId, offerId);
    }

    function test_acceptOffer_marketplaceFrozen_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER);

        vm.prank(borrower);
        vm.expectRevert();
        nftProtocol.acceptMarketplaceOffer(loanId, offerId);
    }
}

// ============================================================================
// ACCEPT COUNTER OFFER
// ============================================================================

contract NFTAcceptCounterOfferTest is NFTMarketplaceSetup {

    function _createCounteredOffer() internal returns (uint256 loanId, uint256 offerId) {
        (loanId, offerId) = _createListingWithOffer();
        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 4_500e6, 1 days);
    }

    function test_acceptCounterOffer_higherThanEscrow() public {
        // Counter is 4500, escrow is 4000 → buyer pays 500 more
        (uint256 loanId, uint256 offerId) = _createCounteredOffer();

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        vm.prank(buyer);
        nftProtocol.acceptMarketplaceCounterOffer(loanId, offerId);

        // Seller got counter amount
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 4_500e6);
        // Position transferred
        assertEq(nftProtocol.getBorrowerPositionOwner(loanId), buyer);
    }

    function test_acceptCounterOffer_lowerThanEscrow() public {
        // Offer 4000, counter to 3500 → buyer gets 500 back
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();
        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 3_500e6, 1 days);

        uint256 buyerBalBefore = loanToken.balanceOf(buyer);
        uint256 sellerBalBefore = loanToken.balanceOf(borrower);

        vm.prank(buyer);
        nftProtocol.acceptMarketplaceCounterOffer(loanId, offerId);

        // Seller got counter price
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 3_500e6);
        // Buyer got refund of difference
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore + 500e6);
    }

    function test_acceptCounterOffer_equalToEscrow() public {
        // Offer 4000, counter to exactly 4000
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();
        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 4_000e6, 1 days);

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        vm.prank(buyer);
        nftProtocol.acceptMarketplaceCounterOffer(loanId, offerId);

        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 4_000e6);
    }

    function test_acceptCounterOffer_notBuyer_reverts() public {
        (uint256 loanId, uint256 offerId) = _createCounteredOffer();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotBuyer.selector);
        nftProtocol.acceptMarketplaceCounterOffer(loanId, offerId);
    }

    function test_acceptCounterOffer_notCountered_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.InvalidOfferStatus.selector);
        nftProtocol.acceptMarketplaceCounterOffer(loanId, offerId);
    }

    function test_acceptCounterOffer_expired_reverts() public {
        (uint256 loanId, uint256 offerId) = _createCounteredOffer();

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        vm.warp(offer.expiresAt);

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.OfferExpired.selector);
        nftProtocol.acceptMarketplaceCounterOffer(loanId, offerId);
    }

    function test_acceptCounterOffer_marketplaceFrozen_reverts() public {
        (uint256 loanId, uint256 offerId) = _createCounteredOffer();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER);

        vm.prank(buyer);
        vm.expectRevert();
        nftProtocol.acceptMarketplaceCounterOffer(loanId, offerId);
    }
}

// ============================================================================
// BUY POSITION (INSTANT BUY AT ASKING PRICE)
// ============================================================================

contract NFTBuyPositionTest is NFTMarketplaceSetup {

    function test_buyPosition_success() public {
        uint256 loanId = _createListedBorrowerPosition();

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        vm.prank(buyer);
        nftProtocol.buyPosition(loanId);

        // Seller received asking price
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 5_000e6);
        // Position transferred
        assertEq(nftProtocol.getBorrowerPositionOwner(loanId), buyer);
        // Listing deactivated
        assertFalse(nftProtocol.isPositionListed(loanId));
    }

    function test_buyPosition_lenderPosition_success() public {
        uint256 loanId = _createListedLenderPosition();

        vm.prank(buyer);
        nftProtocol.buyPosition(loanId);

        assertEq(nftProtocol.getLenderPositionOwner(loanId), buyer);
    }

    function test_buyPosition_notListed_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.NotListed.selector);
        nftProtocol.buyPosition(999);
    }

    function test_buyPosition_cannotBuyOwn_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.CannotBuyOwnPosition.selector);
        nftProtocol.buyPosition(loanId);
    }

    function test_buyPosition_marketplaceFrozen_reverts() public {
        uint256 loanId = _createListedBorrowerPosition();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER);

        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.MarketplaceFrozen.selector);
        nftProtocol.buyPosition(loanId);
    }

    function test_buyPosition_refundsOpenOffers() public {
        (uint256 loanId, ) = _createListingWithOffer();

        vm.prank(buyer); // different buyer buys instantly
        // Can't buy own offer — need a different address
        address buyer2 = makeAddr("buyer2");
        loanToken.mint(buyer2, 10_000_000e6);
        vm.prank(buyer2);
        loanToken.approve(address(nftProtocol), type(uint256).max);

        vm.prank(buyer2);
        nftProtocol.buyPosition(loanId);

        // Original offerer should get refund via pendingRefunds
        uint256 refund = nftProtocol.getPendingRefund(buyer, address(loanToken));
        assertEq(refund, 4_000e6);
    }
}

// ============================================================================
// EXPIRE MARKETPLACE OFFER
// ============================================================================

contract NFTExpireOfferTest is NFTMarketplaceSetup {

    function test_expireOffer_success() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        vm.warp(offer.expiresAt);

        nftProtocol.expireMarketplaceOffer(loanId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offerAfter = nftProtocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offerAfter.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.EXPIRED));
        assertEq(nftProtocol.getPendingRefund(buyer, address(loanToken)), 4_000e6);
    }

    function test_expireOffer_notYetExpired_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.expectRevert(NFTLoanProtocol.OfferNotExpired.selector);
        nftProtocol.expireMarketplaceOffer(loanId, offerId);
    }

    function test_expireOffer_alreadyCancelled_reverts() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        vm.prank(buyer);
        nftProtocol.cancelMarketplaceOffer(loanId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        vm.warp(offer.expiresAt);

        vm.expectRevert(NFTLoanProtocol.InvalidOfferStatus.selector);
        nftProtocol.expireMarketplaceOffer(loanId, offerId);
    }

    function test_expireOffer_counteredCanBeExpired() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();

        // Counter the offer
        vm.prank(borrower);
        nftProtocol.counterMarketplaceOffer(loanId, offerId, 4_500e6, 1 days);

        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        vm.warp(offer.expiresAt);

        nftProtocol.expireMarketplaceOffer(loanId, offerId);

        NFTLoanProtocol.MarketplaceOffer memory offerAfter = nftProtocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offerAfter.status), uint(NFTLoanProtocol.MarketplaceOfferStatus.EXPIRED));
    }
}

// ============================================================================
// MARKETPLACE VIEW FUNCTIONS
// ============================================================================

contract NFTMarketplaceViewTest is NFTMarketplaceSetup {

    function test_getMarketplaceListing() public {
        uint256 loanId = _createListedBorrowerPosition();
        NFTLoanProtocol.MarketplaceListing memory listing = nftProtocol.getMarketplaceListing(loanId);
        assertEq(listing.seller, borrower);
        assertEq(listing.askingPrice, 5_000e6);
    }

    function test_getMarketplaceOffer() public {
        (uint256 loanId, uint256 offerId) = _createListingWithOffer();
        NFTLoanProtocol.MarketplaceOffer memory offer = nftProtocol.getMarketplaceOffer(loanId, offerId);
        assertEq(offer.buyer, buyer);
        assertEq(offer.amount, 4_000e6);
    }

    function test_getMarketplaceOfferCount() public {
        (uint256 loanId, ) = _createListingWithOffer();
        assertEq(nftProtocol.getMarketplaceOfferCount(loanId), 1);
    }
}
