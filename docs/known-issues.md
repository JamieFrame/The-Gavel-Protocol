# Known Issues — v1 contracts (Arbitrum One)

This page lists known issues in the deployed v1 contracts. **The v1 contracts are immutable**: they have no upgrade path, so none of the issues below can be, or will be, changed in the deployed code. Each entry states what is affected, what is not, and how to work with the contracts as they are.

Every claim on this page is reproduced by our own tests, which run against both `LoanProtocol` and `NFTLoanProtocol`: [`test/security/SR1_Marketplace.t.sol`](../test/security/SR1_Marketplace.t.sol) (KI-1, KI-2), [`test/security/SR2_RepaymentBlocklist.t.sol`](../test/security/SR2_RepaymentBlocklist.t.sol) (KI-3) and [`test/security/SR3_PositionAsCollateral.t.sol`](../test/security/SR3_PositionAsCollateral.t.sol) (KI-4):

```bash
forge test --match-path test/security/SR1_Marketplace.t.sol -vv
forge test --match-path test/security/SR2_RepaymentBlocklist.t.sol -vv
forge test --match-path test/security/SR3_PositionAsCollateral.t.sol -vv
```

The KI-3 and KI-4 tests also run against the live contracts and tokens on an Arbitrum One fork when `ARB_RPC_URL` is set (an archive endpoint; see each file's header).

The deployed implementations were compiled with solc 0.8.24 (see [Testing](TESTING.md#toolchain)); the gas figures below are from that compiler. The per-transaction gas limit (32,000,000) and minimum gas price (0.02 gwei) were read from Arbitrum One's `ArbGasInfo` precompile on 25 September 2026.

| ID | Summary | Severity | Funds at risk |
|---|---|---|---|
| [KI-1](#ki-1--marketplace-listing-can-be-made-permanently-unresolvable-by-offer-churn) | A listing can be made permanently unresolvable by offer churn | Low | None |
| [KI-2](#ki-2--listings-on-repaid-or-claimed-loans-cannot-be-closed) | Listings on repaid or claimed loans cannot be closed | Informational | None |
| [KI-3](#ki-3--repayment-reverts-if-the-loan-token-refuses-transfers-to-the-lender-position-holder) | Repayment reverts if the loan token refuses transfers to the lender-position holder (USDC loans) | Medium | Borrower collateral |
| [KI-4](#ki-4--a-position-nft-used-as-collateral-is-burned-when-its-own-loan-settles) | A position NFT used as collateral in NFTLoanProtocol is burned when its own loan settles | Low | Principal of a lender who accepts a Gavel position as collateral; the repayment of a pledged lender position's loan |

---

## KI-1 — Marketplace listing can be made permanently unresolvable by offer churn

**Affected:** `LoanProtocol` and `NFTLoanProtocol` — the internal `_refundOtherOffers`, and therefore every path that resolves a listing: `unlistPosition`, `cleanStaleListing`, `acceptMarketplaceOffer`, `acceptMarketplaceCounterOffer` and `buyPosition`.

**Cause.** When a listing is resolved, `_refundOtherOffers` iterates over every offer ID from 1 to `marketplaceOfferNonce[tokenId]`. That nonce only ever increases while the listing is active; cancelled offers are not removed from the iteration. `MAX_OFFERS_PER_LISTING` (50) caps the number of *active* offers — the Sherlock #13 (M-3) fix — but not the number of offers the loop visits. Anyone can therefore grow the loop by repeatedly making and cancelling an offer.

**Correction to the source comments.** The comments on `MAX_OFFERS_PER_LISTING` ("Gas-safety cap on offers per listing — bounds `_refundOtherOffers` loop") and in `makeMarketplaceOffer` ("cap ACTIVE offers to bound `_refundOtherOffers` loop") are incorrect: the cap bounds the number of active offers, not the length of the loop. Because the deployed code is immutable, the comments remain in the source; this note is the correction.

**Conditions.** Any account can churn an active listing. Each cycle adds one dead offer to the loop; each dead offer costs a resolving transaction about 2,500 gas (one cold storage read). Measured cold, as on mainnet:

| Offers churned | `unlistPosition` gas |
|---|---|
| 0 | ~32,000 |
| 100 | ~283,000 |
| 1,000 | ~2.54 million |
| 5,000 | ~12.6 million |

At about **12,700 cycles**, `unlistPosition` exceeds Arbitrum One's 32 million per-transaction gas limit (an EIP-7825-style cap introduced in ArbOS 50). The other resolution paths do slightly more work and exceed it a little earlier. At 13,000 cycles, all of them fail on gas alone and succeed if given more gas than the network allows.

**Cost to an attacker.** One make-and-cancel cycle costs between about 248,000 gas (batched in a contract) and 341,000 gas (two separate transactions). Reaching the limit costs roughly **3.15 to 4.36 billion gas, about 0.06 to 0.09 ETH** at Arbitrum One's current minimum L2 base fee of 0.02 gwei (raised from 0.01 gwei by ArbOS 51 "Dia" in January 2026), plus L1 data fees. The attacker needs to hold only one offer's worth of the payment token: the escrow is returned on every cancel and reused on the next cycle, so setting `minOfferAmount` does not prevent the attack.

**Impact once the limit is passed.** The brick is **permanent** for the affected listing, and there is **no on-chain recovery path**. Every function that could close the listing (`unlistPosition`, `cleanStaleListing`, `acceptMarketplaceOffer`, `acceptMarketplaceCounterOffer` and `buyPosition`) runs the same loop and fails. That includes `cleanStaleListing`, the permissionless clean-up that otherwise clears a listing after a direct transfer. Because the contracts are immutable, no fix can be applied to them. The listing can never be unlisted, cleaned up, sold or have an offer accepted. It stays marked as listed, so `listPosition` for that position reverts with `AlreadyListed` for as long as the loan is active — including for a new owner if the position is transferred. The position therefore cannot be traded through the integrated marketplace again.

**Not affected:**

- **The loan.** `repayLoan` and `claimCollateral` do not touch the listing and succeed normally (about 100,000 gas each in our tests).
- **Offer escrow.** Any offer maker can call `cancelMarketplaceOffer` at any time and is refunded in full in the same transaction; cancelling does not iterate other offers.
- **Direct transfers.** The position NFT can still be transferred with a standard ERC-721 transfer.

**Working with it.**

- **Sellers:** `marketplaceOfferNonce(tokenId)` shows how far a listing has been churned. Below the limit, unlisting still succeeds and resets the nonce to zero, so a fresh listing starts from zero churn.
- **Buyers and integrators:** check `marketplaceOfferNonce(tokenId)` before relying on a listing being resolvable.

**Severity: Low.** This is a permanent denial of service for the affected listing, but no funds are at risk, the loan settles normally, and the position remains transferable.

**v2.** The fix will ship in v2: resolution will iterate only active offers, bounded by the active-offer cap regardless of past churn, and an invariant test will enforce this. The v1 contracts are immutable and will not change.

**Credits.** yossweh (https://github.com/yossweh), original reporter, on 24 September 2026. Also reported independently by a second researcher on 25 September 2026.

---

## KI-2 — Listings on repaid or claimed loans cannot be closed

**Affected:** `LoanProtocol` and `NFTLoanProtocol` — `unlistPosition`, `cleanStaleListing` and `makeMarketplaceOffer`.

**Cause.** `repayLoan` and `claimCollateral` burn both position NFTs. Both closing paths then look up the position's current owner with `ownerOf`: `unlistPosition` to authorise the caller, and `cleanStaleListing` to check that the listing is stale. `ownerOf` reverts for a burned token (`ERC721NonexistentToken`), so both calls revert. If the position was listed when the loan was repaid or its collateral claimed, the listing's `active` flag can therefore never be cleared. Separately, `makeMarketplaceOffer` does not check the loan's status.

**Conditions.** A position is listed on the marketplace and, while it is still listed, the loan is repaid (`repayLoan`) or its collateral is claimed (`claimCollateral`). `markDefault` alone burns nothing, so a listing on a loan that has only been marked as defaulted can still be unlisted normally.

**Impact.** The ghost listing is **permanent**, and there is **no on-chain path that clears it**. `unlistPosition` and `cleanStaleListing` revert on the burned token, and no sale can complete: `buyPosition` reverts with `LoanNotActive` after either repayment or a collateral claim. Because the contracts are immutable, no fix can be applied to them. The listing therefore remains marked as listed indefinitely. Before maturity, `makeMarketplaceOffer` still accepts new offers, and their escrow, on a ghost listing, but those offers can never be filled: `acceptMarketplaceOffer` reverts with `LoanNotActive`.

**Not affected:**

- **Offer escrow.** `cancelMarketplaceOffer` refunds the offer maker in full, immediately, on a repaid, claimed or stale listing. Offers made before or after the repayment are equally refundable. Escrow is not locked.
- **The loan.** Repayment and collateral claims complete normally; the listing has no effect on them.
- **Re-listing.** There is nothing to re-list: the position no longer exists.

**Working with it.** Before making an offer, check that the listing's loan is active: `getLoan(loanId).status` must be `ACTIVE`. If you have an offer on a ghost listing, cancel it to recover your escrow.

**Severity: Informational.** No funds are affected; the effect is stale marketplace state.

**v2.** The fix will ship in v2: unlisting will not depend on the position NFT still existing, and making an offer will require the loan to be active. The v1 contracts are immutable and will not change.

**Credits.** Reported by a second researcher on 25 September 2026, who also reported KI-1 independently.

---

## KI-3 — Repayment reverts if the loan token refuses transfers to the lender-position holder

**Affected:** `LoanProtocol` and `NFTLoanProtocol` — `repayLoan`, for loans whose loan token refuses transfers *to* a blocked address. Of the loan tokens on Arbitrum One, this is **USDC**. **USD₮0 is not affected.**

**Cause.** `repayLoan` sends the repayment from the borrower directly to the current holder of the lender position NFT (`safeTransferFrom(msg.sender, lender, repaymentAmount)`), and returns the collateral to the borrower in the same transaction. There is no other repayment path: no escrow, no partial repayment, and no way to repay into the contract. If the loan token refuses the transfer, the whole repayment reverts.

Whether it refuses depends on the token, not on the protocol:

- **USDC** (`FiatTokenV2_2`) checks the sender, the source and the recipient of every transfer against its blocklist. A transfer to a blocked address reverts.
- **USD₮0** (`TetherToken`) checks only the source of a transfer, and the caller of `transferFrom`. A transfer to a blocked address succeeds.

The protocol itself accepts any ERC-20 as a loan token, so the same applies to any loan token that refuses transfers to a blocked recipient.

`claimCollateral` does not move the loan token, so it is unaffected by the loan token's blocklist.

**Correction to the source comments.** The header of `LoanProtocol.sol` lists "Tokens with transfer blocklists" as an unsupported token type. USDC and USD₮0, the loan tokens curated in the interface, both have blocklists. The [Trust Assumptions](Trust_Assumptions_Document.md) (§3.1, §7.1) record the USDC blocklist as an external dependency that "could prevent operations" but did not state the consequence described here. Because the deployed code is immutable, the comment remains in the source; this note is the correction.

**Conditions.** A USDC loan whose lender-position holder is blocked by USDC at the time the borrower repays. This can arise in three ways:

- The issuer blocks the holder's address during the loan.
- The holder transfers the lender position to an address that is already blocked. The position is an ERC-721 token and the transfer is not restricted.
- An already-blocked address buys the lender position on the integrated marketplace, from a listing priced in a different payment token (for example USD₮0). A blocked address cannot bid in an auction or buy a listing priced in USDC, but the listing's payment token is independent of the loan token.

The second and third cases need no action by the issuer, and can be arranged deliberately by a lender who controls a blocked address.

**Impact.** The borrower cannot repay: every call reverts, from the start of the loan to the last second of the grace period. Once maturity plus the 1-day grace period has passed, the lender-position holder can call `claimCollateral` and receives the full collateral: the WBTC, or the NFT in `NFTLoanProtocol`. The borrower keeps the loan amount they received and loses the collateral, so their loss is the value of the collateral above the repayment amount. Because loans are over-collateralised, that difference is a gain to the holder.

The owner can pause the protocol. A pause blocks both `repayLoan` and `claimCollateral` and freezes the maturity and grace deadlines; after unpause, the remaining grace period runs and the outcome is unchanged. A pause delays the outcome and does not change it.

**Related: a token-wide pause.** USDC's issuer can also pause USDC as a whole. If USDC is paused across a loan's grace period, the loan cannot be repaid, while `claimCollateral` (which moves only the collateral) still succeeds once the grace period ends. Unlike the protocol's own pause, a USDC pause does not freeze the protocol's deadlines. USD₮0 has no token-wide pause.

**Not affected:**

- **USD₮0 loans.** The repayment reaches a blocked holder and the borrower receives the collateral back as normal. The repayment is then frozen in the holder's address, under Tether's blocklist; that is a matter between the holder and the token issuer, as for any USD₮0 balance.

  One exception applies to every loan token here, USD₮0 included. Each refuses transfers to its own contract address: USD₮0 by design, and USDC because it has blocklisted itself. A holder who transfers the lender position to the loan token's own address therefore makes repayment impossible. Nobody gains from this. The token contract can never call `claimCollateral`, so the collateral stays in the protocol permanently, and the holder forfeits the repayment. It harms the borrower at the holder's own cost.
- **Loans whose lender-position holder is not blocked.** They repay and settle normally, including alongside an affected loan.
- **Lenders.** A lender's own funds are not put at risk by this issue.

**Not KI-3:**

- A borrower who is themselves blocked on the loan token cannot repay from that address, on USDC or USD₮0. That is the borrower's own dependency on their token, not a flaw in the protocol. The borrower position is transferable, and `repayLoan` collects the repayment from, and returns the collateral to, whoever holds it.
- A collateral token with a blocklist (cbBTC, which the protocol accepts) affects only the blocked party. A borrower blocked on the collateral token cannot repay, because the collateral cannot be returned to them; the loan defaults to the lender. A holder blocked on the collateral token cannot claim from that address, but can after transferring the lender position.

**Working with it.**

- **Borrowers with a USDC loan:** the amount exposed is your collateral value above the repayment amount. Before repaying, you can read the current holder with `PositionNFT.ownerOf(PositionNFT.getLenderTokenId(loanId))` and check it with USDC's `isBlacklisted(address)`.
- **Lenders:** if your address is blocked on USDC during a loan, transferring the lender position to an address that is not blocked restores the borrower's ability to repay.
- **Integrators:** do not assume `repayLoan` can always succeed before the grace period ends on a loan token that blocks recipients.

**Severity: Medium.** On a USDC loan, a borrower can lose collateral worth more than their debt with no way to prevent it. It requires the lender-position holder to be blocked by USDC, which the issuer imposes on few addresses; a holder acting deliberately must already control such an address and must either fund the loan first or buy the position.

**v2.** The fix will ship in v2: a repayment will not be sent directly to the lender-position holder's wallet, so the holder's status on the loan token cannot block a borrower from repaying. The v1 contracts are immutable and will not change.

**Credits.** Arash Rahmani (https://github.com/Arashrahmaniii), who reported this in October 2026.

---

## KI-4 — A position NFT used as collateral is burned when its own loan settles

**Affected:** `NFTLoanProtocol` — `createAuction`, `createAuctionFor`, `repayLoan` and `claimCollateral` — when the collateral is a Gavel position NFT (`PositionNFT` or `NFTPositionNFT`). `LoanProtocol` takes ERC-20 collateral only and is not affected as the lending venue, but its position NFTs can be pledged in `NFTLoanProtocol`.

**Cause.** `NFTLoanProtocol` accepts any ERC-721 as collateral, including the protocol's own position NFTs. When a loan settles, `repayLoan` and `claimCollateral` burn both of its position NFTs, whoever holds them. If one of those positions is held by `NFTLoanProtocol` as collateral for a second loan, it is burned there. The second loan can then never settle: its `repayLoan` and `claimCollateral` both end by transferring the collateral, and the transfer of a burned token reverts (`ERC721NonexistentToken`). `repayLoan` also sends the repayment to whoever holds the lender position at that moment; if that is `NFTLoanProtocol`, the repayment is sent to `NFTLoanProtocol`, which does not record it against any loan.

**Conditions.** A Gavel position from loan X is collateral for a second loan, loan Y, in `NFTLoanProtocol`, Y is funded, and X settles while Y is still active. This can happen in two ways:

- **X's lender position is pledged, and X is repaid.** X's borrower can repay at any time before X's grace period ends, so this does not depend on X maturing before Y. If Y is repaid first, both loans settle normally.
- **X's borrower position is pledged, and X defaults.** Only the holder of the borrower position can repay X, and while it is pledged that holder is `NFTLoanProtocol`, so X's borrower cannot repay X. Once X's grace period has ended, X's lender can call `claimCollateral` on X, which burns the pledged position.

**Impact.**

- **Loan Y can never settle.** Y's `repayLoan` and `claimCollateral` both revert when they try to transfer the burned collateral. Y's borrower cannot repay; Y's lender cannot claim. Y's lender loses the principal lent; Y's borrower keeps it.
- **Lender position pledged: X's repayment is trapped permanently** in `NFTLoanProtocol`. No function can release it. X's borrower receives X's collateral back as normal; X's repayment reaches neither X's lender nor Y's lender. Nobody receives it: the repayment is not paid to anyone.
- **Borrower position pledged: nothing is trapped** in `NFTLoanProtocol`. X ends as an ordinary default, with X's collateral going to X's lender.
- After Y's grace period, anyone can call `markDefault` on Y, which changes its status from `ACTIVE` to `DEFAULTED`. Y still cannot settle: `claimCollateral` still reverts on the burned token, `repayLoan` then reverts with `LoanNotActive`, and nothing moves.

The owner can pause the protocol; a pause does not change the outcome.

**Not affected:**

- Loans whose collateral is not a Gavel position NFT.
- `LoanProtocol` loans, except that a `LoanProtocol` position pledged in `NFTLoanProtocol` behaves as above.
- **A pledged lender position whose loan defaults.** If X is not repaid and its grace period ends while its lender position is pledged, nobody can claim X's collateral while Y is active, because the holder of X's lender position is `NFTLoanProtocol`. When Y settles, the position passes to whoever receives Y's collateral — Y's borrower on repayment, Y's lender on a claim — who can then claim X's collateral. X's collateral is held only while Y is active, and nothing is lost.
- At the time of writing, `NFTLoanProtocol` has no auctions or loans on Arbitrum One: `loanNonce()` is 0 at block 525,334,168.

**Working with it.**

- **Lenders:** an `NFTLoanProtocol` auction whose `collateralNFT` is `PositionNFT` (`0xAD6Edb72409605a51dc6C990A09829616178A8f4`) or `NFTPositionNFT` (`0x9A1728C87ac0456cCd882b5D5637e856be0fEec8`) is exposed to this issue. `getAuction(auctionId).collateralNFT` shows the collateral before bidding.
- **Borrowers:** while a position is pledged, its holder is `NFTLoanProtocol`. The loan it represents cannot be repaid by its borrower (borrower position), and its collateral cannot be claimed by anyone (lender position). The pledged position returns to Y's borrower when Y is repaid.
- **Integrators and curation layers:** the two position contracts can be refused as collateral collections. A loan made unable to settle by this issue shows `ACTIVE`, or `DEFAULTED` once `markDefault` has been called.

**Severity: Low.** The loss requires a lender to accept a Gavel position NFT as collateral on the raw protocol, which the contract states accepts any ERC-721; it yields an attacker nothing beyond an ordinary default on loan Y; and the deployed `NFTLoanProtocol` has had no auctions or loans.

**v2.** v2 is not affected by design: repayments are credited to the claim and collected by its holder rather than pushed; claims and positions cannot be deposited in the vault that secures a loan; and the contract that holds positions during a sale handles a loan that settles mid-sale. The v1 contracts are immutable and will not change.

**Credits.** ForkProof (https://forkproof.com/), who reported this in November 2026.

---

## Reporting

To report a new issue, see [`SECURITY.md`](../SECURITY.md).
