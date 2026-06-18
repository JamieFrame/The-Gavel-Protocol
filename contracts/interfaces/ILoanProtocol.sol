// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILoanProtocol
 * @notice Interface for the LoanProtocol contract (with integrated marketplace)
 * @dev Updated with Security Fix functions (C-1, H-1, H-3, L-4)
 */
interface ILoanProtocol {
    // ============================================================================
    // ENUMS
    // ============================================================================

    enum AuctionStatus { 
        // Auction is accepting bids
        OPEN,
        // Auction completed â€” loan created from winning bid
        FINALIZED,
        // Auction cancelled by borrower (no bids)
        CANCELLED,
        // Auction not finalized within window â€” assets reclaimable
        EXPIRED
    }

    enum LoanStatus { 
        // Loan is active â€” borrower owes repayment
        ACTIVE,
        // Borrower repaid in full â€” collateral returned
        REPAID,
        // Borrower defaulted â€” collateral seized by lender
        DEFAULTED
    }

    enum MarketplaceOfferStatus {
        // Offer awaiting seller response
        PENDING,
        // Offer accepted â€” position transferred
        ACCEPTED,
        // Offer rejected by seller
        REJECTED,
        // Seller proposed a counter amount
        COUNTERED,
        // Auction cancelled by borrower (no bids)
        CANCELLED,
        // Offer validity period elapsed
        EXPIRED
    }

    // ============================================================================
    // STRUCTS
    // ============================================================================

    struct Auction {
        /// @dev Address that created the auction and deposited collateral
        address borrower;
        /// @dev ERC-20 token locked as collateral
        address collateralToken;
        /// @dev Amount of collateral token locked
        uint256 collateralAmount;
        /// @dev ERC-20 token requested as loan (e.g., USDC)
        address loanToken;
        /// @dev Principal amount requested by borrower
        uint256 loanAmount;
        /// @dev Maximum repayment borrower will accept (interest cap)
        uint256 maxRepayment;
        /// @dev Loan term in seconds after finalization
        uint256 loanDuration;
        /// @dev Unix timestamp when bidding closes
        uint256 auctionEnd;
        /// @dev Address of the current winning bidder (lender)
        address currentBidder;
        /// @dev Current lowest repayment bid (reverse Dutch auction)
        uint256 currentBid;
        /// @dev Total number of bids placed on this auction
        uint256 bidCount;
        /// @dev Current auction lifecycle state
        AuctionStatus status;
        uint256 bidStep;  // Minimum bid improvement required
    }

    struct Loan {
        /// @dev Address that created the auction and deposited collateral
        address borrower;
        /// @dev ERC-20 token locked as collateral
        address collateralToken;
        /// @dev Amount of collateral token locked
        uint256 collateralAmount;
        /// @dev ERC-20 token requested as loan (e.g., USDC)
        address loanToken;
        /// @dev Principal amount requested by borrower
        uint256 loanAmount;
        /// @dev Total amount due at maturity (principal + interest)
        uint256 repaymentAmount;
        /// @dev Unix timestamp when loan must be repaid
        uint256 maturityTimestamp;
        /// @dev Address that won the auction and funded the loan
        address lender;
        /// @dev Current loan lifecycle state
        LoanStatus status;
    }

    struct MarketplaceListing {
        /// @dev Address listing the position for sale
        address seller;
        /// @dev Associated loan ID (derived from position token ID)
        uint256 loanId;
        /// @dev "borrower" or "lender" â€” which side is being sold
        string positionType;
        /// @dev ERC-20 token used for the offer
        address paymentToken;
        /// @dev Listed sale price in paymentToken units
        uint256 askingPrice;
        /// @dev Minimum offer amount in paymentToken units (spam floor; 0 = no floor)
        uint256 minOfferAmount;
        /// @dev Unix timestamp when position was listed
        uint256 listedAt;
        /// @dev Whether listing is currently active
        bool active;
    }

    struct MarketplaceOffer {
        /// @dev Address making the offer to purchase
        address buyer;
        /// @dev Offered purchase price
        uint256 amount;
        /// @dev Funds held in escrow pending acceptance
        uint256 escrowedAmount;
        /// @dev Current offer lifecycle state
        MarketplaceOfferStatus status;
        /// @dev Seller counter-proposed price (if countered)
        uint256 counterAmount;
        /// @dev Unix timestamp when offer was made
        uint256 createdAt;
        /// @dev Unix timestamp when offer expires
        uint256 expiresAt;
        /// @dev ERC-20 token used for the offer
        address paymentToken;
    }

    // ============================================================================
    // OPERATOR APPROVAL (Security Fix C-1)
    // ============================================================================

