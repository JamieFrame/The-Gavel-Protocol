# The Gavel Protocol

**Oracle-free lending with auction-based rate discovery on Arbitrum.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue.svg)](https://docs.soliditylang.org/)
[![Arbitrum](https://img.shields.io/badge/Network-Arbitrum-blue.svg)](https://arbitrum.io/)

---

## Important Notice

The Gavel Protocol is open-source software published under the MIT licence. It is not a financial service, financial product, or investment offering. The protocol is a set of autonomous smart contracts deployed on Arbitrum One. No entity custodies user funds, executes transactions on users' behalf, or makes lending decisions for any user.

Users interact directly with the deployed smart contracts through their own wallets. Borrowers deposit their own collateral. Lenders place their own bids. The protocol has no operator with the ability to seize user funds or modify active loans.

Nothing in this repository constitutes investment, financial, legal, or tax advice. Use of the protocol is at the user's sole risk and subject to the terms of the MIT licence.

## What is The Gavel?

The Gavel is a peer-to-peer lending protocol where interest rates are discovered through competitive auctions — not set by algorithms, oracles, or governance votes.

Borrowers deposit collateral and create loan auctions. Lenders compete by offering progressively lower repayment amounts. The best bid wins. The market sets the rate.

**No oracles. No price feeds. No liquidation bots.** The lenders *are* the price discovery mechanism.

Every completed auction produces a data point — a market-discovered interest rate at a specific duration and collateral level. Plot enough of these and you get something that doesn't exist anywhere in crypto yet: an authoritative, market-driven Bitcoin credit yield curve.

## Why Oracle-Free?

Most DeFi lending protocols rely on price oracles — external data feeds that tell the smart contract what an asset is worth. Oracle manipulation has caused hundreds of millions in losses across DeFi through flash loan attacks, stale price feeds, and frontrunning.

The Gavel eliminates this entire attack surface. There are no price feeds in the smart contracts. Lenders express their own view of collateral value through their bids. The protocol has zero dependency on external data and cannot be manipulated by oracle attacks because there are no oracles to attack.

The trade-off: loans are originated through auctions (which take time) rather than instant pool-based lending. For borrowers who don't need instant liquidity, this delivers better security and genuinely market-driven rates.

## Architecture

The protocol uses a two-layer architecture:

```
┌─────────────────────────────────────────────────────┐
│  CURATION LAYER (Optional)                          │
│                                                     │
│  ListingService / NFTListingService                 │
│  • Token and NFT collection whitelisting            │
│  • UX convenience (curated token lists)             │
│  • Zero fees at launch                              │
│  • Requires operator approval from user             │
└──────────────────────┬──────────────────────────────┘
                       │ calls
                       ▼
┌─────────────────────────────────────────────────────┐
│  CORE PROTOCOL LAYER (Permissionless)               │
│                                                     │
│  LoanProtocol / NFTLoanProtocol                     │
│  • Collateral deposit and withdrawal                │
│  • Auction creation and bidding                     │
│  • Loan lifecycle (origination → repayment/default) │
│  • Integrated position marketplace                  │
│  • Position NFT minting via PositionNFT contracts   │
│                                                     │
│  Anyone can interact directly — no frontend needed  │
└─────────────────────────────────────────────────────┘
```

### Contract Overview

| Contract | Purpose | Description |
|----------|---------|-------------|
| **LoanProtocol.sol** | Core lending | ERC-20 collateral auctions, bidding, loans, marketplace |
| **NFTLoanProtocol.sol** | NFT lending | Same mechanics for NFT-collateralised loans |
| **PositionNFT.sol** | Position tokens | Mints borrower/lender NFTs for ERC-20 loans |
| **NFTPositionNFT.sol** | Position tokens | Mints borrower/lender NFTs for NFT loans |
| **ListingService.sol** | Curation | Token whitelisting for ERC-20 lending |
| **NFTListingService.sol** | Curation | NFT collection whitelisting |

All contracts are upgradeable (UUPS/Transparent proxy pattern via OpenZeppelin) and pausable by the owner (intended to transition to a multi-sig).

## Key Features

- **Auction-based rate discovery** — Every loan starts as a reverse auction. Lenders compete to offer the best rate.
- **Oracle-free design** — Zero external data dependencies. No price feeds, no liquidation bots.
- **Fixed-term loans** — Borrowers know exactly what they owe and when. No variable rates or surprise liquidations.
- **Position NFTs** — Every loan mints tradeable borrower and lender position NFTs.
- **Integrated marketplace** — Buy, sell, and trade lending positions on-chain. Supports listings, offers, and counter-offers.
- **Pull-based refunds** — Outbid lenders claim refunds at their convenience (DoS-resistant).
- **ERC-20 and NFT collateral** — Borrow against fungible tokens or NFTs through parallel protocol instances.
- **Zero fees** — The protocol is free to use. No listing fees, no transaction fees.

## Documentation

| Document | Description |
|----------|-------------|
| [Integration Guide](docs/INTEGRATION.md) | How to interact with the protocol programmatically |
| [Auction Lifecycle](docs/AUCTION_LIFECYCLE.md) | Complete walkthrough of auction and loan mechanics |
| [Security](docs/SECURITY.md) | Trust assumptions, audit status, and threat model |
| [Deployment](docs/DEPLOYMENT.md) | Contract addresses, deployment, and verification |
| [Audit Report](docs/Gavel_Protocol_Comprehensive_Security_Audit.pdf) | Sherlock audit findings and resolutions |
| [Trust Assumptions](docs/Trust_Assumptions_Document.md) | Reference document for auditors and integrators |

## Contract Addresses

### Arbitrum One (Mainnet)

| Contract | Address |
|----------|---------|
| LoanProtocol (proxy) | `0xFCDd6Ef75638D8D19ad634004C234Ad18751fEf2` |
| PositionNFT (proxy) | `0xAD6Edb72409605a51dc6C990A09829616178A8f4` |
| ListingService (proxy) | `0x22B2C327Ed73da9e32a3eEB9DcBaa9AEBD8BD0d8` |
| NFTLoanProtocol (proxy) | `0x506e414c7D39639B2E9E318C46eD378AD51147eb` |
| NFTPositionNFT (proxy) | `0x9A1728C87ac0456cCd882b5D5637e856be0fEec8` |
| NFTListingService (proxy) | `0x43fD6Fda249820D98BC34733D4B5c896c613C674` |

Admin: 2-of-3 Gnosis Safe at `0x71D81eb872FBDD93B1196fF3738230FCBfa9206b`

### Arbitrum Sepolia (Testnet)


| Contract | Address |
|----------|---------|
| LoanProtocol | `0xF8aD34DeEe0Ac52b16d4dD30E3c4b11D8f117884` |
| PositionNFT | `0x9cB62E16E99C2542A149D252Ccf1881887A15cb9` |
| ListingService | `0x5735bA0a688Ac93d13cD843C9354A1CaBC3B1914` |
| NFTLoanProtocol | `0x7c9E345954D0998B2325575327aAF1B6E820ccCe` |
| NFTPositionNFT | `0x086A56121820F6374C7d7742478e33e92535bBfb` |
| NFTListingService | `0x5f118924c8F1c512e5cF675081a22519e01aA46E` |

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) for building and testing
- Node.js 18+ for frontend interaction
- An Arbitrum Sepolia wallet with testnet ETH

### Build

```bash
git clone https://github.com/JamieFrame/The-Gavel-Protocol.git
cd The-Gavel-Protocol
forge install
forge build
```

### Test

```bash
# Unit tests
forge test

# With gas reporting
forge test --gas-report

# Coverage
forge coverage
```

### Deploy (Testnet)

```bash
# Set environment variables
export PRIVATE_KEY=your_deployer_key
export ARBISCAN_API_KEY=your_api_key

# Deploy core contracts
forge script script/Deploy.s.sol --rpc-url arbitrum-sepolia --broadcast --verify
```

See [Deployment Guide](docs/DEPLOYMENT.md) for full deployment and verification instructions.

## Test Coverage

The protocol has been tested with:

- **411 unit tests** — 100% pass rate
- **59 fuzz test invariants** — Property-based testing across 50,000+ iterations
- **83 manual test cases** — End-to-end user flow verification on testnet
- **>80% line coverage** on all in-scope contracts (Sherlock audit requirement)

See the [Test Coverage Report](docs/TEST_COVERAGE.md) for detailed results.

## Security

The protocol has undergone:

- Comprehensive internal security review (see [Security Documentation](docs/SECURITY.md))
- Adversarial security review with systematic attack vector analysis
- Stateful invariant fuzz testing across 50,000+ iterations
- Independent security audit by [Sherlock](https://www.sherlock.xyz/) — completed April 2026. 9 Medium and 4 Low severity findings identified, all resolved prior to mainnet deployment. Zero High or Critical findings. The full audit report is available in [docs/Gavel_Protocol_Comprehensive_Security_Audit.md](docs/Gavel_Protocol_Comprehensive_Security_Audit.md).

See [Security Documentation](docs/SECURITY.md) for the full threat model, trust assumptions, and known limitations.

### Responsible Disclosure

If you discover a vulnerability, please report it responsibly. Contact: **security@thegavel.finance**

Do not open public issues for security vulnerabilities.

## How It Works (30-Second Version)

1. **Borrower** deposits WBTC collateral and creates an auction: "I want to borrow 10,000 USDC for 30 days."
2. **Lenders** compete by bidding lower repayment amounts. First bid: "I'll lend for 10,150 USDC repayment." Next bid: "I'll do it for 10,120 USDC."
3. **Auction ends**, best bid wins. Loan is created, borrower receives USDC, lender holds a Position NFT.
4. **Borrower repays** within 30 days to reclaim their WBTC. If they don't, the lender claims the collateral.
5. **Meanwhile**, the lender can sell their Position NFT on the marketplace if they want early liquidity.

Every auction = a data point on the yield curve. More auctions = richer credit market data.

## Contributing

The protocol smart contracts are open source under the MIT licence.

Issues and discussion are welcome via the GitHub issue tracker. For material code contributions, please open an issue to discuss the proposed change before submitting a pull request. Any contributed code will be licensed under the MIT licence on the same terms as the existing codebase, and contributors are deemed to assign their rights in the contributed code to the project on those terms.

Please ensure all existing tests pass and add tests for new functionality before submitting a PR.

## Authorship, Licence, and Scope

### Authorship

The Gavel Protocol smart contracts are authored by Jamie Frame.

### What is in this repository (MIT licensed)

This repository contains the canonical smart contract implementation of The Gavel Protocol — the core protocol contracts, position NFT contracts, curation layer contracts, interface definitions, and technical documentation. All code in this repository is published under the [MIT licence](LICENSE) and may be used, modified, and redeployed by any party in accordance with that licence.

### What is NOT in this repository

The following components are not part of the open-source release and remain proprietary:

- Frontend web application (thegavel.finance)
- Event indexer and data pipeline
- Auction analytics, indicator computation, and yield curve methodology
- Public data API and MCP server
- Commercial documentation and marketing materials

These are operated by Aletheia Analytics SASU as the commercial reference deployment. Any third party may fork this repository and deploy their own instance of the protocol without using or referencing these proprietary components.

### Trademarks

"The Gavel" and "The Gavel Protocol" are trademarks (EUTM application 019366213, filed 18 May 2026). The MIT licence covers the source code only and does not grant any right to use these trademarks. Forks and derivative deployments must use different names to distinguish them from the canonical project.

## Links

- **Website:** [thegavel.finance](https://thegavel.finance)
- **Mainnet App:** [thegavel.io](https://thegavel.io)
- **Testnet App:** [testnet.thegavel.io](https://testnet.thegavel.io)
- **Substack:** [The Credit Surface](https://thegavelfinance.substack.com/)
- **Twitter/X:** [@GavelFinance](https://x.com/GavelFinance)

---

*Authored by [Jamie Frame](https://x.com/GavelFinance)*