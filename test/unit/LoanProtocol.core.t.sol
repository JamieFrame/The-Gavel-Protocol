// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/TestSetup.sol";

/**
 * @title LoanProtocolCoreTests
 * @notice Unit tests for LoanProtocol core auction + loan lifecycle
 * @dev Targets: depositCollateral, withdrawCollateral, createAuction, createAuctionFor,
 *      cancelAuction, placeBid, claimRefund, finalizeAuction, claimExpiredAuction,
 *      repayLoan, claimCollateral, setOperatorApproval, pause/unpause, view functions
 *
 * Coverage target: LoanProtocol.sol 37% → 90%+ line coverage
 * Test count: ~55 tests
 */

// ============================================================================
// COLLATERAL MANAGEMENT
// ============================================================================

contract DepositCollateralTest is TestSetup {

    function test_depositCollateral_success() public {
        vm.prank(borrower);
        protocol.depositCollateral(address(collateralToken), 1e8);
        
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), 1e8);
        assertEq(collateralToken.balanceOf(address(protocol)), 1e8);
    }
    
    function test_depositCollateral_multipleDeposits() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), 1e8);
        protocol.depositCollateral(address(collateralToken), 2e8);
        vm.stopPrank();
        
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), 3e8);
    }
    
    function test_depositCollateral_zeroAmount_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InvalidAmount.selector);
        protocol.depositCollateral(address(collateralToken), 0);
    }
    
    function test_depositCollateral_zeroAddress_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InvalidToken.selector);
        protocol.depositCollateral(address(0), 1e8);
    }
    
    function test_depositCollateral_whenPaused_reverts() public {
        protocol.pause();
        vm.prank(borrower);
        vm.expectRevert();
        protocol.depositCollateral(address(collateralToken), 1e8);
    }
}

contract WithdrawCollateralTest is TestSetup {

    function test_withdrawCollateral_success() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), 5e8);
        protocol.withdrawCollateral(address(collateralToken), 3e8);
        vm.stopPrank();
        
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), 2e8);
        assertEq(collateralToken.balanceOf(borrower), 98e8); // 100 - 5 + 3 = 98
    }
    
    function test_withdrawCollateral_exactBalance() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), 5e8);
        protocol.withdrawCollateral(address(collateralToken), 5e8);
        vm.stopPrank();
        
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), 0);
    }
    
    function test_withdrawCollateral_zeroAmount_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), 5e8);
        vm.expectRevert(LoanProtocol.InvalidAmount.selector);
        protocol.withdrawCollateral(address(collateralToken), 0);
        vm.stopPrank();
    }
    
    function test_withdrawCollateral_insufficientBalance_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), 5e8);
        vm.expectRevert(LoanProtocol.InsufficientBalance.selector);
        protocol.withdrawCollateral(address(collateralToken), 6e8);
        vm.stopPrank();
    }
    
    function test_withdrawCollateral_noDeposit_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InsufficientBalance.selector);
        protocol.withdrawCollateral(address(collateralToken), 1);
    }
}

// ============================================================================
// AUCTION CREATION
// ============================================================================