    /// @notice Approve or revoke an operator to act on behalf of msg.sender
    /// @param operator The address to approve/revoke
    /// @param approved True to approve, false to revoke
    function setOperatorApproval(address operator, bool approved) external;

    /// @notice Check if an operator is approved for an owner
    /// @param owner The owner address
    /// @param operator The operator address
    /// @return True if operator is approved for owner
    function operatorApprovals(address owner, address operator) external view returns (bool);

    // ============================================================================
    // CORE PROTOCOL FUNCTIONS
    // ============================================================================

    function depositCollateral(address token, uint256 amount) external;
    /// @notice Withdraw unused ERC-20 collateral from the protocol
    function withdrawCollateral(address token, uint256 amount) external;
    
    function createAuction(
        address collateralToken,
        uint256 collateralAmount,
        address loanToken,
        uint256 loanAmount,
        uint256 maxRepayment,
        uint256 loanDuration,
        uint256 auctionDuration,
        uint256 bidStep
    ) external returns (uint256 auctionId);
    
    function createAuctionFor(
        address borrower,
        address collateralFrom,
        address collateralToken,
        uint256 collateralAmount,
        address loanToken,
        uint256 loanAmount,
        uint256 maxRepayment,
        uint256 loanDuration,
        uint256 auctionDuration,
        uint256 bidStep
    ) external returns (uint256 auctionId);
    
    function cancelAuction(uint256 auctionId) external;
    /// @notice Place a bid on an auction â€” lower repayment beats current bid
    function placeBid(uint256 auctionId, uint256 repaymentAmount) external;
    /// @notice Claim refund for outbid lender deposits (pull-based DoS prevention)
    function claimRefund(address token) external;
    /// @notice Finalize an ended auction â€” creates loan and disburses funds
    function finalizeAuction(uint256 auctionId) external;
    /// @notice Claim an expired, unfinalized auction â€” returns assets to participants
    function claimExpiredAuction(uint256 auctionId) external;
    
    function repayLoan(uint256 loanId) external;
    /// @notice Claim collateral from a defaulted loan (lender only, after grace period)
    function claimCollateral(uint256 loanId) external;

    /// @notice Permissionlessly mark a loan as defaulted past grace period
    /// @dev Emits LoanDefaultMarked; does not transfer collateral. Additive to claimCollateral.
    function markDefault(uint256 loanId) external;

    // ============================================================================
    // MARKETPLACE FUNCTIONS
    // ============================================================================

    /// @notice List a position for sale (direct call by position owner)
    /// @param minOfferAmount Minimum offer the seller will accept (0 = no floor)
    function listPosition(
        uint256 loanId,
        string calldata positionType,
        address paymentToken,
        uint256 askingPrice,
        uint256 minOfferAmount
    ) external;

    /// @notice List a position for sale on behalf of the seller (Security Fix H-1)
    /// @dev Requires msg.sender to be an approved operator for seller
    /// @param loanId The loan ID
    /// @param seller The address of the position owner
    /// @param positionType "borrower" or "lender"
    /// @param paymentToken Token to receive payment in
    /// @param askingPrice Price in paymentToken units
    /// @param minOfferAmount Minimum offer the seller will accept (0 = no floor)
    function listPositionFor(
        uint256 loanId,
        address seller,
        string calldata positionType,
        address paymentToken,
        uint256 askingPrice,
        uint256 minOfferAmount
    ) external;
    
    function unlistPosition(uint256 tokenId) external;

    function cleanStaleListing(uint256 tokenId) external;
    /// @notice Update the asking price of a listed position
    function updateListingPrice(uint256 tokenId, uint256 newPrice) external;
    
    function makeMarketplaceOffer(uint256 tokenId, uint256 offerAmount, uint256 offerDuration, address expectedPaymentToken) external returns (uint256 offerId);
    /// @notice Cancel a pending marketplace offer and reclaim escrowed funds
    function cancelMarketplaceOffer(uint256 tokenId, uint256 offerId) external;
    /// @notice Reject a marketplace offer (seller returns escrowed funds)
    function rejectMarketplaceOffer(uint256 tokenId, uint256 offerId) external;
    /// @notice Mark an expired offer and release escrowed funds
    function expireMarketplaceOffer(uint256 tokenId, uint256 offerId) external;
    /// @notice Counter a marketplace offer with a different price
    function counterMarketplaceOffer(uint256 tokenId, uint256 offerId, uint256 counterAmount, uint256 counterDuration) external;
    /// @notice Accept a marketplace offer â€” transfers position and releases escrow
    function acceptMarketplaceOffer(uint256 tokenId, uint256 offerId) external;
    /// @notice Accept a counter-offer â€” buyer pays counter amount for position
    function acceptMarketplaceCounterOffer(uint256 tokenId, uint256 offerId) external;
    /// @notice Buy a listed position at the asking price with slippage protection
    /// @param tokenId Token ID of the position to purchase
    /// @param maxPrice Maximum price the buyer is willing to pay
    /// @param expectedPaymentToken Expected payment token address
    function buyPosition(uint256 tokenId, uint256 maxPrice, address expectedPaymentToken) external;

