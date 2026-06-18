# The Gavel Protocol
# Trust Assumptions & Security Model

**Version:** 2.0
**Date:** June 2026
**Purpose:** Security reference for auditors, integrators, and protocol users
**Status:** Audited (Sherlock collaborative audit, April 2026) — deployed on Arbitrum One

---

## Executive Summary

This document defines the explicit trust assumptions, security boundaries, and architectural decisions of The Gavel Protocol. It is intended for security auditors, integrators, and users to understand the protocol's threat model and to verify that the implemented controls align with the documented assumptions.

**Protocol Overview:** The Gavel Protocol is an oracle-free lending platform using competitive auction mechanics for interest-rate discovery. Users deposit collateral, create loan auctions, and lenders bid by offering progressively lower repayment amounts.

---

## 1. Contract Architecture & Trust Hierarchy

### 1.1 Contract Dependency Graph

```
                         ┌──────────────────┐
                         │      USERS        │
                         │ (Externally       │
                         │  Owned Accounts)  │
                         └────────┬──────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
          ▼                       ▼                       ▼
 ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
 │  ListingService  │  │ NFTListingService│  │  Direct Protocol │
 │  (Curated Layer) │  │  (Curated Layer) │  │      Access      │
 │                  │  │                  │  │ (Permissionless) │
 │ • Fee collection │  │ • Fee collection │  │                  │
 │ • Whitelisting   │  │ • Collection WL  │  │  Any ERC-20,     │
 │                  │  │                  │  │  no whitelist    │
 └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
          │ Requires            │ Requires            │
          │ Operator Approval   │ Operator Approval   │
          ▼                     ▼                     ▼
 ┌──────────────────────────────────────────────────────────────┐
 │           LoanProtocol.sol / NFTLoanProtocol.sol             │
 │                                                              │
 │   CORE PROTOCOL LAYER (Permissionless · Immutable)           │
 │   • Collateral management      • Loan lifecycle              │
 │   • Auction mechanics          • Marketplace trading         │
 └──────────────────────────┬───────────────────────────────────┘
                            │ Mints / Burns / Transfers
                            ▼
                 ┌──────────────────────┐
                 │  PositionNFT /        │
                 │  NFTPositionNFT       │
                 │  • Borrower NFTs      │
                 │  • Lender NFTs        │
                 │  • Protocol-only ops  │
                 └──────────────────────┘
```

### 1.2 Trust Levels

| Trust Level | Entities | Privileges |
|-------------|----------|------------|
| **OWNER** | 2-of-3 Gnosis Safe | Pause/unpause; (curation layer only) token/collection whitelist and fee configuration. **No upgrade power.** |
| **AUTHORIZED OPERATOR** | ListingService, NFTListingService (and any operator a user approves) | Call `*For()` functions on behalf of users who have approved them |
| **USER** | Any EOA or contract | Deposit, withdraw, create auctions, bid, trade |
| **EXTERNAL** | ERC20/ERC721 tokens | Token transfer mechanics |

---

## 2. Trust Assumptions by Contract

### 2.1 LoanProtocol.sol / NFTLoanProtocol.sol

#### Assumption 1: Owner Powers Are Narrow, and the Logic Is Immutable

**State:** All six contracts are owned by a **2-of-3 Gnosis Safe** (`0x71D81eb872FBDD93B1196fF3738230FCBfa9206b`). The deploying account transferred ownership at launch and retains no admin power.

**The contracts are non-upgradeable.** Each is deployed behind a minimal **ERC1967 proxy**, and the implementations are **not UUPS** — they contain no `upgradeTo`/`upgradeToAndCall` entry point and no `_authorizeUpgrade` function, and there is no proxy admin with upgrade authority. There is therefore **no on-chain path by which the business logic can be changed**, by the owner or by anyone else. Fixes are delivered by deploying new, separate contracts (a "redeploy-as-v2" model), never by upgrading the live ones.

| Owner Capability | Risk if Compromised | Mitigation |
|------------------|---------------------|------------|
| `pause()` / `unpause()` | Protocol halt — user funds remain safe; no logic or balance change | 2-of-3 multi-sig; progressive renunciation planned |

**Trust Assumption:** In an emergency the owner could pause the protocol. The owner **cannot** upgrade the contracts, alter loan terms, change protocol constants, or move user funds. The pause power is held by a 2-of-3 Safe and is slated for progressive renunciation.