contract CreateAuctionTest is TestSetup {

    function test_createAuction_success() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        assertEq(auctionId, 1);
        assertEq(protocol.loanNonce(), 1);
        
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(auction.borrower, borrower);
        assertEq(auction.collateralToken, address(collateralToken));
        assertEq(auction.collateralAmount, DEFAULT_COLLATERAL);
        assertEq(auction.loanToken, address(loanToken));
        assertEq(auction.loanAmount, DEFAULT_LOAN_AMOUNT);
        assertEq(auction.maxRepayment, DEFAULT_MAX_REPAYMENT);
        assertEq(auction.loanDuration, DEFAULT_LOAN_DURATION);
        assertEq(auction.currentBid, DEFAULT_MAX_REPAYMENT); // starts at max
        assertEq(auction.currentBidder, address(0));
        assertEq(auction.bidCount, 0);
        assertEq(uint(auction.status), uint(LoanProtocol.AuctionStatus.OPEN));
        assertEq(auction.bidStep, DEFAULT_BID_STEP);
    }
    
    function test_createAuction_locksCollateral() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), 5e8);
        protocol.createAuction(
            address(collateralToken), 1e8, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
        
        // 5 deposited, 1 locked in auction = 4 available
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), 4e8);
    }
    
    function test_createAuction_bidStepZeroUsesMinimum() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        uint256 id = protocol.createAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION,
            0  // zero bid step → uses MIN_BID_STEP
        );
        vm.stopPrank();
        
        LoanProtocol.Auction memory auction = protocol.getAuction(id);
        assertEq(auction.bidStep, MIN_BID_STEP);
    }
    
    function test_createAuction_sameToken_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        vm.expectRevert(LoanProtocol.SameToken.selector);
        protocol.createAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(collateralToken), // same token!
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
    
    function test_createAuction_zeroCollateralToken_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.InvalidToken.selector);
        protocol.createAuction(
            address(0), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }
    
    function test_createAuction_zeroLoanToken_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        vm.expectRevert(LoanProtocol.InvalidToken.selector);
        protocol.createAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(0),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
    
    function test_createAuction_zeroAmounts_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        vm.expectRevert(LoanProtocol.InvalidAmount.selector);
        protocol.createAuction(
            address(collateralToken), 0, address(loanToken), // zero collateral
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
    
    function test_createAuction_maxRepaymentBelowLoan_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        vm.expectRevert(LoanProtocol.InvalidRepayment.selector);
        protocol.createAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_LOAN_AMOUNT - 1, // maxRepayment < loanAmount
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
    
    function test_createAuction_auctionDurationTooShort_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        vm.expectRevert(LoanProtocol.InvalidDuration.selector);
        protocol.createAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION,
            MIN_AUCTION_DURATION - 1, // too short
            DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
    
    function test_createAuction_auctionDurationTooLong_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        vm.expectRevert(LoanProtocol.InvalidDuration.selector);
        protocol.createAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION,
            MAX_AUCTION_DURATION + 1, // too long
            DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
    
    function test_createAuction_loanDurationTooShort_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        vm.expectRevert(LoanProtocol.InvalidDuration.selector);
        protocol.createAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            MIN_LOAN_DURATION - 1, // too short
            DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
    
    function test_createAuction_insufficientCollateral_reverts() public {
        // Deposit less than needed
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL - 1);
        vm.expectRevert(LoanProtocol.InsufficientCollateral.selector);
        protocol.createAuction(
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        vm.stopPrank();
    }
}

contract CreateAuctionForTest is TestSetup {

    function test_createAuctionFor_asOperator() public {
        address operator = makeAddr("operator");
        
        // Borrower deposits and approves operator
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        protocol.setOperatorApproval(operator, true);
        vm.stopPrank();
        
        // Operator creates auction on behalf of borrower
        vm.prank(operator);
        uint256 auctionId = protocol.createAuctionFor(
            borrower, borrower,
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
        
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(auction.borrower, borrower);
    }
    
    function test_createAuctionFor_zeroBorrower_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.ZeroAddress.selector);
        protocol.createAuctionFor(
            address(0), borrower,
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }
    
    function test_createAuctionFor_unauthorized_reverts() public {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), DEFAULT_COLLATERAL);
        vm.stopPrank();
        
        // Attacker tries to create auction using borrower's collateral
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.Unauthorized.selector);
        protocol.createAuctionFor(
            borrower, borrower,
            address(collateralToken), DEFAULT_COLLATERAL, address(loanToken),
            DEFAULT_LOAN_AMOUNT, DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION, DEFAULT_AUCTION_DURATION, DEFAULT_BID_STEP
        );
    }
}

// ============================================================================
// AUCTION CANCELLATION
// ============================================================================

contract CancelAuctionTest is TestSetup {

    function test_cancelAuction_success() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(borrower);
        protocol.cancelAuction(auctionId);
        
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(uint(auction.status), uint(LoanProtocol.AuctionStatus.CANCELLED));
        
        // Collateral returned to balance
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), DEFAULT_COLLATERAL);
    }
    
    function test_cancelAuction_notFound_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.AuctionNotFound.selector);
        protocol.cancelAuction(999);
    }
    
    function test_cancelAuction_notBorrower_reverts() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.NotBorrower.selector);
        protocol.cancelAuction(auctionId);
    }
    
    function test_cancelAuction_hasBids_reverts() public {
        uint256 auctionId = _createAuctionWithBid();
        
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.HasBids.selector);
        protocol.cancelAuction(auctionId);
    }
    
    function test_cancelAuction_alreadyCancelled_reverts() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.startPrank(borrower);
        protocol.cancelAuction(auctionId);
        vm.expectRevert(LoanProtocol.AuctionNotOpen.selector);
        protocol.cancelAuction(auctionId);
        vm.stopPrank();
    }
}

