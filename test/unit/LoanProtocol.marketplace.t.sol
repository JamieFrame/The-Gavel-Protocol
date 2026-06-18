// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/TestSetup.sol";

/**
 * @title LoanProtocolMarketplaceTests
 * @notice Unit tests for LoanProtocol integrated marketplace (current/deployed API)
 * @dev Covers: listPosition, listPositionFor, unlistPosition, updateListingPrice,
 *      cleanStaleListing, makeMarketplaceOffer, cancelMarketplaceOffer,
 *      rejectMarketplaceOffer, expireMarketplaceOffer, counterMarketplaceOffer,
 *      acceptMarketplaceOffer, acceptMarketplaceCounterOffer, buyPosition.
 *
 * API notes (source of truth: contracts/interfaces/ILoanProtocol.sol + LoanProtocol.sol):
 *   - listPosition / listPositionFor take a loanId + positionType + minOfferAmount.
 *   - ALL OTHER marketplace ops and ALL views are keyed by the Position NFT tokenId,
 *     where borrower tokenId = loanId*2 and lender tokenId = loanId*2+1.
 *   - makeMarketplaceOffer(tokenId, amount, duration, expectedPaymentToken).
 *   - buyPosition(tokenId, maxPrice, expectedPaymentToken) — MEV/slippage protection.
 *
 * Coverage target: LoanProtocol marketplace paths.
 */

// ============================================================================
// SHARED MARKETPLACE BASE
// ============================================================================

abstract contract MarketplaceBase is TestSetup {
    /// @dev Borrower position tokenId for a loan (even).
    function _borrowerToken(uint256 loanId) internal view returns (uint256) {
        return positionNFT.getBorrowerTokenId(loanId);
    }

    /// @dev Lender position tokenId for a loan (odd).
    function _lenderToken(uint256 loanId) internal view returns (uint256) {
        return positionNFT.getLenderTokenId(loanId);
    }

    /// @dev List the borrower position at `price` (default loanToken, no min floor).
    function _listBorrower(uint256 loanId, uint256 price) internal returns (uint256 tokenId) {
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), price, 0);
        tokenId = _borrowerToken(loanId);
    }
}

// ============================================================================
// LISTING
// ============================================================================

contract ListPositionTest is MarketplaceBase {

    function test_listPosition_borrower() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6, 0);

        uint256 tokenId = _borrowerToken(loanId);
        LoanProtocol.MarketplaceListing memory listing = protocol.getMarketplaceListing(tokenId);
        assertEq(listing.seller, borrower);
        assertEq(listing.askingPrice, 1000e6);
        assertEq(listing.loanId, loanId);
        assertEq(listing.paymentToken, address(loanToken));
        assertTrue(listing.active);
        assertTrue(protocol.isPositionListed(tokenId));
    }

    function test_listPosition_lender() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(lender);
        protocol.listPosition(loanId, "lender", address(loanToken), 2000e6, 0);

        uint256 tokenId = _lenderToken(loanId);
        LoanProtocol.MarketplaceListing memory listing = protocol.getMarketplaceListing(tokenId);
        assertEq(listing.seller, lender);
        assertEq(listing.askingPrice, 2000e6);
        assertTrue(protocol.isPositionListed(tokenId));
    }

    function test_listPosition_withMinOfferFloor() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6, 500e6);

        LoanProtocol.MarketplaceListing memory listing = protocol.getMarketplaceListing(_borrowerToken(loanId));
        assertEq(listing.minOfferAmount, 500e6);
    }

    function test_listPosition_notOwner_reverts() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotPositionOwner.selector);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6, 0);
    }

    function test_listPosition_invalidType_reverts() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InvalidPositionType.selector);
        protocol.listPosition(loanId, "invalid", address(loanToken), 1000e6, 0);
    }

    function test_listPosition_zeroPrice_reverts() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InvalidPrice.selector);
        protocol.listPosition(loanId, "borrower", address(loanToken), 0, 0);
    }

    function test_listPosition_minOfferAboveAsking_reverts() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InvalidPrice.selector);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6, 1001e6);
    }

    function test_listPosition_alreadyListed_reverts() public {
        uint256 loanId = _createActiveLoan();

        vm.startPrank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6, 0);
        vm.expectRevert(LoanProtocol.AlreadyListed.selector);
        protocol.listPosition(loanId, "borrower", address(loanToken), 2000e6, 0);
        vm.stopPrank();
    }

    function test_listPosition_afterRepay_reverts() public {
        uint256 loanId = _createActiveLoan();

        // Repay the loan first. repayLoan() BURNS both position NFTs, so the
        // position no longer exists. listPosition() checks NFT ownership
        // (ownerOf) BEFORE it checks loan status, so the revert is the
        // ERC721 nonexistent-token error — NOT LoanNotActive. There is no
        // reachable state where the loan is inactive but the NFT still exists
        // (repay and default both burn the NFTs), so we assert the true revert.
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), DEFAULT_MAX_REPAYMENT);
        protocol.repayLoan(loanId);

        uint256 burnedTokenId = positionNFT.getBorrowerTokenId(loanId);
        vm.expectRevert(
            abi.encodeWithSignature("ERC721NonexistentToken(uint256)", burnedTokenId)
        );
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6, 0);
        vm.stopPrank();
    }

    function test_listPosition_withinMaturityBuffer_reverts() public {
        uint256 loanId = _createActiveLoan();

        // Warp to within maturity buffer (marketplace frozen)
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER);

        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.MarketplaceFrozen.selector);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6, 0);
    }

    function test_listPosition_zeroPaymentToken_reverts() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.ZeroAddress.selector);
        protocol.listPosition(loanId, "borrower", address(0), 1000e6, 0);
    }
}