#### Assumption 2: Operator Approval is User-Controlled

The `operatorApprovals` mapping grants delegated authority:

```solidity
// User explicitly grants approval
function setOperatorApproval(address operator, bool approved) external {
    if (operator == address(0)) revert ZeroAddress();
    operatorApprovals[msg.sender][operator] = approved;
    emit OperatorApprovalSet(msg.sender, operator, approved);
}
```

**Security Property:** Only the user (`msg.sender`) can grant or revoke operator status for their own address. No external party can grant themselves operator access.

**Trust Assumption:** Users who approve an operator trust that operator to:
- Create auctions using their deposited collateral
- List their position NFTs on the marketplace

**Verification Point for Auditors:** Verify that all `*For()` functions correctly check:
```solidity
if (msg.sender != collateralFrom && !operatorApprovals[collateralFrom][msg.sender]) {
    revert UnauthorizedOperator();
}
```

#### Assumption 3: PositionNFT is Trusted

The protocol assumes `PositionNFT` correctly:
- Only allows LoanProtocol to mint/burn
- Correctly implements `protocolTransfer()` for marketplace trades
- Returns accurate ownership information

**Trust Basis:** PositionNFT is deployed by the same deployer, with verified source code, and its `loanProtocol` reference is fixed at initialization and cannot be changed.

```solidity
// PositionNFT access control
modifier onlyLoanProtocol() {
    if (msg.sender != loanProtocol) revert OnlyLoanProtocol();
    _;
}
```

---

### 2.2 ListingService.sol / NFTListingService.sol

#### Assumption 4: Protocol Contracts are Immutable References

```solidity
ILoanProtocol public loanProtocol;  // Set once in initialize()
```

**Trust Assumption:** The referenced `loanProtocol` address is the legitimate protocol contract and is not changed after deployment.

**Security Property:** ListingService cannot redirect calls to a malicious protocol contract.

#### Assumption 5: Treasury is Honest

```solidity
address public treasury;  // Receives all fees
```

**Trust Assumption:** The treasury address is controlled by the protocol team and will not reject incoming transfers (which would cause DoS).

**Risk:** If treasury is a contract that reverts on receive, fee collection fails.
**Mitigation:** Treasury should be an EOA or non-reverting multi-sig.

> **Note (launch state):** Fees are configured to zero at launch. Any future activation of a non-zero fee is a material change to the operating model and is governed by the published curation methodology.

#### Assumption 6: Fee Collection is Atomic

Fees are collected via direct `safeTransferFrom` to treasury in the same transaction as auction creation:

```solidity
// Fee collected BEFORE auction created
IERC20(collateralToken).safeTransferFrom(msg.sender, treasury, fee);
loanProtocol.createAuctionFor(...);
```

**Security Property:** If fee transfer fails, the auction is not created. No accumulated-fee vulnerabilities.

---

### 2.3 PositionNFT.sol

#### Assumption 7: Only Protocol Performs Privileged Operations

```solidity
function mintBorrowerPosition(...) external onlyLoanProtocol { ... }
function mintLenderPosition(...) external onlyLoanProtocol { ... }
function burn(uint256 tokenId) external onlyLoanProtocol { ... }
function protocolTransfer(...) external onlyLoanProtocol { ... }
```

**Trust Assumption:** The `loanProtocol` address set during initialization is the only contract that can perform minting, burning, and protocol-controlled transfers.

**Verification Point for Auditors:** Verify `loanProtocol` cannot be changed after initialization.

---

## 3. External Dependency Assumptions

### 3.1 ERC20 Token Assumptions

| Assumption | Status | Impact if Violated |
|------------|--------|-------------------|
| Tokens return true or revert on transfer | ✅ Handled | SafeERC20 handles non-standard returns |
| No fee-on-transfer mechanics | ⚠️ DOCUMENTED | Collateral accounting mismatch |
| No rebasing mechanics | ⚠️ DOCUMENTED | Collateral accounting mismatch |
| Transfer does not callback (not ERC-777) | ⚠️ PARTIAL | Reentrancy guard protects, but callback could have side effects |
| Token is not pausable | ⚠️ EXTERNAL | Transfer failures during loan resolution |
| Token does not have blocklist | ⚠️ EXTERNAL | USDC blocklist could prevent operations |