    // ============================================================================
    // VIEW FUNCTIONS - CORE
    // ============================================================================

    function getAuction(uint256 auctionId) external view returns (Auction memory);
    /// @notice Get full loan data by ID
    function getLoan(uint256 loanId) external view returns (Loan memory);
    /// @notice Get the current winning bid (bidder address and amount)
    function getCurrentBid(uint256 auctionId) external view returns (address bidder, uint256 amount);
    /// @notice Get the number of bids placed on an auction
    function getBidCount(uint256 auctionId) external view returns (uint256);
    /// @notice Get a user's deposited collateral balance for a token
    function getCollateralBalance(address user, address token) external view returns (uint256);
    /// @notice Get a user's claimable refund for a token (outbid deposits)
    function getPendingRefund(address user, address token) external view returns (uint256);
    /// @notice Get the current owner of the borrower position NFT
    function getBorrowerPositionOwner(uint256 loanId) external view returns (address);
    /// @notice Get the current owner of the lender position NFT
    function getLenderPositionOwner(uint256 loanId) external view returns (address);
    /// @notice Get seconds remaining in an auction's bidding period
    function getAuctionTimeRemaining(uint256 auctionId) external view returns (uint256);
    /// @notice Get seconds remaining until loan maturity
    function getLoanTimeRemaining(uint256 loanId) external view returns (uint256);
    /// @notice Check if a matured loan is within its grace period
    function isInGracePeriod(uint256 loanId) external view returns (bool);
    /// @notice Check if lender can claim collateral (post-grace default)
    function canClaimCollateral(uint256 loanId) external view returns (bool);
    /// @notice Get seconds remaining in the finalization window
    function getFinalizationTimeRemaining(uint256 auctionId) external view returns (uint256);
    /// @notice Check if an auction can be finalized
    function canFinalize(uint256 auctionId) external view returns (bool);
    /// @notice Check if a claimant can claim an expired auction's assets
    function canClaimExpiredAuction(uint256 auctionId, address claimant) external view returns (bool canClaim, bool isLender);
    /// @notice Get the minimum valid bid for an auction (current bid - step)
    function getMinimumBid(uint256 auctionId) external view returns (uint256);
    /// @notice Get the maximum valid bid (maxRepayment or current bid)
    function getMaximumBid(uint256 auctionId) external view returns (uint256);
    /// @notice Get the bid step size for an auction
    function getAuctionBidStep(uint256 auctionId) external view returns (uint256);

    // ============================================================================
    // VIEW FUNCTIONS - MARKETPLACE
    // ============================================================================

    function getMarketplaceListing(uint256 tokenId) external view returns (MarketplaceListing memory);
    /// @notice Get a specific marketplace offer by loan and offer ID
    function getMarketplaceOffer(uint256 tokenId, uint256 offerId) external view returns (MarketplaceOffer memory);
    /// @notice Get the number of offers on a listed position
    function getMarketplaceOfferCount(uint256 tokenId) external view returns (uint256);
    /// @notice Check if a position is currently listed on the marketplace
    function isPositionListed(uint256 tokenId) external view returns (bool);

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    function MIN_AUCTION_DURATION() external view returns (uint256);
    /// @notice Maximum allowed auction bidding period
    function MAX_AUCTION_DURATION() external view returns (uint256);
    /// @notice Minimum allowed loan term
    function MIN_LOAN_DURATION() external view returns (uint256);
    /// @notice Maximum allowed loan term (~30 years for full yield curve)
    function MAX_LOAN_DURATION() external view returns (uint256);
    /// @notice Post-maturity window before lender can seize collateral
    function GRACE_PERIOD() external view returns (uint256);
    /// @notice Window after auction ends to finalize before expiry
    function FINALIZATION_WINDOW() external view returns (uint256);
    /// @notice Absolute minimum bid improvement per step
    function MIN_BID_STEP() external view returns (uint256);
    /// @notice Minimum validity period for marketplace offers
    function MIN_OFFER_DURATION() external view returns (uint256);
    /// @notice Safety buffer before maturity â€” freezes marketplace operations
    function MATURITY_BUFFER() external view returns (uint256);
    /// @notice Maximum concurrent offers per listing (gas-safety cap)
    function MAX_OFFERS_PER_LISTING() external view returns (uint256);  // Security Fix H-3
    /// @notice Get the current loan/auction nonce (next available ID)
    function loanNonce() external view returns (uint256);
}