// ============================================================================
// BIDDING
// ============================================================================

contract PlaceBidTest is TestSetup {

    function test_placeBid_firstBid_success() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
        
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(auction.currentBidder, lender);
        assertEq(auction.currentBid, DEFAULT_MAX_REPAYMENT);
        assertEq(auction.bidCount, 1);
        
        // Loan amount escrowed from lender
        assertEq(loanToken.balanceOf(address(protocol)), DEFAULT_LOAN_AMOUNT);
    }
    
    function test_placeBid_firstBid_belowMax() public {
        uint256 auctionId = _depositAndCreateAuction();
        uint256 bid = DEFAULT_LOAN_AMOUNT + 1000e6; // loanAmount + 1000 USDC
        
        vm.prank(lender);
        protocol.placeBid(auctionId, bid);
        
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(auction.currentBid, bid);
    }
    
    function test_placeBid_firstBid_atLoanAmount() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_LOAN_AMOUNT); // 0% interest
        
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(auction.currentBid, DEFAULT_LOAN_AMOUNT);
    }
    
    function test_placeBid_secondBid_improvesbyStep() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT); // 55000
        
        // Second bid must be <= 55000 - 100 = 54900
        vm.prank(lender2);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT - DEFAULT_BID_STEP);
        
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(auction.currentBidder, lender2);
        assertEq(auction.currentBid, DEFAULT_MAX_REPAYMENT - DEFAULT_BID_STEP);
        assertEq(auction.bidCount, 2);
    }
    
    function test_placeBid_secondBid_queuesRefund() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
        
        vm.prank(lender2);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT - DEFAULT_BID_STEP);
        
        // Lender1 should have a pending refund
        assertEq(protocol.getPendingRefund(lender, address(loanToken)), DEFAULT_LOAN_AMOUNT);
    }
    
    function test_placeBid_auctionNotFound_reverts() public {
        vm.prank(lender);
        vm.expectRevert(LoanProtocol.AuctionNotFound.selector);
        protocol.placeBid(999, DEFAULT_MAX_REPAYMENT);
    }
    
    function test_placeBid_auctionEnded_reverts() public {
        uint256 auctionId = _depositAndCreateAuction();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION); // exactly at end
        
        vm.prank(lender);
        vm.expectRevert(LoanProtocol.AuctionEnded.selector);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
    }
    
    function test_placeBid_borrowerSelfBid_reverts() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        // Give borrower some loan tokens
        loanToken.mint(borrower, DEFAULT_LOAN_AMOUNT);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), DEFAULT_LOAN_AMOUNT);
        vm.expectRevert(LoanProtocol.Unauthorized.selector);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
        vm.stopPrank();
    }
    
    function test_placeBid_firstBid_aboveMax_reverts() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(lender);
        vm.expectRevert(LoanProtocol.BidTooHigh.selector);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT + 1);
    }
    
    function test_placeBid_belowLoanAmount_reverts() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(lender);
        vm.expectRevert(LoanProtocol.BidTooLow.selector);
        protocol.placeBid(auctionId, DEFAULT_LOAN_AMOUNT - 1);
    }
    
    function test_placeBid_secondBid_insufficientStep_reverts() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
        
        // Try to bid only 1 below current (step is 100e6)
        vm.prank(lender2);
        vm.expectRevert(LoanProtocol.BidTooHigh.selector);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT - 1);
    }
}

// ============================================================================
// REFUND CLAIMING
// ============================================================================