**Explicit Unsupported Token Types:**
1. Fee-on-transfer tokens (e.g., PAXG with 0.02% fee)
2. Rebasing tokens (e.g., stETH, AMPL)
3. Tokens with transfer callbacks that modify protocol state

**Recommendation for Auditors:** Verify that the Curation Layer whitelist provides a control point to exclude problematic tokens for interface users. Note that direct (permissionless) callers of the core protocol bypass this control and select tokens at their own risk.

### 3.2 ERC721 Token Assumptions (NFTLoanProtocol)

| Assumption | Status | Impact if Violated |
|------------|--------|-------------------|
| NFT implements standard ERC-721 | ✅ Required | `safeTransferFrom` will fail |
| NFT `onERC721Received` callback is safe | ⚠️ PARTIAL | Reentrancy guard protects |
| NFT is not pausable/frozen | ⚠️ EXTERNAL | Collateral cannot be released |
| NFT ownership cannot be manipulated | ⚠️ EXTERNAL | Loan collateral at risk |

**Trust Assumption:** Whitelisted NFT collections are legitimate and non-malicious. As with ERC-20s, direct callers select collections at their own risk.

### 3.3 Arbitrum L2 Assumptions

| Assumption | Impact if Violated |
|------------|-------------------|
| `block.timestamp` is accurate within ~24 hours | Auction timing manipulation |
| Transactions are processed in order | Front-running (inherent to public blockchains) |
| Sequencer is available | Protocol temporarily unusable |
| No L2 state rollback | Loan state corruption |

**Trust Assumption:** Arbitrum operates correctly as documented. The protocol does not implement L2-specific mitigations beyond standard practices.

---

## 4. Economic & Game-Theoretic Assumptions

### 4.1 Auction Mechanism

| Assumption | Basis |
|------------|-------|
| Lenders bid rationally to maximize returns | Economic incentive |
| Escrow prevents griefing bids | Funds locked on bid |
| Self-bidding is prevented | `msg.sender != auction.borrower` check |
| Auction duration is sufficient for price discovery | Configurable 1-72 hours |

**Known Limitations:**
- **Front-running:** Lenders can observe pending bids and front-run. This is inherent to public blockchain auctions and not mitigated.
- **Bid sniping:** Last-second bids cannot be countered. Consider an auction-extension mechanism for future versions.

### 4.2 Marketplace Trading

| Assumption | Basis |
|------------|-------|
| Offer amounts are rational market prices | Escrow prevents spam |
| Expired offers are cleaned up | Permissionless expiration mechanism |
| Maturity buffer prevents late-stage manipulation | `MATURITY_BUFFER` constant |

### 4.3 Collateralization

**CRITICAL DESIGN DECISION:** The protocol is **oracle-free** and does not enforce collateralization ratios.

| Traditional DeFi | The Gavel Protocol |
|------------------|-------------------|
| Oracle determines collateral value | Market determines via auction bids |
| Protocol enforces LTV ratio | Any collateral amount accepted |
| Liquidation on undercollateralization | Fixed-term loans, no liquidation |

**Trust Assumption:** Lenders evaluate collateral quality themselves before bidding. The protocol provides no guarantee that collateral value exceeds loan value.

---

## 5. Timing & State Machine Assumptions

### 5.1 Auction State Machine

```
   OPEN ──► FINALIZED ──► (Loan ACTIVE) ──► (REPAID | DEFAULTED)
    │
    ├──► CANCELLED
    │
    └──► EXPIRED   (if no bids and the finalization window passes)
```

**Invariants:**
1. An auction cannot transition backward in state
2. An auction with bids cannot be cancelled
3. Only one state transition can occur per auction

**Verification Point for Auditors:** Verify no state can be skipped or repeated.

### 5.2 Time Boundary Assumptions

| Boundary | Assumption |
|----------|------------|
| Auction end time | `block.timestamp >= auctionEndTime` allows finalization |
| Loan maturity | `block.timestamp >= maturityTime` allows collateral claim |
| Grace period | `block.timestamp >= maturityTime + GRACE_PERIOD` required for lender claim |
| Offer expiration | `block.timestamp >= offer.expiresAt` allows cleanup |

**Edge Case:** What happens at exact boundary timestamps?
- Protocol uses `>=` comparisons, meaning the action becomes available AT the boundary
- No special handling for exact-second timing

