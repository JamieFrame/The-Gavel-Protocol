# Direct Access Guide

This guide shows how to use The Gavel Protocol **directly** — by calling the deployed smart contracts yourself, with no interface and no curated token list. This is the permissionless path, and it is fully supported.

The core contract, `LoanProtocol`, accepts **any ERC-20 token** and enforces **no whitelist**. Its own source states this plainly: the protocol accepts any ERC-20, and the separate `ListingService` contract is an optional curation layer that adds token whitelisting, bid steps, and (potentially) fees on top. The hosted interface routes through `ListingService`; this guide does not. When you call `LoanProtocol` directly, you choose the tokens and the parameters.

> **This is the raw protocol.** The convenience and safety checks of the interface and the Curation Layer do not apply here. You are responsible for the validity of the tokens you use, for getting decimals and amounts right (USDC/USDT use 6 decimals, WBTC uses 8, most ERC-20s use 18), and for the sanity of every parameter. Nothing here is advice. See [Security](../SECURITY.md) and the Risk Disclaimers before you act.

## Before you start

- A self-custody wallet holding ETH on **Arbitrum One** (chain ID 42161) for gas.
- The contract addresses from **[Deployed Contracts](deployed-contracts.md)**.
- ERC-20 approvals: before depositing collateral or funding a loan, you must `approve` the relevant token to spend on behalf of `LoanProtocol`.
- A way to send transactions: the Arbiscan **"Write Contract"** tab on the verified proxy works with a connected wallet and needs no code; for scripting, any library (ethers.js, viem, `cast`) works against the verified ABI.

All amounts are in the token's base units (e.g. 100 USDC = `100000000`, because USDC has 6 decimals).

---

## How the auction works

The Gavel auction is a competitive auction for a loan. A borrower opens an auction stating how much collateral they are posting, which token they want to borrow, how much, and the maximum total repayment they will accept. Lenders then compete by bidding the **repayment amount** they require to fund the loan — a lower repayment is more favourable to the borrower, so lenders bid each other down, each improving on the current best by at least the auction's `bidStep`. When the auction ends, it is finalised and the loan is created with the best (lowest-repayment) bid. The difference between the loan amount and the repayment is the lender's return; the auction discovers it, with no oracle involved.

---

## Borrower walkthrough

1. **Approve the collateral token** for `LoanProtocol` (standard ERC-20 `approve`).
2. **Deposit collateral** into the protocol:
   `depositCollateral(address token, uint256 amount)`
3. **Open an auction:**
   `createAuction(address collateralToken, uint256 collateralAmount, address loanToken, uint256 loanAmount, uint256 maxRepayment, uint256 loanDuration, uint256 auctionDuration, uint256 bidStep) → (uint256 auctionId)`
   - `maxRepayment` caps the total you will repay (your interest-rate ceiling).
   - `loanDuration` / `auctionDuration` are in seconds.
   - `bidStep` is the minimum bid improvement; pass `0` to use the protocol default.
4. **Wait for the auction to run.** Read live state with `getAuction`, `getCurrentBid`, `getBidCount`, `canFinalize`, `getAuctionTimeRemaining`.
5. **Finalise** once the auction has ended:
   `finalizeAuction(uint256 auctionId)` — creates the loan with the winning bid and releases the loan tokens to you.
6. **Repay** before the loan matures:
   - `approve` the loan token to `LoanProtocol` for the repayment amount, then
   - `repayLoan(uint256 loanId)` — repays and returns your collateral.

If no acceptable bid arrives, you can `cancelAuction(uint256 auctionId)` before finalisation, and `withdrawCollateral(address token, uint256 amount)` to retrieve any deposited collateral that was never locked into a loan.

---

## Lender walkthrough

1. **Approve the loan token** for `LoanProtocol` for the amount you intend to fund.
2. **Bid** on an open auction:
   `placeBid(uint256 auctionId, uint256 repaymentAmount)` — `repaymentAmount` is the total you require to be repaid. Lower is more competitive. Use `getMinimumBid`, `getMaximumBid`, and `getAuctionBidStep` to see the valid range right now.
3. **If you are outbid,** reclaim your funds with `claimRefund(address token)`.
4. **If you win,** finalisation creates the loan and you hold the **lender position** (an NFT). At maturity you receive the repayment.
5. **On borrower default,** after the grace period:
   - `markDefault(uint256 loanId)` (if not already marked), then
   - `claimCollateral(uint256 loanId)` to take the collateral. Check eligibility first with `isInGracePeriod` and `canClaimCollateral`.