contract ListPositionForTest is MarketplaceBase {

    function test_listPositionFor_asOperator() public {
        uint256 loanId = _createActiveLoan();
        address operator = makeAddr("operator");

        vm.prank(borrower);
        protocol.setOperatorApproval(operator, true);

        vm.prank(operator);
        protocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 1000e6, 0);

        uint256 tokenId = _borrowerToken(loanId);
        assertTrue(protocol.isPositionListed(tokenId));
        assertEq(protocol.getMarketplaceListing(tokenId).seller, borrower);
    }

    function test_listPositionFor_asSelf() public {
        uint256 loanId = _createActiveLoan();

        // seller == msg.sender path (no operator approval needed)
        vm.prank(borrower);
        protocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 1000e6, 0);

        assertTrue(protocol.isPositionListed(_borrowerToken(loanId)));
    }

    function test_listPositionFor_unauthorized_reverts() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.Unauthorized.selector);
        protocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 1000e6, 0);
    }

    function test_listPositionFor_zeroSeller_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.ZeroAddress.selector);
        protocol.listPositionFor(1, address(0), "borrower", address(loanToken), 1000e6, 0);
    }
}

// ============================================================================
// UNLIST & UPDATE
// ============================================================================

contract UnlistPositionTest is MarketplaceBase {

    function test_unlistPosition_success() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(borrower);
        protocol.unlistPosition(tokenId);

        assertFalse(protocol.isPositionListed(tokenId));
    }

    function test_unlistPosition_notListed_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.NotListed.selector);
        protocol.unlistPosition(999);
    }

    function test_unlistPosition_notSeller_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotSeller.selector);
        protocol.unlistPosition(tokenId);
    }

    function test_unlistPosition_refundsOffers() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        // Buyer makes offer
        vm.prank(buyer);
        protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        uint256 buyerBalBefore = loanToken.balanceOf(buyer);

        // Seller unlists — buyer's refund is queued (pull pattern, seller is msg.sender)
        vm.prank(borrower);
        protocol.unlistPosition(tokenId);

        // Buyer claims refund
        vm.prank(buyer);
        protocol.claimRefund(address(loanToken));

        assertEq(loanToken.balanceOf(buyer), buyerBalBefore + 800e6);
    }
}

