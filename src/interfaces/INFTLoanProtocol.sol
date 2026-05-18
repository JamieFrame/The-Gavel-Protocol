// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title INFTLoanProtocol
 * @notice Interface for NFTLoanProtocol contract
 * @dev Updated with Security Fix functions (M-1, H-1, H-3, L-4)
 */
interface INFTLoanProtocol {
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
        /// @dev ERC-721 NFT contract locked as collateral
        address collateralNFT;
        /// @dev Token ID of the NFT locked as collateral
        uint256 collateralTokenId;
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
        /// @dev Minimum improvement required for each new bid
        uint256 bidStep;
    }

    struct Loan {
        /// @dev Address that created the auction and deposited collateral
        address borrower;
        /// @dev ERC-721 NFT contract locked as collateral
        address collateralNFT;
        /// @dev Token ID of the NFT locked as collateral
        uint256 collateralTokenId;
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
    // OPERATOR APPROVAL (Security Fix M-1)
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
    // CORE FUNCTIONS
    // ============================================================================

    function createAuction(
        // ERC-721 NFT contract address for collateral
        address collateralNFT,
        // Token ID of the NFT to lock
        uint256 collateralTokenId,
        // ERC-20 token to borrow (e.g., USDC)
        address loanToken,
        // Principal amount requested
        uint256 loanAmount,
        // Maximum repayment borrower will accept
        uint256 maxRepayment,
        // Loan term in seconds after finalization
        uint256 loanDuration,
        // Bidding period duration in seconds
        uint256 auctionDuration,
        // Minimum bid improvement required per step
        uint256 bidStep
    // Returns the new auction ID
    ) external returns (uint256 auctionId);

    function createAuctionFor(
        // Address of the borrower creating the auction
        address borrower,
        // ERC-721 NFT contract address for collateral
        address collateralNFT,
        // Token ID of the NFT to lock
        uint256 collateralTokenId,
        // ERC-20 token to borrow (e.g., USDC)
        address loanToken,
        // Principal amount requested
        uint256 loanAmount,
        // Maximum repayment borrower will accept
        uint256 maxRepayment,
        // Loan term in seconds after finalization
        uint256 loanDuration,
        // Bidding period duration in seconds
        uint256 auctionDuration,
        // Minimum bid improvement required per step
        uint256 bidStep
    // Returns the new auction ID
    ) external returns (uint256 auctionId);

    function cancelAuction(uint256 auctionId) external;

    function placeBid(uint256 auctionId, uint256 repaymentAmount) external;

    function claimRefund(address token) external;

    function finalizeAuction(uint256 auctionId) external;

    function claimExpiredAuction(uint256 auctionId) external;

    function repayLoan(uint256 loanId) external;

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
        // Loan identifier
        uint256 loanId,
        // "borrower" or "lender" position type
        string calldata positionType,
        // ERC-20 token accepted as payment
        address paymentToken,
        // Listed sale price in paymentToken units
        uint256 askingPrice,
        // Minimum offer floor (0 = no floor)
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
        // Loan identifier
        uint256 loanId,
        // Position owner listing for sale
        address seller,
        // "borrower" or "lender" position type
        string calldata positionType,
        // ERC-20 token accepted as payment
        address paymentToken,
        // Listed sale price in paymentToken units
        uint256 askingPrice,
        // Minimum offer floor (0 = no floor)
        uint256 minOfferAmount
    ) external;

    function unlistPosition(uint256 tokenId) external;

    function cleanStaleListing(uint256 tokenId) external;

    function updateListingPrice(uint256 tokenId, uint256 newPrice) external;

    function makeMarketplaceOffer(
        // Loan identifier
        uint256 loanId, 
        // Purchase offer price
        uint256 offerAmount, 
        // Offer validity period in seconds
        uint256 offerDuration,
        // Expected payment token (MEV/front-run protection, mirrors buyPosition)
        address expectedPaymentToken
    // Returns the new offer ID
    ) external returns (uint256 offerId);

    function cancelMarketplaceOffer(uint256 tokenId, uint256 offerId) external;

    function rejectMarketplaceOffer(uint256 tokenId, uint256 offerId) external;

    function expireMarketplaceOffer(uint256 tokenId, uint256 offerId) external;

    function counterMarketplaceOffer(
        // Loan identifier
        uint256 loanId, 
        // Offer identifier within this listing
        uint256 offerId, 
        // Seller counter-proposed price
        uint256 counterAmount,
        // Counter-offer validity period in seconds
        uint256 counterDuration
    ) external;

    function acceptMarketplaceOffer(uint256 tokenId, uint256 offerId) external;

    function acceptMarketplaceCounterOffer(uint256 tokenId, uint256 offerId) external;

    /// @notice Buy a listed position at the asking price with slippage protection
    /// @param tokenId Token ID of the position to purchase
    /// @param maxPrice Maximum price the buyer is willing to pay
    /// @param expectedPaymentToken Expected payment token address
    function buyPosition(uint256 tokenId, uint256 maxPrice, address expectedPaymentToken) external;

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    function getAuction(uint256 auctionId) external view returns (Auction memory);

    function getLoan(uint256 loanId) external view returns (Loan memory);

    function getMarketplaceListing(uint256 tokenId) external view returns (MarketplaceListing memory);

    function getMarketplaceOffer(uint256 tokenId, uint256 offerId) external view returns (MarketplaceOffer memory);

    function getMarketplaceOfferCount(uint256 tokenId) external view returns (uint256);

    function isPositionListed(uint256 tokenId) external view returns (bool);

    function getBorrowerPositionOwner(uint256 loanId) external view returns (address);

    function getLenderPositionOwner(uint256 loanId) external view returns (address);

    function getPendingRefund(address user, address token) external view returns (uint256);

    function loanNonce() external view returns (uint256);

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
}