---

## Secondary market (trading positions)

Both sides of a loan are transferable NFTs and can be sold before maturity. This is a built-in marketplace inside `LoanProtocol`.

**Token IDs.** Marketplace functions act on a **`tokenId`, not a `loanId`.** For a given loan:
- borrower position `tokenId = loanId × 2`
- lender position `tokenId = loanId × 2 + 1`

(`listPosition` / `listPositionFor` are the exception — they take a `loanId` and a `positionType`.)

- **List a position for sale:**
  `listPosition(uint256 loanId, string positionType, address paymentToken, uint256 askingPrice, uint256 minOfferAmount)` — `positionType` is `"borrower"` or `"lender"`; `minOfferAmount` is your offer floor (`0` = none).
- **Buy at the asking price (MEV-protected):**
  `buyPosition(uint256 tokenId, uint256 maxPrice, address expectedPaymentToken)` — `maxPrice` and `expectedPaymentToken` protect you against a listing being changed underneath your transaction; the buy reverts if the price exceeds `maxPrice` or the payment token differs.
- **Make an offer below asking:**
  `makeMarketplaceOffer(uint256 tokenId, uint256 offerAmount, uint256 offerDuration, address expectedPaymentToken) → (uint256 offerId)`
- **Negotiate / manage:** `acceptMarketplaceOffer`, `counterMarketplaceOffer`, `acceptMarketplaceCounterOffer`, `cancelMarketplaceOffer`, `updateListingPrice`, `unlistPosition`, `cleanStaleListing`.

Read marketplace state with `getMarketplaceListing`, `isPositionListed`, and `getMarketplaceOfferCount`.

---

## Acting through an operator

If you want a third party (a bot, a custom frontend, a service) to act on your positions, approve it once:
`setOperatorApproval(address operator, bool approved)`. Approved operators can then call the `…For` variants on your behalf.

---

## Reading protocol state without the interface

All of these are free `view` calls — no transaction, no gas:

| Question | Function |
|---|---|
| Auction details | `getAuction(auctionId)` |
| Loan details | `getLoan(loanId)` |
| Current best bid | `getCurrentBid(auctionId)` |
| Number of bids | `getBidCount(auctionId)` |
| Valid bid range now | `getMinimumBid`, `getMaximumBid`, `getAuctionBidStep` |
| Can it be finalised? | `canFinalize(auctionId)` |
| Time left (auction / loan) | `getAuctionTimeRemaining`, `getLoanTimeRemaining` |
| Default status | `isInGracePeriod(loanId)`, `canClaimCollateral(loanId)` |
| Who owns a position | `getBorrowerPositionOwner(loanId)`, `getLenderPositionOwner(loanId)` |
| My deposited collateral | `getCollateralBalance(user, token)` |
| My refundable bid funds | `getPendingRefund(user, token)` |

---

## Function reference (write functions)

| Function | Role |
|---|---|
| `depositCollateral(address token, uint256 amount)` | Borrower: fund collateral balance |
| `withdrawCollateral(address token, uint256 amount)` | Borrower: retrieve unlocked collateral |
| `createAuction(collateralToken, collateralAmount, loanToken, loanAmount, maxRepayment, loanDuration, auctionDuration, bidStep)` | Borrower: open an auction |
| `cancelAuction(uint256 auctionId)` | Borrower: cancel before finalisation |
| `finalizeAuction(uint256 auctionId)` | Anyone: finalise an ended auction, create the loan |
| `repayLoan(uint256 loanId)` | Borrower: repay and reclaim collateral |
| `placeBid(uint256 auctionId, uint256 repaymentAmount)` | Lender: bid the repayment you require |
| `claimRefund(address token)` | Lender: reclaim outbid funds |
| `markDefault(uint256 loanId)` | Anyone: mark a defaulted loan |
| `claimCollateral(uint256 loanId)` | Lender: claim collateral on default |
| `listPosition(loanId, positionType, paymentToken, askingPrice, minOfferAmount)` | Seller: list a position |
| `buyPosition(tokenId, maxPrice, expectedPaymentToken)` | Buyer: buy a listed position |
| `makeMarketplaceOffer(tokenId, offerAmount, offerDuration, expectedPaymentToken)` | Buyer: offer below asking |
| `setOperatorApproval(address operator, bool approved)` | Approve an operator to act for you |

The verified source and full ABI for every function are on Arbiscan via the links in [Deployed Contracts](deployed-contracts.md).