---

## 6. Administrative Trust Boundaries

### 6.1 Owner Capabilities Summary

| Action | LoanProtocol | NFTLoanProtocol | ListingService | NFTListingService |
|--------|--------------|-----------------|----------------|-------------------|
| Pause/Unpause | ✅ | ✅ | ✅ | ✅ |
| Change treasury | N/A | N/A | ✅ | ✅ |
| Change fees | N/A | N/A | ✅ (capped) | ✅ (capped) |
| Whitelist tokens | N/A | N/A | ✅ | ✅ |
| Whitelist collections | N/A | N/A | N/A | ✅ |
| **Upgrade logic** | **❌ Not possible** | **❌ Not possible** | **❌ Not possible** | **❌ Not possible** |

> Two capabilities listed in earlier drafts have been removed because they do not exist on the deployed contracts: **upgrade** (the contracts are non-upgradeable — ERC1967 proxies with non-UUPS implementations and no proxy-admin upgrade authority) and **set grace period** (`GRACE_PERIOD` is a compile-time constant, not an owner-settable parameter).

### 6.2 What Owner CANNOT Do

| Action | Why Not Possible |
|--------|------------------|
| Upgrade or alter contract logic | Contracts are non-upgradeable (ERC1967 + non-UUPS); no upgrade function exists |
| Change the grace period or core constants | Hardcoded as compile-time constants |
| Steal user collateral | No function to withdraw arbitrary user funds |
| Modify existing loans | Loan terms are immutable after creation |
| Change auction bids | Bids are immutable after placement |
| Force loan default | Only time-based default, no admin trigger |
| Prevent repayment | `repayLoan` only requires NFT ownership |

### 6.3 Centralization Risk Timeline

Because the contracts are immutable, the only centralisation vector is the emergency pause power — there is no upgrade or timelock dimension to consider.

| Phase | Owner Setup | Upgrade Path | Risk Level |
|-------|-------------|--------------|------------|
| Deployment | 2-of-3 Gnosis Safe | None (immutable) | Reduced — owner can only pause |
| Post-launch | 2-of-3 Gnosis Safe | None | Reduced |
| Maturity | Pause renunciation under way | None | Minimal |
| Final state | Ownership renounced | None | None — no admin power remains |

---

## 7. Known Limitations & Accepted Risks

### 7.1 Accepted Risks

| Risk | Severity | Acceptance Rationale |
|------|----------|----------------------|
| Front-running bids | Medium | Inherent to public blockchains; no practical mitigation |
| Token blocklist (USDC) | Medium | External dependency; cannot prevent |
| Owner can pause | Medium | Necessary for emergency response; multi-sig mitigates; renunciation planned |
| No liquidation mechanism | Low | By design; fixed-term loans |

### 7.2 Explicitly Unsupported

| Feature | Status | Rationale |
|---------|--------|-----------|
| Fee-on-transfer tokens | Unsupported | Accounting complexity |
| Rebasing tokens | Unsupported | Collateral tracking issues |
| Partial loan repayment | Not implemented | Simplicity for Phase 1 |
| Variable rate loans | Not implemented | Future consideration |
| Cross-chain collateral | Not implemented | Phase 2-3 feature |

### 7.3 Documentation Requirements

The following must be communicated to users:

1. **Operator Approval Warning:** Approving an operator grants them significant control over your deposited collateral and positions.

2. **Token Compatibility:** Only use standard ERC-20 tokens. Fee-on-transfer and rebasing tokens are not supported.

3. **No Collateralization Guarantee:** The protocol does not enforce minimum collateralization. Lenders must evaluate collateral quality independently.

4. **Fixed-Term Loans:** Loans have fixed terms. There is no liquidation mechanism if collateral value drops.

5. **Direct Access:** Interacting with the core contracts directly bypasses the Curation Layer's whitelist and safety checks. Direct users are responsible for the tokens and parameters they choose.

---

## 8. Verification Checklist for Auditors

### 8.1 Access Control Verification

- [ ] All `*For()` functions verify operator approval
- [ ] No function modifies another user's balance without authorization
- [ ] Owner functions are protected by `onlyOwner`
- [ ] PositionNFT privileged functions are protected by `onlyLoanProtocol`

### 8.2 State Machine Verification

