// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/TestSetup.sol";

/**
 * @title LoanProtocolMarketplaceTests
 * @notice Unit tests for LoanProtocol integrated marketplace
 * @dev Covers: listPosition, listPositionFor, unlistPosition, updateListingPrice,
 *      makeMarketplaceOffer, cancelMarketplaceOffer, rejectMarketplaceOffer,
 *      expireMarketplaceOffer, counterMarketplaceOffer, acceptMarketplaceOffer,
 *      acceptMarketplaceCounterOffer, buyPosition
 *
 * Coverage target: LoanProtocol marketplace paths (currently ~0% covered)
 */

// ============================================================================
// LISTING
// ============================================================================

contract ListPositionTest is TestSetup {

    function test_listPosition_borrower() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        LoanProtocol.MarketplaceListing memory listing = protocol.getMarketplaceListing(loanId);
        assertEq(listing.seller, borrower);
        assertEq(listing.askingPrice, 1000e6);
        assertTrue(listing.active);
        assertTrue(protocol.isPositionListed(loanId));
    }
    
    function test_listPosition_lender() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(lender);
        protocol.listPosition(loanId, "lender", address(loanToken), 2000e6);
        
        LoanProtocol.MarketplaceListing memory listing = protocol.getMarketplaceListing(loanId);
        assertEq(listing.seller, lender);
    }
    
    function test_listPosition_notOwner_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotPositionOwner.selector);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
    }
    
    function test_listPosition_invalidType_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InvalidPositionType.selector);
        protocol.listPosition(loanId, "invalid", address(loanToken), 1000e6);
    }
    
    function test_listPosition_zeroPrice_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InvalidPrice.selector);
        protocol.listPosition(loanId, "borrower", address(loanToken), 0);
    }
    
    function test_listPosition_alreadyListed_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.startPrank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        vm.expectRevert(LoanProtocol.AlreadyListed.selector);
        protocol.listPosition(loanId, "borrower", address(loanToken), 2000e6);
        vm.stopPrank();
    }
    
    function test_listPosition_loanNotActive_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        // Repay the loan first
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), DEFAULT_MAX_REPAYMENT);
        protocol.repayLoan(loanId);
        
        vm.expectRevert();
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        vm.stopPrank();
    }
    
    function test_listPosition_withinMaturityBuffer_reverts() public {
        // Create loan with short duration (just above minimum + buffer)
        uint256 shortDuration = MIN_LOAN_DURATION + MATURITY_BUFFER;
        uint256 loanId = _depositAndCreateAuction(
            DEFAULT_COLLATERAL, DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            shortDuration, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.prank(lender);
        protocol.placeBid(loanId, DEFAULT_MAX_REPAYMENT);
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        protocol.finalizeAuction(loanId);
        
        // Warp to within maturity buffer
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        vm.warp(loan.maturityTimestamp - MATURITY_BUFFER);
        
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.MarketplaceFrozen.selector);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
    }
    
    function test_listPosition_zeroPaymentToken_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.ZeroAddress.selector);
        protocol.listPosition(loanId, "borrower", address(0), 1000e6);
    }
}

contract ListPositionForTest is TestSetup {

    function test_listPositionFor_asOperator() public {
        uint256 loanId = _createActiveLoan();
        address operator = makeAddr("operator");
        
        vm.prank(borrower);
        protocol.setOperatorApproval(operator, true);
        
        vm.prank(operator);
        protocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 1000e6);
        
        assertTrue(protocol.isPositionListed(loanId));
    }
    
    function test_listPositionFor_unauthorized_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.Unauthorized.selector);
        protocol.listPositionFor(loanId, borrower, "borrower", address(loanToken), 1000e6);
    }
    
    function test_listPositionFor_zeroSeller_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.ZeroAddress.selector);
        protocol.listPositionFor(1, address(0), "borrower", address(loanToken), 1000e6);
    }
}

// ============================================================================
// UNLIST & UPDATE
// ============================================================================

