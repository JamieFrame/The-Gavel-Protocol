// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/NFTTestSetup.sol";

/**
 * @title NFTLoanProtocol Core Tests
 * @notice Unit tests for NFTLoanProtocol core lifecycle (non-marketplace)
 * @dev Covers: createAuction, createAuctionFor, cancelAuction, placeBid, claimRefund,
 *      finalizeAuction, repayLoan, claimCollateral, claimExpiredAuction,
 *      operator approvals, admin (pause/unpause), view functions
 *
 * Coverage target: NFTLoanProtocol.sol 27% → 80%+ line coverage
 * Test count: ~65 tests
 */

// ============================================================================
// AUCTION CREATION
// ============================================================================

contract NFTCreateAuctionTest is NFTTestSetup {

    function test_createAuction_success() public {
        vm.prank(borrower);
        uint256 auctionId = nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );

        assertEq(auctionId, 1);
        // NFT transferred to protocol
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), address(nftProtocol));

        NFTLoanProtocol.Auction memory auction = nftProtocol.getAuction(auctionId);
        assertEq(auction.borrower, borrower);
        assertEq(auction.collateralNFT, address(mockNFT));
        assertEq(auction.collateralTokenId, DEFAULT_NFT_TOKEN_ID);
        assertEq(auction.loanToken, address(loanToken));
        assertEq(auction.loanAmount, DEFAULT_LOAN_AMOUNT);
        assertEq(auction.maxRepayment, DEFAULT_MAX_REPAYMENT);
        assertEq(auction.bidStep, DEFAULT_BID_STEP);
        assertEq(uint(auction.status), uint(NFTLoanProtocol.AuctionStatus.OPEN));
    }

    function test_createAuction_bidStepZero_defaultsToMin() public {
        vm.prank(borrower);
        uint256 auctionId = nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, 0
        );

        NFTLoanProtocol.Auction memory auction = nftProtocol.getAuction(auctionId);
        assertEq(auction.bidStep, 1); // MIN_BID_STEP
    }

    function test_createAuction_invalidNFT_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidNFT.selector);
        nftProtocol.createAuction(
            address(0), 1, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_createAuction_notNFTOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotNFTOwner.selector);
        nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_createAuction_zeroLoanAmount_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidAmount.selector);
        nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            0, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_createAuction_repaymentLessThanLoan_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidRepayment.selector);
        nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_LOAN_AMOUNT - 1,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_createAuction_auctionDurationTooShort_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidDuration.selector);
        nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, 1 minutes, DEFAULT_BID_STEP
        );
    }

    function test_createAuction_loanDurationTooShort_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidDuration.selector);
        nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            1 minutes, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_createAuction_invalidLoanToken_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.InvalidToken.selector);
        nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(0),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }
}

// ============================================================================
// AUCTION CREATION FOR (OPERATOR DELEGATION)
// ============================================================================

contract NFTCreateAuctionForTest is NFTTestSetup {

    function test_createAuctionFor_asOperator() public {
        address operator = makeAddr("operator");
        vm.prank(borrower);
        nftProtocol.setOperatorApproval(operator, true);

        vm.prank(operator);
        uint256 auctionId = nftProtocol.createAuctionFor(
            borrower,
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );

        assertEq(auctionId, 1);
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), address(nftProtocol));
    }

    function test_createAuctionFor_unauthorized_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.createAuctionFor(
            borrower,
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_createAuctionFor_zeroBorrower_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.ZeroAddress.selector);
        nftProtocol.createAuctionFor(
            address(0),
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }
}

// ============================================================================
// CANCEL AUCTION
// ============================================================================

contract NFTCancelAuctionTest is NFTTestSetup {

    function test_cancelAuction_success() public {
        uint256 auctionId = _createNFTAuction();

        vm.prank(borrower);
        nftProtocol.cancelAuction(auctionId);

        NFTLoanProtocol.Auction memory auction = nftProtocol.getAuction(auctionId);
        assertEq(uint(auction.status), uint(NFTLoanProtocol.AuctionStatus.CANCELLED));
        // NFT returned to borrower
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), borrower);
    }

    function test_cancelAuction_notBorrower_reverts() public {
        uint256 auctionId = _createNFTAuction();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.NotBorrower.selector);
        nftProtocol.cancelAuction(auctionId);
    }

    function test_cancelAuction_hasBids_reverts() public {
        uint256 auctionId = _createNFTAuctionWithBid();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.HasBids.selector);
        nftProtocol.cancelAuction(auctionId);
    }

    function test_cancelAuction_notOpen_reverts() public {
        uint256 auctionId = _createNFTAuction();
        vm.prank(borrower);
        nftProtocol.cancelAuction(auctionId);

        // Try to cancel again
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.AuctionNotOpen.selector);
        nftProtocol.cancelAuction(auctionId);
    }

    function test_cancelAuction_notFound_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.AuctionNotFound.selector);
        nftProtocol.cancelAuction(999);
    }
}

