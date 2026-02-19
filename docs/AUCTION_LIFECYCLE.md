# Auction Lifecycle

A complete walkthrough of how auctions, loans, and positions work in The Gavel Protocol.

---

## Overview

Every loan in The Gavel Protocol begins as a reverse auction. The borrower defines what they need. Lenders compete to offer the best terms. The market discovers the rate.

```
Deposit → Create Auction → Bidding → Finalize → Active Loan → Repay or Default
                                                      ↓
                                              Position NFTs minted
                                                      ↓
                                              Tradeable on Marketplace
```

---

## 1. Collateral Deposit

Before creating an auction, the borrower must deposit collateral into the protocol.

```
Borrower wallet ──[approve]──> ERC-20 token
Borrower wallet ──[depositCollateral]──> LoanProtocol
```

Collateral sits in the borrower's internal balance within the protocol. It can be withdrawn at any time unless it's locked in an active auction or loan.

**Key detail:** Collateral is deposited separately from auction creation. This means a borrower can deposit once and create multiple auctions from the same pool.

---

## 2. Auction Creation

The borrower creates an auction specifying:

| Parameter | What it means |
|-----------|---------------|
| Collateral token + amount | What they're putting up (e.g., 0.5 WBTC) |
| Loan token + amount | What they want to borrow (e.g., 10,000 USDC) |
| Max repayment | The most they'll pay back — this is the starting bid |
| Loan duration | How long they have to repay (e.g., 30 days) |
| Auction duration | How long bidding stays open (e.g., 24 hours) |
| Bid step | Minimum improvement per bid (e.g., $10 USDC) |

The collateral is **locked** when the auction is created. It cannot be withdrawn until the auction resolves.

### Auction States

```
OPEN ──→ FINALIZED (bids exist, auction ended, someone finalized)
  │
  ├──→ CANCELLED (borrower cancelled before any bids)
  │
  └──→ CANCELLED (auction ended with no bids, then finalized)
```

---

## 3. Bidding

Lenders bid by offering a **repayment amount** lower than the current best bid. Lower repayment = lower interest rate for the borrower = more competitive for the lender.

### Bidding Rules

