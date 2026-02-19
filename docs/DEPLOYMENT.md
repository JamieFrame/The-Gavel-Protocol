# Deployment and Verification

Contract addresses, deployment procedure, and verification instructions for The Gavel Protocol.

---

## Table of Contents

- [Contract Addresses](#contract-addresses)
- [Deployment Order](#deployment-order)
- [Deployment Scripts](#deployment-scripts)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Verification](#verification)
- [Mainnet Migration](#mainnet-migration)
- [Local Development](#local-development)
- [Environment Setup](#environment-setup)

---

## Contract Addresses

### Arbitrum Sepolia (Testnet)

| Contract | Address | Proxy Type |
|----------|---------|------------|
| LoanProtocol | `0x5B54...742e` | Transparent Proxy |
| PositionNFT | `0x272B...90dF` | Transparent Proxy |
| ListingService | `0x9108...836e` | Transparent Proxy |
| NFTLoanProtocol | `0x2FB7...0Ba75` | Transparent Proxy |
| NFTPositionNFT | `0xDCBD...0aab` | Transparent Proxy |
| NFTListingService | `0xBAf0...9C57` | Transparent Proxy |

### Arbitrum One (Mainnet)

Deployment pending completion of security audit. Addresses will be published here once deployed.

### Supported Tokens (Testnet)

| Token | Address | Decimals |
|-------|---------|----------|
| WBTC (mock) | `0xE735...2110` | 8 |
| USDC (mock) | `0xa85b...dD14` | 6 |
| USDT (mock) | `0x04f1...0c2` | 6 |

### Supported Tokens (Mainnet — Arbitrum One)

| Token | Address | Decimals |
|-------|---------|----------|
| WBTC | `0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f` | 8 |
| USDC (native) | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | 6 |
| USDT | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` | 6 |

---

## Deployment Order

Contracts must be deployed in this exact order due to cross-references set during initialisation.

### ERC-20 Lending Stack

```
1. PositionNFT
2. LoanProtocol          (receives PositionNFT address)
3. Authorise LoanProtocol in PositionNFT
4. ListingService         (receives LoanProtocol address)
5. Whitelist tokens in ListingService
```

### NFT Lending Stack

```
1. NFTPositionNFT
2. NFTLoanProtocol        (receives NFTPositionNFT address)
3. Authorise NFTLoanProtocol in NFTPositionNFT
4. NFTListingService      (receives NFTLoanProtocol address)
5. Whitelist NFT collections in NFTListingService
```

---

## Deployment Scripts

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install

# Set environment variables
export PRIVATE_KEY=0x...
export ARBISCAN_API_KEY=your_key
export RPC_URL=https://arb-sepolia.g.alchemy.com/v2/YOUR_KEY
```

### Deploy ERC-20 Stack

```solidity
// script/DeployERC20.s.sol
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/PositionNFT.sol";
import "../src/LoanProtocol.sol";
import "../src/ListingService.sol";

contract DeployERC20 is Script {
    function run() external {
        vm.startBroadcast();

        // 1. Deploy PositionNFT
        PositionNFT positionNFTImpl = new PositionNFT();
        TransparentUpgradeableProxy positionNFTProxy = new TransparentUpgradeableProxy(
            address(positionNFTImpl),
            msg.sender,  // proxy admin
            abi.encodeCall(PositionNFT.initialize, ("Gavel Position", "GPOS"))
        );
        PositionNFT positionNFT = PositionNFT(address(positionNFTProxy));

        // 2. Deploy LoanProtocol
        LoanProtocol loanProtocolImpl = new LoanProtocol();
        TransparentUpgradeableProxy loanProtocolProxy = new TransparentUpgradeableProxy(
            address(loanProtocolImpl),
            msg.sender,
            abi.encodeCall(LoanProtocol.initialize, (address(positionNFT)))
        );
        LoanProtocol loanProtocol = LoanProtocol(address(loanProtocolProxy));

        // 3. Authorise LoanProtocol in PositionNFT
        positionNFT.setLoanProtocol(address(loanProtocol));

        // 4. Deploy ListingService
        ListingService listingServiceImpl = new ListingService();
        TransparentUpgradeableProxy listingServiceProxy = new TransparentUpgradeableProxy(
            address(listingServiceImpl),
            msg.sender,
            abi.encodeCall(ListingService.initialize, (
                address(loanProtocol),
                msg.sender,  // treasury
                0,           // auctionFeeBps (zero at launch)
                0            // marketplaceListingFee (zero at launch)
            ))
        );
        ListingService listingService = ListingService(address(listingServiceProxy));

        // 5. Whitelist tokens
        listingService.setTokenWhitelist(WBTC_ADDRESS, true);
        listingService.setTokenWhitelist(USDC_ADDRESS, true);
        listingService.setTokenWhitelist(USDT_ADDRESS, true);

        vm.stopBroadcast();

        // Log addresses
        console.log("PositionNFT:", address(positionNFT));
        console.log("LoanProtocol:", address(loanProtocol));
        console.log("ListingService:", address(listingService));
    }
}
```

### Run Deployment

```bash
# Testnet
forge script script/DeployERC20.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY

# Mainnet (add --slow for safety)
forge script script/DeployERC20.s.sol \
  --rpc-url https://arb1.arbitrum.io/rpc \
  --broadcast \
  --verify \
  --slow \
  --etherscan-api-key $ARBISCAN_API_KEY
```

---

## Post-Deployment Configuration

After deploying all contracts, verify the following:

### Checklist

```bash
# 1. Verify PositionNFT knows the LoanProtocol
cast call $POSITION_NFT "loanProtocol()" --rpc-url $RPC_URL
# Should return LoanProtocol proxy address

# 2. Verify ListingService knows the LoanProtocol
cast call $LISTING_SERVICE "loanProtocol()" --rpc-url $RPC_URL
# Should return LoanProtocol proxy address

# 3. Verify token whitelist
cast call $LISTING_SERVICE "isTokenWhitelisted(address)" $WBTC --rpc-url $RPC_URL
# Should return true

# 4. Verify fees are zero
cast call $LISTING_SERVICE "auctionFeeBps()" --rpc-url $RPC_URL
# Should return 0

# 5. Verify owner
cast call $LOAN_PROTOCOL "owner()" --rpc-url $RPC_URL
# Should return deployer address

# 6. Verify protocol is not paused
cast call $LOAN_PROTOCOL "paused()" --rpc-url $RPC_URL
# Should return false

# 7. Test pause/unpause
cast send $LOAN_PROTOCOL "pause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $LOAN_PROTOCOL "unpause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Transfer Ownership to Multi-Sig (Mainnet)

```bash
MULTISIG=0x...  # Gnosis Safe address

# Transfer each contract
cast send $LOAN_PROTOCOL "transferOwnership(address)" $MULTISIG --private-key $PRIVATE_KEY
cast send $POSITION_NFT "transferOwnership(address)" $MULTISIG --private-key $PRIVATE_KEY
cast send $LISTING_SERVICE "transferOwnership(address)" $MULTISIG --private-key $PRIVATE_KEY
cast send $NFT_LOAN_PROTOCOL "transferOwnership(address)" $MULTISIG --private-key $PRIVATE_KEY
cast send $NFT_POSITION_NFT "transferOwnership(address)" $MULTISIG --private-key $PRIVATE_KEY
cast send $NFT_LISTING_SERVICE "transferOwnership(address)" $MULTISIG --private-key $PRIVATE_KEY
```

---

## Verification

All contracts should be verified on Arbiscan so users can inspect the source code.

### Automatic Verification (via Forge)

If you used `--verify` during deployment, contracts should already be verified. Check:

```
https://sepolia.arbiscan.io/address/CONTRACT_ADDRESS#code
```

### Manual Verification

If automatic verification failed:

```bash
forge verify-contract \
  --chain-id 421614 \
  --compiler-version v0.8.20+commit.a1b79de6 \
  --optimizer-runs 200 \
  --etherscan-api-key $ARBISCAN_API_KEY \
  $IMPLEMENTATION_ADDRESS \
  src/LoanProtocol.sol:LoanProtocol
```

For proxy contracts, also verify the proxy itself and link the implementation:

```bash
# Verify the proxy points to the correct implementation
cast call $PROXY_ADDRESS "implementation()" --rpc-url $RPC_URL
```

### Verification Checklist

For each of the 6 contracts, confirm:

- [ ] Implementation contract source verified on Arbiscan
- [ ] Proxy contract marked as proxy on Arbiscan
- [ ] "Read as Proxy" tab available showing implementation functions
- [ ] Constructor arguments match deployment parameters
- [ ] Compiler version and optimiser settings match `foundry.toml`

---

## Mainnet Migration

When moving from testnet to mainnet, the following changes are required:

### Duration Units

Testnet uses **minutes** for fast iteration. Mainnet uses **days**.

```javascript
// Testnet: durations in minutes
const loanDuration = BigInt(Math.round(parseFloat(days) * 60));

// Mainnet: durations in days
const loanDuration = BigInt(Math.round(parseFloat(days) * 86400));
```

### Network Configuration

| Setting | Testnet | Mainnet |
|---------|---------|---------|
| Chain ID | `421614` (Arbitrum Sepolia) | `42161` (Arbitrum One) |
| Block explorer | `https://sepolia.arbiscan.io` | `https://arbiscan.io` |
| RPC endpoint | Sepolia RPC | Arbitrum One RPC |

### Token Addresses

Replace all mock token addresses with real Arbitrum One token addresses (see [Supported Tokens](#supported-tokens-mainnet--arbitrum-one) above).

### Testnet-Only Features to Remove

- Mock token minting functions
- Testnet faucet integration
- `testMintAmount` configuration
- Any hardcoded testnet addresses

---

## Local Development

### Foundry Setup

```bash
# Clone repository
git clone https://github.com/thegavel/protocol.git
cd protocol

# Install dependencies
forge install

# Build
forge build

# Run tests
forge test

# Run tests with verbose output
forge test -vvv

# Run specific test file
forge test --match-path test/LoanProtocol.t.sol

# Coverage report
forge coverage

# Gas report
forge test --gas-report
```

### Foundry Configuration

```toml
# foundry.toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.20"
optimizer = true
optimizer_runs = 200
via_ir = true

[fuzz]
runs = 10000

[invariant]
runs = 1000
depth = 50000
```

### Local Fork Testing

```bash
# Fork Arbitrum Sepolia for testing against deployed contracts
anvil --fork-url $RPC_URL

# In another terminal, run tests against the fork
forge test --fork-url http://localhost:8545
```

---

## Environment Setup

### Required Environment Variables

```bash
# .env (do not commit this file)
PRIVATE_KEY=0x...                    # Deployer private key
ARBISCAN_API_KEY=...                 # For contract verification
RPC_URL=https://...                  # Arbitrum RPC endpoint
```

### Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Foundry | Latest stable | Build, test, deploy |
| OpenZeppelin Contracts | 5.x | Upgradeable contract bases |
| OpenZeppelin Contracts Upgradeable | 5.x | Proxy and access control |
| Node.js | 18+ | Frontend and scripts |

### Project Structure

```
protocol/
├── src/
│   ├── LoanProtocol.sol          # Core ERC-20 lending
│   ├── NFTLoanProtocol.sol       # Core NFT lending
│   ├── PositionNFT.sol           # Position tokens (ERC-20 loans)
│   ├── NFTPositionNFT.sol        # Position tokens (NFT loans)
│   ├── ListingService.sol        # Token curation layer
│   ├── NFTListingService.sol     # NFT curation layer
│   └── interfaces/
│       ├── ILoanProtocol.sol
│       ├── INFTLoanProtocol.sol
│       ├── IPositionNFT.sol
│       └── INFTPositionNFT.sol
├── test/
│   ├── LoanProtocol.t.sol
│   ├── NFTLoanProtocol.t.sol
│   ├── PositionNFT.t.sol
│   ├── ListingService.t.sol
│   ├── NFTListingService.t.sol
│   ├── NFTPositionNFT.t.sol
│   ├── helpers/
│   │   ├── TestSetup.sol
│   │   └── NFTTestSetup.sol
│   └── fuzz/
│       └── handlers/
├── script/
│   └── Deploy.s.sol
├── docs/
│   ├── INTEGRATION.md
│   ├── AUCTION_LIFECYCLE.md
│   ├── SECURITY.md
│   └── DEPLOYMENT.md
├── foundry.toml
├── README.md
└── LICENSE
```

---

*This document is maintained alongside the codebase. Last updated: February 2026.*