// ============================================================================
// BID PLACEMENT
// ============================================================================

contract NFTPlaceBidTest is NFTTestSetup {

    function test_placeBid_firstBid_atMaxRepayment() public {
        uint256 auctionId = _createNFTAuction();

        vm.prank(lender);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);

        NFTLoanProtocol.Auction memory auction = nftProtocol.getAuction(auctionId);
        assertEq(auction.currentBidder, lender);
        assertEq(auction.currentBid, DEFAULT_MAX_REPAYMENT);
        assertEq(auction.bidCount, 1);
    }

    function test_placeBid_secondBid_outbidsPrevious() public {
        uint256 auctionId = _createNFTAuction();

        vm.prank(lender);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);

        // lender2 bids lower (better for borrower)
        uint256 betterBid = DEFAULT_MAX_REPAYMENT - DEFAULT_BID_STEP;
        vm.prank(buyer);
        nftProtocol.placeBid(auctionId, betterBid);

        NFTLoanProtocol.Auction memory auction = nftProtocol.getAuction(auctionId);
        assertEq(auction.currentBidder, buyer);
        assertEq(auction.currentBid, betterBid);
        assertEq(auction.bidCount, 2);

        // Previous bidder has pending refund
        assertEq(nftProtocol.pendingRefunds(lender, address(loanToken)), DEFAULT_LOAN_AMOUNT);
    }

    function test_placeBid_auctionEnded_reverts() public {
        uint256 auctionId = _createNFTAuction();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);

        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.AuctionEnded.selector);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
    }

    function test_placeBid_borrowerCannotBid_reverts() public {
        uint256 auctionId = _createNFTAuction();

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
    }

    function test_placeBid_belowLoanAmount_reverts() public {
        uint256 auctionId = _createNFTAuction();

        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.BidTooLow.selector);
        nftProtocol.placeBid(auctionId, DEFAULT_LOAN_AMOUNT - 1);
    }

    function test_placeBid_aboveMaxRepayment_reverts() public {
        uint256 auctionId = _createNFTAuction();

        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.BidTooHigh.selector);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT + 1);
    }

    function test_placeBid_notEnoughImprovement_reverts() public {
        uint256 auctionId = _createNFTAuction();

        vm.prank(lender);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);

        // Second bid only improves by 1 (need bidStep = 100 USDC)
        vm.prank(buyer);
        vm.expectRevert(NFTLoanProtocol.BidTooHigh.selector);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT - 1);
    }

    function test_placeBid_auctionNotFound_reverts() public {
        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.AuctionNotFound.selector);
        nftProtocol.placeBid(999, DEFAULT_MAX_REPAYMENT);
    }
}

// ============================================================================
// CLAIM REFUND
// ============================================================================

contract NFTClaimRefundTest is NFTTestSetup {

    function test_claimRefund_success() public {
        uint256 auctionId = _createNFTAuction();

        // Lender bids, then buyer outbids
        vm.prank(lender);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);

        vm.prank(buyer);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT - DEFAULT_BID_STEP);

        // Lender claims refund
        uint256 balBefore = loanToken.balanceOf(lender);
        vm.prank(lender);
        nftProtocol.claimRefund(address(loanToken));

        assertEq(loanToken.balanceOf(lender), balBefore + DEFAULT_LOAN_AMOUNT);
        assertEq(nftProtocol.pendingRefunds(lender, address(loanToken)), 0);
    }

    function test_claimRefund_noRefund_reverts() public {
        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.NoRefundAvailable.selector);
        nftProtocol.claimRefund(address(loanToken));
    }
}

// ============================================================================
// FINALIZE AUCTION
// ============================================================================

