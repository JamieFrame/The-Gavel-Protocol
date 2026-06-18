# Deployed Contracts — Arbitrum One

**Network:** Arbitrum One (chain ID 42161)
**Deployed:** 6 May 2026
**Administration:** all six contracts are owned by a 2-of-3 Gnosis Safe (below). The deployer account has no remaining admin power.

> **Immutability.** Every contract is deployed behind a minimal ERC1967 proxy, and the implementations are **not** UUPS — they contain no upgrade function. The business logic therefore cannot be changed by anyone, including the authors. The only retained on-chain powers are: emergency `pause`/`unpause`, the Curation Layer's whitelist and fee configuration (ListingService / NFTListingService), and `setBaseURI` for position-NFT metadata. None of these can alter loan terms, balances, or contract logic.

## Core contracts (ERC-20 collateralised lending)

| Contract | Proxy (use this address) | Verified source |
|---|---|---|
| LoanProtocol | `0xFCDd6Ef75638D8D19ad634004C234Ad18751fEf2` | [Arbiscan](https://arbiscan.io/address/0xFCDd6Ef75638D8D19ad634004C234Ad18751fEf2#code) |
| PositionNFT | `0xAD6Edb72409605a51dc6C990A09829616178A8f4` | [Arbiscan](https://arbiscan.io/address/0xAD6Edb72409605a51dc6C990A09829616178A8f4#code) |
| ListingService (Curation Layer) | `0x22B2C327Ed73da9e32a3eEB9DcBaa9AEBD8BD0d8` | [Arbiscan](https://arbiscan.io/address/0x22B2C327Ed73da9e32a3eEB9DcBaa9AEBD8BD0d8#code) |

## NFT-collateralised lending

| Contract | Proxy (use this address) | Verified source |
|---|---|---|
| NFTLoanProtocol | `0x506e414c7D39639B2E9E318C46eD378AD51147eb` | [Arbiscan](https://arbiscan.io/address/0x506e414c7D39639B2E9E318C46eD378AD51147eb#code) |
| NFTPositionNFT | `0x9A1728C87ac0456cCd882b5D5637e856be0fEec8` | [Arbiscan](https://arbiscan.io/address/0x9A1728C87ac0456cCd882b5D5637e856be0fEec8#code) |
| NFTListingService (Curation Layer) | `0x43fD6Fda249820D98BC34733D4B5c896c613C674` | [Arbiscan](https://arbiscan.io/address/0x43fD6Fda249820D98BC34733D4B5c896c613C674#code) |

> NFT-collateralised lending is live, but no NFT collection is whitelisted in the Curation Layer at launch. Direct callers may still use the core contracts with any collection.

## Tokens (reference)

These are the tokens curated in the interface at launch. The protocol itself accepts **any** ERC-20 — these addresses are provided for convenience only.

| Token | Address | Decimals |
|---|---|---|
| USDC (native) | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | 6 |
| USDT | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` | 6 |
| WBTC | `0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f` | 8 |

## Administration

| Role | Address |
|---|---|
| Owner (2-of-3 Gnosis Safe) | `0x71D81eb872FBDD93B1196fF3738230FCBfa9206b` |

Each proxy also has a fixed implementation address; because the contracts are non-upgradeable, the implementation cannot change. Implementation addresses are recorded in the deployment artifacts and can be read from each proxy on Arbiscan.
