# Known Issues — v1 contracts (Arbitrum One)

This page lists known issues in the deployed v1 contracts. **The v1 contracts are immutable**: they have no upgrade path, so none of the issues below can be, or will be, changed in the deployed code. Each entry states what is affected, what is not, and how to work with the contracts as they are.

Every claim on this page is reproduced by our own tests in [`test/security/SR1_Marketplace.t.sol`](../test/security/SR1_Marketplace.t.sol), which run against both `LoanProtocol` and `NFTLoanProtocol`:

```bash
forge test --match-path test/security/SR1_Marketplace.t.sol -vv
```

The deployed implementations were compiled with solc 0.8.24 (see [Testing](TESTING.md#toolchain)); the gas figures below are from that compiler. The per-transaction gas limit (32,000,000) and minimum gas price (0.02 gwei) were read from Arbitrum One's `ArbGasInfo` precompile on 25 September 2026.

| ID | Summary | Severity | Funds at risk |
|---|---|---|---|
| [KI-1](#ki-1--marketplace-listing-can-be-made-permanently-unresolvable-by-offer-churn) | A listing can be made permanently unresolvable by offer churn | Low | None |
| [KI-2](#ki-2--listings-on-repaid-or-claimed-loans-cannot-be-closed) | Listings on repaid or claimed loans cannot be closed | Informational | None |

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

At about **12,700 cycles**, `unlistPosition` exceeds Arbitrum One's 32 million per-transaction gas limit (EIP-7825, adopted in ArbOS 50). The other resolution paths do slightly more work and exceed it a little earlier. At 13,000 cycles, all of them fail on gas alone and succeed if given more gas than the network allows.

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

## Reporting

To report a new issue, see [`SECURITY.md`](../SECURITY.md).