contract NFTFinalizeAuctionTest is NFTTestSetup {

    function test_finalizeAuction_success() public {
        uint256 auctionId = _createNFTAuctionWithBid();

        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        nftProtocol.finalizeAuction(auctionId);

        // Auction finalized
        NFTLoanProtocol.Auction memory auction = nftProtocol.getAuction(auctionId);
        assertEq(uint(auction.status), uint(NFTLoanProtocol.AuctionStatus.FINALIZED));

        // Loan created
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(auctionId);
        assertEq(loan.borrower, borrower);
        assertEq(loan.lender, lender);
        assertEq(loan.loanAmount, DEFAULT_LOAN_AMOUNT);
        assertEq(loan.repaymentAmount, DEFAULT_MAX_REPAYMENT);
        assertEq(uint(loan.status), uint(NFTLoanProtocol.LoanStatus.ACTIVE));

        // Position NFTs minted
        assertTrue(nftPositionNFT.exists(nftPositionNFT.getBorrowerTokenId(auctionId)));
        assertTrue(nftPositionNFT.exists(nftPositionNFT.getLenderTokenId(auctionId)));

        // Borrower received loan amount
        assertGt(loanToken.balanceOf(borrower), 0);
    }

    function test_finalizeAuction_noBids_cancels() public {
        uint256 auctionId = _createNFTAuction();

        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        nftProtocol.finalizeAuction(auctionId);

        NFTLoanProtocol.Auction memory auction = nftProtocol.getAuction(auctionId);
        assertEq(uint(auction.status), uint(NFTLoanProtocol.AuctionStatus.CANCELLED));
        // NFT returned to borrower
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), borrower);
    }

    function test_finalizeAuction_stillOpen_reverts() public {
        uint256 auctionId = _createNFTAuctionWithBid();

        vm.expectRevert(NFTLoanProtocol.AuctionStillOpen.selector);
        nftProtocol.finalizeAuction(auctionId);
    }

    function test_finalizeAuction_windowExpired_reverts() public {
        uint256 auctionId = _createNFTAuctionWithBid();

        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);
        vm.expectRevert(NFTLoanProtocol.FinalizationWindowExpired.selector);
        nftProtocol.finalizeAuction(auctionId);
    }

    function test_finalizeAuction_notFound_reverts() public {
        vm.expectRevert(NFTLoanProtocol.AuctionNotFound.selector);
        nftProtocol.finalizeAuction(999);
    }

    function test_finalizeAuction_alreadyFinalized_reverts() public {
        uint256 auctionId = _createNFTAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        nftProtocol.finalizeAuction(auctionId);

        vm.expectRevert(NFTLoanProtocol.AuctionNotOpen.selector);
        nftProtocol.finalizeAuction(auctionId);
    }
}

// ============================================================================
// CLAIM EXPIRED AUCTION
// ============================================================================

contract NFTClaimExpiredAuctionTest is NFTTestSetup {

    function _createExpiredAuctionWithBid() internal returns (uint256) {
        uint256 auctionId = _createNFTAuctionWithBid();
        // Warp past auction end + finalization window
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);
        return auctionId;
    }

    function test_claimExpiredAuction_lenderGetsRefund() public {
        uint256 auctionId = _createExpiredAuctionWithBid();

        uint256 lenderBalBefore = loanToken.balanceOf(lender);
        vm.prank(lender);
        nftProtocol.claimExpiredAuction(auctionId);

        assertEq(loanToken.balanceOf(lender), lenderBalBefore + DEFAULT_LOAN_AMOUNT);
        assertTrue(nftProtocol.expiredAuctionLenderClaimed(auctionId));
    }

    function test_claimExpiredAuction_borrowerGetsNFT() public {
        uint256 auctionId = _createExpiredAuctionWithBid();

        vm.prank(borrower);
        nftProtocol.claimExpiredAuction(auctionId);

        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), borrower);
        assertTrue(nftProtocol.expiredAuctionBorrowerClaimed(auctionId));
    }

    function test_claimExpiredAuction_lenderDoubleClaim_reverts() public {
        uint256 auctionId = _createExpiredAuctionWithBid();

        vm.prank(lender);
        nftProtocol.claimExpiredAuction(auctionId);

        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.AlreadyClaimed.selector);
        nftProtocol.claimExpiredAuction(auctionId);
    }

    function test_claimExpiredAuction_borrowerDoubleClaim_reverts() public {
        uint256 auctionId = _createExpiredAuctionWithBid();

        vm.prank(borrower);
        nftProtocol.claimExpiredAuction(auctionId);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.AlreadyClaimed.selector);
        nftProtocol.claimExpiredAuction(auctionId);
    }

    function test_claimExpiredAuction_windowNotExpired_reverts() public {
        uint256 auctionId = _createNFTAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1); // within finalization window

        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.FinalizationWindowActive.selector);
        nftProtocol.claimExpiredAuction(auctionId);
    }

    function test_claimExpiredAuction_noBids_reverts() public {
        uint256 auctionId = _createNFTAuction();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.NoBids.selector);
        nftProtocol.claimExpiredAuction(auctionId);
    }

    function test_claimExpiredAuction_unauthorized_reverts() public {
        uint256 auctionId = _createExpiredAuctionWithBid();

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.claimExpiredAuction(auctionId);
    }
}

