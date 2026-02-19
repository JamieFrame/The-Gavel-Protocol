# The Gavel Protocol - Comprehensive Security Audit
## LoanProtocol.sol & NFTLoanProtocol.sol

**Date:** February 6, 2026  
**Scope:** Complete function-by-function security analysis  
**Perspective:** All known smart contract attack vectors applied systematically

---

## Table of Contents
1. [Attack Vector Taxonomy](#1-attack-vector-taxonomy)
2. [LoanProtocol.sol Function-by-Function Analysis](#2-loanprotocolsol-function-by-function-analysis)
3. [NFTLoanProtocol.sol Function-by-Function Analysis](#3-nftloanprotocolsol-function-by-function-analysis)
4. [Cross-Contract Attack Vectors](#4-cross-contract-attack-vectors)
5. [Economic Attack Vectors](#5-economic-attack-vectors)
6. [Summary of Findings](#6-summary-of-findings)
7. [Recommendations](#7-recommendations)

---

## 1. Attack Vector Taxonomy

### 1.1 Reentrancy Attacks
**Description:** Attacker contract calls back into the vulnerable contract during an external call before state updates complete.

| Sub-Type | Risk Level | Protocol Relevance |
|----------|------------|-------------------|
| Single-function reentrancy | HIGH | Token transfers in multiple functions |
| Cross-function reentrancy | HIGH | Shared state across functions |
| Read-only reentrancy | MEDIUM | View functions used in decisions |
| Cross-contract reentrancy | HIGH | PositionNFT callbacks |

### 1.2 Access Control Vulnerabilities
**Description:** Functions callable by unauthorized parties, missing permission checks.

| Sub-Type | Risk Level | Protocol Relevance |
|----------|------------|-------------------|
| Missing access control | CRITICAL | `createAuctionFor` pattern |
| Incorrect modifier usage | HIGH | `onlyOwner` vs `onlyLoanProtocol` |
| Privilege escalation | HIGH | Operator approval pattern |
| Default visibility | MEDIUM | Internal vs external |

### 1.3 Integer Overflow/Underflow
**Description:** Arithmetic operations that wrap around causing unexpected values.

| Sub-Type | Risk Level | Protocol Relevance |
|----------|------------|-------------------|
| Multiplication overflow | MEDIUM | Fee calculations |
| Division truncation | MEDIUM | Percentage calculations |
| Subtraction underflow | HIGH | Balance deductions |
| Addition overflow | MEDIUM | Refund accumulation |

**Note:** Solidity 0.8.x has built-in overflow protection. ✅ MITIGATED

### 1.4 Flash Loan Attacks
**Description:** Borrow assets atomically to manipulate prices, votes, or protocol state.

| Sub-Type | Risk Level | Protocol Relevance |
|----------|------------|-------------------|
| Price manipulation | N/A | Oracle-free design |
| Governance manipulation | N/A | No governance |
| Collateral manipulation | LOW | Escrow mechanism |
| Bid manipulation | LOW | Funds locked on bid |

### 1.5 Front-Running / MEV
**Description:** Attackers observe pending transactions and execute their own first.

| Sub-Type | Risk Level | Protocol Relevance |
|----------|------------|-------------------|
| Transaction ordering | MEDIUM | Auction bids |
| Sandwich attacks | LOW | No swaps involved |
| Time-bandit attacks | LOW | No oracle dependencies |
| Backrunning | LOW | Minimal extractable value |

### 1.6 Denial of Service (DoS)
**Description:** Making the contract unusable for legitimate users.

| Sub-Type | Risk Level | Protocol Relevance |
|----------|------------|-------------------|
| Gas griefing | MEDIUM | Loop-based refunds |
| Block gas limit | LOW | Bounded loops |
| External call failure | MEDIUM | Token transfers |
| State bloat | LOW | Offer limits (50 max) |

### 1.7 Token-Related Vulnerabilities
**Description:** Malicious or non-standard token behavior.

| Sub-Type | Risk Level | Protocol Relevance |
|----------|------------|-------------------|
| Fee-on-transfer tokens | HIGH | Documented unsupported |
| Rebasing tokens | HIGH | Documented unsupported |
| ERC-777 hooks | MEDIUM | Potential reentrancy |
| Pausable tokens | MEDIUM | Transfer failures |
| Blocklist tokens (USDC) | MEDIUM | Address blocking |

### 1.8 Logic Errors
**Description:** Incorrect business logic implementation.

| Sub-Type | Risk Level | Protocol Relevance |
|----------|------------|-------------------|
| Incorrect state transitions | HIGH | Auction/loan status |
| Off-by-one errors | MEDIUM | Time boundaries |
| Incorrect comparisons | HIGH | Bid validation |
| Missing edge cases | MEDIUM | Zero amounts, durations |

### 1.9 Oracle Manipulation
**Description:** Manipulating price feeds to exploit protocol.

**Status:** ✅ N/A - Protocol is oracle-free by design

### 1.10 Upgradeability Risks
**Description:** Vulnerabilities related to proxy patterns.

| Sub-Type | Risk Level | Protocol Relevance |
|----------|------------|-------------------|
| Storage collision | HIGH | Upgradeable contracts |
| Initialization front-running | MEDIUM | `initialize()` function |
| Malicious upgrade | HIGH | Owner-controlled |
| Missing upgrade gap | MEDIUM | Future storage slots |

---

## 2. LoanProtocol.sol Function-by-Function Analysis

### 2.1 Initialization & Admin Functions

#### `initialize(address _positionNFT)`
**Lines:** 436-444

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Front-running initialization | ⚠️ RISK | Deploy + initialize should be atomic via factory |
| Zero address | ✅ MITIGATED | `if (_positionNFT == address(0)) revert ZeroAddress()` |
| Re-initialization | ✅ MITIGATED | `initializer` modifier |

**Recommendation:** Use a deployment factory that atomically deploys and initializes.

---

#### `pause()` / `unpause()`
**Lines:** 451-458

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Unauthorized pause | ✅ MITIGATED | `onlyOwner` modifier |
| Permanent lockout | ⚠️ RISK | Single owner can pause indefinitely |

**Recommendation:** Consider timelock or multi-sig for pause functionality.

---

#### `setOperatorApproval(address operator, bool approved)`
**Lines:** 470-474

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Zero address approval | ✅ MITIGATED | `if (operator == address(0)) revert ZeroAddress()` |
| Self-approval | ✅ SAFE | Approving self has no effect |
| Unlimited operator power | ⚠️ DESIGN | Operator can create auctions with user's collateral |

**Recommendation:** Consider time-limited or scope-limited approvals.

---

### 2.2 Collateral Management

#### `depositCollateral(address token, uint256 amount)`
**Lines:** 483-498

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Zero amount | ✅ MITIGATED | `if (amount == 0) revert InvalidAmount()` |
| Zero token | ✅ MITIGATED | `validToken(token)` modifier |
| Fee-on-transfer tokens | ⚠️ DOCUMENTED | Contract receives less than expected; documented unsupported |
| CEI pattern | ✅ FOLLOWED | Effects before interactions |

```solidity
// SECURE PATTERN:
collateralBalances[msg.sender][token] += amount;  // Effect first
IERC20(token).safeTransferFrom(msg.sender, address(this), amount);  // Interaction last
```

---

#### `withdrawCollateral(address token, uint256 amount)`
**Lines:** 503-520

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Insufficient balance | ✅ MITIGATED | Balance check before deduction |
| Zero amount | ✅ MITIGATED | `if (amount == 0) revert InvalidAmount()` |
| CEI pattern | ✅ FOLLOWED | Balance deducted before transfer |
| Unauthorized withdrawal | ✅ MITIGATED | Only `msg.sender` can withdraw their own balance |

```solidity
// SECURE: Only modifies msg.sender's balance
collateralBalances[msg.sender][token] -= amount;
```

---

### 2.3 Auction Creation

#### `createAuction(...)`
**Lines:** 536-563

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Invalid tokens | ✅ MITIGATED | Zero address and same-token checks |
| Invalid amounts | ✅ MITIGATED | Zero amount checks |
| Invalid durations | ✅ MITIGATED | Min/max duration bounds |
| Insufficient collateral | ✅ MITIGATED | Balance check in `_createAuction` |
| Self-borrowing attack | ⚠️ N/A | Borrower blocked from self-bidding in `placeBid` |

---

#### `createAuctionFor(...)`
**Lines:** 578-616

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| **Unauthorized collateral use** | ✅ MITIGATED | Operator approval required |
| Zero addresses | ✅ MITIGATED | Explicit zero checks |
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |

**Critical Check (Line 600):**
```solidity
if (msg.sender != collateralFrom && !operatorApprovals[collateralFrom][msg.sender]) {
    revert Unauthorized();
}
```

This prevents the attack where an attacker could steal another user's collateral.

---

#### `_createAuction(...)`
**Lines:** 618-689 (Internal)

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Token validation | ✅ MITIGATED | Zero and same-token checks |
| Amount validation | ✅ MITIGATED | Zero checks |
| Duration bounds | ✅ MITIGATED | Min/max enforced |
| Collateral locking | ✅ SECURE | Balance deducted atomically |
| ID collision | ✅ MITIGATED | Monotonic `loanNonce` increment |

---

#### `cancelAuction(uint256 auctionId)`
**Lines:** 693-712

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Non-existent auction | ✅ MITIGATED | `if (auction.borrower == address(0)) revert AuctionNotFound()` |
| Wrong status | ✅ MITIGATED | Status check |
| Unauthorized cancellation | ✅ MITIGATED | `msg.sender != auction.borrower` check |
| Cancellation with bids | ✅ MITIGATED | `if (auction.bidCount > 0) revert HasBids()` |
| Reentrancy | ✅ MITIGATED | `nonReentrant` + no external calls (balance update only) |

**Collateral Return:**
```solidity
// Returns to collateralFrom, not borrower - CORRECT!
collateralBalances[auction.collateralFrom][auction.collateralToken] += auction.collateralAmount;
```

---

### 2.4 Auction Bidding

#### `placeBid(uint256 auctionId, uint256 repaymentAmount)`
**Lines:** 722-780

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| **Reentrancy** | ✅ MITIGATED | `nonReentrant` modifier |
| Non-existent auction | ✅ MITIGATED | Borrower address check |
| Wrong status | ✅ MITIGATED | Status check |
| Auction ended | ✅ MITIGATED | Timestamp check |
| **Self-bidding** | ✅ MITIGATED | `if (msg.sender == auction.borrower) revert Unauthorized()` |
| Bid too low | ✅ MITIGATED | Must be ≥ loanAmount |
| Bid too high | ✅ MITIGATED | First bid ≤ maxRepayment, subsequent must improve by bidStep |
| **Front-running** | ⚠️ INHERENT | MEV bots can front-run bids - inherent to public auctions |
| CEI pattern | ✅ FOLLOWED | State updated before token transfer |
| **Previous bidder DoS** | ✅ MITIGATED | Pull-based refunds (pendingRefunds mapping) |

**Secure Refund Pattern (Lines 770-774):**
```solidity
// Pull-based refund - prevents DoS from malicious bidder contracts
if (hasPreviousBid) {
    pendingRefunds[previousBidder][loanToken] += loanAmount;
    emit RefundAvailable(previousBidder, loanToken, loanAmount, auctionId);
}
```

---

#### `claimRefund(address token)`
**Lines:** 784-799

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Zero refund | ✅ MITIGATED | `if (amount == 0) revert NoRefundAvailable()` |
| Double claim | ✅ MITIGATED | Balance set to 0 before transfer |
| CEI pattern | ✅ FOLLOWED | `pendingRefunds[msg.sender][token] = 0` before transfer |

---

### 2.5 Auction Finalization

#### `finalizeAuction(uint256 auctionId)`
**Lines:** 807-877

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Non-existent auction | ✅ MITIGATED | Borrower address check |
| Wrong status | ✅ MITIGATED | Status check |
| Auction still open | ✅ MITIGATED | `block.timestamp < auction.auctionEnd` check |
| Finalization window expired | ✅ MITIGATED | Window check |
| No bids edge case | ✅ HANDLED | Returns collateral, emits AuctionExpiredNoBids |
| CEI pattern | ✅ FOLLOWED | Status updated before external calls |
| NFT minting callback | ⚠️ TRUST | PositionNFT trusted to not reenter |

**State Update Before External Calls:**
```solidity
auction.status = AuctionStatus.FINALIZED;  // Effect
// ... create loan ...
positionNFT.mintBorrowerPosition(auctionId, borrower);  // Interaction
IERC20(loanToken).safeTransfer(borrower, loanAmount);  // Interaction
```

---

#### `claimExpiredAuction(uint256 auctionId)`
**Lines:** 881-928

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Wrong status | ✅ MITIGATED | Allows OPEN and EXPIRED status |
| Premature claim | ✅ MITIGATED | Finalization window check |
| No bids | ✅ MITIGATED | `if (auction.bidCount == 0) revert NoBids()` |
| Unauthorized claim | ✅ MITIGATED | Must be borrower or lender |
| Double claim | ✅ MITIGATED | Separate tracking for lender/borrower claims |

**Bug Fix Applied (Lines 889-892):**
```solidity
// BUG FIX: Allow both OPEN and EXPIRED status so both parties can claim
if (auction.status != AuctionStatus.OPEN && auction.status != AuctionStatus.EXPIRED) {
    revert AuctionNotOpen();
}
```

---

### 2.6 Loan Resolution

#### `repayLoan(uint256 loanId)`
**Lines:** 936-975

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Non-existent loan | ✅ MITIGATED | Borrower address check |
| Wrong status | ✅ MITIGATED | Status check |
| **Repayment after grace period** | ✅ MITIGATED | `if (block.timestamp >= loan.maturityTimestamp + GRACE_PERIOD) revert` |
| Unauthorized repayment | ✅ MITIGATED | NFT ownership check |
| **Lender NFT transfer race** | ✅ MITIGATED | Gets lender from current NFT owner, not stored address |
| CEI pattern | ✅ FOLLOWED | Status updated before transfers |
| NFT burn callback | ⚠️ TRUST | PositionNFT trusted |

**Secure Lender Resolution:**
```solidity
// Gets CURRENT lender, not stored - handles marketplace transfers correctly
uint256 lenderTokenId = positionNFT.getLenderTokenId(loanId);
address lender = positionNFT.ownerOf(lenderTokenId);
```

---

#### `claimCollateral(uint256 loanId)`
**Lines:** 979-1010

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Premature claim | ✅ MITIGATED | Maturity + grace period check |
| Unauthorized claim | ✅ MITIGATED | NFT ownership check |
| Double claim | ✅ MITIGATED | Status set to DEFAULTED |
| CEI pattern | ✅ FOLLOWED | Status updated before transfer |

---

### 2.7 Marketplace Functions

#### `listPosition(...)`
**Lines:** 1065-1072

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Already listed | ✅ MITIGATED | Check in `_listPosition` |
| Zero price | ✅ MITIGATED | Check in `_listPosition` |
| Invalid position type | ✅ MITIGATED | Check in `_listPosition` |
| Not owner | ✅ MITIGATED | NFT ownership check |
| Inactive loan | ✅ MITIGATED | Status check |
| **Marketplace frozen** | ✅ MITIGATED | Maturity buffer check |

---

#### `listPositionFor(...)`
**Lines:** 1081-1093

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| **Unauthorized listing** | ✅ MITIGATED | Operator approval check |
| Zero seller | ✅ MITIGATED | `if (seller == address(0)) revert ZeroAddress()` |

---

#### `_listPosition(...)`
**Lines:** 1096-1139

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Already listed | ✅ MITIGATED | `if (marketplaceListings[loanId].active) revert AlreadyListed()` |
| Zero price | ✅ MITIGATED | `if (askingPrice == 0) revert InvalidPrice()` |
| Zero payment token | ✅ MITIGATED | `if (paymentToken == address(0)) revert ZeroAddress()` |
| Invalid position type | ✅ MITIGATED | String comparison validation |
| Not position owner | ✅ MITIGATED | NFT ownership verification |
| Inactive loan | ✅ MITIGATED | Status check |
| **Maturity buffer** | ✅ MITIGATED | Cannot list within MATURITY_BUFFER of expiry |

---

#### `unlistPosition(uint256 loanId)`
**Lines:** 1144-1155

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Not listed | ✅ MITIGATED | Active check |
| Not seller | ✅ MITIGATED | `if (listing.seller != msg.sender) revert NotSeller()` |
| Offer refund failure | ⚠️ RISK | Loop-based refund could be costly |

---

#### `updateListingPrice(uint256 loanId, uint256 newPrice)`
**Lines:** 1160-1168

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Not listed | ✅ MITIGATED | Active check |
| Not seller | ✅ MITIGATED | Seller check |
| Zero price | ✅ MITIGATED | `if (newPrice == 0) revert InvalidPrice()` |

---

#### `makeMarketplaceOffer(...)`
**Lines:** 1179-1225

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Not listed | ✅ MITIGATED | Active check |
| Zero offer | ✅ MITIGATED | `if (offerAmount == 0) revert InvalidOffer()` |
| Self-buy | ✅ MITIGATED | `if (msg.sender == listing.seller) revert CannotBuyOwnPosition()` |
| Short duration | ✅ MITIGATED | `MIN_OFFER_DURATION` check |
| **Duration past maturity** | ✅ MITIGATED | `if (requestedExpiry > maxExpiry) revert OfferDurationTooLong()` |
| **Marketplace frozen** | ✅ MITIGATED | Buffer period check |
| **Gas DoS via offers** | ✅ MITIGATED | `if (marketplaceOfferNonce[loanId] >= MAX_OFFERS_PER_LISTING) revert TooManyOffers()` |
| CEI pattern | ✅ FOLLOWED | Offer created before escrow transfer |

---

#### `cancelMarketplaceOffer(uint256 loanId, uint256 offerId)`
**Lines:** 1230-1257

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Not buyer | ✅ MITIGATED | `if (offer.buyer != msg.sender) revert NotBuyer()` |
| Wrong status | ✅ MITIGATED | PENDING or COUNTERED only |
| CEI pattern | ✅ FOLLOWED | Status updated before refund |
| Push-based refund | ✅ SAFE | Buyer is msg.sender, so push is acceptable |

---

#### `rejectMarketplaceOffer(uint256 loanId, uint256 offerId)`
**Lines:** 1262-1290

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Not seller | ✅ MITIGATED | Seller check |
| Wrong status | ✅ MITIGATED | PENDING only |
| **Malicious buyer DoS** | ✅ MITIGATED | Pull-based refund (pendingRefunds) |

---

#### `expireMarketplaceOffer(uint256 loanId, uint256 offerId)`
**Lines:** 1296-1325

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Premature expiry | ✅ MITIGATED | `if (block.timestamp < offer.expiresAt) revert OfferNotExpired()` |
| Wrong status | ✅ MITIGATED | PENDING or COUNTERED only |
| Pull-based refund | ✅ SECURE | Prevents malicious buyer blocking |

---

#### `counterMarketplaceOffer(...)`
**Lines:** 1333-1370

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Not seller | ✅ MITIGATED | Seller check |
| Wrong status | ✅ MITIGATED | PENDING only |
| Zero counter | ✅ MITIGATED | `if (counterAmount == 0) revert InvalidOffer()` |
| Short duration | ✅ MITIGATED | MIN_OFFER_DURATION check |
| Duration past maturity | ✅ MITIGATED | Buffer check |
| Marketplace frozen | ✅ MITIGATED | Buffer period check |

---

#### `acceptMarketplaceOffer(uint256 loanId, uint256 offerId)`
**Lines:** 1376-1423

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Not seller | ✅ MITIGATED | Seller check |
| Wrong status | ✅ MITIGATED | PENDING only |
| **Expired offer** | ✅ MITIGATED | `if (block.timestamp >= offer.expiresAt) revert OfferExpired()` |
| **Stale listing** | ✅ MITIGATED | Loan status re-verified |
| **Marketplace frozen** | ✅ MITIGATED | Buffer period check |
| CEI pattern | ✅ FOLLOWED | Status updated before transfers |
| Other offer refunds | ⚠️ GAS | Loop in `_refundOtherOffers` bounded by MAX_OFFERS_PER_LISTING |

---

#### `acceptMarketplaceCounterOffer(uint256 loanId, uint256 offerId)`
**Lines:** 1429-1489

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Not buyer | ✅ MITIGATED | Buyer check |
| Wrong status | ✅ MITIGATED | COUNTERED only |
| Expired counter | ✅ MITIGATED | Expiry check |
| Stale listing | ✅ MITIGATED | Loan status check |
| Marketplace frozen | ✅ MITIGATED | Buffer check |
| **Insufficient funds for counter** | ✅ HANDLED | `safeTransferFrom` will revert if insufficient |
| **Overpayment** | ✅ HANDLED | Excess refunded to buyer (push safe - buyer is msg.sender) |

---

#### `buyPosition(uint256 loanId)`
**Lines:** 1498-1532

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Reentrancy | ✅ MITIGATED | `nonReentrant` modifier |
| Not listed | ✅ MITIGATED | Active check |
| Self-buy | ✅ MITIGATED | `if (msg.sender == listing.seller) revert CannotBuyOwnPosition()` |
| Stale listing | ✅ MITIGATED | Loan status check |
| Marketplace frozen | ✅ MITIGATED | Buffer check |
| CEI pattern | ✅ FOLLOWED | Active set to false before transfers |

---

### 2.8 Internal Helper Functions

#### `_executePositionTransfer(...)`
**Lines:** 1539-1552

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Invalid position type | ✅ MITIGATED | Boolean comparison |
| Unauthorized transfer | ✅ MITIGATED | Relies on caller validation |

---

#### `_transferBorrowerPosition(...)` / `_transferLenderPosition(...)`
**Lines:** 1018-1054

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| Non-existent loan | ✅ MITIGATED | Borrower address check |
| Inactive loan | ✅ MITIGATED | Status check |
| Zero recipient | ✅ MITIGATED | `if (to == address(0)) revert ZeroAddress()` |
| Not owner | ✅ MITIGATED | NFT ownership verification |
| **ERC721 approval bypass** | ✅ SECURE | Uses `protocolTransfer` not standard transfer |

---

#### `_refundOtherOffers(uint256 loanId, uint256 acceptedOfferId)`
**Lines:** 1565-1593

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| **Gas DoS** | ✅ MITIGATED | Loop bounded by MAX_OFFERS_PER_LISTING (50) |
| Pull-based refunds | ✅ SECURE | Uses pendingRefunds mapping |
| Double refund | ✅ MITIGATED | Status set to CANCELLED, escrow zeroed |

---

## 3. NFTLoanProtocol.sol Function-by-Function Analysis

The NFTLoanProtocol follows the same patterns as LoanProtocol with these key differences:

### 3.1 NFT-Specific Considerations

#### `createAuction(...)`
**Lines:** 491-567

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| **Malicious NFT** | ⚠️ DOCUMENTED | Protocol accepts ANY NFT - documented risk |
| **NFT transfer callback reentrancy** | ✅ MITIGATED | Uses `safeTransferFrom`, `nonReentrant` |
| Not NFT owner | ✅ MITIGATED | Ownership verified before transfer |
| CEI pattern | ✅ FOLLOWED | State set before NFT transfer |

---

#### `createAuctionFor(...)`
**Lines:** 573-660

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| **Unauthorized NFT use** | ✅ MITIGATED | Operator approval check |
| Not owner | ✅ MITIGATED | `if (IERC721(collateralNFT).ownerOf(collateralTokenId) != borrower)` |

---

#### `onERC721Received(...)`
**Lines:** 438-445

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| **Arbitrary NFT deposits** | ⚠️ ACCEPTS | Returns selector for any NFT - by design |

**Note:** This is necessary for `safeTransferFrom` to work but means anyone can send any NFT to the contract. These NFTs would be stuck but not cause protocol issues.

---

### 3.2 Loan Resolution with NFT Collateral

#### `repayLoan(uint256 loanId)`

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| NFT transfer failure | ✅ HANDLED | `safeTransferFrom` reverts on failure |
| **NFT received by contract during loan** | N/A | NFT held by protocol, not contract issue |

---

#### `claimCollateral(uint256 loanId)`

| Attack Vector | Status | Analysis |
|---------------|--------|----------|
| **NFT to non-receiver contract** | ✅ HANDLED | Uses `safeTransferFrom` |
| **NFT frozen/paused** | ⚠️ EXTERNAL | External NFT contract could prevent transfer |

---

### 3.3 Expired Auction Claims

#### `claimExpiredAuction(uint256 auctionId)`

The NFTLoanProtocol has the same dual-claim pattern with separate tracking for lender (funds) and borrower (NFT collateral).

---

## 4. Cross-Contract Attack Vectors

### 4.1 PositionNFT Trust Assumptions

| Function | Trust | Risk |
|----------|-------|------|
| `mintBorrowerPosition` | Called by protocol | ✅ Low - onlyLoanProtocol |
| `mintLenderPosition` | Called by protocol | ✅ Low - onlyLoanProtocol |
| `burn` | Called by protocol | ✅ Low - onlyLoanProtocol |
| `protocolTransfer` | Called by protocol | ✅ Low - onlyLoanProtocol |
| `_safeMint` callback | Goes to user | ⚠️ Medium - could reenter |

**Recommendation:** While reentrancy guard exists, verify no cross-function reentrancy paths exist.

---

### 4.2 ListingService Trust Assumptions

| Function | Trust | Risk |
|----------|-------|------|
| `createAuctionFor` | Requires operator approval | ✅ Low |
| `listPositionFor` | Requires operator approval | ✅ Low |
| Fee collection | From user wallet | ✅ Low - user approves |

---

### 4.3 Token Contract Interactions

| Token Type | Risk | Status |
|------------|------|--------|
| Standard ERC20 | Low | ✅ Uses SafeERC20 |
| Fee-on-transfer | High | ⚠️ Documented unsupported |
| Rebasing | High | ⚠️ Documented unsupported |
| ERC-777 | Medium | ⚠️ Could trigger hooks - reentrancy guard protects |
| Pausable (USDC) | Medium | ⚠️ Could fail transfers |
| Blocklist (USDC) | Medium | ⚠️ Could prevent operations |

---

## 5. Economic Attack Vectors

### 5.1 Auction Manipulation

| Attack | Feasibility | Mitigation |
|--------|-------------|------------|
| **Griefing bids** | Low | Bids are escrowed |
| **Bid sniping** | Medium | Inherent to fixed-end auctions |
| **Self-bid manipulation** | Impossible | Self-bid blocked |
| **Sybil bidding** | Low value | Multiple addresses = multiple escrows |

### 5.2 Marketplace Manipulation

| Attack | Feasibility | Mitigation |
|--------|-------------|------------|
| **Offer spam** | Blocked | MAX_OFFERS_PER_LISTING (50) |
| **Stale listing exploitation** | Blocked | Loan status checked on acceptance |
| **Grace period arbitrage** | Blocked | Maturity buffer + frozen marketplace |

### 5.3 Flash Loan Considerations

| Attack | Feasibility | Reason |
|--------|-------------|--------|
| Flash bid | Impossible | Funds must remain escrowed |
| Flash collateral | Impossible | Collateral locked in auction |
| Flash position buy | Low value | No price oracle to manipulate |

---

## 6. Summary of Findings

### 6.1 Critical Findings
**NONE IDENTIFIED** ✅

The previous critical finding (C-1 in adversarial review: `createAuctionFor` without access control) has been **FIXED** with operator approval pattern.

### 6.2 High Severity Findings

| ID | Description | Status |
|----|-------------|--------|
| H-1 | Single owner control | ⚠️ DESIGN - Recommend multi-sig |
| H-2 | Initialization front-running | ⚠️ RISK - Use factory pattern |

### 6.3 Medium Severity Findings

| ID | Description | Status |
|----|-------------|--------|
| M-1 | Front-running bids | ⚠️ INHERENT to public auctions |
| M-2 | Unsupported token types | ✅ DOCUMENTED |
| M-3 | Blocklist token risks | ⚠️ EXTERNAL dependency |
| M-4 | NFT callback complexity | ✅ MITIGATED with reentrancy guard |

### 6.4 Low Severity Findings

| ID | Description | Status |
|----|-------------|--------|
| L-1 | Gas cost for bulk refunds | ✅ BOUNDED by MAX_OFFERS |
| L-2 | Stuck arbitrary NFTs | ⚠️ COSMETIC - no fund risk |
| L-3 | Missing upgrade storage gaps | ⚠️ VERIFY in OpenZeppelin bases |

### 6.5 Informational

| ID | Description |
|----|-------------|
| I-1 | Consider time-limited operator approvals |
| I-2 | Consider partial repayment feature |
| I-3 | Consider auction extension on late bids |

---

## 7. Recommendations

### 7.1 Pre-Mainnet Critical

1. **Use deployment factory** for atomic deploy + initialize
2. **Implement multi-sig ownership** before mainnet
3. **Add timelock** for admin functions (minimum 24-48 hours)

### 7.2 Security Best Practices

1. **Formal verification** of core auction and loan state machines
2. **Fuzz testing** with Foundry for edge cases
3. **Invariant testing** for protocol guarantees:
   - Total collateral == sum of locked + balances
   - All active loans have valid position NFTs
   - No double-spending of escrow

### 7.3 Operational Security

1. Monitor `OperatorApprovalSet` events
2. Monitor pause/unpause events
3. Set up alerts for large value transactions
4. Prepare emergency response playbook

### 7.4 Future Considerations

1. Consider adding emergency withdrawal with timelock
2. Consider upgradeability sunset clause
3. Consider bug bounty program

---

## Appendix A: Attack Vector Coverage Matrix

| Attack Vector | LoanProtocol | NFTLoanProtocol |
|---------------|--------------|-----------------|
| Reentrancy - Single | ✅ Protected | ✅ Protected |
| Reentrancy - Cross-function | ✅ CEI Pattern | ✅ CEI Pattern |
| Access Control | ✅ Proper checks | ✅ Proper checks |
| Integer Overflow | ✅ Solidity 0.8+ | ✅ Solidity 0.8+ |
| Flash Loans | ✅ Escrow model | ✅ Escrow model |
| Front-running | ⚠️ Inherent | ⚠️ Inherent |
| DoS - Gas | ✅ Bounded loops | ✅ Bounded loops |
| DoS - Revert | ✅ Pull pattern | ✅ Pull pattern |
| Oracle Manipulation | ✅ N/A (Oracle-free) | ✅ N/A (Oracle-free) |
| Malicious Tokens | ⚠️ Documented | ⚠️ Documented |
| Upgradeability | ⚠️ Owner-controlled | ⚠️ Owner-controlled |

---

**Document Version:** 1.0  
**Analysis Completed:** February 6, 2026  
**Contracts Analyzed:**
- LoanProtocol.sol (1806 lines)
- NFTLoanProtocol.sol (1530 lines)
- PositionNFT.sol (333 lines)
- ListingService.sol (468 lines)

**Overall Assessment:** ✅ **READY FOR EXTERNAL AUDIT**

The contracts demonstrate strong security practices including consistent use of reentrancy guards, CEI pattern, proper access controls, and bounded loops. The previous critical vulnerability has been fixed. Recommend proceeding with formal audit while implementing multi-sig and timelock before mainnet deployment.
