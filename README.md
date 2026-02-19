# The Gavel Protocol

**Oracle-free lending with auction-based rate discovery on Arbitrum.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue.svg)](https://docs.soliditylang.org/)
[![Arbitrum](https://img.shields.io/badge/Network-Arbitrum-blue.svg)](https://arbitrum.io/)

---

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

## Contract Addresses

### Arbitrum Sepolia (Testnet)

| Contract | Address |
|----------|---------|
| LoanProtocol | `0xF8aD34DeEe0Ac52b16d4dD30E3c4b11D8f117884` |
| PositionNFT | `0x9cB62E16E99C2542A149D252Ccf1881887A15cb9` |
| ListingService | `0x5735bA0a688Ac93d13cD843C9354A1CaBC3B1914` |
| NFTLoanProtocol | `0x7c9E345954D0998B2325575327aAF1B6E820ccCe` |
| NFTPositionNFT | `0x086A56121820F6374C7d7742478e33e92535bBfb` |
| NFTListingService | `0x5f118924c8F1c512e5cF675081a22519e01aA46E` |

### Arbitrum One (Mainnet)

Deployment pending completion of security audit.

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) for building and testing
- Node.js 18+ for frontend interaction
- An Arbitrum Sepolia wallet with testnet ETH

### Build

```bash
git clone https://github.com/thegavel/protocol.git
cd protocol
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

The protocol has undergone extensive internal security review:

- Comprehensive security documentation and threat modelling
- Adversarial security review with systematic attack vector analysis
- Fuzz testing with stateful invariant verification
- Trust assumptions document for auditor reference

**External audit status:** [In progress with Sherlock]

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

The protocol smart contracts are open source under the MIT licence. Contributions are welcome.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes (`git commit -m 'Add improvement'`)
4. Push to the branch (`git push origin feature/improvement`)
5. Open a Pull Request

Please ensure all tests pass before submitting a PR.

## Licence

Smart contracts: [MIT](LICENSE)

The Gavel name, logo, and associated branding are trademarks of The Gavel Protocol.

## Links

- **Website:** [thegavel.finance](https://thegavel.finance)
- **Testnet App:** [thegavel.io](https://thegavel.io)
- **Substack:** [The Credit Surface](https://thegavelfinance.substack.com/)
- **Twitter/X:** [@GavelFinance](https://x.com/GavelFinance)

---

*Built by [Jamie Frame](https://x.com/GavelFinance)*