// ============================================================================
// LOAN REPAYMENT
// ============================================================================

contract NFTRepayLoanTest is NFTTestSetup {

    function test_repayLoan_success() public {
        uint256 loanId = _createActiveNFTLoan();

        // Fund borrower for repayment
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(nftProtocol), DEFAULT_MAX_REPAYMENT);
        nftProtocol.repayLoan(loanId);
        vm.stopPrank();

        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);
        assertEq(uint(loan.status), uint(NFTLoanProtocol.LoanStatus.REPAID));

        // Borrower got NFT back
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), borrower);

        // Position NFTs burned
        assertFalse(nftPositionNFT.exists(nftPositionNFT.getBorrowerTokenId(loanId)));
        assertFalse(nftPositionNFT.exists(nftPositionNFT.getLenderTokenId(loanId)));
    }

    function test_repayLoan_notBorrowerNFTOwner_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        loanToken.mint(attacker, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(attacker);
        loanToken.approve(address(nftProtocol), DEFAULT_MAX_REPAYMENT);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.repayLoan(loanId);
        vm.stopPrank();
    }

    function test_repayLoan_afterGracePeriod_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);

        vm.warp(loan.maturityTimestamp + GRACE_PERIOD);

        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(nftProtocol), DEFAULT_MAX_REPAYMENT);
        vm.expectRevert(NFTLoanProtocol.GracePeriodExpired.selector);
        nftProtocol.repayLoan(loanId);
        vm.stopPrank();
    }

    function test_repayLoan_notActive_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        // Repay once
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(nftProtocol), DEFAULT_MAX_REPAYMENT);
        nftProtocol.repayLoan(loanId);
        vm.stopPrank();

        // Try again
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.LoanNotActive.selector);
        nftProtocol.repayLoan(loanId);
    }

    function test_repayLoan_notFound_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.LoanNotFound.selector);
        nftProtocol.repayLoan(999);
    }
}

// ============================================================================
// CLAIM COLLATERAL (DEFAULT)
// ============================================================================

contract NFTClaimCollateralTest is NFTTestSetup {

    function test_claimCollateral_success() public {
        uint256 loanId = _createActiveNFTLoan();

        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD + 1);

        vm.prank(lender);
        nftProtocol.claimCollateral(loanId);

        NFTLoanProtocol.Loan memory loanAfter = nftProtocol.getLoan(loanId);
        assertEq(uint(loanAfter.status), uint(NFTLoanProtocol.LoanStatus.DEFAULTED));

        // Lender got the NFT
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), lender);

        // Position NFTs burned
        assertFalse(nftPositionNFT.exists(nftPositionNFT.getBorrowerTokenId(loanId)));
        assertFalse(nftPositionNFT.exists(nftPositionNFT.getLenderTokenId(loanId)));
    }

    function test_claimCollateral_notLenderNFTOwner_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD + 1);

        vm.prank(attacker);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.claimCollateral(loanId);
    }

    function test_claimCollateral_gracePeriodNotEnded_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);
        vm.warp(loan.maturityTimestamp + 1); // Past maturity but in grace

        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.GracePeriodNotEnded.selector);
        nftProtocol.claimCollateral(loanId);
    }

    function test_claimCollateral_loanNotMatured_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.LoanNotMatured.selector);
        nftProtocol.claimCollateral(loanId);
    }

    function test_claimCollateral_notActive_reverts() public {
        uint256 loanId = _createActiveNFTLoan();

        // Repay first
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(nftProtocol), DEFAULT_MAX_REPAYMENT);
        nftProtocol.repayLoan(loanId);
        vm.stopPrank();

        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD + 1);

        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.LoanNotActive.selector);
        nftProtocol.claimCollateral(loanId);
    }
}