contract UnlistPositionTest is TestSetup {

    function test_unlistPosition_success() public {
        uint256 loanId = _createActiveLoan();
        
        vm.startPrank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        protocol.unlistPosition(loanId);
        vm.stopPrank();
        
        assertFalse(protocol.isPositionListed(loanId));
    }
    
    function test_unlistPosition_notListed_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.NotListed.selector);
        protocol.unlistPosition(999);
    }
    
    function test_unlistPosition_notSeller_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotSeller.selector);
        protocol.unlistPosition(loanId);
    }
    
    function test_unlistPosition_refundsOffers() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        // Buyer makes offer
        vm.prank(buyer);
        protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        uint256 buyerBalBefore = loanToken.balanceOf(buyer);
        
        // Seller unlists — buyer gets refund queued
        vm.prank(borrower);
        protocol.unlistPosition(loanId);
        
        // Buyer claims refund
        vm.prank(buyer);
        protocol.claimRefund(address(loanToken));
        
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore + 800e6);
    }
}

contract UpdateListingPriceTest is TestSetup {

    function test_updateListingPrice_success() public {
        uint256 loanId = _createActiveLoan();
        
        vm.startPrank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        protocol.updateListingPrice(loanId, 2000e6);
        vm.stopPrank();
        
        LoanProtocol.MarketplaceListing memory listing = protocol.getMarketplaceListing(loanId);
        assertEq(listing.askingPrice, 2000e6);
    }
    
    function test_updateListingPrice_zeroPrice_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.startPrank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        vm.expectRevert(LoanProtocol.InvalidPrice.selector);
        protocol.updateListingPrice(loanId, 0);
        vm.stopPrank();
    }
    
    function test_updateListingPrice_notSeller_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotSeller.selector);
        protocol.updateListingPrice(loanId, 2000e6);
    }
}

// ============================================================================
// OFFERS
// ============================================================================

contract MakeOfferTest is TestSetup {

    function test_makeOffer_success() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        uint256 buyerBalBefore = loanToken.balanceOf(buyer);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        assertEq(offerId, 1);
        assertEq(protocol.getMarketplaceOfferCount(loanId), 1);
        
        // Funds escrowed
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore - 800e6);
        
        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(loanId, offerId);
        assertEq(offer.buyer, buyer);
        assertEq(offer.amount, 800e6);
        assertEq(offer.escrowedAmount, 800e6);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.PENDING));
    }
    
    function test_makeOffer_zeroAmount_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.InvalidOffer.selector);
        protocol.makeMarketplaceOffer(loanId, 0, MIN_OFFER_DURATION);
    }
    
    function test_makeOffer_sellerBuysOwn_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        loanToken.mint(borrower, 1000e6);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), 1000e6);
        vm.expectRevert(LoanProtocol.CannotBuyOwnPosition.selector);
        protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        vm.stopPrank();
    }
    
    function test_makeOffer_tooShortDuration_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.OfferDurationTooShort.selector);
        protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION - 1);
    }
    
    function test_makeOffer_notListed_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.NotListed.selector);
        protocol.makeMarketplaceOffer(999, 800e6, MIN_OFFER_DURATION);
    }
}

contract CancelOfferTest is TestSetup {

    function test_cancelOffer_success() public {
        uint256 loanId = _createActiveLoan();
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        uint256 buyerBalBefore = loanToken.balanceOf(buyer);
        
        vm.prank(buyer);
        protocol.cancelMarketplaceOffer(loanId, offerId);
        
        // Funds returned immediately (buyer is msg.sender)
        assertEq(loanToken.balanceOf(buyer), buyerBalBefore + 800e6);
        
        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.CANCELLED));
        assertEq(offer.escrowedAmount, 0);
    }
    
    function test_cancelOffer_notBuyer_reverts() public {
        uint256 loanId = _createActiveLoan();
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotBuyer.selector);
        protocol.cancelMarketplaceOffer(loanId, offerId);
    }
    
    function test_cancelOffer_notFound_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.OfferNotFound.selector);
        protocol.cancelMarketplaceOffer(1, 999);
    }
}

contract RejectOfferTest is TestSetup {

    function test_rejectOffer_success() public {
        uint256 loanId = _createActiveLoan();
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        vm.prank(borrower);
        protocol.rejectMarketplaceOffer(loanId, offerId);
        
        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.REJECTED));
        
        // Buyer's refund queued (pull pattern since seller is msg.sender)
        uint256 pendingRefund = protocol.getPendingRefund(buyer, address(loanToken));
        assertEq(pendingRefund, 800e6);
    }
    
    function test_rejectOffer_notSeller_reverts() public {
        uint256 loanId = _createActiveLoan();
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotSeller.selector);
        protocol.rejectMarketplaceOffer(loanId, offerId);
    }
}

