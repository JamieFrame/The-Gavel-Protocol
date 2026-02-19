# Integration Guide

How to interact with The Gavel Protocol smart contracts programmatically.

---

## Table of Contents

- [Overview](#overview)
- [Contract ABIs](#contract-abis)
- [Collateral Management](#collateral-management)
- [Auction Lifecycle](#auction-lifecycle)
- [Loan Management](#loan-management)
- [Position Marketplace](#position-marketplace)
- [NFT Lending](#nft-lending)
- [View Functions and Queries](#view-functions-and-queries)
- [Events](#events)
- [Common Patterns](#common-patterns)
- [Error Reference](#error-reference)

---

## Overview

The Gavel Protocol can be accessed in two ways:

1. **Direct protocol access** — Call `LoanProtocol` or `NFTLoanProtocol` directly. Fully permissionless, no whitelisting required.
2. **Via ListingService** — Uses curated token whitelists for safety. Requires the user to grant operator approval to the ListingService contract.

Most integrators should interact with the core protocol directly. The ListingService adds curation but is not required.

### Dependencies

```bash
# ethers.js v6
npm install ethers

# or ethers.js v5
npm install ethers@5
```

### Connection Setup

```javascript
import { ethers } from 'ethers';

// Connect to Arbitrum
const provider = new ethers.JsonRpcProvider('https://arb-sepolia.g.alchemy.com/v2/YOUR_KEY');
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

// Contract instances
const loanProtocol = new ethers.Contract(LOAN_PROTOCOL_ADDRESS, LOAN_PROTOCOL_ABI, signer);
const positionNFT = new ethers.Contract(POSITION_NFT_ADDRESS, POSITION_NFT_ABI, signer);
```

---

## Contract ABIs

### LoanProtocol (Core Functions)

```javascript
const LOAN_PROTOCOL_ABI = [
  // Collateral
  "function depositCollateral(address token, uint256 amount) external",
  "function withdrawCollateral(address token, uint256 amount) external",
  "function collateralBalances(address user, address token) external view returns (uint256)",

  // Auctions
  "function createAuction(address collateralToken, uint256 collateralAmount, address loanToken, uint256 loanAmount, uint256 maxRepayment, uint256 loanDuration, uint256 auctionDuration, uint256 bidStep) external returns (uint256)",
  "function placeBid(uint256 auctionId, uint256 repaymentAmount) external",
  "function finalizeAuction(uint256 auctionId) external",
  "function cancelAuction(uint256 auctionId) external",
  "function claimExpiredAuction(uint256 auctionId) external",
  "function claimRefund(address token) external",

  // Loans
  "function repayLoan(uint256 loanId) external",
  "function claimCollateral(uint256 loanId) external",

  // Marketplace
  "function listPosition(uint256 loanId, string positionType, address paymentToken, uint256 askingPrice) external",
  "function unlistPosition(uint256 loanId) external",
  "function buyPosition(uint256 loanId) external",
  "function makeMarketplaceOffer(uint256 loanId, uint256 offerAmount, uint256 offerDuration) external returns (uint256)",
  "function acceptMarketplaceOffer(uint256 loanId, uint256 offerId) external",
  "function cancelMarketplaceOffer(uint256 loanId, uint256 offerId) external",
  "function rejectMarketplaceOffer(uint256 loanId, uint256 offerId) external",
  "function counterMarketplaceOffer(uint256 loanId, uint256 offerId, uint256 counterAmount, uint256 counterDuration) external",
  "function acceptMarketplaceCounterOffer(uint256 loanId, uint256 offerId) external",
  "function expireMarketplaceOffer(uint256 loanId, uint256 offerId) external",

  // View
  "function getAuction(uint256 auctionId) external view returns (tuple)",
  "function getLoan(uint256 loanId) external view returns (tuple)",
  "function pendingRefunds(address user, address token) external view returns (uint256)",
  "function loanNonce() external view returns (uint256)",

  // Operator
  "function setOperatorApproval(address operator, bool approved) external",
  "function operatorApprovals(address owner, address operator) external view returns (bool)",
];
```

### PositionNFT

```javascript
const POSITION_NFT_ABI = [
  "function getBorrowerTokenId(uint256 loanId) external view returns (uint256)",
  "function getLenderTokenId(uint256 loanId) external view returns (uint256)",
  "function ownerOf(uint256 tokenId) external view returns (address)",
  "function approve(address to, uint256 tokenId) external",
  "function setApprovalForAll(address operator, bool approved) external",
  "function isApprovedForAll(address owner, address operator) external view returns (bool)",
];
```

---

## Collateral Management

Before creating an auction, the borrower must deposit collateral into the protocol.

### Step 1: Approve Token Transfer

```javascript
const wbtc = new ethers.Contract(WBTC_ADDRESS, ERC20_ABI, signer);

// Approve the LoanProtocol to spend your WBTC
const amount = ethers.parseUnits('0.5', 8); // 0.5 WBTC (8 decimals)
await wbtc.approve(LOAN_PROTOCOL_ADDRESS, amount);
```

### Step 2: Deposit

```javascript
await loanProtocol.depositCollateral(WBTC_ADDRESS, amount);
```

### Step 3: Check Balance

```javascript
const balance = await loanProtocol.collateralBalances(signer.address, WBTC_ADDRESS);
console.log('Deposited WBTC:', ethers.formatUnits(balance, 8));
```

### Withdraw Unused Collateral

```javascript
// Only withdraws collateral not locked in active auctions/loans
await loanProtocol.withdrawCollateral(WBTC_ADDRESS, amount);
```

---

## Auction Lifecycle

### Create an Auction (Borrower)

```javascript
const tx = await loanProtocol.createAuction(
  WBTC_ADDRESS,                          // collateralToken
  ethers.parseUnits('0.5', 8),           // collateralAmount (0.5 WBTC)
  USDC_ADDRESS,                          // loanToken
  ethers.parseUnits('10000', 6),         // loanAmount (10,000 USDC)
  ethers.parseUnits('10500', 6),         // maxRepayment (10,500 USDC = 5% cap)
  30 * 86400,                            // loanDuration (30 days in seconds)
  24 * 3600,                             // auctionDuration (24 hours)
  ethers.parseUnits('10', 6)             // bidStep (minimum $10 improvement)
);

const receipt = await tx.wait();
// Parse AuctionCreated event to get auctionId
```

### Parameters Explained

| Parameter | Description | Constraints |
|-----------|-------------|-------------|
| `collateralToken` | ERC-20 token used as collateral | Must have deposited balance |
| `collateralAmount` | Amount of collateral to lock | ≤ your deposited balance |
| `loanToken` | Token you want to borrow (e.g., USDC) | Different from collateral |
| `loanAmount` | Principal amount to borrow | > 0 |
| `maxRepayment` | Maximum you'll repay (caps rate) | > loanAmount |
| `loanDuration` | How long you have to repay (seconds) | Protocol min/max apply |
| `auctionDuration` | How long bidding is open (seconds) | Protocol min/max apply |
| `bidStep` | Minimum bid improvement | 0 = protocol default |

### Place a Bid (Lender)

Lenders bid by offering a lower repayment amount. Their `loanAmount` in USDC is escrowed when they bid.

```javascript
const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);

// Step 1: Approve USDC for the loan amount (not the bid amount)
const loanAmount = ethers.parseUnits('10000', 6);
await usdc.approve(LOAN_PROTOCOL_ADDRESS, loanAmount);

// Step 2: Place bid with desired repayment
const myBid = ethers.parseUnits('10200', 6); // Offering 2% rate
await loanProtocol.placeBid(auctionId, myBid);
```

**Important:** The USDC approval and transfer is for the `loanAmount`, not your bid. If you win, the full loan amount goes to the borrower. If you're outbid, your funds are queued for refund.

### Claim Refund (Outbid Lender)

```javascript
// Check pending refund
const refund = await loanProtocol.pendingRefunds(signer.address, USDC_ADDRESS);

if (refund > 0n) {
  await loanProtocol.claimRefund(USDC_ADDRESS);
}
```

### Finalize Auction

Anyone can finalize an auction after the bidding period ends. This creates the loan.

```javascript
await loanProtocol.finalizeAuction(auctionId);
```

If no bids were placed, finalization cancels the auction and returns collateral.

### Cancel Auction

Borrowers can cancel their auction before any bids are placed.

```javascript
await loanProtocol.cancelAuction(auctionId);
```

### Claim Expired Auction

If an auction isn't finalized within the finalization window (7 days after end), participants can reclaim their assets.

```javascript
await loanProtocol.claimExpiredAuction(auctionId);
```

---

## Loan Management

### Repay Loan (Borrower)

The borrower (or whoever holds the borrower Position NFT) repays to reclaim collateral.

```javascript
// Step 1: Approve repayment amount
const loan = await loanProtocol.getLoan(loanId);
await usdc.approve(LOAN_PROTOCOL_ADDRESS, loan.repaymentAmount);

// Step 2: Repay
await loanProtocol.repayLoan(loanId);
// Collateral is released to borrower, repayment goes to lender
```

### Claim Collateral (Lender — on Default)

If the borrower doesn't repay by maturity + grace period, the lender claims the collateral.

```javascript
await loanProtocol.claimCollateral(loanId);
```

---

## Position Marketplace

When a loan is created, both borrower and lender receive Position NFTs. These are tradeable on the integrated marketplace.

### List a Position

```javascript
await loanProtocol.listPosition(
  loanId,
  'lender',                              // or 'borrower'
  USDC_ADDRESS,                          // payment token
  ethers.parseUnits('9800', 6)           // asking price
);
```

### Buy a Listed Position

```javascript
// Approve payment
await usdc.approve(LOAN_PROTOCOL_ADDRESS, askingPrice);

// Buy
await loanProtocol.buyPosition(loanId);
```

### Make an Offer

```javascript
// Approve offer amount
await usdc.approve(LOAN_PROTOCOL_ADDRESS, offerAmount);

await loanProtocol.makeMarketplaceOffer(
  loanId,
  ethers.parseUnits('9500', 6),          // offer amount
  7 * 86400                              // offer valid for 7 days
);
```

### Offer Negotiation Flow

```
Buyer makes offer → Seller accepts / rejects / counters
                  → If countered → Buyer accepts counter / lets it expire
```

```javascript
// Seller accepts
await loanProtocol.acceptMarketplaceOffer(loanId, offerId);

// Seller counters
await loanProtocol.counterMarketplaceOffer(loanId, offerId, counterAmount, counterDuration);

// Buyer accepts counter
await loanProtocol.acceptMarketplaceCounterOffer(loanId, offerId);

// Anyone can expire a timed-out offer
await loanProtocol.expireMarketplaceOffer(loanId, offerId);
```

---

## NFT Lending

`NFTLoanProtocol` mirrors the ERC-20 protocol but uses NFTs as collateral.

```javascript
// Approve NFT transfer
const nft = new ethers.Contract(NFT_ADDRESS, ERC721_ABI, signer);
await nft.approve(NFT_LOAN_PROTOCOL_ADDRESS, tokenId);

// Create auction
await nftLoanProtocol.createAuction(
  NFT_ADDRESS,                           // collateral NFT contract
  tokenId,                               // NFT token ID
  USDC_ADDRESS,                          // loan token
  ethers.parseUnits('5000', 6),          // loan amount
  ethers.parseUnits('5250', 6),          // max repayment
  30 * 86400,                            // loan duration
  24 * 3600,                             // auction duration
  ethers.parseUnits('5', 6)              // bid step
);
```

Bidding, finalization, repayment, and marketplace functions work identically to the ERC-20 protocol.

---

## View Functions and Queries

### Read Auction State

```javascript
const auction = await loanProtocol.getAuction(auctionId);

console.log({
  borrower: auction.borrower,
  collateralToken: auction.collateralToken,
  collateralAmount: auction.collateralAmount,
  loanToken: auction.loanToken,
  loanAmount: auction.loanAmount,
  maxRepayment: auction.maxRepayment,
  currentBid: auction.currentBid,
  currentBidder: auction.currentBidder,
  bidCount: auction.bidCount,
  auctionEnd: auction.auctionEnd,          // unix timestamp
  loanDuration: auction.loanDuration,      // seconds
  status: auction.status,                  // 0=OPEN, 1=FINALIZED, 2=CANCELLED
});
```

### Read Loan State

```javascript
const loan = await loanProtocol.getLoan(loanId);

console.log({
  borrower: loan.borrower,
  lender: loan.lender,
  collateralToken: loan.collateralToken,
  collateralAmount: loan.collateralAmount,
  loanToken: loan.loanToken,
  loanAmount: loan.loanAmount,
  repaymentAmount: loan.repaymentAmount,
  maturityTimestamp: loan.maturityTimestamp,
  status: loan.status,                     // 0=ACTIVE, 1=REPAID, 2=DEFAULTED
});
```

### Calculate Implied Rate

```javascript
function calcImpliedRate(loanAmount, repaymentAmount, durationSeconds) {
  const principal = parseFloat(loanAmount);
  const repayment = parseFloat(repaymentAmount);
  const interest = repayment - principal;
  const durationYears = durationSeconds / (365.25 * 86400);
  return (interest / principal / durationYears) * 100; // APR %
}
```

### Enumerate All Auctions and Loans

```javascript
const totalLoans = await loanProtocol.loanNonce();

for (let i = 1; i <= totalLoans; i++) {
  const auction = await loanProtocol.getAuction(i);
  const loan = await loanProtocol.getLoan(i);
  // Process...
}
```

---

## Events

### Core Events

```solidity
event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);
event AuctionCreated(uint256 indexed auctionId, address indexed borrower, ...);
event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 repaymentAmount, uint256 bidCount);
event AuctionFinalized(uint256 indexed auctionId, address indexed lender, uint256 repaymentAmount);
event AuctionCancelled(uint256 indexed auctionId);
event AuctionExpiredNoBids(uint256 indexed auctionId);
event LoanRepaid(uint256 indexed loanId);
event CollateralClaimed(uint256 indexed loanId);
event RefundQueued(address indexed user, address indexed token, uint256 amount);
event RefundClaimed(address indexed user, address indexed token, uint256 amount);
```

### Marketplace Events

```solidity
event PositionListed(uint256 indexed loanId, address indexed seller, string positionType, uint256 askingPrice);
event PositionUnlisted(uint256 indexed loanId);
event PositionSold(uint256 indexed loanId, address indexed buyer, uint256 price);
event MarketplaceOfferMade(uint256 indexed loanId, uint256 offerId, address indexed buyer, uint256 amount);
event MarketplaceOfferAccepted(uint256 indexed loanId, uint256 offerId);
event MarketplaceOfferRejected(uint256 indexed loanId, uint256 offerId);
event MarketplaceOfferCancelled(uint256 indexed loanId, uint256 offerId);
event MarketplaceOfferExpired(uint256 indexed loanId, uint256 offerId);
event MarketplaceCounterOffer(uint256 indexed loanId, uint256 offerId, uint256 counterAmount);
event MarketplaceCounterAccepted(uint256 indexed loanId, uint256 offerId);
```

---

## Common Patterns

### Listening for Auctions (Indexer / Bot)

```javascript
loanProtocol.on('AuctionCreated', (auctionId, borrower, ...args) => {
  console.log(`New auction #${auctionId} by ${borrower}`);
  // Evaluate and bid if attractive
});

loanProtocol.on('BidPlaced', (auctionId, bidder, repaymentAmount, bidCount) => {
  console.log(`Auction #${auctionId}: new bid at ${repaymentAmount} (${bidCount} bids)`);
});
```

### Multi-Step Flows with Error Handling

```javascript
async function createFullAuction(params) {
  try {
    // 1. Approve collateral
    const approveTx = await token.approve(LOAN_PROTOCOL_ADDRESS, params.collateralAmount);
    await approveTx.wait();

    // 2. Deposit
    const depositTx = await loanProtocol.depositCollateral(params.collateralToken, params.collateralAmount);
    await depositTx.wait();

    // 3. Create auction
    const auctionTx = await loanProtocol.createAuction(
      params.collateralToken, params.collateralAmount,
      params.loanToken, params.loanAmount,
      params.maxRepayment, params.loanDuration,
      params.auctionDuration, params.bidStep
    );
    const receipt = await auctionTx.wait();

    // 4. Parse auction ID from event
    const event = receipt.logs.find(l => l.fragment?.name === 'AuctionCreated');
    return event.args.auctionId;
  } catch (err) {
    console.error('Auction creation failed:', err.reason || err.message);
    throw err;
  }
}
```

---

## Error Reference

| Error | Cause |
|-------|-------|
| `ZeroAddress` | Passed address(0) where a valid address is required |
| `ZeroAmount` | Passed 0 for an amount that must be positive |
| `InvalidToken` | Token address not whitelisted (ListingService only) |
| `InsufficientBalance` | Trying to use more collateral than deposited |
| `AuctionNotOpen` | Auction has already been finalized or cancelled |
| `AuctionNotEnded` | Trying to finalize before auction end time |
| `AuctionEnded` | Trying to bid after auction end time |
| `SelfBidNotAllowed` | Borrower cannot bid on their own auction |
| `BidTooHigh` | Bid must be lower than current best bid by at least bidStep |
| `BidBelowLoanAmount` | Bid cannot be less than the loan principal (no negative interest) |
| `UnauthorizedOperator` | Caller is not the owner or an approved operator |
| `LoanNotActive` | Loan has already been repaid or defaulted |
| `LoanNotExpired` | Cannot claim collateral before maturity + grace period |
| `NotPositionOwner` | Caller doesn't hold the required Position NFT |
| `MaxOffersReached` | Listing has reached 50 offers (MAX_OFFERS_PER_LISTING) |
| `NoRefundAvailable` | No pending refund for this user/token pair |