// ============================================================================
// OPERATOR APPROVALS
// ============================================================================

contract NFTOperatorApprovalTest is NFTTestSetup {

    function test_setOperatorApproval_success() public {
        address operator = makeAddr("operator");
        vm.prank(borrower);
        nftProtocol.setOperatorApproval(operator, true);

        assertTrue(nftProtocol.operatorApprovals(borrower, operator));
    }

    function test_setOperatorApproval_revoke() public {
        address operator = makeAddr("operator");
        vm.prank(borrower);
        nftProtocol.setOperatorApproval(operator, true);

        vm.prank(borrower);
        nftProtocol.setOperatorApproval(operator, false);

        assertFalse(nftProtocol.operatorApprovals(borrower, operator));
    }

    function test_setOperatorApproval_zeroAddress_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.ZeroAddress.selector);
        nftProtocol.setOperatorApproval(address(0), true);
    }
}

// ============================================================================
// ADMIN FUNCTIONS
// ============================================================================

contract NFTProtocolAdminTest is NFTTestSetup {

    function test_pause_blocksAuctions() public {
        nftProtocol.pause();

        vm.prank(borrower);
        vm.expectRevert(); // EnforcedPause
        nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }

    function test_unpause_restores() public {
        nftProtocol.pause();
        nftProtocol.unpause();

        vm.prank(borrower);
        uint256 id = nftProtocol.createAuction(
            address(mockNFT), DEFAULT_NFT_TOKEN_ID, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        assertEq(id, 1);
    }

    function test_pause_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert();
        nftProtocol.pause();
    }

    function test_onERC721Received_returnsSelector() public {
        bytes4 selector = nftProtocol.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")));
    }
}

// ============================================================================
// VIEW FUNCTIONS
// ============================================================================

contract NFTProtocolViewTest is NFTTestSetup {

    function test_getAuction() public {
        uint256 auctionId = _createNFTAuction();
        NFTLoanProtocol.Auction memory auction = nftProtocol.getAuction(auctionId);
        assertEq(auction.borrower, borrower);
    }

    function test_getLoan() public {
        uint256 loanId = _createActiveNFTLoan();
        NFTLoanProtocol.Loan memory loan = nftProtocol.getLoan(loanId);
        assertEq(loan.borrower, borrower);
        assertEq(loan.lender, lender);
    }

    function test_getPendingRefund() public {
        uint256 auctionId = _createNFTAuction();

        vm.prank(lender);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);

        vm.prank(buyer);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT - DEFAULT_BID_STEP);

        assertEq(nftProtocol.getPendingRefund(lender, address(loanToken)), DEFAULT_LOAN_AMOUNT);
    }

    function test_getBorrowerPositionOwner() public {
        uint256 loanId = _createActiveNFTLoan();
        assertEq(nftProtocol.getBorrowerPositionOwner(loanId), borrower);
    }

    function test_getLenderPositionOwner() public {
        uint256 loanId = _createActiveNFTLoan();
        assertEq(nftProtocol.getLenderPositionOwner(loanId), lender);
    }

    function test_getBorrowerPositionOwner_nonexistent() public {
        assertEq(nftProtocol.getBorrowerPositionOwner(999), address(0));
    }

    function test_getLenderPositionOwner_nonexistent() public {
        assertEq(nftProtocol.getLenderPositionOwner(999), address(0));
    }

    function test_isPositionListed_false() public {
        assertFalse(nftProtocol.isPositionListed(999));
    }

    function test_getMarketplaceOfferCount_zero() public {
        assertEq(nftProtocol.getMarketplaceOfferCount(999), 0);
    }

    function test_loanNonce_increments() public {
        _createNFTAuction(1);
        assertEq(nftProtocol.loanNonce(), 1);

        _createNFTAuction(2);
        assertEq(nftProtocol.loanNonce(), 2);
    }
}