- **First bid** must be ≤ `maxRepayment` (the borrower's ceiling)
- **Subsequent bids** must be < `currentBid - bidStep`
- **All bids** must be ≥ `loanAmount` (no negative interest — the lender must at least get their principal back)
- **Self-bidding blocked** — the borrower cannot bid on their own auction
- **Funds escrowed** — the lender's `loanAmount` in USDC is transferred to the contract when they bid

### When a Lender is Outbid

Their escrowed funds are queued for refund via a **pull-based** mechanism:

```
Bidder A bids → 10,000 USDC escrowed
Bidder B outbids → Bidder A's 10,000 USDC added to pendingRefunds
Bidder A calls claimRefund() → 10,000 USDC returned
```

Pull-based refunds prevent denial-of-service attacks where a malicious contract could block push refunds.

### Example Bidding Sequence

```
Auction: Borrow 10,000 USDC against 0.5 WBTC, 30 days, max repayment 10,500

Bid #1: Alice offers 10,400 USDC repayment → 16.2% APR implied
Bid #2: Bob offers   10,300 USDC repayment → 12.2% APR implied
Bid #3: Alice offers 10,200 USDC repayment →  8.1% APR implied
Bid #4: Carol offers 10,120 USDC repayment →  4.9% APR implied

Auction ends → Carol wins at 4.9% APR
```

---

## 4. Finalization

After the auction duration expires, anyone can call `finalizeAuction()`. This is permissionless — the borrower, lender, or any third party can trigger it.

### If Bids Exist

1. Auction status set to `FINALIZED`
2. Loan created with the winning bid's terms
3. Escrowed USDC sent to the borrower
4. Collateral remains locked until loan resolution
5. **Position NFTs minted:**
   - Borrower Position NFT → to the borrower
   - Lender Position NFT → to the winning bidder

### If No Bids

1. Auction status set to `CANCELLED`
2. Collateral returned to borrower's internal balance
3. `AuctionExpiredNoBids` event emitted

### Finalization Window

There is a 7-day window after the auction ends to finalize. If nobody finalizes within this window, participants can call `claimExpiredAuction()` to recover their assets.

---

## 5. Active Loan

Once finalized, the loan is active. The key terms are locked:

| Term | Determined by |
|------|---------------|
| Principal | Borrower's `loanAmount` |
| Repayment | Winning bid amount |
| Interest rate | Implied from principal vs. repayment |
| Duration | Borrower's `loanDuration` |
| Maturity | Finalization timestamp + loan duration |
| Collateral | Locked in protocol |

### Loan States

```
ACTIVE ──→ REPAID (borrower repaid before maturity)
  │
  └──→ DEFAULTED (lender claimed collateral after maturity + grace period)
```

---

## 6. Position NFTs

Every loan mints two ERC-721 tokens via the `PositionNFT` contract:

| NFT | Token ID | Holder | Rights |
|-----|----------|--------|--------|
| Borrower Position | `loanId * 2` | Borrower | Right to repay and reclaim collateral |
| Lender Position | `loanId * 2 + 1` | Lender | Right to receive repayment (or claim collateral on default) |

**Critical:** Position NFTs determine who can perform loan actions. If you sell your Lender Position NFT, the buyer becomes the lender — they receive the repayment or claim the collateral. The protocol checks `ownerOf()` on the PositionNFT contract, not the original addresses.

### Position NFT Transfer

Position NFTs are standard ERC-721 tokens. They can be transferred freely using `transferFrom` or `safeTransferFrom`. However, the integrated marketplace provides a structured way to trade them.

---

## 7. Loan Resolution

### Repayment (Borrower)

The holder of the Borrower Position NFT repays the exact `repaymentAmount` in the loan token.

```
Borrower ──[approve repaymentAmount]──> USDC
Borrower ──[repayLoan(loanId)]──> LoanProtocol
```

On repayment:
1. Repayment amount transferred from borrower to lender (Lender NFT owner)
2. Collateral released to borrower (Borrower NFT owner)
3. Both Position NFTs burned
4. Loan status → `REPAID`

### Default (Lender Claims)

If the loan is not repaid by `maturityTimestamp + GRACE_PERIOD`, the lender can claim the collateral.

```
Lender ──[claimCollateral(loanId)]──> LoanProtocol
```

On default:
1. Collateral transferred to lender (Lender NFT owner)
2. Both Position NFTs burned
3. Loan status → `DEFAULTED`

The grace period gives borrowers a buffer and ensures the lender cannot claim at the exact second of maturity.

---

## 8. Position Marketplace

The integrated marketplace allows trading Position NFTs before loan resolution.

### Why Trade Positions?

- **Lender wants early liquidity** — Sell the position rather than waiting for maturity
- **Position changes value over time** — As the loan approaches maturity without default, a lender position becomes more valuable ("pull-to-par")
- **Speculation** — Buy discounted positions on loans you believe will be repaid

### Marketplace Flow

```
List ──→ Direct Buy (anyone pays asking price)
  │
  ├──→ Offer (buyer proposes lower price)
  │     ├──→ Accept
  │     ├──→ Reject
  │     ├──→ Counter-offer
  │     │     ├──→ Accept counter
  │     │     └──→ Let expire
  │     └──→ Expire (timed out)
  │
  └──→ Unlist (seller removes listing)
```

### Marketplace Constraints

- Positions cannot be listed if the loan is within the **maturity buffer** (prevents late-stage manipulation)
- Maximum 50 offers per listing (`MAX_OFFERS_PER_LISTING`)
- Offers have an expiration timestamp set by the buyer
- Offer funds are escrowed; expired offers are refunded

### Settlement

All marketplace trades are atomic — the Position NFT and payment change hands in a single transaction. The protocol uses `protocolTransfer()` on the PositionNFT contract, which bypasses normal ERC-721 approval requirements since the protocol is trusted by the NFT contract.

---

## 9. Yield Curve Data

Every finalized auction creates a data point:

```javascript
{
  duration: loanDuration,            // in seconds
  rate: impliedAPR,                  // calculated from loanAmount vs repaymentAmount
  collateral: collateralToken,
  collateralAmount: amount,
  loanAmount: principal,
  timestamp: finalizationTime,
  status: 'ACTIVE' | 'REPAID' | 'DEFAULTED'
}
```

Plot these points (x-axis: duration, y-axis: rate) and you get the Bitcoin credit yield curve. Different loan statuses are plotted differently:

- **Active loans** — Current credit conditions
- **Repaid loans** — Confirmed rate data
- **Defaulted loans** — Risk pricing signals
- **Open auctions with bids** — Leading rate indicators

The yield curve is constructed entirely from market activity. No external data feeds. No algorithmic rate-setting. Pure market discovery.

---

## 10. State Machine Summary

### Auction States

| State | Entry Condition | Exits |
|-------|----------------|-------|
| `OPEN` | `createAuction()` called | → `FINALIZED` (bids + finalized), → `CANCELLED` (no bids + finalized), → `CANCELLED` (borrower cancelled) |
| `FINALIZED` | `finalizeAuction()` with bids | Terminal |
| `CANCELLED` | Various (see above) | Terminal |

### Loan States

| State | Entry Condition | Exits |
|-------|----------------|-------|
| `ACTIVE` | Auction finalized with bids | → `REPAID` (borrower repaid), → `DEFAULTED` (lender claimed after grace period) |
| `REPAID` | `repayLoan()` called before maturity | Terminal |
| `DEFAULTED` | `claimCollateral()` called after maturity + grace | Terminal |

### Marketplace Offer States

| State | Entry Condition | Exits |
|-------|----------------|-------|
| `PENDING` | `makeMarketplaceOffer()` | → Accepted, → Rejected, → Cancelled, → Expired, → `COUNTERED` |
| `COUNTERED` | `counterMarketplaceOffer()` | → Counter accepted, → Expired |
| `ACCEPTED` | Seller accepts / buyer accepts counter | Terminal |
| `REJECTED` | Seller rejects | Terminal |
| `CANCELLED` | Buyer cancels | Terminal |
| `EXPIRED` | Past expiration timestamp | Terminal |
