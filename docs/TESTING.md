# Testing

The Gavel Protocol contracts are tested with [Foundry](https://book.getfoundry.sh/). This document explains how to run the suite, how it is organised, and the coverage it achieves against the deployed contracts.

## Running the suite

```bash
forge install        # fetch pinned dependencies (forge-std, OpenZeppelin v5.0.0)
forge build          # compile contracts + tests
forge test           # run the full unit suite
```

Coverage (uses `--ir-minimum` to avoid "stack too deep" during instrumentation):

```bash
forge coverage --ir-minimum --report summary
```

## Toolchain

| Component | Version |
|---|---|
| Solidity | 0.8.20 (`via_ir = true`) |
| OpenZeppelin Contracts / Upgradeable | 5.0.0 |
| forge-std | (pinned in `.gitmodules`) |

The source in `contracts/` and the OpenZeppelin version are identical to those of the deployed, verified contracts on Arbitrum One. The deployed implementations were compiled with **solc 0.8.24** (`via_ir`, 200 optimizer runs), as recorded on Sourcify; this repository pins 0.8.20. Behaviour is the same, but gas figures differ slightly between the two compilers. To reproduce deployed gas figures, run with the deployed compiler:

```bash
forge test --use 0.8.24
```

## Layout

```
contracts/                     # the deployed protocol source (unit under test)
test/
├── unit/                      # per-contract unit suites
│   ├── LoanProtocol.core.t.sol            # ERC-20 lending: deposits, auctions, bids, loans
│   ├── LoanProtocol.marketplace.t.sol     # ERC-20 position marketplace
│   ├── ListingService.unit.t.sol          # ERC-20 Curation Layer
│   ├── PositionNFT.unit.t.sol             # ERC-20 position NFT
│   ├── NFTLoanProtocol.core.t.sol         # NFT-collateralised lending
│   ├── NFTLoanProtocol.marketplace.t.sol  # NFT position marketplace
│   ├── NFTListingService.unit.t.sol       # NFT Curation Layer
│   └── NFTPositionNFT.unit.t.sol          # NFT position NFT
├── security/                  # reproductions of known issues (see known-issues.md)
│   └── SR1_Marketplace.t.sol              # KI-1, KI-2 on both protocol families
└── utils/                     # shared test harnesses
    ├── TestSetup.sol          # deploys the ERC-20 protocol stack + funded actors
    └── NFTTestSetup.sol       # deploys the NFT protocol stack + funded actors
```

Each protocol family (ERC-20-collateralised and NFT-collateralised) is split into a **core** suite (collateral, auctions, bidding, loan lifecycle, default) and a **marketplace** suite (listing, offers, counter-offers, buys, MEV-protection parameters), plus dedicated suites for the Curation Layer and the position NFT. The two `TestSetup` harnesses deploy the contracts behind minimal ERC1967 proxies — mirroring the real deployment — and expose helper flows (`_createActiveLoan`, `_createDefaultedLoan`, etc.) used across the suites.

## Headline numbers

- **472 tests, 0 failing** (`forge test`): 448 unit tests plus 24 known-issue reproductions in `test/security/`.

Line coverage by contract (`forge coverage --ir-minimum`):

| Contract | Lines | Functions |
|---|---|---|
| `LoanProtocol.sol` | 87.8% | 93.7% |
| `ListingService.sol` | 92.1% | 100% |
| `PositionNFT.sol` | 94.4% | 94.7% |
| `NFTLoanProtocol.sol` | 92.9% | 97.9% |
| `NFTListingService.sol` | 93.3% | 100% |
| `NFTPositionNFT.sol` | 73.5% | 96.6% |

The lower line coverage on `NFTPositionNFT` is concentrated in its on-chain metadata / `tokenURI` rendering paths; its privileged state-changing functions are fully exercised. Branch coverage is lower than line coverage on the two `LoanProtocol` contracts because several branches are defensive reverts on states unreachable through the public API.

## Relationship to the external audit

These are unit tests that exercise the **deployed contracts** (the `contracts/` source here is byte-identical to the audited source and corresponds to what is verified on Arbiscan — see [Deployed Contracts](deployed-contracts.md)). They are the project's maintained unit-test suite; they are **not** the external Sherlock audit itself. The independent Sherlock collaborative audit (finalised April 2026) is published separately under [`audit/`](audit/).