contract ClaimRefundTest is TestSetup {

    function test_claimRefund_success() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
        
        vm.prank(lender2);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT - DEFAULT_BID_STEP);
        
        uint256 balBefore = loanToken.balanceOf(lender);
        
        vm.prank(lender);
        protocol.claimRefund(address(loanToken));
        
        assertEq(loanToken.balanceOf(lender), balBefore + DEFAULT_LOAN_AMOUNT);
        assertEq(protocol.getPendingRefund(lender, address(loanToken)), 0);
    }
    
    function test_claimRefund_noPending_reverts() public {
        vm.prank(lender);
        vm.expectRevert(LoanProtocol.NoRefundAvailable.selector);
        protocol.claimRefund(address(loanToken));
    }
}

// ============================================================================
// AUCTION FINALIZATION
// ============================================================================

contract FinalizeAuctionTest is TestSetup {

    function test_finalizeAuction_success() public {
        uint256 auctionId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        
        uint256 borrowerBalBefore = loanToken.balanceOf(borrower);
        
        protocol.finalizeAuction(auctionId);
        
        // Auction finalized
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(uint(auction.status), uint(LoanProtocol.AuctionStatus.FINALIZED));
        
        // Loan created
        LoanProtocol.Loan memory loan = protocol.getLoan(auctionId);
        assertEq(loan.borrower, borrower);
        assertEq(loan.lender, lender);
        assertEq(loan.loanAmount, DEFAULT_LOAN_AMOUNT);
        assertEq(loan.repaymentAmount, DEFAULT_MAX_REPAYMENT);
        assertEq(uint(loan.status), uint(LoanProtocol.LoanStatus.ACTIVE));
        
        // Borrower received loan funds
        assertEq(loanToken.balanceOf(borrower), borrowerBalBefore + DEFAULT_LOAN_AMOUNT);
        
        // Position NFTs minted
        uint256 borrowerTokenId = positionNFT.getBorrowerTokenId(auctionId);
        uint256 lenderTokenId = positionNFT.getLenderTokenId(auctionId);
        assertEq(positionNFT.ownerOf(borrowerTokenId), borrower);
        assertEq(positionNFT.ownerOf(lenderTokenId), lender);
    }
    
    function test_finalizeAuction_noBids_cancelledAutomatically() public {
        uint256 auctionId = _depositAndCreateAuction();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        
        protocol.finalizeAuction(auctionId);
        
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(uint(auction.status), uint(LoanProtocol.AuctionStatus.CANCELLED));
        
        // Collateral returned
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), DEFAULT_COLLATERAL);
    }
    
    function test_finalizeAuction_stillOpen_reverts() public {
        uint256 auctionId = _createAuctionWithBid();
        // Don't warp — auction still open
        
        vm.expectRevert(LoanProtocol.AuctionStillOpen.selector);
        protocol.finalizeAuction(auctionId);
    }
    
    function test_finalizeAuction_windowExpired_reverts() public {
        uint256 auctionId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);
        
        vm.expectRevert(LoanProtocol.FinalizationWindowExpired.selector);
        protocol.finalizeAuction(auctionId);
    }
    
    function test_finalizeAuction_notFound_reverts() public {
        vm.expectRevert(LoanProtocol.AuctionNotFound.selector);
        protocol.finalizeAuction(999);
    }
    
    function test_finalizeAuction_alreadyFinalized_reverts() public {
        uint256 auctionId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        protocol.finalizeAuction(auctionId);
        
        vm.expectRevert(LoanProtocol.AuctionNotOpen.selector);
        protocol.finalizeAuction(auctionId);
    }
}

// ============================================================================
// EXPIRED AUCTION CLAIMS
// ============================================================================