contract CleanStaleListingTest is MarketplaceBase {

    function test_cleanStaleListing_afterDirectTransfer() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        // Borrower transfers the NFT directly, bypassing the marketplace -> listing is stale
        vm.prank(borrower);
        positionNFT.transferFrom(borrower, lender2, tokenId);

        // Anyone can clean the stale listing
        vm.prank(attacker);
        protocol.cleanStaleListing(tokenId);

        assertFalse(protocol.isPositionListed(tokenId));
    }

    function test_cleanStaleListing_notStale_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        // Seller still owns the position -> not stale
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.ListingNotStale.selector);
        protocol.cleanStaleListing(tokenId);
    }

    function test_cleanStaleListing_notListed_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotListed.selector);
        protocol.cleanStaleListing(999);
    }
}

contract UpdateListingPriceTest is MarketplaceBase {

    function test_updateListingPrice_success() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(borrower);
        protocol.updateListingPrice(tokenId, 2000e6);

        LoanProtocol.MarketplaceListing memory listing = protocol.getMarketplaceListing(tokenId);
        assertEq(listing.askingPrice, 2000e6);
    }

    function test_updateListingPrice_zeroPrice_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InvalidPrice.selector);
        protocol.updateListingPrice(tokenId, 0);
    }

    function test_updateListingPrice_notSeller_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotSeller.selector);
        protocol.updateListingPrice(tokenId, 2000e6);
    }

    function test_updateListingPrice_notListed_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.NotListed.selector);
        protocol.updateListingPrice(999, 2000e6);
    }
}

// ============================================================================
// OFFERS
// ============================================================================

contract MakeOfferTest is MarketplaceBase {

    function test_makeOffer_success() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        uint256 buyerBalBefore = loanToken.balanceOf(buyer);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        assertEq(offerId, 1);
        assertEq(protocol.getMarketplaceOfferCount(tokenId), 1);

        // Funds escrowed
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore - 800e6);

        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(offer.buyer, buyer);
        assertEq(offer.amount, 800e6);
        assertEq(offer.escrowedAmount, 800e6);
        assertEq(offer.paymentToken, address(loanToken));
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.PENDING));
    }

    function test_makeOffer_zeroAmount_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.InvalidOffer.selector);
        protocol.makeMarketplaceOffer(tokenId, 0, MIN_OFFER_DURATION, address(loanToken));
    }

    function test_makeOffer_belowMinFloor_reverts() public {
        uint256 loanId = _createActiveLoan();

        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6, 500e6);
        uint256 tokenId = _borrowerToken(loanId);

        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.OfferBelowMinimum.selector);
        protocol.makeMarketplaceOffer(tokenId, 400e6, MIN_OFFER_DURATION, address(loanToken));
    }

    function test_makeOffer_sellerBuysOwn_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        loanToken.mint(borrower, 1000e6);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), 1000e6);
        vm.expectRevert(LoanProtocol.CannotBuyOwnPosition.selector);
        protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));
        vm.stopPrank();
    }

    function test_makeOffer_tooShortDuration_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.OfferDurationTooShort.selector);
        protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION - 1, address(loanToken));
    }

    function test_makeOffer_paymentTokenMismatch_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        // Buyer expects collateralToken but listing uses loanToken (MEV protection)
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.PaymentTokenMismatch.selector);
        protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(collateralToken));
    }

    function test_makeOffer_notListed_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.NotListed.selector);
        protocol.makeMarketplaceOffer(999, 800e6, MIN_OFFER_DURATION, address(loanToken));
    }

    function test_makeOffer_tooManyOffers_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, type(uint256).max / 2);

        // Fill the cap with MAX_OFFERS_PER_LISTING distinct buyers.
        for (uint256 i = 0; i < MAX_OFFERS_PER_LISTING; i++) {
            address b = makeAddr(string(abi.encodePacked("offerer", i)));
            loanToken.mint(b, 1e6);
            vm.startPrank(b);
            loanToken.approve(address(protocol), 1e6);
            protocol.makeMarketplaceOffer(tokenId, 1e6, MIN_OFFER_DURATION, address(loanToken));
            vm.stopPrank();
        }

        // One past the cap reverts.
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.TooManyOffers.selector);
        protocol.makeMarketplaceOffer(tokenId, 1e6, MIN_OFFER_DURATION, address(loanToken));
    }
}

