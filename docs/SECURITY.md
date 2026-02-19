# Security

Trust assumptions, threat model, audit status, and known limitations of The Gavel Protocol.

---

## Table of Contents

- [Security Philosophy](#security-philosophy)
- [Audit Status](#audit-status)
- [Architecture and Trust Hierarchy](#architecture-and-trust-hierarchy)
- [Trust Assumptions by Contract](#trust-assumptions-by-contract)
- [External Dependency Assumptions](#external-dependency-assumptions)
- [Economic and Game-Theoretic Model](#economic-and-game-theoretic-model)
- [Attack Surface Analysis](#attack-surface-analysis)
- [Known Limitations](#known-limitations)
- [Security Measures Implemented](#security-measures-implemented)
- [Responsible Disclosure](#responsible-disclosure)

---

## Security Philosophy

The Gavel Protocol is designed around a core principle: **eliminate external trust dependencies wherever possible.**

Traditional DeFi lending protocols depend on price oracles, liquidation bots, and algorithmic rate-setters. Each is an attack surface. The Gavel replaces all three with a single mechanism — competitive auctions where lenders express their own valuation of collateral through their bids.

The result is a protocol with a deliberately narrow attack surface: no oracles to manipulate, no liquidation logic to exploit, no external data feeds to corrupt. The trade-off is that loans take time to originate (auctions must run) rather than being instant.

---

## Audit Status

| Audit | Auditor | Status | Report |
|-------|---------|--------|--------|
| Competitive audit | Sherlock | Pending | [Link when available] |

### Pre-Audit Security Work

Before the external audit, the protocol underwent:

- **Comprehensive security documentation** — Function-by-function security analysis of all contracts, documenting access control, reentrancy protection, and CEI (Checks-Effects-Interactions) compliance.
- **Adversarial security review** — Systematic analysis of cross-contract attack vectors, economic attacks, and flash loan considerations.
- **Trust assumptions document** — Explicit enumeration of every trust assumption, intended for auditor reference.
- **Fuzz testing** — 59 property-based invariant tests run across 50,000+ iterations per test, covering collateral conservation, bid monotonicity, loan state transitions, and marketplace offer lifecycle.
- **411 unit tests** — >80% line coverage on all six in-scope contracts.
- **83 manual test cases** — End-to-end user flow testing on Arbitrum Sepolia testnet.

---

## Architecture and Trust Hierarchy

### Trust Levels

| Level | Entities | Privileges |
|-------|----------|------------|
| **Owner** | Protocol deployer (→ multi-sig post-launch) | Pause/unpause, whitelist tokens, adjust fees, upgrade proxies |
| **Authorised Operator** | ListingService, NFTListingService | Call `*For()` functions on behalf of users who have granted approval |
| **User** | Any EOA or contract | Deposit, withdraw, create auctions, bid, trade positions |
| **External** | ERC-20/ERC-721 token contracts | Token transfer mechanics |

### Privilege Escalation Path

```
Owner (single EOA at launch)
  → Gnosis Safe multi-sig (2-of-3 or 3-of-5)
    → Multi-sig + timelock
      → Ownership renouncement (long-term goal)
```

The protocol is designed to operate fully autonomously. Owner privileges exist for emergency pausing and initial configuration, not for ongoing operation.

### Owner Capabilities and Risks

| Capability | Risk if Compromised | Planned Mitigation |
|------------|--------------------|--------------------|
| `pause()` / `unpause()` | Protocol halt (temporary DoS) | Multi-sig + timelock |
| Proxy upgrade | Complete protocol compromise | Multi-sig + timelock, eventual renouncement |
| Whitelist management | Malicious tokens added | Multi-sig review process |
| Fee parameter changes | Unexpected user costs (currently 0) | Multi-sig + timelock |

**Important:** The owner cannot access, move, or redirect user funds. Owner privileges are limited to protocol configuration and emergency controls.

---

## Trust Assumptions by Contract

### LoanProtocol / NFTLoanProtocol

**Assumption 1: Owner is trusted (until multi-sig)**

The single EOA owner will not maliciously pause the protocol or upgrade to malicious logic. This assumption is acceptable pre-launch but must be replaced with multi-sig governance before mainnet.

**Assumption 2: Operator approval is user-controlled**

Only `msg.sender` can grant or revoke operator status for their own address. No external party can grant themselves operator access. The check:

```solidity
if (msg.sender != collateralFrom && !operatorApprovals[collateralFrom][msg.sender]) {
    revert UnauthorizedOperator();
}
```

**Assumption 3: PositionNFT is trusted**

The protocol assumes the PositionNFT contract correctly restricts minting, burning, and protocol transfers to the LoanProtocol address. Both contracts are deployed by the same deployer with verified source code.

### ListingService / NFTListingService

**Assumption 4: Protocol reference is immutable**

The `loanProtocol` address is set once during initialisation and cannot be changed. The ListingService cannot redirect calls to a malicious contract.

**Assumption 5: Treasury is honest**

The treasury address will not reject incoming transfers (which would cause DoS on fee collection). Treasury should be an EOA or non-reverting multi-sig. At launch, fees are zero so this assumption has no practical impact.

### PositionNFT / NFTPositionNFT

**Assumption 6: Only protocol performs privileged operations**

Minting, burning, and `protocolTransfer()` are restricted to the `loanProtocol` address via the `onlyLoanProtocol` modifier. This address cannot be changed after initialisation.

---

## External Dependency Assumptions

### ERC-20 Tokens

| Assumption | Status | Impact if Violated |
|------------|--------|-------------------|
| Tokens return true or revert on transfer | Handled | SafeERC20 handles non-standard returns |
| No fee-on-transfer mechanics | Documented | Collateral accounting mismatch |
| No rebasing mechanics | Documented | Collateral accounting mismatch |
| Transfer does not callback (not ERC-777) | Partial | Reentrancy guard protects core paths |
| Token is not pausable | External risk | Transfer failures during loan resolution |
| Token does not have blocklist | External risk | USDC blocklist could prevent operations |

**Explicitly unsupported token types:**

1. Fee-on-transfer tokens (e.g., PAXG with 0.02% fee)
2. Rebasing tokens (e.g., stETH, AMPL)
3. Tokens with transfer callbacks that modify protocol state

The whitelist mechanism provides a control point to exclude problematic tokens.

### ERC-721 Tokens (NFTLoanProtocol)

| Assumption | Status | Impact if Violated |
|------------|--------|-------------------|
| NFT implements standard ERC-721 | Required | `safeTransferFrom` will fail |
| NFT `onERC721Received` callback is safe | Partial | Reentrancy guard protects |
| NFT is not pausable/frozen | External risk | Collateral cannot be released |
| NFT ownership cannot be manipulated | External risk | Loan collateral at risk |

Whitelisted NFT collections are assumed to be legitimate and non-malicious.

### Arbitrum L2

| Assumption | Impact if Violated |
|------------|-------------------|
| `block.timestamp` accurate within ~24 hours | Auction timing manipulation |
| Transactions processed in order | Front-running (inherent to public blockchains) |
| Sequencer available | Protocol temporarily unusable |
| No L2 state rollback | Loan state corruption |

The protocol does not implement L2-specific mitigations beyond standard practices. Arbitrum is assumed to operate correctly as documented.

---

## Economic and Game-Theoretic Model

### Oracle-Free Collateralisation

This is the protocol's most significant design decision. Unlike Aave, Compound, or Maker, The Gavel does not enforce loan-to-value ratios and does not use price oracles.

| Traditional DeFi | The Gavel |
|------------------|-----------|
| Oracle determines collateral value | Market determines via auction bids |
| Protocol enforces LTV ratio | Any collateral amount accepted |
| Liquidation on undercollateralisation | Fixed-term loans, no liquidation |
| Liquidation bot infrastructure required | No infrastructure required |

**Trust assumption:** Lenders evaluate collateral quality themselves before bidding. The protocol provides no guarantee that collateral value exceeds loan value. This is by design — the market sets the price.

### Auction Mechanism

| Property | Basis |
|----------|-------|
| Lenders bid rationally to maximise returns | Economic incentive |
| Escrow prevents griefing bids | Funds locked on bid |
| Self-bidding prevented | `msg.sender != auction.borrower` check |
| Auction duration sufficient for price discovery | Configurable 1–72 hours |

### Marketplace Trading

| Property | Basis |
|----------|-------|
| Offer amounts are rational market prices | Escrow prevents spam |
| Expired offers are cleaned up | Permissionless expiration mechanism |
| Maturity buffer prevents late-stage manipulation | `MATURITY_BUFFER` constant |
| Offer spam capped | `MAX_OFFERS_PER_LISTING = 50` |

---

## Attack Surface Analysis

### Auction Manipulation

| Attack | Feasibility | Mitigation |
|--------|-------------|------------|
| Griefing bids | Low | Bids are escrowed — attacker loses capital |
| Bid sniping | Medium | Inherent to fixed-end auctions (no extension mechanism) |
| Self-bid manipulation | Impossible | Self-bid blocked in contract |
| Sybil bidding | Low value | Multiple addresses = multiple escrows, no benefit |
| Front-running | Medium | Inherent to public blockchains, not mitigated |

### Flash Loan Attacks

| Attack | Feasibility | Reason |
|--------|-------------|--------|
| Flash bid | Impossible | Funds must remain escrowed for auction duration |
| Flash collateral | Impossible | Collateral locked in auction |
| Flash position buy | Low value | No price oracle to manipulate |

Flash loan attacks are structurally ineffective against this protocol because there is no oracle to manipulate and no liquidation to trigger. The most profitable flash loan attacks in DeFi exploit price oracle dependencies — which this protocol does not have.

### Cross-Contract Vectors

| Vector | Risk | Status |
|--------|------|--------|
| PositionNFT `_safeMint` callback | Medium | Reentrancy guard protects |
| ListingService fee collection DoS | Low | Fees are zero; atomic collection |
| Malicious token `transfer` callback | Low | SafeERC20 + reentrancy guard |
| Proxy upgrade to malicious logic | High (if owner compromised) | Multi-sig planned |

### Denial of Service

| Vector | Mitigation |
|--------|------------|
| Push refund blocking (malicious contract) | Pull-based refund pattern |
| Offer spam on marketplace | MAX_OFFERS_PER_LISTING = 50 |
| Treasury revert blocking fees | Treasury is EOA; fees are zero |
| Block gas limit on loops | No unbounded loops in state-changing functions |

---

## Known Limitations

### By Design

1. **No instant lending.** Loans require an auction period. This is inherent to the auction-based rate discovery model.

2. **No automatic liquidation.** If collateral value drops below the loan value during the loan term, the protocol does not liquidate. The lender accepted this risk when they bid. The loan runs to maturity regardless of collateral value.

3. **Bid sniping.** Last-second bids cannot be countered. A time-extension mechanism (extending the auction when a late bid arrives) is considered for a future version.

4. **Front-running.** Lenders can observe pending bids in the mempool and front-run. This is inherent to public blockchain auctions. Arbitrum's sequencer provides some mitigation but does not eliminate this.

5. **No cross-collateral or cross-margin.** Each loan is independent. There is no portfolio-level margin or cross-collateralisation.

### External Risks

1. **USDC blocklist.** If Circle blocklists a borrower or lender address, USDC transfers to/from that address will fail. This could block loan repayment or collateral release. Mitigation: the marketplace allows selling positions to an unblocked address.

2. **Arbitrum sequencer downtime.** If the Arbitrum sequencer goes offline, no transactions can be processed. Auctions could expire without bids during downtime. The finalization window (7 days) and claim mechanism provide buffers.

3. **Upgradeable proxy risk.** Until ownership is renounced, the owner can upgrade contract logic. Multi-sig governance mitigates but does not eliminate this risk.

---

## Security Measures Implemented

### Smart Contract Level

| Measure | Implementation |
|---------|---------------|
| Reentrancy protection | `ReentrancyGuardUpgradeable` on all state-changing functions |
| Checks-Effects-Interactions | All external calls happen after state updates |
| Access control | `onlyOwner`, `onlyLoanProtocol`, operator approval checks |
| Safe token transfers | OpenZeppelin `SafeERC20` for all ERC-20 operations |
| Integer overflow protection | Solidity 0.8.20 built-in overflow checks |
| Pull-based refunds | Prevents DoS from malicious contracts blocking push refunds |
| Offer limits | `MAX_OFFERS_PER_LISTING = 50` prevents gas griefing |
| Self-bid prevention | Borrower cannot bid on their own auction |
| Maturity buffer | Marketplace frozen near loan maturity |
| Finalization window | 7-day window with fallback claim mechanism |
| Pausability | Emergency pause capability on all contracts |

### Operational Level

| Measure | Status |
|---------|--------|
| Multi-sig ownership | Planned for mainnet |
| Timelock on admin functions | Planned for mainnet |
| Contract verification on Arbiscan | All contracts verified |
| Open-source code | MIT licence |
| Comprehensive test suite | 411 unit tests, 59 fuzz invariants |

---

## Responsible Disclosure

If you discover a security vulnerability in The Gavel Protocol, please report it responsibly.

**Contact:** security@thegavel.finance

**Please:**
- Do not open public GitHub issues for security vulnerabilities
- Provide sufficient detail to reproduce the issue
- Allow reasonable time for a fix before public disclosure
- Do not exploit the vulnerability on mainnet

We will acknowledge receipt within 48 hours and aim to provide an initial assessment within 5 business days.

**Scope:** Smart contract vulnerabilities, access control bypasses, economic exploits, and denial-of-service vectors. Frontend-only issues (XSS, CSRF) are appreciated but lower priority.

---

*This document is maintained alongside the codebase and updated with each significant protocol change. Last updated: February 2026.*
