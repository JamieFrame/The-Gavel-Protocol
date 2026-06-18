# The Gavel Protocol

**Oracle-free, permissionless, auction-based lending on Arbitrum One.**

Borrowers post collateral and open a reverse auction for a loan; lenders compete by bidding down the repayment they require; the interest rate is discovered by the auction rather than set by an oracle or an administrator. Both sides of every loan are represented as transferable position NFTs and can be traded on a built-in secondary market. The protocol is oracle-free and accepts **any ERC-20 token** as collateral or loan asset — it is used primarily for Bitcoin-collateralised credit (e.g. WBTC), but enforces no asset restriction at the contract level.

## Key properties

- **Oracle-free** — rates are set by competitive auction, not price feeds. No oracle dependency, no liquidations.
- **Permissionless** — anyone can interact with the contracts directly, with any ERC-20. No gatekeeper.
- **Immutable (non-upgradeable)** — deployed behind minimal ERC1967 proxies with non-UUPS implementations; there is no upgrade function and no proxy-admin upgrade authority. The logic cannot be changed by anyone, including the authors.
- **Audited** — reviewed in a Sherlock collaborative audit, finalised April 2026.
- **MIT licensed** — see [`LICENSE`](LICENSE).

## Architecture

The protocol is a set of immutable smart contracts in two parallel families — ERC-20-collateralised lending (`LoanProtocol`, `PositionNFT`, `ListingService`) and NFT-collateralised lending (`NFTLoanProtocol`, `NFTPositionNFT`, `NFTListingService`).

The **core** contracts (`LoanProtocol` / `NFTLoanProtocol`) are fully permissionless and accept any asset. The **Curation Layer** (`ListingService` / `NFTListingService`) is an *optional* convenience layer that adds a curated token/collection whitelist and fee configuration on top of the core; the hosted interface routes through it, but direct callers bypass it entirely. Positions are minted as ERC-721 NFTs by the `PositionNFT` contracts.

For the full mechanism and threat model see:
- [Auction Lifecycle](docs/AUCTION_LIFECYCLE.md) — how auctions, loans, and position trading work end to end.
- [Trust Assumptions & Security Model](docs/Trust_Assumptions_Document.md) — trust hierarchy, owner powers, external-dependency assumptions, and a contract dependency diagram.

## Deployed contracts

All contracts are live on **Arbitrum One** and owned by a 2-of-3 Gnosis Safe with the deployer renounced. Authoritative addresses and verified-source links are in **[Deployed Contracts](docs/deployed-contracts.md)**.

## Quickstart

The contracts are built and tested with [Foundry](https://book.getfoundry.sh/).

```bash
git clone https://github.com/JamieFrame/The-Gavel-Protocol.git
cd The-Gavel-Protocol
forge install      # fetch dependencies
forge build        # compile
forge test         # run the test suite
```

The Solidity source lives in [`contracts/`](contracts/); tests are in [`test/`](test/). See [Testing](docs/TESTING.md) for the suite layout, coverage, and how to reproduce the audited results.

## Using the protocol

The hosted interface at [thegavel.io](https://thegavel.io) is **one** way to access the protocol — provided as a convenience, presenting a curated token set and a guided UI. It is not the only way and is not required.

To interact with the deployed contracts **directly** — with any ERC-20 and no curation — follow the **[Direct Access Guide](docs/direct-access-guide.md)**. This is the permissionless path and is fully supported.

## Audit

The protocol's contracts were reviewed in a Sherlock collaborative audit, finalised 15 April 2026. The full report is published in this repository:

- [`docs/audit/2026-04-15-Sherlock-Collaborative-Audit.pdf`](docs/audit/2026-04-15-Sherlock-Collaborative-Audit.pdf)

## Security

Responsible-disclosure policy and contact are in [`SECURITY.md`](SECURITY.md). To report a vulnerability, email **security@thegavel.io**.

## Disclaimer

The Gavel Protocol is not a deposit-taking institution, a broker, a custodian, or an investment adviser, and holds no view on whether any token, loan, or position is suitable for you. Interacting with the protocol — especially directly — carries risk, including the total loss of funds. The protocol is oracle-free and does not enforce collateralisation ratios; lenders must evaluate collateral quality themselves. Nothing in this repository is financial, legal, or investment advice. The Token Curation Methodology and Risk Disclaimers are published separately.

## Licence

Released under the MIT Licence. See [`LICENSE`](LICENSE).