contract ClaimExpiredAuctionTest is TestSetup {

    function test_claimExpiredAuction_lenderClaims() public {
        uint256 auctionId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);
        
        uint256 lenderBalBefore = loanToken.balanceOf(lender);
        
        vm.prank(lender);
        protocol.claimExpiredAuction(auctionId);
        
        // Lender gets loan amount back
        assertEq(loanToken.balanceOf(lender), lenderBalBefore + DEFAULT_LOAN_AMOUNT);
        
        // Status changed to EXPIRED
        LoanProtocol.Auction memory auction = protocol.getAuction(auctionId);
        assertEq(uint(auction.status), uint(LoanProtocol.AuctionStatus.EXPIRED));
    }
    
    function test_claimExpiredAuction_borrowerClaims() public {
        uint256 auctionId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);
        
        vm.prank(borrower);
        protocol.claimExpiredAuction(auctionId);
        
        // Collateral returned to borrower's balance
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), DEFAULT_COLLATERAL);
    }
    
    function test_claimExpiredAuction_bothClaim() public {
        uint256 auctionId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);
        
        vm.prank(lender);
        protocol.claimExpiredAuction(auctionId);
        
        vm.prank(borrower);
        protocol.claimExpiredAuction(auctionId);
        
        // Both claimed successfully
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), DEFAULT_COLLATERAL);
    }
    
    function test_claimExpiredAuction_doubleClaim_reverts() public {
        uint256 auctionId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);
        
        vm.prank(lender);
        protocol.claimExpiredAuction(auctionId);
        
        vm.prank(lender);
        vm.expectRevert(LoanProtocol.AlreadyClaimed.selector);
        protocol.claimExpiredAuction(auctionId);
    }
    
    function test_claimExpiredAuction_withinFinalizationWindow_reverts() public {
        uint256 auctionId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1); // within window
        
        vm.prank(lender);
        vm.expectRevert(LoanProtocol.FinalizationWindowActive.selector);
        protocol.claimExpiredAuction(auctionId);
    }
    
    function test_claimExpiredAuction_unauthorized_reverts() public {
        uint256 auctionId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.Unauthorized.selector);
        protocol.claimExpiredAuction(auctionId);
    }
    
    function test_claimExpiredAuction_noBids_reverts() public {
        uint256 auctionId = _depositAndCreateAuction();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + FINALIZATION_WINDOW + 1);
        
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.NoBids.selector);
        protocol.claimExpiredAuction(auctionId);
    }
}

// ============================================================================
// LOAN REPAYMENT
// ============================================================================

contract RepayLoanTest is TestSetup {

    function test_repayLoan_success() public {
        uint256 loanId = _createActiveLoan();
        
        // Fund borrower for repayment
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), DEFAULT_MAX_REPAYMENT);
        protocol.repayLoan(loanId);
        vm.stopPrank();
        
        // Loan marked repaid
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        assertEq(uint(loan.status), uint(LoanProtocol.LoanStatus.REPAID));
        
        // Collateral returned to borrower
        assertEq(collateralToken.balanceOf(borrower), 100e8); // got full collateral back
        
        // Lender received repayment
        uint256 lenderBal = loanToken.balanceOf(lender);
        // Lender started with 10M, spent loanAmount on bid, received repaymentAmount back
        assertEq(lenderBal, 10_000_000e6 - DEFAULT_LOAN_AMOUNT + DEFAULT_MAX_REPAYMENT);
    }
    
    function test_repayLoan_duringGracePeriod() public {
        uint256 loanId = _createActiveLoan();
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        
        // Warp to just within grace period (maturity + half of grace)
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD / 2);
        
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), DEFAULT_MAX_REPAYMENT);
        protocol.repayLoan(loanId);
        vm.stopPrank();
        
        LoanProtocol.Loan memory updated = protocol.getLoan(loanId);
        assertEq(uint(updated.status), uint(LoanProtocol.LoanStatus.REPAID));
    }
    
    function test_repayLoan_afterGracePeriod_reverts() public {
        uint256 loanId = _createActiveLoan();
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD); // exactly at end of grace
        
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), DEFAULT_MAX_REPAYMENT);
        vm.expectRevert(LoanProtocol.GracePeriodExpired.selector);
        protocol.repayLoan(loanId);
        vm.stopPrank();
    }
    
    function test_repayLoan_notBorrowerNFTOwner_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        loanToken.mint(attacker, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(attacker);
        loanToken.approve(address(protocol), DEFAULT_MAX_REPAYMENT);
        vm.expectRevert(LoanProtocol.Unauthorized.selector);
        protocol.repayLoan(loanId);
        vm.stopPrank();
    }
    
    function test_repayLoan_notFound_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.LoanNotFound.selector);
        protocol.repayLoan(999);
    }
    
    function test_repayLoan_alreadyRepaid_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), DEFAULT_MAX_REPAYMENT);
        protocol.repayLoan(loanId);
        
        // Try again
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        loanToken.approve(address(protocol), DEFAULT_MAX_REPAYMENT);
        vm.expectRevert(LoanProtocol.LoanNotActive.selector);
        protocol.repayLoan(loanId);
        vm.stopPrank();
    }
}