contract ExpireOfferTest is TestSetup {

    function test_expireOffer_success() public {
        uint256 loanId = _createActiveLoan();
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        // Warp past expiry
        vm.warp(block.timestamp + MIN_OFFER_DURATION + 1);
        
        protocol.expireMarketplaceOffer(loanId, offerId);
        
        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.EXPIRED));
    }
    
    function test_expireOffer_notYetExpired_reverts() public {
        uint256 loanId = _createActiveLoan();
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        // Don't warp
        vm.expectRevert(LoanProtocol.OfferNotExpired.selector);
        protocol.expireMarketplaceOffer(loanId, offerId);
    }
}

// ============================================================================
// COUNTER-OFFERS
// ============================================================================

contract CounterOfferTest is TestSetup {

    function test_counterOffer_success() public {
        uint256 loanId = _createActiveLoan();
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        vm.prank(borrower);
        protocol.counterMarketplaceOffer(loanId, offerId, 900e6, MIN_OFFER_DURATION);
        
        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.COUNTERED));
        assertEq(offer.counterAmount, 900e6);
    }
    
    function test_counterOffer_notSeller_reverts() public {
        uint256 loanId = _createActiveLoan();
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotSeller.selector);
        protocol.counterMarketplaceOffer(loanId, offerId, 900e6, MIN_OFFER_DURATION);
    }
}

// ============================================================================
// ACCEPT OFFER & BUY
// ============================================================================

contract AcceptOfferTest is TestSetup {

    function test_acceptOffer_transfersPosition() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 1000e6, MIN_OFFER_DURATION);
        
        vm.prank(borrower);
        protocol.acceptMarketplaceOffer(loanId, offerId);
        
        // Buyer now owns borrower position NFT
        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);
        assertEq(positionNFT.ownerOf(tokenId), buyer);
        
        // Offer accepted
        LoanProtocol.MarketplaceOffer memory offer = protocol.getMarketplaceOffer(loanId, offerId);
        assertEq(uint(offer.status), uint(LoanProtocol.MarketplaceOfferStatus.ACCEPTED));
        
        // Listing deactivated
        assertFalse(protocol.isPositionListed(loanId));
    }
    
    function test_acceptCounterOffer_success() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        vm.prank(buyer);
        uint256 offerId = protocol.makeMarketplaceOffer(loanId, 800e6, MIN_OFFER_DURATION);
        
        // Seller counters at 900
        vm.prank(borrower);
        protocol.counterMarketplaceOffer(loanId, offerId, 900e6, MIN_OFFER_DURATION);
        
        // Buyer needs to top up the difference (900 - 800 = 100)
        vm.prank(buyer);
        protocol.acceptMarketplaceCounterOffer(loanId, offerId);
        
        // Buyer owns position
        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);
        assertEq(positionNFT.ownerOf(tokenId), buyer);
    }
}

contract BuyPositionTest is TestSetup {

    function test_buyPosition_atAskingPrice() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        uint256 sellerBalBefore = loanToken.balanceOf(borrower);
        
        vm.prank(buyer);
        protocol.buyPosition(loanId);
        
        // Buyer owns position
        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);
        assertEq(positionNFT.ownerOf(tokenId), buyer);
        
        // Seller received payment
        assertEq(loanToken.balanceOf(borrower), sellerBalBefore + 1000e6);
        
        // Listing deactivated
        assertFalse(protocol.isPositionListed(loanId));
    }
    
    function test_buyPosition_notListed_reverts() public {
        vm.prank(buyer);
        vm.expectRevert(LoanProtocol.NotListed.selector);
        protocol.buyPosition(999);
    }
    
    function test_buyPosition_sellerBuysOwn_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(borrower);
        protocol.listPosition(loanId, "borrower", address(loanToken), 1000e6);
        
        loanToken.mint(borrower, 1000e6);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), 1000e6);
        vm.expectRevert(LoanProtocol.CannotBuyOwnPosition.selector);
        protocol.buyPosition(loanId);
        vm.stopPrank();
    }
}