contract CancelOfferTest is MarketplaceBase {

    function test_cancelOffer_success() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        uint256 buyerBalBefore = loanToken.balanceOf(buyer);

        vm.prank(buyer);
        protocol.cancelMarketplaceOffer(tokenId, offerId);

        // Funds returned immediately (buyer is msg.sender)
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore + 800e6);

        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.CANCELLED));
        assertEq(offer.escrowedAmount, 0);
    }

    function test_cancelOffer_notBuyer_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotBuyer.selector);
        protocol.cancelMarketplaceOffer(tokenId, offerId);
    }

    function test_cancelOffer_notFound_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.OfferNotFound.selector);
        protocol.cancelMarketplaceOffer(1, 999);
    }
}

contract RejectOfferTest is MarketplaceBase {

    function test_rejectOffer_success() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        vm.prank(borrower);
        protocol.rejectMarketplaceOffer(tokenId, offerId);

        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.REJECTED));

        // Buyer's refund queued (pull pattern since seller is msg.sender)
        assertEq(protocol.getPendingRefund(buyer, address(loanToken)), 800e6);
    }

    function test_rejectOffer_notSeller_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotSeller.selector);
        protocol.rejectMarketplaceOffer(tokenId, offerId);
    }
}

contract ExpireOfferTest is MarketplaceBase {

    function test_expireOffer_success() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        // Warp past expiry — permissionless expire
        vm.warp(block.timestamp + MIN_OFFER_DURATION + 1);

        protocol.expireMarketplaceOffer(tokenId, offerId);

        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.EXPIRED));

        // Refund queued for buyer (pull pattern)
        assertEq(protocol.getPendingRefund(buyer, address(loanToken)), 800e6);
    }

    function test_expireOffer_notYetExpired_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        // Don't warp
        vm.expectRevert(LoanProtocol.OfferNotExpired.selector);
        protocol.expireMarketplaceOffer(tokenId, offerId);
    }
}

// ============================================================================
// COUNTER-OFFERS
// ============================================================================

contract CounterOfferTest is MarketplaceBase {

    function test_counterOffer_success() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        vm.prank(borrower);
        protocol.counterMarketplaceOffer(tokenId, offerId, 900e6, MIN_OFFER_DURATION);

        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.COUNTERED));
        assertEq(offer.counterAmount, 900e6);
    }

    function test_counterOffer_notSeller_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotSeller.selector);
        protocol.counterMarketplaceOffer(tokenId, offerId, 900e6, MIN_OFFER_DURATION);
    }

    function test_counterOffer_durationTooShort_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.OfferDurationTooShort.selector);
        protocol.counterMarketplaceOffer(tokenId, offerId, 900e6, MIN_OFFER_DURATION - 1);
    }
}

// ============================================================================
// ACCEPT OFFER & ACCEPT COUNTER
// ============================================================================