- [ ] Auction states can only progress forward
- [ ] Loan states can only progress forward
- [ ] No state can be skipped
- [ ] Time boundaries are correctly implemented with `>=`

### 8.3 Token Handling Verification

- [ ] All ERC-20 transfers use SafeERC20
- [ ] All ERC-721 transfers use `safeTransferFrom`
- [ ] Balance checks occur before deductions
- [ ] CEI pattern followed in all functions

### 8.4 Economic Invariants

- [ ] Total collateral in contract = sum of (user balances + locked in auctions + locked in loans)
- [ ] Total escrowed bids = sum of all active auction `currentBid` amounts
- [ ] All position NFTs map to exactly one active loan
- [ ] Escrow cannot be double-spent

### 8.5 Cross-Contract Verification

- [ ] ListingService cannot escalate privileges beyond operator approval
- [ ] PositionNFT cannot be manipulated by external contracts
- [ ] Fee collection cannot be bypassed within ListingService flow

---

## 9. Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Feb 2026 | Initial document (pre-audit preparation) |
| 2.0 | Jun 2026 | Updated to deployed reality: contracts confirmed **non-upgradeable** (ERC1967 + non-UUPS, no upgrade path); owner is the 2-of-3 Gnosis Safe with the deployer renounced; removed the upgrade capability and the incorrect owner-settable grace-period row; added the "owner cannot upgrade" assurance; populated mainnet addresses; added direct-access risk note. |

---

## Appendix A: Contract Addresses (Arbitrum One)

| Contract | Address |
|----------|---------|
| LoanProtocol | `0xFCDd6Ef75638D8D19ad634004C234Ad18751fEf2` |
| NFTLoanProtocol | `0x506e414c7D39639B2E9E318C46eD378AD51147eb` |
| PositionNFT | `0xAD6Edb72409605a51dc6C990A09829616178A8f4` |
| NFTPositionNFT | `0x9A1728C87ac0456cCd882b5D5637e856be0fEec8` |
| ListingService | `0x22B2C327Ed73da9e32a3eEB9DcBaa9AEBD8BD0d8` |
| NFTListingService | `0x43fD6Fda249820D98BC34733D4B5c896c613C674` |
| Owner (2-of-3 Gnosis Safe) | `0x71D81eb872FBDD93B1196fF3738230FCBfa9206b` |

Verified source for every contract is available on Arbiscan. See [Deployed Contracts](deployed-contracts.md) for direct links.

---

## Appendix B: Key Security Fixes Implemented

### B.1 Authorization Vulnerability Fix (Critical - Resolved)

**Original Issue:** `createAuctionFor` had no access control, allowing anyone to steal deposited collateral.

**Fix Implemented:** Operator approval pattern requiring explicit user consent.

```solidity
// BEFORE (Vulnerable)
function createAuctionFor(address borrower, address collateralFrom, ...) external {
    // NO CHECK - anyone could call with any addresses
}

// AFTER (Secure)
function createAuctionFor(address borrower, address collateralFrom, ...) external {
    if (msg.sender != collateralFrom && !operatorApprovals[collateralFrom][msg.sender]) {
        revert UnauthorizedOperator();
    }
    // ... rest of function
}
```

**Verification:** This fix has been applied to both `LoanProtocol.sol` and `NFTLoanProtocol.sol`.

### B.2 Pull-Based Refunds (DoS Mitigation)

**Original Issue:** Push-based refunds could be blocked by malicious contracts.

**Fix Implemented:** Pull-based refund pattern using `pendingRefunds` mapping.

```solidity
// Refunds queued for pull
pendingRefunds[previousBidder][loanToken] += previousBid;

// User claims via separate function
function claimRefund(address token) external nonReentrant {
    uint256 amount = pendingRefunds[msg.sender][token];
    if (amount == 0) revert NoRefundAvailable();
    pendingRefunds[msg.sender][token] = 0;
    IERC20(token).safeTransfer(msg.sender, amount);
}
```

### B.3 Offer Limit (DoS Mitigation)

**Original Issue:** Unlimited offers could cause gas griefing on bulk operations.

**Fix Implemented:** `MAX_OFFERS_PER_LISTING = 50`

---

**Repository:** https://github.com/JamieFrame/The-Gavel-Protocol
**Security contact:** security@thegavel.io