// ============================================================================
// LOAN DEFAULT / COLLATERAL CLAIM
// ============================================================================

contract ClaimCollateralTest is TestSetup {

    function test_claimCollateral_success() public {
        uint256 loanId = _createActiveLoan();
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD + 1);
        
        uint256 collBefore = collateralToken.balanceOf(lender);
        
        vm.prank(lender);
        protocol.claimCollateral(loanId);
        
        // Loan marked defaulted
        LoanProtocol.Loan memory updated = protocol.getLoan(loanId);
        assertEq(uint(updated.status), uint(LoanProtocol.LoanStatus.DEFAULTED));
        
        // Lender received collateral
        assertEq(collateralToken.balanceOf(lender), collBefore + DEFAULT_COLLATERAL);
        
        // NFTs burned
        uint256 borrowerTokenId = positionNFT.getBorrowerTokenId(loanId);
        vm.expectRevert(); // ownerOf reverts for burned token
        positionNFT.ownerOf(borrowerTokenId);
    }
    
    function test_claimCollateral_beforeMaturity_reverts() public {
        uint256 loanId = _createActiveLoan();
        
        vm.prank(lender);
        vm.expectRevert(LoanProtocol.LoanNotMatured.selector);
        protocol.claimCollateral(loanId);
    }
    
    function test_claimCollateral_duringGracePeriod_reverts() public {
        uint256 loanId = _createActiveLoan();
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD / 2);
        
        vm.prank(lender);
        vm.expectRevert(LoanProtocol.GracePeriodNotEnded.selector);
        protocol.claimCollateral(loanId);
    }
    
    function test_claimCollateral_notLenderNFTOwner_reverts() public {
        uint256 loanId = _createActiveLoan();
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD + 1);
        
        vm.prank(attacker);
        vm.expectRevert(LoanProtocol.Unauthorized.selector);
        protocol.claimCollateral(loanId);
    }
}

// ============================================================================
// OPERATOR APPROVALS
// ============================================================================

contract OperatorApprovalTest is TestSetup {

    function test_setOperatorApproval_approve() public {
        address operator = makeAddr("operator");
        
        vm.prank(borrower);
        protocol.setOperatorApproval(operator, true);
        
        assertTrue(protocol.operatorApprovals(borrower, operator));
    }
    
    function test_setOperatorApproval_revoke() public {
        address operator = makeAddr("operator");
        
        vm.startPrank(borrower);
        protocol.setOperatorApproval(operator, true);
        protocol.setOperatorApproval(operator, false);
        vm.stopPrank();
        
        assertFalse(protocol.operatorApprovals(borrower, operator));
    }
    
    function test_setOperatorApproval_zeroAddress_reverts() public {
        vm.prank(borrower);
        vm.expectRevert(LoanProtocol.ZeroAddress.selector);
        protocol.setOperatorApproval(address(0), true);
    }
}

// ============================================================================
// ADMIN FUNCTIONS
// ============================================================================

contract AdminTest is TestSetup {

    function test_pause_unpause() public {
        protocol.pause();
        
        vm.prank(borrower);
        vm.expectRevert(); // EnforcedPause
        protocol.depositCollateral(address(collateralToken), 1e8);
        
        protocol.unpause();
        
        vm.prank(borrower);
        protocol.depositCollateral(address(collateralToken), 1e8);
        assertEq(protocol.getCollateralBalance(borrower, address(collateralToken)), 1e8);
    }
    
    function test_pause_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        protocol.pause();
    }
}

// ============================================================================
// VIEW FUNCTIONS
// ============================================================================