contract AcceptOfferTest is MarketplaceBase {

    function test_acceptOffer_transfersPosition() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 1000e6, MIN_OFFER_DURATION, address(loanToken));

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);

        vm.prank(borrower);
        protocol.acceptMarketplaceOffer(tokenId, offerId);

        // Buyer now owns borrower position NFT
        assertEq(positionNFT.ownerOf(tokenId), buyer);

        // Seller received escrowed payment
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 1000e6);

        // Offer accepted
        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(tokenId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.ACCEPTED));

        // Listing deactivated
        assertFalse(protocol.isPositionListed(tokenId));
    }

    function test_acceptOffer_notSeller_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 1000e6, MIN_OFFER_DURATION, address(loanToken));

        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotSeller.selector);
        protocol.acceptMarketplaceOffer(tokenId, offerId);
    }

    function test_acceptCounterOffer_success() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        // Seller counters at 900
        vm.prank(borrower);
        protocol.counterMarketplaceOffer(tokenId, offerId, 900e6, MIN_OFFER_DURATION);

        uint256 buyerBalBefore = loanToken.balanceOf(buyer);
        uint256 sellerBalBefore = loanToken.balanceOf(borrower);

        // Buyer tops up the difference (900 - 800 = 100) and accepts
        vm.prank(buyer);
        protocol.acceptMarketplaceCounterOffer(tokenId, offerId);

        // Buyer owns position
        assertEq(positionNFT.ownerOf(tokenId), buyer);

        // Buyer paid 100 more (delta), seller received 900
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore - 100e6);
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 900e6);

        assertFalse(protocol.isPositionListed(tokenId));
    }

    function test_acceptCounterOffer_notBuyer_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(tokenId, 800e6, MIN_OFFER_DURATION, address(loanToken));

        vm.prank(borrower);
        protocol.counterMarketplaceOffer(tokenId, offerId, 900e6, MIN_OFFER_DURATION);

        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotBuyer.selector);
        protocol.acceptMarketplaceCounterOffer(tokenId, offerId);
    }
}

// ============================================================================
// DIRECT PURCHASE (buyPosition) — incl. MEV/slippage protection
// ============================================================================

contract BuyPositionTest is MarketplaceBase {

    function test_buyPosition_atAskingPrice() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        uint256 sellerBalBefore = loanToken.balanceOf(borrower);

        vm.prank(buyer);
        protocol.buyPosition(tokenId, 1000e6, address(loanToken));

        // Buyer owns position
        assertEq(positionNFT.ownerOf(tokenId), buyer);

        // Seller received payment
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 1000e6);

        // Listing deactivated
        assertFalse(protocol.isPositionListed(tokenId));
    }

    function test_buyPosition_maxPriceAboveAsking_ok() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        // Buyer willing to pay up to 1500 but only pays the 1000 asking price
        uint256 buyerBalBefore = loanToken.balanceOf(buyer);
        vm.prank(buyer);
        protocol.buyPosition(tokenId, 1500e6, address(loanToken));

        assertEq(positionNFT.ownerOf(tokenId), buyer);
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore - 1000e6);
    }

    function test_buyPosition_priceExceedsMaxPrice_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        // Slippage protection: asking 1000 > maxPrice 999
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.PriceExceedsMaximum.selector);
        protocol.buyPosition(tokenId, 999e6, address(loanToken));
    }

    function test_buyPosition_paymentTokenMismatch_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        // MEV protection: buyer expects collateralToken, listing uses loanToken
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.PaymentTokenMismatch.selector);
        protocol.buyPosition(tokenId, 1000e6, address(collateralToken));
    }

    function test_buyPosition_notListed_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.NotListed.selector);
        protocol.buyPosition(999, 1000e6, address(loanToken));
    }

    function test_buyPosition_sellerBuysOwn_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        loanToken.mint(borrower, 1000e6);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), 1000e6);
        vm.expectRevert(LoanProtocol.CannotBuyOwnPosition.selector);
        protocol.buyPosition(tokenId, 1000e6, address(loanToken));
        vm.stopPrank();
    }

    function test_buyPosition_withinMaturityBuffer_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        // Warp into the maturity-buffer freeze window
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER);

        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.MarketplaceFrozen.selector);
        protocol.buyPosition(tokenId, 1000e6, address(loanToken));
    }

    function test_buyPosition_refundsExistingOffers() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = _listBorrower(loanId, 1000e6);

        // lender2 makes a standing offer that must be refunded when buyer buys outright
        vm.prank(lender2);
        protocol.makeMarketplaceOffer(tokenId, 700e6, MIN_OFFER_DURATION, address(loanToken));

        vm.prank(buyer);
        protocol.buyPosition(tokenId, 1000e6, address(loanToken));

        // lender2's escrow is queued as a pull refund
        assertEq(protocol.getPendingRefund(lender2, address(loanToken)), 700e6);
        assertEq(positionNFT.ownerOf(tokenId), buyer);
    }
}
