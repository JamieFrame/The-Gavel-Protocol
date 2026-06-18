# Security

## Reporting a vulnerability

If you believe you have found a security vulnerability in The Gavel Protocol's deployed contracts, please report it by email to **security@thegavel.io**.

Please include enough detail to reproduce and assess the issue (affected contract and function, conditions, and where possible a proof of concept), and please give us a reasonable opportunity to investigate and respond before any public disclosure.

There is no formal bug-bounty programme at this time. Responsible disclosure is nonetheless welcomed and appreciated.

## Scope

In scope: the deployed contracts listed in [Deployed Contracts](docs/deployed-contracts.md).

Out of scope: the hosted interface and any third-party frontends, infrastructure, or data services; issues that require control of a user's wallet or keys; and general market or economic risks inherent to permissionless lending.

## Audit and design

The contracts were reviewed in a Sherlock collaborative audit, finalised 15 April 2026. The full report is published at [`docs/audit/2026-04-15-Sherlock-Collaborative-Audit.pdf`](docs/audit/2026-04-15-Sherlock-Collaborative-Audit.pdf).

The contracts are immutable: deployed behind minimal ERC1967 proxies with non-UUPS implementations, they have no upgrade path. Fixes to the protocol logic are delivered by deploying new, separate contracts (a "redeploy-as-v2" model), not by upgrading the live ones. The only retained on-chain powers are emergency pause/unpause, Curation-Layer whitelist/fee configuration, and position-NFT metadata — none of which can alter loan terms, balances, or logic. See [Deployed Contracts](docs/deployed-contracts.md) for detail.