contract ViewFunctionTest is TestSetup {

    function test_getMinimumBid_firstBid() public {
        uint256 auctionId = _depositAndCreateAuction();
        uint256 minBid = protocol.getMinimumBid(auctionId);
        
        // First bid: minimum is loanAmount
        assertEq(minBid, DEFAULT_LOAN_AMOUNT);
    }
    
    function test_getMaximumBid_firstBid() public {
        uint256 auctionId = _depositAndCreateAuction();
        uint256 maxBid = protocol.getMaximumBid(auctionId);
        
        // First bid: maximum is maxRepayment
        assertEq(maxBid, DEFAULT_MAX_REPAYMENT);
    }
    
    function test_getMaximumBid_subsequentBid() public {
        uint256 auctionId = _depositAndCreateAuction();
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
        
        uint256 maxBid = protocol.getMaximumBid(auctionId);
        // After first bid: max is currentBid - bidStep
        assertEq(maxBid, DEFAULT_MAX_REPAYMENT - DEFAULT_BID_STEP);
    }
    
    function test_getAuctionTimeRemaining() public {
        uint256 auctionId = _depositAndCreateAuction();
        uint256 remaining = protocol.getAuctionTimeRemaining(auctionId);
        
        // Should be approximately DEFAULT_AUCTION_DURATION
        assertGt(remaining, 0);
        assertLe(remaining, DEFAULT_AUCTION_DURATION);
    }
    
    function test_getAuctionTimeRemaining_expired() public {
        uint256 auctionId = _depositAndCreateAuction();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        
        assertEq(protocol.getAuctionTimeRemaining(auctionId), 0);
    }
    
    function test_getLoanTimeRemaining() public {
        uint256 loanId = _createActiveLoan();
        uint256 remaining = protocol.getLoanTimeRemaining(loanId);
        
        assertGt(remaining, 0);
    }
    
    function test_isInGracePeriod() public {
        uint256 loanId = _createActiveLoan();
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        
        // Before maturity — not in grace
        assertFalse(protocol.isInGracePeriod(loanId));
        
        // At maturity — in grace
        vm.warp(loan.maturityTimestamp);
        assertTrue(protocol.isInGracePeriod(loanId));
        
        // Past grace — not in grace
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD + 1);
        assertFalse(protocol.isInGracePeriod(loanId));
    }
    
    function test_canClaimCollateral() public {
        uint256 loanId = _createActiveLoan();
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        
        assertFalse(protocol.canClaimCollateral(loanId));
        
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD + 1);
        assertTrue(protocol.canClaimCollateral(loanId));
    }
    
    function test_canFinalize() public {
        uint256 auctionId = _createAuctionWithBid();
        
        // Before end — cannot finalize
        assertFalse(protocol.canFinalize(auctionId));
        
        // After end, within window — can finalize
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        assertTrue(protocol.canFinalize(auctionId));
        
        // Past window — cannot finalize
        vm.warp(block.timestamp + FINALIZATION_WINDOW + 1);
        assertFalse(protocol.canFinalize(auctionId));
    }
    
    function test_getAuctionBidStep() public {
        uint256 auctionId = _depositAndCreateAuction();
        assertEq(protocol.getAuctionBidStep(auctionId), DEFAULT_BID_STEP);
    }
    
    function test_getBidCount() public {
        uint256 auctionId = _depositAndCreateAuction();
        assertEq(protocol.getBidCount(auctionId), 0);
        
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
        assertEq(protocol.getBidCount(auctionId), 1);
    }
    
    function test_getCurrentBid() public {
        uint256 auctionId = _depositAndCreateAuction();
        
        (address bidder, uint256 amount) = protocol.getCurrentBid(auctionId);
        assertEq(bidder, address(0));
        assertEq(amount, DEFAULT_MAX_REPAYMENT); // starts at max
        
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
        
        (bidder, amount) = protocol.getCurrentBid(auctionId);
        assertEq(bidder, lender);
        assertEq(amount, DEFAULT_MAX_REPAYMENT);
    }
    
    function test_getBorrowerPositionOwner() public {
        uint256 loanId = _createActiveLoan();
        assertEq(protocol.getBorrowerPositionOwner(loanId), borrower);
    }
    
    function test_getLenderPositionOwner() public {
        uint256 loanId = _createActiveLoan();
        assertEq(protocol.getLenderPositionOwner(loanId), lender);
    }
    
    function test_getFinalizationTimeRemaining() public {
        uint256 auctionId = _createAuctionWithBid();
        
        // Before auction end — returns 0 (or full window, depending on impl)
        uint256 remaining = protocol.getFinalizationTimeRemaining(auctionId);
        
        // After auction end
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        remaining = protocol.getFinalizationTimeRemaining(auctionId);
        assertGt(remaining, 0);
    }
}
