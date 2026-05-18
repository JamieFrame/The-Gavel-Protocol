// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev OpenZeppelin upgradeable proxy initialization (replaces constructor)
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
/// @dev Owner-restricted access control for admin functions
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
/// @dev Emergency pause mechanism â€” halts all state-changing operations
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
/// @dev Mutex guard preventing reentrant external calls
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
/// @dev Standard ERC-20 token interface for loan tokens
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/// @dev Safe ERC-20 wrappers handling non-standard return values
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
/// @dev Standard ERC-721 interface for collateral NFTs
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
/// @dev Interface for contracts that accept ERC-721 safeTransferFrom
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @dev Interface for the borrower/lender NFT Position contract
import "./interfaces/INFTPositionNFT.sol";

/**
 * @title NFTLoanProtocol
 * @author Bitcoin Yield Curve
 * @notice Core lending protocol with NFT collateral using oracle-free competitive bidding auctions
 * @dev Phase 1.5 EVM implementation - NFT Collateral Extension
 * 
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  WARNING: PERMISSIONLESS PROTOCOL - USE AT YOUR OWN RISK                  ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â£
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  This protocol accepts ANY ERC-721 NFT as collateral. There is NO         ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  whitelist. Malicious or worthless NFTs can be used as collateral.        ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ                                                                           ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  For curated, vetted NFT collection listings, use the NFTListingService   ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  contract which provides collection whitelisting and safety checks.       ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ                                                                           ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  Users interacting directly with this protocol assume ALL risk.           ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ                                                                           ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  LENDER RISK WARNING:                                                     ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  - If borrower defaults, you receive the NFT (not stablecoins)            ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  - NFT may be illiquid or worthless                                       ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  - Assess NFT value carefully before bidding                              ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
 * ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
 * 
 * SECURITY FEATURES:
 * - All state-changing functions use ReentrancyGuard
 * - Follows Checks-Effects-Interactions pattern throughout
 * - No price oracles - market determines rates via auction
 * - NFT positions enable secondary market liquidity
 * - Pull-based refunds prevent DoS on auction bidding
 * - Fixed grace period (not admin-configurable)
 * - Integrated marketplace - no external contract trust needed
 * - IERC721Receiver implemented for safe NFT transfers
 */
contract NFTLoanProtocol is 
        // Upgradeable proxy pattern â€” replaces constructor with initialize()
    Initializable, 
        // Single-owner access control for pause/unpause admin functions
    OwnableUpgradeable, 
        // Emergency circuit breaker â€” halts all user-facing operations
    PausableUpgradeable, 
        // Mutex lock preventing reentrant calls on state-changing functions
    ReentrancyGuardUpgradeable,
        // Enables this contract to receive ERC-721 NFTs via safeTransferFrom
    IERC721Receiver
{
    //
    // â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
    // â”‚                    ARCHITECTURE OVERVIEW                         â”‚
    // â”‚                                                                  â”‚
    // â”‚  NFT Collateral Extension:                                       â”‚
    // â”‚    This contract mirrors LoanProtocol but accepts ERC-721 NFTs   â”‚
    // â”‚    as collateral instead of ERC-20 tokens. The NFT is held in    â”‚
    // â”‚    escrow by this contract during the auction and loan lifecycle. â”‚
    // â”‚                                                                  â”‚
    // â”‚  Oracle-Free Design:                                             â”‚
    // â”‚    No price oracles. Interest rates are discovered through       â”‚
    // â”‚    competitive reverse Dutch auctions where lenders bid lower    â”‚
    // â”‚    repayment amounts. Lenders implicitly price the NFT by        â”‚
    // â”‚    choosing how much to lend against it.                         â”‚
    // â”‚                                                                  â”‚
    // â”‚  Position NFTs:                                                  â”‚
    // â”‚    Both borrower and lender receive ERC-721 position tokens      â”‚
    // â”‚    (from NFTPositionNFT contract) representing their loan        â”‚
    // â”‚    positions. These can be traded on the integrated marketplace.  â”‚
    // â”‚                                                                  â”‚
    // â”‚  Pull-Based Refunds:                                             â”‚
    // â”‚    Outbid lenders and rejected offer-makers receive refunds      â”‚
    // â”‚    via pull pattern â€” funds queued in pendingRefunds mapping,    â”‚
    // â”‚    claimed via claimRefund(). Prevents DoS via revert-on-receive.â”‚
    // â”‚                                                                  â”‚
    // â”‚  CEI Pattern:                                                    â”‚
    // â”‚    All state-changing functions follow Checks-Effects-            â”‚
    // â”‚    Interactions to prevent reentrancy. Combined with             â”‚
    // â”‚    ReentrancyGuard for defense-in-depth.                        â”‚
    // â”‚                                                                  â”‚
    // â”‚  Marketplace Freeze:                                             â”‚
    // â”‚    The integrated marketplace freezes MATURITY_BUFFER before     â”‚
    // â”‚    loan maturity to prevent last-second position transfers       â”‚
    // â”‚    that could interfere with repayment or default claims.        â”‚
    // â”‚                                                                  â”‚
    // â”‚  Two-Layer Model:                                                â”‚
    // â”‚    This contract is permissionless (any ERC-721 + ERC-20 pair).  â”‚
    // â”‚    NFTListingService wraps it with collection whitelisting       â”‚
    // â”‚    and fees for curated, safer user experience.                  â”‚
    // â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
    //
    using SafeERC20 for IERC20;

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    uint256 public constant MIN_AUCTION_DURATION = 1 days;  
    /// @notice Cap on bidding period â€” prevents indefinitely open auctions
    uint256 public constant MAX_AUCTION_DURATION = 7 days;
    /// @notice Minimum loan term â€” prevents trivially short loans
    uint256 public constant MIN_LOAN_DURATION = 7 days;     
    /// @notice Maximum loan term (~30 years) â€” enables full yield curve coverage
    uint256 public constant MAX_LOAN_DURATION = 10950 days; // ~30 years
    /// @notice Post-maturity repayment window before lender can seize NFT collateral
    uint256 public constant GRACE_PERIOD = 1 days;          
    /// @notice Window after auction ends during which finalize() can be called
    uint256 public constant FINALIZATION_WINDOW = 3 days;      
    /// @notice Basis points denominator: 10000 = 100%
    uint256 public constant BPS_DENOMINATOR = 10000;
    /// @notice Absolute floor for bid step (1 unit of loan token)
    uint256 public constant MIN_BID_STEP = 1;
    /// @notice Maximum bid step expressed in basis points of loanAmount.
    /// @dev Caps the bid step at 10% of loanAmount. Prevents a borrower from setting bidStep
    ///      so large that auction.currentBid - auction.bidStep would underflow below loanAmount,
    ///      which would silently bypass the step requirement and degrade the auction to
    ///      strict-monotonic-only bidding. See createAuction/createAuctionFor for the enforcement check.
    uint256 public constant MAX_BID_STEP_BPS = 1000; // 10% of loanAmount
    /// @notice Minimum marketplace offer validity period
    uint256 public constant MIN_OFFER_DURATION = 1 days;   
    /// @notice Safety buffer â€” marketplace freezes this long before loan maturity
    uint256 public constant MATURITY_BUFFER = 1 days;       
    /// @notice Gas-safety cap on offers per listing â€” bounds _refundOtherOffers loop
    uint256 public constant MAX_OFFERS_PER_LISTING = 50;        // Prevent gas DoS via unbounded refund loops

    // ============================================================================
    // ENUMS
    // ============================================================================

    enum AuctionStatus { 
        OPEN,           // Accepting bids
        FINALIZED,      // Loan created
        CANCELLED,      // No bids or borrower cancelled
        EXPIRED         // Had bids but not finalized within window
    }

    enum LoanStatus { 
        ACTIVE,         // Loan in progress
        REPAID,         // Borrower repaid
        DEFAULTED       // Lender claimed collateral NFT
    }

    enum MarketplaceOfferStatus {
        PENDING,
        ACCEPTED,
        REJECTED,
        COUNTERED,
        CANCELLED,
        // Had bids but not finalized within finalization window
        EXPIRED
    }

    // ============================================================================
    // STRUCTS
    // ============================================================================

    struct Auction {
        /// @dev Loan recipient â€” receives funds, must repay at maturity
        address borrower;
        address collateralNFT;      // NFT contract address
        uint256 collateralTokenId;  // NFT token ID
        address loanToken;          // ERC-20 token to borrow
        uint256 loanAmount;         // Principal to borrow
        uint256 maxRepayment;       // Maximum repayment (caps interest)
        uint256 loanDuration;       // Loan term in seconds
        uint256 auctionEnd;         // When auction bidding ends
        address currentBidder;      // Current winning bidder
        uint256 currentBid;         // Current best bid (repayment amount)
        uint256 bidCount;           // Number of bids placed
        /// @dev Current lifecycle state: OPEN â†’ FINALIZED/CANCELLED/EXPIRED
        AuctionStatus status;
        uint256 bidStep;            // Minimum bid improvement required
        /// @dev Snapshot of totalPausedDuration at auction creation. Used by _pauseElapsed()
        ///      to compute pause-adjusted deadlines so this auction's lifecycle freezes during pause.
        uint256 pauseSnapshot;
    }

    struct Loan {
        address borrower;           // Current borrower (can change via NFT transfer)
        address collateralNFT;      // NFT contract address
        uint256 collateralTokenId;  // NFT token ID
        address loanToken;          // Borrowed token
        uint256 loanAmount;         // Principal borrowed
        uint256 repaymentAmount;    // Total amount due at maturity
        uint256 maturityTimestamp;  // When loan is due
        address lender;             // Current lender (can change via NFT transfer)
        /// @dev Current lifecycle state: ACTIVE â†’ REPAID/DEFAULTED
        LoanStatus status;
        /// @dev Snapshot of totalPausedDuration at loan creation (auction finalization).
        ///      Used by _pauseElapsed() to compute pause-adjusted maturity and grace deadlines.
        uint256 pauseSnapshot;
    }

    struct MarketplaceListing {
        /// @dev Position owner who created the listing
        address seller;
        /// @dev Associated loan ID (derived from position token ID)
        uint256 loanId;
        string positionType;        // "borrower" or "lender"
        /// @dev Token used for payment (cached for refunds)
        address paymentToken;
        /// @dev Listed price in payment token units
        uint256 askingPrice;
        /// @dev Minimum offer amount in paymentToken units (spam floor; 0 = no floor)
        uint256 minOfferAmount;
        /// @dev Unix timestamp when listing was created
        uint256 listedAt;
        /// @dev Whether listing is live (false after sale/unlist)
        bool active;
    }

    struct MarketplaceOffer {
        /// @dev Offer maker â€” receives position if accepted
        address buyer;
        /// @dev Original offer amount in payment tokens
        uint256 amount;
        /// @dev Funds currently held in contract escrow
        uint256 escrowedAmount;
        /// @dev Lifecycle: PENDING/ACCEPTED/REJECTED/COUNTERED/CANCELLED/EXPIRED
        MarketplaceOfferStatus status;
        /// @dev Seller counter-offer price (0 if not countered)
        uint256 counterAmount;
        /// @dev Unix timestamp when offer was submitted
        uint256 createdAt;
        /// @dev Unix timestamp after which offer can be expired
        uint256 expiresAt;
        /// @dev Token used for payment (cached for refunds)
        address paymentToken;
        /// @dev Snapshot of totalPausedDuration at offer creation (overwritten by counterOffer).
        ///      Used by _pauseElapsed() to compute pause-adjusted offer expiry.
        uint256 pauseSnapshot;
    }

    // ============================================================================
    // STATE VARIABLES - CORE PROTOCOL
    // ============================================================================

    /// @notice Position NFT contract for minting borrower/lender positions
    INFTPositionNFT public positionNFT;

    /// @notice Counter for auction/loan IDs
    uint256 public loanNonce;

    /// @notice All auctions by ID
    mapping(uint256 => Auction) public auctions;

    /// @notice All loans by ID
    mapping(uint256 => Loan) public loans;

    /// @notice Track if lender has claimed from expired auction
    mapping(uint256 => bool) public expiredAuctionLenderClaimed;
    
    /// @notice Track if borrower has claimed from expired auction
    mapping(uint256 => bool) public expiredAuctionBorrowerClaimed;

    /// @notice Pending refunds for outbid lenders (pull pattern)
    mapping(address => mapping(address => uint256)) public pendingRefunds;

    /// @notice Operator approvals: owner => operator => approved
    mapping(address => mapping(address => bool)) public operatorApprovals;

    // ============================================================================
    // STATE VARIABLES - INTEGRATED MARKETPLACE
    // ============================================================================

    /// @notice Marketplace listings keyed by Position NFT token ID (supports simultaneous borrower/lender listings)
    mapping(uint256 => MarketplaceListing) public marketplaceListings;

    /// @notice Marketplace offers: positionTokenId => offerId => Offer
    mapping(uint256 => mapping(uint256 => MarketplaceOffer)) public marketplaceOffers;

    /// @notice Offer counter per position token ID
    mapping(uint256 => uint256) public marketplaceOfferNonce;

    /// @notice Active offer count per position token ID (PENDING + COUNTERED only).
    /// @dev Tracked separately from marketplaceOfferNonce because the nonce is monotonic
    ///      and would otherwise allow a churn-DoS: an attacker could create+cancel offers
    ///      until nonce reaches MAX_OFFERS_PER_LISTING and block all future legitimate
    ///      offers (Sherlock #13). This counter increments on makeOffer and decrements
    ///      on every transition out of PENDING/COUNTERED (cancel/reject/expire). Reset
    ///      to 0 alongside marketplaceOfferNonce at every listing finalization site.
    mapping(uint256 => uint256) public activeOfferCount;

    // ============================================================================
    // STATE VARIABLES - PAUSE-TIME FREEZE
    // ============================================================================

    /// @notice Timestamp when the current pause began (0 if not currently paused).
    /// @dev Set in _pause() override, cleared in _unpause() override after totalling.
    uint256 public pauseStartTimestamp;

    /// @notice Cumulative seconds the protocol has spent in paused state across all completed pauses.
    /// @dev Each Loan, Auction, and MarketplaceOffer snapshots this value at creation. Time-based
    ///      checks subtract (currentTotal - snapshot) from elapsed real time so deadlines effectively
    ///      freeze while paused. See _pauseElapsed() for the live computation including in-progress pause.
    uint256 public totalPausedDuration;

    // ============================================================================
    // EVENTS - CORE PROTOCOL
    // ============================================================================

    /// @param auctionId Auction this NFT is collateralizing
    /// @param depositor Address depositing the NFT
    /// @param nftContract ERC-721 contract address
    /// @param tokenId NFT token ID deposited
    event NFTCollateralDeposited(
        // auction identifier
        uint256 indexed auctionId,
        // NFT depositor address
        address indexed depositor,
        // ERC-721 contract address
        address indexed nftContract,
        // NFT token ID
        uint256 tokenId
    );

    /// @param auctionId Unique auction identifier
    /// @param borrower Address requesting the loan
    /// @param collateralNFT NFT contract locked as collateral
    /// @param collateralTokenId NFT token ID locked
    /// @param loanToken ERC-20 token being borrowed
    /// @param loanAmount Principal amount requested
    /// @param maxRepayment Maximum repayment cap (starting bid)
    /// @param loanDuration Duration of the resulting loan in seconds
    /// @param auctionEnd Timestamp when bidding closes
    event AuctionCreated(
        // auction identifier
        uint256 indexed auctionId,
        // loan borrower
        address indexed borrower,
        // NFT contract address
        address collateralNFT,
        // NFT token ID
        uint256 collateralTokenId,
        // loan token address
        address loanToken,
        // principal requested
        uint256 loanAmount,
        // max repayment cap
        uint256 maxRepayment,
        // loan duration in seconds
        uint256 loanDuration,
        // auction end timestamp
        uint256 auctionEnd
    );
    
    /// @notice Emitted when a zero-bid auction is cancelled by the borrower
    event AuctionCancelled(uint256 indexed auctionId);
    
    /// @param auctionId Auction receiving the bid
    /// @param bidder Address of the lender placing the bid
    /// @param repaymentAmount Total repayment offered (lower is better for borrower)
    /// @param bidNumber Sequential bid number for this auction
    event BidPlaced(
        // auction identifier
        uint256 indexed auctionId,
        // lender placing the bid
        address indexed bidder,
        // total repayment amount
        uint256 repaymentAmount,
        // sequential bid count
        uint256 bidNumber
    );

    /// @notice Emitted when a bid reaches the loanAmount floor (zero interest) and ends
    ///         the auction early. No further bid can improve on this, so the auction's
    ///         effective deadline is advanced to the current moment (Sherlock #21).
    /// @param auctionId Auction that reached the floor
    /// @param bidder Lender whose bid hit the floor (the winning bidder)
    event AuctionFloorReached(
        uint256 indexed auctionId,
        address indexed bidder
    );

    /// @param user Address that was outbid and can claim refund
    /// @param token Loan token to be refunded
    /// @param amount Refund amount (equals loanAmount)
    /// @param auctionId Auction where user was outbid
    event RefundAvailable(
        // user address
        address indexed user,
        // ERC-20 token address
        address indexed token,
        // token amount
        uint256 amount,
        // auction identifier
        uint256 indexed auctionId
    );

    /// @param user Address claiming their refund
    /// @param token Token being refunded
    /// @param amount Amount refunded
    event RefundClaimed(
        // user address
        address indexed user,
        // ERC-20 token address
        address indexed token,
        // token amount
        uint256 amount
    );
    
    /// @param auctionId Finalized auction ID
    /// @param loanId Loan ID (same as auctionId)
    /// @param lender Winning bidder who becomes the lender
    /// @param finalRepayment Final repayment amount from winning bid
    event AuctionFinalized(
        // auction identifier
        uint256 indexed auctionId,
        // loan identifier
        uint256 indexed loanId,
        // loan lender / winning bidder
        address indexed lender,
        // winning bid repayment
        uint256 finalRepayment
    );
    
    /// @notice Emitted when an auction ends with zero bids â€” NFT collateral returned
    event AuctionExpiredNoBids(uint256 indexed auctionId);
    
    /// @param auctionId Expired auction ID
    /// @param borrower Auction borrower
    /// @param lender Winning bidder whose funds are locked
    event AuctionExpiredNotFinalized(
        // auction identifier
        uint256 indexed auctionId,
        // loan borrower
        address indexed borrower,
        // loan lender / winning bidder
        address indexed lender
    );
    
    /// @param auctionId Expired auction ID
    /// @param claimant Address claiming funds
    /// @param isLender True if claimant is the lender
    /// @param amount Amount returned to claimant
    event ExpiredAuctionClaimed(
        // auction identifier
        uint256 indexed auctionId,
        // address claiming funds/NFT
        address indexed claimant,
        // true if claimant is lender
        bool isLender,
        // token amount
        uint256 amount
    );

    /// @param auctionId Expired auction ID
    /// @param claimant Address reclaiming the NFT
    /// @param nftContract ERC-721 contract address
    /// @param tokenId NFT token ID returned
    event ExpiredAuctionNFTClaimed(
        // auction identifier
        uint256 indexed auctionId,
        // address claiming funds/NFT
        address indexed claimant,
        // ERC-721 contract address
        address indexed nftContract,
        // NFT token ID
        uint256 tokenId
    );
    
    /// @param loanId Loan that was repaid
    /// @param borrower Address that repaid (position NFT holder)
    /// @param repaymentAmount Total amount repaid to lender
    event LoanRepaid(
        // loan identifier
        uint256 indexed loanId,
        // loan borrower
        address indexed borrower,
        // total repayment amount
        uint256 repaymentAmount
    );
    
    /// @param loanId Defaulted loan ID
    /// @param lender Address that claimed the NFT
    /// @param collateralNFT NFT contract address of seized collateral
    /// @param collateralTokenId Token ID of the seized NFT
    event LoanDefaulted(
        // loan identifier
        uint256 indexed loanId,
        // loan lender / winning bidder
        address indexed lender,
        // NFT contract address
        address collateralNFT,
        // NFT token ID
        uint256 collateralTokenId
    );

    /// @notice Emitted when a loan is explicitly marked as defaulted via markDefault()
    /// @dev Fires at most once per loan; subsequent claimCollateral does not re-emit
    /// @param loanId Loan that has been marked as defaulted
    event LoanDefaultMarked(uint256 indexed loanId);

    /// @param loanId Loan whose borrower position was transferred
    /// @param from Previous borrower
    /// @param to New borrower
    event BorrowerPositionTransferred(
        // loan identifier
        uint256 indexed loanId,
        // previous position owner
        address indexed from,
        // new position owner
        address indexed to
    );

    /// @param loanId Loan whose lender position was transferred
    /// @param from Previous lender
    /// @param to New lender
    event LenderPositionTransferred(
        // loan identifier
        uint256 indexed loanId,
        // previous position owner
        address indexed from,
        // new position owner
        address indexed to
    );

    /// @param owner Address granting/revoking permission
    /// @param operator Address being approved/revoked
    /// @param approved True to approve, false to revoke
    event OperatorApprovalSet(
        // address granting permission
        address indexed owner,
        // address being approved
        address indexed operator,
        // true = approve, false = revoke
        bool approved
    );

    // ============================================================================
    // EVENTS - INTEGRATED MARKETPLACE
    // ============================================================================

    /// @param loanId Loan ID of the listed position
    /// @param seller Address listing the position
    /// @param positionType "borrower" or "lender"
    /// @param paymentToken Token accepted as payment
    /// @param askingPrice Listed price
    event PositionListed(
        // loan identifier
        uint256 indexed loanId,
        // position seller
        address indexed seller,
        // "borrower" or "lender"
        string positionType,
        // payment token address
        address paymentToken,
        // listed price
        uint256 askingPrice,
        // minimum offer amount (spam floor; 0 = no floor)
        uint256 minOfferAmount
    );

    /// @notice Emitted when a listing is removed from the marketplace
    event PositionUnlisted(uint256 indexed loanId);

    /// @notice Emitted when seller updates their listing price
    event ListingPriceUpdated(uint256 indexed loanId, uint256 oldPrice, uint256 newPrice);

    /// @param loanId Loan ID of the listing
    /// @param offerId Unique offer identifier
    /// @param buyer Address making the offer
    /// @param amount Offer amount (escrowed)
    event MarketplaceOfferMade(
        // loan identifier
        uint256 indexed loanId,
        // offer identifier
        uint256 indexed offerId,
        // offer maker / buyer
        address indexed buyer,
        // token amount
        uint256 amount
    );

    /// @notice Emitted when buyer cancels their offer and reclaims escrow
    event MarketplaceOfferCancelled(uint256 indexed loanId, uint256 indexed offerId);

    /// @notice Emitted when seller rejects an offer â€” refund queued for buyer
    event MarketplaceOfferRejected(uint256 indexed loanId, uint256 indexed offerId);

    /// @param loanId Loan ID of the listing
    /// @param offerId Offer being countered
    /// @param counterAmount Seller counter price
    event MarketplaceCounterOffer(
        // loan identifier
        uint256 indexed loanId,
        // offer identifier
        uint256 indexed offerId,
        // seller counter price
        uint256 counterAmount
    );

    /// @param loanId Loan ID of the position sold
    /// @param offerId Accepted offer ID
    /// @param buyer Address receiving the position
    /// @param seller Address transferring the position
    /// @param price Final sale price
    event MarketplaceOfferAccepted(
        // loan identifier
        uint256 indexed loanId,
        // offer identifier
        uint256 indexed offerId,
        // offer maker / buyer
        address indexed buyer,
        // seller address
        address seller,
        // sale price
        uint256 price
    );

    /// @param loanId Loan ID of the position
    /// @param seller Previous position owner
    /// @param buyer New position owner
    /// @param price Sale price paid
    event PositionSold(
        // loan identifier
        uint256 indexed loanId,
        // position seller
        address indexed seller,
        // offer maker / buyer
        address indexed buyer,
        // sale price
        uint256 price
    );

    /// @notice Emitted when an offer reaches its expiration deadline
    event MarketplaceOfferExpired(uint256 indexed loanId, uint256 indexed offerId);

    /// @param loanId Loan ID of the listing
    /// @param offerId Offer whose escrow is being refunded
    /// @param buyer Address who will receive refund
    /// @param amount Refund amount queued
    event MarketplaceOfferRefundQueued(
        // loan identifier
        uint256 indexed loanId,
        // offer identifier
        uint256 indexed offerId,
        // offer maker / buyer
        address indexed buyer,
        // token amount
        uint256 amount
    );

    // ============================================================================
    // ERRORS
    // ============================================================================

    // Core Protocol Errors
    error ZeroAddress();
    /// @dev InvalidToken: Loan token address is zero or otherwise invalid
    error InvalidToken();
    /// @dev InvalidNFT: NFT contract address is zero
    error InvalidNFT();
    /// @dev InvalidAmount: Zero amount provided for loan principal
    error InvalidAmount();
    /// @dev InvalidRepayment: maxRepayment is less than loanAmount (would imply negative interest)
    error InvalidRepayment();
    /// @dev InvalidDuration: Duration outside allowed bounds [MIN, MAX]
    error InvalidDuration();
    /// @dev AuctionNotFound: Referencing a non-existent auction ID (zero borrower)
    error AuctionNotFound();
    /// @dev AuctionNotOpen: Auction is not in OPEN status
    error AuctionNotOpen();
    /// @dev AuctionEnded: Bid placed after auction end timestamp
    error AuctionEnded();
    /// @dev AuctionStillOpen: Finalize/expire attempted before auction end timestamp
    error AuctionStillOpen();
    /// @dev AuctionNotExpired: Claiming from auction not yet past finalization window
    error AuctionNotExpired();
    /// @dev BidTooHigh: Bid does not improve on current bid by at least bidStep
    error BidTooHigh();
    /// @dev BidTooLow: Bid below loan amount (no negative interest)
    error BidTooLow();
    /// @dev BidStepTooHigh: bidStep exceeds MAX_BID_STEP_BPS of loanAmount.
    ///      A bid step too large would underflow below loanAmount in placeBid's maxValidBid
    ///      computation, allowing strict-monotonic-only bidding and bypassing step enforcement.
    error BidStepTooHigh();
    /// @dev NoBids: Expired auction received zero bids
    error NoBids();
    /// @dev HasBids: Cannot cancel auction that already has bids
    error HasBids();
    /// @dev NotBorrower: Caller is not the auction borrower
    error NotBorrower();
    /// @dev Unauthorized: Caller lacks permission (not owner/operator/position-holder)
    error Unauthorized();
    /// @dev LoanNotFound: Referencing a non-existent loan ID
    error LoanNotFound();
    /// @dev LoanNotActive: Loan already repaid or defaulted
    error LoanNotActive();
    /// @dev LoanNotMatured: Claiming collateral before loan maturity
    error LoanNotMatured();
    /// @dev GracePeriodNotEnded: Claiming collateral during grace period
    error GracePeriodNotEnded();
    /// @dev AlreadyClaimed: Double-claim from expired auction
    error AlreadyClaimed();
    /// @dev NoRefundAvailable: Zero pending refund balance
    error NoRefundAvailable();
    /// @dev FinalizationWindowExpired: Finalize called after finalization window closed
    error FinalizationWindowExpired();
    /// @dev FinalizationWindowActive: Claiming expired while finalization still possible
    error FinalizationWindowActive();
    /// @dev NotNFTOwner: Caller does not own the collateral NFT
    error NotNFTOwner();
    /// @dev GracePeriodExpired: Repaying after grace period ended
    error GracePeriodExpired();
    /// @dev LoanExpired: Loan past maturity plus grace period
    error LoanExpired();

    // Marketplace Errors
    error NotListed();
    /// @dev AlreadyListed: Duplicate listing for same position
    error AlreadyListed();
    /// @dev NotSeller: Caller is not the listing seller
    error NotSeller();
    /// @dev ListingNotStale: cleanStaleListing called but seller still owns the position
    error ListingNotStale();
    /// @dev NotBuyer: Caller is not the offer maker
    error NotBuyer();
    /// @dev InvalidOffer: Offer amount is zero
    error InvalidOffer();
    /// @dev OfferNotFound: Non-existent offer ID
    error OfferNotFound();
    /// @dev InvalidOfferStatus: Offer not in expected lifecycle state
    error InvalidOfferStatus();
    /// @dev CannotBuyOwnPosition: Seller tried to buy their own listing
    error CannotBuyOwnPosition();
    /// @dev InvalidPrice: Listing price is zero
    error InvalidPrice();
    /// @dev InvalidPositionType: Not "borrower" or "lender"
    error InvalidPositionType();
    /// @dev NotPositionOwner: Caller does not own the position NFT
    error NotPositionOwner();
    /// @dev OfferNotExpired: Offer has not yet reached its expiration deadline
    error OfferNotExpired();
    /// @dev OfferDurationTooShort: Below MIN_OFFER_DURATION
    error OfferDurationTooShort();
    /// @dev OfferDurationExceedsLoanMaturity: Offer would expire after maturity minus buffer
    error OfferDurationExceedsLoanMaturity();
    /// @dev MarketplaceFrozen: Operation within MATURITY_BUFFER of loan maturity
    error MarketplaceFrozen();
    /// @dev OfferDurationTooLong: Offer expiry extends past marketplace freeze point
    error OfferDurationTooLong();
    /// @dev OfferExpired: Accepting an already-expired offer
    error OfferExpired();
    /// @dev TooManyOffers: MAX_OFFERS_PER_LISTING reached (gas DoS protection)
    error TooManyOffers();
    /// @dev PriceExceedsMaximum: Listing price exceeds buyer's maxPrice (slippage protection)
    error PriceExceedsMaximum();
    /// @dev PaymentTokenMismatch: Listing payment token differs from buyer's expected token (slippage protection)
    error PaymentTokenMismatch();

    error OfferBelowMinimum();

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier validLoanToken(address token) {
        // Validate loan token address
        if (token == address(0)) revert InvalidToken();
        // Continue to the modified function body
        _;
    }

    // ============================================================================
    // INITIALIZER
    // ============================================================================

    /// @notice Initialize the protocol
    /// @param _positionNFT NFTPositionNFT contract address
    function initialize(address _positionNFT) external initializer {
        // Reject zero address to prevent permanently locked funds
        if (_positionNFT == address(0)) revert ZeroAddress();

        __Ownable_init(msg.sender);
        // Initialize emergency pause mechanism as unpaused
        __Pausable_init();
        // Initialize reentrancy guard mutex as unlocked
        __ReentrancyGuard_init();

        positionNFT = INFTPositionNFT(_positionNFT);
    }

    // ============================================================================
    // ERC-721 RECEIVER
    // ============================================================================

    /// @notice Handle receiving NFTs - required for safeTransferFrom
    function onERC721Received(
        address,
        address,
        uint256,
        // Extra data (unused â€” we accept all NFT transfers)
        bytes calldata
    ) external pure override returns (bytes4) {
        // Return magic value to accept ERC-721 safeTransferFrom
        return this.onERC721Received.selector;
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /// @notice Pause the protocol (emergency only)
    function pause() external onlyOwner {
        // Activate emergency pause
        _pause();
    }

    /// @notice Unpause the protocol
    function unpause() external onlyOwner {
        // Deactivate emergency pause
        _unpause();
    }

    // ============================================================================
    // PAUSE-TIME FREEZE - INTERNAL HOOKS AND HELPER
    // ============================================================================

    /// @dev Override OpenZeppelin _pause() to record the moment the pause begins.
    ///      Time-based deadlines for existing positions effectively freeze from this point.
    function _pause() internal virtual override {
        // Record start of this pause cycle
        pauseStartTimestamp = block.timestamp;
        super._pause();
    }

    /// @dev Override OpenZeppelin _unpause() to fold the completed pause cycle into
    ///      the cumulative total. Subsequent _pauseElapsed() calls reflect the new total.
    function _unpause() internal virtual override {
        // Add this cycle's duration to the cumulative total
        totalPausedDuration += block.timestamp - pauseStartTimestamp;
        // Clear the in-progress marker
        pauseStartTimestamp = 0;
        super._unpause();
    }

    /// @notice Compute the pause time accrued since a given snapshot, including any in-progress pause.
    /// @dev For a position created when totalPausedDuration was `snapshot`, the return value is
    ///      the number of seconds of pause time that have elapsed during the position's lifetime.
    ///      Add this to any deadline derived from the position's creation time to get the pause-adjusted
    ///      effective deadline. Always returns a non-negative value because totalPausedDuration is
    ///      monotonically non-decreasing and snapshot is captured at creation.
    /// @param snapshot The totalPausedDuration value captured when the position was created
    /// @return elapsed Pause-time seconds accrued since the snapshot
    function _pauseElapsed(uint256 snapshot) internal view returns (uint256 elapsed) {
        uint256 currentTotal = totalPausedDuration;
        // Add in-progress pause time if currently paused
        if (paused()) {
            currentTotal += block.timestamp - pauseStartTimestamp;
        }
        return currentTotal - snapshot;
    }

    // ============================================================================
    // OPERATOR APPROVALS
    // ============================================================================

    /// @notice Approve or revoke an operator to act on your behalf
    /// @param operator Address to approve/revoke
    /// @param approved Whether to approve or revoke
    function setOperatorApproval(address operator, bool approved) external {
        // Reject zero address to prevent permanently locked funds
        if (operator == address(0)) revert ZeroAddress();
        // Update operator permission mapping
        operatorApprovals[msg.sender][operator] = approved;
        // Emit OperatorApprovalSet for off-chain indexing and frontend updates
        emit OperatorApprovalSet(msg.sender, operator, approved);
    }

    // ============================================================================
    // AUCTION CREATION
    // ============================================================================

    /**
     * @notice Create a new loan auction with NFT collateral
     * @dev NFT is transferred to this contract and locked for the auction
     * @param collateralNFT NFT contract address
     * @param collateralTokenId NFT token ID to use as collateral
     * @param loanToken Token to borrow (stablecoin)
     * @param loanAmount Amount to borrow
     * @param maxRepayment Maximum total repayment (caps interest rate)
     * @param loanDuration Loan duration in seconds
     * @param auctionDuration Auction duration in seconds
     * @param bidStep Minimum bid improvement required
     * @return auctionId The ID of the created auction
     */
    function createAuction(
        address collateralNFT,
        uint256 collateralTokenId,
        address loanToken,
        uint256 loanAmount,
        uint256 maxRepayment,
        uint256 loanDuration,
        uint256 auctionDuration,
        // Minimum bid improvement (0 = default to MIN_BID_STEP)
        uint256 bidStep
    ) 
        external 
        whenNotPaused 
        nonReentrant 
        // Validate loan token address is non-zero
        validLoanToken(loanToken)
        returns (uint256 auctionId) 
    {
        // Validate NFT
        if (collateralNFT == address(0)) revert InvalidNFT();
        
        // Verify caller owns the NFT
        if (IERC721(collateralNFT).ownerOf(collateralTokenId) != msg.sender) {
            // Caller does not own the required NFT
            revert NotNFTOwner();
        }

        // Validate amounts
        if (loanAmount == 0) revert InvalidAmount();
        // maxRepayment must be >= loanAmount (non-negative interest only)
        if (maxRepayment < loanAmount) revert InvalidRepayment();

        // Validate durations
        if (auctionDuration < MIN_AUCTION_DURATION || auctionDuration > MAX_AUCTION_DURATION) {
            // Duration outside protocol bounds
            revert InvalidDuration();
        }
        // Validate loan duration is within allowed bounds
        if (loanDuration < MIN_LOAN_DURATION || loanDuration > MAX_LOAN_DURATION) {
            // Duration outside protocol bounds
            revert InvalidDuration();
        }

        // Determine effective bid step (clamp to MIN_BID_STEP if below minimum, including 0).
        // Previously this only substituted MIN_BID_STEP when bidStep == 0, allowing values
        // 1..MIN_BID_STEP-1 to bypass the floor entirely (Sherlock #12). Now matches LoanProtocol.
        uint256 effectiveBidStep = bidStep < MIN_BID_STEP ? MIN_BID_STEP : bidStep;
        // Reject bid step exceeding MAX_BID_STEP_BPS of loanAmount.
        // Without this cap, a borrower could set bidStep so large that the maxValidBid
        // computation in placeBid would underflow below loanAmount, silently degrading
        // the auction to strict-monotonic-only bidding (any tiny improvement accepted).
        if (effectiveBidStep > (loanAmount * MAX_BID_STEP_BPS) / BPS_DENOMINATOR) {
            revert BidStepTooHigh();
        }

        // Create auction
        auctionId = ++loanNonce;

        auctions[auctionId] = Auction({
            borrower: msg.sender,
            collateralNFT: collateralNFT,
            collateralTokenId: collateralTokenId,
            loanToken: loanToken,
            loanAmount: loanAmount,
            maxRepayment: maxRepayment,
            loanDuration: loanDuration,
            // Set auction deadline relative to current block timestamp
            auctionEnd: block.timestamp + auctionDuration,
            // No bidder yet â€” set on first bid
            currentBidder: address(0),
            // Start at 0 â€” bids fill from maxRepayment downward
            currentBid: 0,
            // Zero bids initially
            bidCount: 0,
            // Auction starts in OPEN state, accepting bids
            status: AuctionStatus.OPEN,
            // Per-auction bid step (configurable, clamped above to [MIN_BID_STEP, MAX_BID_STEP_BPS%])
            bidStep: effectiveBidStep,
            // Snapshot pause-time accumulator so this auction's deadlines freeze during pause
            pauseSnapshot: totalPausedDuration
        });

        // Transfer NFT to this contract
        IERC721(collateralNFT).safeTransferFrom(msg.sender, address(this), collateralTokenId);

        emit NFTCollateralDeposited(auctionId, msg.sender, collateralNFT, collateralTokenId);

        emit AuctionCreated(
            auctionId,
            msg.sender,
            collateralNFT,
            collateralTokenId,
            loanToken,
            loanAmount,
            maxRepayment,
            loanDuration,
            // Pass calculated auction end timestamp to event
            block.timestamp + auctionDuration
        );
    }

    /**
     * @notice Create an auction on behalf of another user (for ListingService)
     * @dev The borrower must have approved this contract to transfer their NFT
     */
    function createAuctionFor(
        address borrower,
        address collateralNFT,
        uint256 collateralTokenId,
        address loanToken,
        uint256 loanAmount,
        uint256 maxRepayment,
        uint256 loanDuration,
        uint256 auctionDuration,
        uint256 bidStep
    ) 
        external 
        whenNotPaused 
        nonReentrant 
        // Validate loan token address is non-zero
        validLoanToken(loanToken)
        returns (uint256 auctionId) 
    {
        // Reject zero address to prevent permanently locked funds
        if (borrower == address(0)) revert ZeroAddress();
        // Validate NFT contract address is non-zero
        if (collateralNFT == address(0)) revert InvalidNFT();
        
        // SECURITY: Only the borrower or an approved operator can create auctions
        // Prevents attackers from forcing NFT transfers for approved users
        if (msg.sender != borrower && !operatorApprovals[borrower][msg.sender]) {
            // Caller lacks required permission for this action
            revert Unauthorized();
        }
        
        // Verify borrower owns the NFT
        if (IERC721(collateralNFT).ownerOf(collateralTokenId) != borrower) {
            // Caller does not own the required NFT
            revert NotNFTOwner();
        }

        if (loanAmount == 0) revert InvalidAmount();
        // maxRepayment must be >= loanAmount (non-negative interest only)
        if (maxRepayment < loanAmount) revert InvalidRepayment();

        if (auctionDuration < MIN_AUCTION_DURATION || auctionDuration > MAX_AUCTION_DURATION) {
            // Duration outside protocol bounds
            revert InvalidDuration();
        }
        // Validate loan duration is within allowed bounds
        if (loanDuration < MIN_LOAN_DURATION || loanDuration > MAX_LOAN_DURATION) {
            // Duration outside protocol bounds
            revert InvalidDuration();
        }

        // Determine effective bid step (clamp to MIN_BID_STEP if below minimum, including 0).
        // Previously this only substituted MIN_BID_STEP when bidStep == 0, allowing values
        // 1..MIN_BID_STEP-1 to bypass the floor entirely (Sherlock #12). Now matches LoanProtocol.
        uint256 effectiveBidStep = bidStep < MIN_BID_STEP ? MIN_BID_STEP : bidStep;
        // Reject bid step exceeding MAX_BID_STEP_BPS of loanAmount.
        if (effectiveBidStep > (loanAmount * MAX_BID_STEP_BPS) / BPS_DENOMINATOR) {
            revert BidStepTooHigh();
        }

        auctionId = ++loanNonce;

        auctions[auctionId] = Auction({
            borrower: borrower,
            collateralNFT: collateralNFT,
            collateralTokenId: collateralTokenId,
            loanToken: loanToken,
            loanAmount: loanAmount,
            maxRepayment: maxRepayment,
            loanDuration: loanDuration,
            // Set auction deadline relative to current block timestamp
            auctionEnd: block.timestamp + auctionDuration,
            // No bidder yet â€” set on first bid
            currentBidder: address(0),
            // Start at 0 â€” bids fill from maxRepayment downward
            currentBid: 0,
            // Zero bids initially
            bidCount: 0,
            // Auction starts in OPEN state, accepting bids
            status: AuctionStatus.OPEN,
            // Per-auction bid step (configurable, clamped above to [MIN_BID_STEP, MAX_BID_STEP_BPS%])
            bidStep: effectiveBidStep,
            // Snapshot pause-time accumulator so this auction's deadlines freeze during pause
            pauseSnapshot: totalPausedDuration
        });

        // Transfer NFT directly from borrower to this contract
        // Borrower must have approved this contract (NFTLoanProtocol)
        IERC721(collateralNFT).safeTransferFrom(borrower, address(this), collateralTokenId);

        emit NFTCollateralDeposited(auctionId, borrower, collateralNFT, collateralTokenId);

        emit AuctionCreated(
            auctionId,
            borrower,
            collateralNFT,
            collateralTokenId,
            loanToken,
            loanAmount,
            maxRepayment,
            loanDuration,
            // Pass calculated auction end timestamp to event
            block.timestamp + auctionDuration
        );
    }

    // ============================================================================
    // AUCTION MANAGEMENT
    // ============================================================================

    /// @notice Cancel an auction with no bids
    /// @param auctionId Auction to cancel
    function cancelAuction(uint256 auctionId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        
        if (auction.borrower == address(0)) revert AuctionNotFound();
        // Only the auction creator (borrower) can cancel
        if (auction.borrower != msg.sender) revert NotBorrower();
        // Only OPEN auctions accept bids / can be finalized
        if (auction.status != AuctionStatus.OPEN) revert AuctionNotOpen();
        // Cannot cancel â€” existing bids create obligations to bidders
        if (auction.bidCount > 0) revert HasBids();

        // Cache values
        address collateralNFT = auction.collateralNFT;
        // Cache NFT token ID before state changes
        uint256 collateralTokenId = auction.collateralTokenId;

        // Effects
        auction.status = AuctionStatus.CANCELLED;

        // Return NFT to borrower
        IERC721(collateralNFT).safeTransferFrom(address(this), msg.sender, collateralTokenId);

        emit AuctionCancelled(auctionId);
    }

    /// @notice Place a bid on an auction
    /// @param auctionId Auction to bid on
    /// @param repaymentAmount Total repayment offered (lower = better for borrower)
    function placeBid(uint256 auctionId, uint256 repaymentAmount) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        
        if (auction.borrower == address(0)) revert AuctionNotFound();
        // Only OPEN auctions accept bids / can be finalized
        if (auction.status != AuctionStatus.OPEN) revert AuctionNotOpen();
        // Bidding window has closed â€” no more bids accepted
        if (block.timestamp >= auction.auctionEnd + _pauseElapsed(auction.pauseSnapshot)) revert AuctionEnded();
        // Caller lacks required permission for this action
        if (msg.sender == auction.borrower) revert Unauthorized();

        // Validate bid amount
        if (repaymentAmount < auction.loanAmount) revert BidTooLow();

        // Calculate max valid bid
        uint256 maxValidBid = auction.bidCount == 0 
            // First bid: max is maxRepayment; subsequent: current minus step
            ? auction.maxRepayment 
            // Subsequent: check if step subtraction is safe
            : auction.currentBid > auction.bidStep 
                // Subtract bid step from current bid (may underflow to 0)
                ? auction.currentBid - auction.bidStep 
                // Fallback to 0 if subtraction would underflow
                : 0;

        // Near-zero interest edge case handling
        if (maxValidBid < auction.loanAmount) {
            // Bid must improve on current best by at least bidStep
            if (repaymentAmount >= auction.currentBid) revert BidTooHigh();
        // Has bids â€” proceed to finalize
        } else {
            // Bid must improve on current best by at least bidStep
            if (repaymentAmount > maxValidBid) revert BidTooHigh();
        }

        // Cache previous bidder for refund
        address previousBidder = auction.currentBidder;
        // Cache in memory to save gas on repeated storage reads
        address loanToken = auction.loanToken;
        // Cache loan amount in memory for gas efficiency
        uint256 loanAmount = auction.loanAmount;
        // Determine if there is a previous bidder who needs a refund
        bool hasPreviousBid = auction.bidCount > 0 && previousBidder != address(0);

        // Effects
        auction.currentBidder = msg.sender;
        // Record new winning bid (lowest repayment = best for borrower)
        auction.currentBid = repaymentAmount;
        // Increment bid counter for auction analytics
        auction.bidCount++;

        // End auction early if bid reached loanAmount floor (zero interest).
        // No further bid can improve on this: any subsequent bid is either < loanAmount
        // (rejected by BidTooLow) or >= currentBid (rejected by BidTooHigh in the
        // near-zero-interest branch). Waiting for auctionEnd is pointless (Sherlock #21).
        // Collapse the effective deadline to now by subtracting the accumulated pause
        // elapsed so that auction.auctionEnd + _pauseElapsed(pauseSnapshot) == block.timestamp.
        // finalizeAuction can then be called immediately; view functions report the
        // auction as ended; claimExpiredAuction's window starts from this moment.
        if (repaymentAmount == loanAmount) {
            uint256 pauseElapsed = _pauseElapsed(auction.pauseSnapshot);
            auction.auctionEnd = block.timestamp - pauseElapsed;
            emit AuctionFloorReached(auctionId, msg.sender);
        }

        // Queue refund for previous bidder (pull pattern)
        // Refund loanAmount since that's what was actually escrowed
        if (hasPreviousBid) {
            // Queue refund via pull pattern â€” recipient claims via claimRefund()
            pendingRefunds[previousBidder][loanToken] += loanAmount;
            // Emit RefundAvailable for off-chain indexing and frontend updates
            emit RefundAvailable(previousBidder, loanToken, loanAmount, auctionId);
        }

        // Transfer loan amount (principal only) from new bidder to escrow
        // Only principal is escrowed â€” matches ERC20 LoanProtocol pattern.
        // The bid records the full repaymentAmount, but only loanAmount is held.
        IERC20(loanToken).safeTransferFrom(msg.sender, address(this), loanAmount);

        emit BidPlaced(auctionId, msg.sender, repaymentAmount, auction.bidCount);
    }

    /// @notice Claim refund from being outbid
    /// @param token Token to claim refund in
    function claimRefund(address token) external whenNotPaused nonReentrant {
        // Read pending refund balance for this user/token pair
        uint256 refundAmount = pendingRefunds[msg.sender][token];
        // No pending refund balance for this user/token pair
        if (refundAmount == 0) revert NoRefundAvailable();

        pendingRefunds[msg.sender][token] = 0;

        IERC20(token).safeTransfer(msg.sender, refundAmount);

        emit RefundClaimed(msg.sender, token, refundAmount);
    }

    /// @notice Finalize an auction and create the loan
    /// @param auctionId Auction to finalize
    function finalizeAuction(uint256 auctionId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        
        if (auction.borrower == address(0)) revert AuctionNotFound();
        // Only OPEN auctions accept bids / can be finalized
        if (auction.status != AuctionStatus.OPEN) revert AuctionNotOpen();
        // Auction must have ended before finalization or expiry
        if (block.timestamp < auction.auctionEnd + _pauseElapsed(auction.pauseSnapshot)) revert AuctionStillOpen();
        // Check if finalization window has passed
        if (block.timestamp > auction.auctionEnd + FINALIZATION_WINDOW + _pauseElapsed(auction.pauseSnapshot)) {
            // Window closed â€” use claimExpiredAuction() instead
            revert FinalizationWindowExpired();
        }

        // Handle no bids case
        if (auction.bidCount == 0) {
            // Mark auction cancelled â€” NFT will be returned
            auction.status = AuctionStatus.CANCELLED;
            
            // Return NFT to borrower
            IERC721(auction.collateralNFT).safeTransferFrom(
                address(this), 
                auction.borrower, 
                // Pass NFT token ID to transfer
                auction.collateralTokenId
            );
            
            emit AuctionExpiredNoBids(auctionId);
            // Exit early â€” no loan to create
            return;
        }

        // Cache values
        address borrower = auction.borrower;
        // Cache winning bidder as lender for the new loan
        address lender = auction.currentBidder;
        // Cache loan amount in memory for gas efficiency
        uint256 loanAmount = auction.loanAmount;
        // Cache winning bid as repayment amount
        uint256 repaymentAmount = auction.currentBid;
        // Cache in memory to save gas on repeated storage reads
        address loanToken = auction.loanToken;

        // Effects - update auction
        auction.status = AuctionStatus.FINALIZED;

        // Create loan record
        loans[auctionId] = Loan({
            borrower: borrower,
            collateralNFT: auction.collateralNFT,
            collateralTokenId: auction.collateralTokenId,
            loanToken: loanToken,
            loanAmount: loanAmount,
            repaymentAmount: repaymentAmount,
            // Calculate absolute maturity: now + loan duration
            maturityTimestamp: block.timestamp + auction.loanDuration,
            lender: lender,
            // Loan starts in ACTIVE state
            status: LoanStatus.ACTIVE,
            // Snapshot pause-time accumulator so this loan's maturity and grace deadlines freeze during pause
            pauseSnapshot: totalPausedDuration
        });

        // Mint position NFTs
        positionNFT.mintBorrowerPosition(auctionId, borrower);
        // Mint lender position NFT â€” holder receives repayment or claims collateral
        positionNFT.mintLenderPosition(auctionId, lender);

        // Store loan metadata for NFT display
        positionNFT.setLoanMetadata(
            auctionId,
            auction.collateralNFT,
            auction.collateralTokenId,
            loanToken,
            loanAmount,
            repaymentAmount,
            // Pass calculated maturity timestamp to NFT metadata
            block.timestamp + auction.loanDuration
        );

        // Transfer loan amount to borrower (repayment amount is already held from bid)
        // The difference (repaymentAmount - loanAmount) stays in contract until repayment
        IERC20(loanToken).safeTransfer(borrower, loanAmount);

        emit AuctionFinalized(auctionId, auctionId, lender, repaymentAmount);
    }

    /// @notice Claim funds from an expired auction (not finalized within window)
    /// @param auctionId The expired auction ID
    function claimExpiredAuction(uint256 auctionId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        
        if (auction.borrower == address(0)) revert AuctionNotFound();
        // Allow claims for both OPEN (first claim) and EXPIRED (subsequent) auctions
        if (auction.status != AuctionStatus.OPEN && auction.status != AuctionStatus.EXPIRED) {
            // Only OPEN auctions accept bids / can be finalized
            revert AuctionNotOpen();
        }
        // Verify finalization window has expired before allowing expiry claims
        if (block.timestamp <= auction.auctionEnd + FINALIZATION_WINDOW + _pauseElapsed(auction.pauseSnapshot)) {
            // Cannot claim as expired while finalization still possible
            revert FinalizationWindowActive();
        }
        // No bids were placed â€” nothing to claim
        if (auction.bidCount == 0) revert NoBids();

        bool isLender = msg.sender == auction.currentBidder;
        // Check if claimant is the auction borrower
        bool isBorrower = msg.sender == auction.borrower;
        
        if (!isLender && !isBorrower) revert Unauthorized();

        // Mark as expired if not already
        if (auction.status == AuctionStatus.OPEN) {
            // Mark auction expired â€” both parties can reclaim funds/NFT
            auction.status = AuctionStatus.EXPIRED;
            // Emit AuctionExpiredNotFinalized for off-chain indexing and frontend updates
            emit AuctionExpiredNotFinalized(auctionId, auction.borrower, auction.currentBidder);
        }

        if (isLender) {
            // Prevent double-claiming from expired auctions
            if (expiredAuctionLenderClaimed[auctionId]) revert AlreadyClaimed();
            // Mark lender claim as complete (prevents double-claim)
            expiredAuctionLenderClaimed[auctionId] = true;

            // Return escrowed loan amount (principal) to lender
            uint256 escrowedAmount = auction.loanAmount;
            // Push tokens to caller
            IERC20(auction.loanToken).safeTransfer(msg.sender, escrowedAmount);

            emit ExpiredAuctionClaimed(auctionId, msg.sender, true, escrowedAmount);
        }

        if (isBorrower) {
            // Prevent double-claiming from expired auctions
            if (expiredAuctionBorrowerClaimed[auctionId]) revert AlreadyClaimed();
            // Mark borrower claim as complete (prevents double-claim)
            expiredAuctionBorrowerClaimed[auctionId] = true;

            // Return NFT to borrower
            IERC721(auction.collateralNFT).safeTransferFrom(
                address(this),
                msg.sender,
                // Pass NFT token ID to transfer
                auction.collateralTokenId
            );

            emit ExpiredAuctionNFTClaimed(
                auctionId, 
                msg.sender, 
                auction.collateralNFT, 
                // Pass NFT token ID to event
                auction.collateralTokenId
            );
        }
    }

    // ============================================================================
    // LOAN MANAGEMENT
    // ============================================================================

    /// @notice Repay a loan and reclaim collateral NFT
    /// @param loanId Loan to repay
    function repayLoan(uint256 loanId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        
        if (loan.borrower == address(0)) revert LoanNotFound();
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        // Too late to repay â€” grace period has ended
        if (block.timestamp >= loan.maturityTimestamp + GRACE_PERIOD + _pauseElapsed(loan.pauseSnapshot)) revert GracePeriodExpired();  

        // Verify caller owns borrower position NFT
        uint256 borrowerTokenId = positionNFT.getBorrowerTokenId(loanId);
        // Caller lacks required permission for this action
        if (positionNFT.ownerOf(borrowerTokenId) != msg.sender) revert Unauthorized();

        // Cache values
        address loanToken = loan.loanToken;
        // Cache repayment amount before state changes
        uint256 repaymentAmount = loan.repaymentAmount;
        // Cache NFT contract address before state update
        address collateralNFT = loan.collateralNFT;
        // Cache NFT token ID before state update
        uint256 collateralTokenId = loan.collateralTokenId;

        // Get lender's current address (NFT owner)
        uint256 lenderTokenId = positionNFT.getLenderTokenId(loanId);
        // Resolve current owner from NFT (may differ from stored loan record)
        address lenderAddress = positionNFT.ownerOf(lenderTokenId);

        // Effects
        loan.status = LoanStatus.REPAID;

        // Burn position NFTs
        positionNFT.burn(borrowerTokenId);
        // Burn lender position NFT â€” loan resolved
        positionNFT.burn(lenderTokenId);

        // Transfer repayment to lender
        IERC20(loanToken).safeTransferFrom(msg.sender, lenderAddress, repaymentAmount);

        // Return collateral NFT to borrower
        IERC721(collateralNFT).safeTransferFrom(address(this), msg.sender, collateralTokenId);

        emit LoanRepaid(loanId, msg.sender, repaymentAmount);
    }

    /// @notice Claim collateral NFT from a defaulted loan
    /// @param loanId Loan to claim from
    function claimCollateral(uint256 loanId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        
        if (loan.borrower == address(0)) revert LoanNotFound();
        // Loan must be ACTIVE or already DEFAULTED (via markDefault) for this operation
        if (loan.status != LoanStatus.ACTIVE && loan.status != LoanStatus.DEFAULTED) revert LoanNotActive();
        // Cannot claim collateral before loan maturity
        if (block.timestamp < loan.maturityTimestamp + _pauseElapsed(loan.pauseSnapshot)) revert LoanNotMatured();
        // Must wait for grace period to end before default claim
        if (block.timestamp < loan.maturityTimestamp + GRACE_PERIOD + _pauseElapsed(loan.pauseSnapshot)) revert GracePeriodNotEnded();

        // Verify caller owns lender position NFT
        uint256 lenderTokenId = positionNFT.getLenderTokenId(loanId);
        // Caller lacks required permission for this action
        if (positionNFT.ownerOf(lenderTokenId) != msg.sender) revert Unauthorized();

        // Cache values
        address collateralNFT = loan.collateralNFT;
        // Cache NFT token ID before state update
        uint256 collateralTokenId = loan.collateralTokenId;

        // Effects
        loan.status = LoanStatus.DEFAULTED;

        // Burn position NFTs
        positionNFT.burn(positionNFT.getBorrowerTokenId(loanId));
        // Burn lender position NFT â€” loan resolved
        positionNFT.burn(lenderTokenId);

        // Transfer collateral NFT to lender
        IERC721(collateralNFT).safeTransferFrom(address(this), msg.sender, collateralTokenId);

        emit LoanDefaulted(loanId, msg.sender, collateralNFT, collateralTokenId);
    }

    /// @notice Permissionlessly mark a loan as defaulted past grace period
    /// @dev Additive to claimCollateral: transitions ACTIVE -> DEFAULTED without transferring collateral.
    ///      Anyone can call after maturity + GRACE_PERIOD has elapsed (pause-adjusted).
    ///      claimCollateral() remains the path that transfers collateral and burns NFTs; this
    ///      function only provides an on-chain default signal for indexers and downstream
    ///      extensions (insurance, BOND, dashboards) that need a definitive default event
    ///      independent of the lender's claim timing.
    /// @param loanId Loan to mark as defaulted
    function markDefault(uint256 loanId) external whenNotPaused {
        // Load loan from storage
        Loan storage loan = loans[loanId];
        // Verify loan exists
        if (loan.borrower == address(0)) revert LoanNotFound();
        // Only ACTIVE loans may be marked; prevents double-emission and matches claim gating
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        // Maturity check must use pause-adjusted timing (mirrors claimCollateral)
        if (block.timestamp < loan.maturityTimestamp + _pauseElapsed(loan.pauseSnapshot)) revert LoanNotMatured();
        // Grace period check must use pause-adjusted timing (mirrors claimCollateral)
        if (block.timestamp < loan.maturityTimestamp + GRACE_PERIOD + _pauseElapsed(loan.pauseSnapshot)) revert GracePeriodNotEnded();

        // Transition status; no external calls, no transfers, no NFT burns
        loan.status = LoanStatus.DEFAULTED;

        emit LoanDefaultMarked(loanId);
    }

    // ============================================================================
    // NFT POSITION TRANSFERS (INTERNAL - FOR MARKETPLACE)
    // ============================================================================

    /// @notice Transfer borrower position
    function _transferBorrowerPosition(uint256 loanId, address from, address to) internal {
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        // Verify loan record exists
        if (loan.borrower == address(0)) revert LoanNotFound();
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        // Reject zero address to prevent permanently locked funds
        if (to == address(0)) revert ZeroAddress();

        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);
        // Caller must own the position NFT
        if (positionNFT.ownerOf(tokenId) != from) revert NotPositionOwner();

        loan.borrower = to;
        // Transfer position NFT to new owner
        positionNFT.transferFrom(from, to, tokenId);

        emit BorrowerPositionTransferred(loanId, from, to);
    }

    /// @notice Transfer lender position
    function _transferLenderPosition(uint256 loanId, address from, address to) internal {
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        // Verify loan record exists
        if (loan.borrower == address(0)) revert LoanNotFound();
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        // Reject zero address to prevent permanently locked funds
        if (to == address(0)) revert ZeroAddress();

        uint256 tokenId = positionNFT.getLenderTokenId(loanId);
        // Caller must own the position NFT
        if (positionNFT.ownerOf(tokenId) != from) revert NotPositionOwner();

        loan.lender = to;
        // Transfer position NFT to new owner
        positionNFT.transferFrom(from, to, tokenId);

        emit LenderPositionTransferred(loanId, from, to);
    }

    // ============================================================================
    // INTEGRATED MARKETPLACE - LISTINGS
    // ============================================================================

    /// @notice List a position for sale on the marketplace
    function listPosition(
        uint256 loanId,
        string calldata positionType,
        address paymentToken,
        uint256 askingPrice,
        uint256 minOfferAmount
    ) external whenNotPaused {
        // Delegate to internal listing logic
        _listPosition(loanId, msg.sender, positionType, paymentToken, askingPrice, minOfferAmount);
    }

    /// @notice List a position for sale on behalf of the position owner
    /// @dev Caller must be an approved operator (via setOperatorApproval)
    /// @param minOfferAmount Minimum offer the seller will accept (0 = no floor)
    function listPositionFor(
        uint256 loanId,
        address seller,
        string calldata positionType,
        address paymentToken,
        uint256 askingPrice,
        uint256 minOfferAmount
    ) external whenNotPaused {
        // Reject zero address to prevent permanently locked funds
        if (seller == address(0)) revert ZeroAddress();
        // SECURITY: Caller must be seller or approved operator
        if (msg.sender != seller && !operatorApprovals[seller][msg.sender]) {
            // Caller lacks required permission for this action
            revert Unauthorized();
        }
        // Delegate to internal listing logic
        _listPosition(loanId, seller, positionType, paymentToken, askingPrice, minOfferAmount);
    }

    /// @dev Internal listing logic
    function _listPosition(
        uint256 loanId,
        address seller,
        string calldata positionType,
        address paymentToken,
        // Listing price in payment token units
        uint256 askingPrice,
        // Minimum offer floor in paymentToken units (0 = no floor)
        uint256 minOfferAmount
    ) internal {
        // Listing price must be non-zero
        if (askingPrice == 0) revert InvalidPrice();
        // Min offer floor must not exceed asking price
        if (minOfferAmount > askingPrice) revert InvalidPrice();
        // Reject zero address to prevent permanently locked funds
        if (paymentToken == address(0)) revert ZeroAddress();

        bool isBorrower = _compareStrings(positionType, "borrower");
        // Check if this is a lender position
        bool isLender = _compareStrings(positionType, "lender");
        // Must be exactly "borrower" or "lender"
        if (!isBorrower && !isLender) revert InvalidPositionType();

        // Derive Position NFT token ID (borrower=even, lender=odd)
        uint256 tokenId = isBorrower 
            // If borrower: use even token ID; otherwise: use odd token ID
            ? positionNFT.getBorrowerTokenId(loanId)
            // Lender position NFT token ID (odd numbers)
            : positionNFT.getLenderTokenId(loanId);
        
        // Cannot create duplicate listings for the same position
        if (marketplaceListings[tokenId].active) revert AlreadyListed();
        
        if (positionNFT.ownerOf(tokenId) != seller) revert NotPositionOwner();

        // Verify loan is still active
        Loan storage loan = loans[loanId];
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        
        // Block listing if within maturity buffer (marketplace frozen)
        uint256 freezeTime = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback: for very short loans, freeze only at maturity itself
            : loan.maturityTimestamp;
        // Operations blocked within MATURITY_BUFFER of loan maturity
        if (block.timestamp >= freezeTime + _pauseElapsed(loan.pauseSnapshot)) revert MarketplaceFrozen();

        marketplaceListings[tokenId] = MarketplaceListing({
            seller: seller,
            // Store loan ID for downstream loan lookups
            loanId: loanId,
            positionType: positionType,
            // Cache listing payment token for refund routing
            paymentToken: paymentToken,
            askingPrice: askingPrice,
            // Minimum offer floor (0 = no floor)
            minOfferAmount: minOfferAmount,
            // Record listing creation timestamp
            listedAt: block.timestamp,
            // Listing starts as active
            active: true
        });

        emit PositionListed(loanId, seller, positionType, paymentToken, askingPrice, minOfferAmount);
    }

    /// @notice Remove a listing from the marketplace
    /// @dev Automatically refunds all pending offers. Allows both the stored seller
    ///      and the current position NFT owner to unlist (handles stale listings after direct transfers).
    function unlistPosition(uint256 tokenId) external whenNotPaused nonReentrant {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[tokenId];
        uint256 loanId = listing.loanId;
        // Position must be actively listed
        if (!listing.active) revert NotListed();
        // Allow stored seller OR current NFT owner to unlist
        bool isSeller = listing.seller == msg.sender;
        bool isCurrentOwner = _getPositionOwner(loanId, listing.positionType) == msg.sender;
        if (!isSeller && !isCurrentOwner) revert NotSeller();

        listing.active = false;
        // Refund ALL pending offers (0 = no accepted offer to skip)
        _refundOtherOffers(tokenId, loanId, 0);
        // Reset offer counter AFTER refunds (must read nonce first)
        marketplaceOfferNonce[tokenId] = 0;
        // Reset active offer counter at finalization (Sherlock #13)
        activeOfferCount[tokenId] = 0;

        emit PositionUnlisted(loanId);
    }

    /// @notice Clean up a stale listing where the seller no longer owns the position NFT
    /// @dev Permissionless — anyone can call to deactivate stale listings and free escrowed offers.
    /// @param tokenId Position NFT token ID with stale listing
    function cleanStaleListing(uint256 tokenId) external whenNotPaused nonReentrant {
        MarketplaceListing storage listing = marketplaceListings[tokenId];
        uint256 loanId = listing.loanId;
        if (!listing.active) revert NotListed();

        // Verify the listing is actually stale (seller no longer owns the position)
        address currentOwner = _getPositionOwner(loanId, listing.positionType);
        if (currentOwner == listing.seller) revert ListingNotStale();

        listing.active = false;
        // Refund all pending offers
        _refundOtherOffers(tokenId, loanId, 0);
        // Reset offer counter AFTER refunds (must read nonce first)
        marketplaceOfferNonce[tokenId] = 0;
        // Reset active offer counter at finalization (Sherlock #13)
        activeOfferCount[tokenId] = 0;

        emit PositionUnlisted(loanId);
    }

    /// @notice Update listing price
    function updateListingPrice(uint256 tokenId, uint256 newPrice) external whenNotPaused {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[tokenId];
        uint256 loanId = listing.loanId;
        // Position must be actively listed
        if (!listing.active) revert NotListed();
        // Only the listing seller can manage this listing
        if (listing.seller != msg.sender) revert NotSeller();
        // Listing price must be non-zero
        if (newPrice == 0) revert InvalidPrice();

        emit ListingPriceUpdated(loanId, listing.askingPrice, newPrice);
        // Update the asking price in storage
        listing.askingPrice = newPrice;
    }

    // ============================================================================
    // INTEGRATED MARKETPLACE - OFFERS
    // ============================================================================

    /// @notice Make an offer on a listed position
    /// @dev expectedPaymentToken is MEV/front-run protection: the buyer commits to the payment
    ///      token they expect the listing to use. If the seller unlists and re-lists with a
    ///      different (more expensive) token while the buyer's tx is in the mempool, the call
    ///      reverts rather than silently escrowing the wrong token. Mirrors buyPosition.
    /// @param tokenId Position NFT token ID
    /// @param offerAmount Offer amount (will be escrowed)
    /// @param offerDuration How long the offer is valid (minimum 1 day)
    /// @param expectedPaymentToken Expected payment token address (reverts if listing uses different token)
    /// @return offerId The created offer ID
    function makeMarketplaceOffer(uint256 tokenId, uint256 offerAmount, uint256 offerDuration, address expectedPaymentToken) 
        external 
        whenNotPaused 
        nonReentrant
        returns (uint256 offerId) 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[tokenId];
        uint256 loanId = listing.loanId;
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        
        if (!listing.active) revert NotListed();
        // Offer amount must be non-zero
        if (offerAmount == 0) revert InvalidOffer();
        // Reject offers below seller's spam floor (0 = no floor, any non-zero offer passes)
        if (offerAmount < listing.minOfferAmount) revert OfferBelowMinimum();
        // Seller cannot make offers on their own listing
        if (msg.sender == listing.seller) revert CannotBuyOwnPosition();
        // Duration below minimum (prevents instant-expire offers)
        if (offerDuration < MIN_OFFER_DURATION) revert OfferDurationTooShort();
        // Slippage/MEV protection: revert if seller changed the payment token between
        // the buyer's tx construction and execution (Sherlock #14). Without this check,
        // a seller could unlist and re-list with a more expensive token in the same block,
        // causing the buyer's offer tx to escrow the wrong token. Mirrors buyPosition.
        if (listing.paymentToken != expectedPaymentToken) revert PaymentTokenMismatch();

        // Calculate max allowed expiry (maturity - buffer)
        uint256 maxExpiry = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback: for very short loans, freeze only at maturity itself
            : loan.maturityTimestamp;
        
        // Reject if marketplace is frozen (within buffer period)
        if (block.timestamp >= maxExpiry + _pauseElapsed(loan.pauseSnapshot)) revert MarketplaceFrozen();
        
        // Reject if offer duration extends past the buffer (no silent capping)
        uint256 requestedExpiry = block.timestamp + offerDuration;
        // Offer must expire before marketplace freeze point
        if (requestedExpiry > maxExpiry + _pauseElapsed(loan.pauseSnapshot)) revert OfferDurationTooLong();

        // Prevent gas DoS: cap ACTIVE offers to bound _refundOtherOffers loop.
        // Counts only PENDING + COUNTERED offers, not the monotonic nonce, so an attacker
        // cannot fill the cap with cancelled offers (Sherlock #13).
        if (activeOfferCount[tokenId] >= MAX_OFFERS_PER_LISTING) revert TooManyOffers();

        offerId = ++marketplaceOfferNonce[tokenId];
        activeOfferCount[tokenId]++;

        marketplaceOffers[tokenId][offerId] = MarketplaceOffer({
            buyer: msg.sender,
            amount: offerAmount,
            // Full offer amount held in escrow until resolution
            escrowedAmount: offerAmount,
            // Offer starts in PENDING state, awaiting seller response
            status: MarketplaceOfferStatus.PENDING,
            // No counter-offer initially
            counterAmount: 0,
            // Record offer creation timestamp
            createdAt: block.timestamp,
            // Set offer expiration deadline
            expiresAt: requestedExpiry,
            // Cache listing payment token for refund routing
            paymentToken: listing.paymentToken,
            // Snapshot pause-time accumulator so this offer's expiry freezes during pause
            pauseSnapshot: totalPausedDuration
        });

        IERC20(listing.paymentToken).safeTransferFrom(msg.sender, address(this), offerAmount);

        emit MarketplaceOfferMade(loanId, offerId, msg.sender, offerAmount);
    }

    /// @notice Cancel an offer and get refund
    function cancelMarketplaceOffer(uint256 tokenId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Derive loanId from listing for event emission
        uint256 loanId = marketplaceListings[tokenId].loanId;
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[tokenId][offerId];
        
        if (offer.buyer == address(0)) revert OfferNotFound();
        // Only the offer maker can cancel/accept their offer
        if (offer.buyer != msg.sender) revert NotBuyer();
        // Verify offer is in PENDING state
        if (offer.status != MarketplaceOfferStatus.PENDING && 
            // Also allow COUNTERED offers to be cancelled/expired
            offer.status != MarketplaceOfferStatus.COUNTERED) {
            // Offer not in the expected state for this operation
            revert InvalidOfferStatus();
        }

        uint256 refundAmount = offer.escrowedAmount;
        // Cache payment token for transfer routing
        address paymentToken = offer.paymentToken;

        offer.status = MarketplaceOfferStatus.CANCELLED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;
        // Decrement active offer counter (Sherlock #13: prevent churn-DoS via cancel)
        activeOfferCount[tokenId]--;

        if (refundAmount > 0) {
            // Push tokens to caller
            IERC20(paymentToken).safeTransfer(msg.sender, refundAmount);
        }

        emit MarketplaceOfferCancelled(loanId, offerId);
    }

    /// @notice Reject an offer
    function rejectMarketplaceOffer(uint256 tokenId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[tokenId];
        uint256 loanId = listing.loanId;
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[tokenId][offerId];

        if (!listing.active) revert NotListed();
        // Only the listing seller can manage this listing
        if (listing.seller != msg.sender) revert NotSeller();
        // Verify offer record exists
        if (offer.buyer == address(0)) revert OfferNotFound();
        // Offer not in the expected state for this operation
        if (offer.status != MarketplaceOfferStatus.PENDING) revert InvalidOfferStatus();

        uint256 refundAmount = offer.escrowedAmount;
        // Cache buyer address for refund transfer
        address buyer = offer.buyer;
        // Cache payment token for transfer routing
        address paymentToken = offer.paymentToken;

        offer.status = MarketplaceOfferStatus.REJECTED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;
        // Decrement active offer counter (Sherlock #13: prevent churn-DoS via reject)
        activeOfferCount[tokenId]--;

        if (refundAmount > 0) {
            // Queue refund via pull pattern â€” recipient claims via claimRefund()
            pendingRefunds[buyer][paymentToken] += refundAmount;
            // Emit MarketplaceOfferRefundQueued for off-chain indexing and frontend updates
            emit MarketplaceOfferRefundQueued(loanId, offerId, buyer, refundAmount);
        }

        emit MarketplaceOfferRejected(loanId, offerId);
    }

    /// @notice Expire an offer that has passed its expiration time
    function expireMarketplaceOffer(uint256 tokenId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Derive loanId from listing for event emission
        uint256 loanId = marketplaceListings[tokenId].loanId;
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[tokenId][offerId];

        if (offer.buyer == address(0)) revert OfferNotFound();
        // Verify offer is in PENDING state
        if (offer.status != MarketplaceOfferStatus.PENDING && 
            // Also allow COUNTERED offers to be cancelled/expired
            offer.status != MarketplaceOfferStatus.COUNTERED) {
            // Offer not in the expected state for this operation
            revert InvalidOfferStatus();
        }
        // Offer has not yet reached its expiration timestamp
        if (block.timestamp < offer.expiresAt + _pauseElapsed(offer.pauseSnapshot)) revert OfferNotExpired();

        uint256 refundAmount = offer.escrowedAmount;
        // Cache buyer address for refund transfer
        address buyer = offer.buyer;
        // Cache payment token for transfer routing
        address paymentToken = offer.paymentToken;

        offer.status = MarketplaceOfferStatus.EXPIRED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;
        // Decrement active offer counter (Sherlock #13: prevent churn-DoS via expire)
        activeOfferCount[tokenId]--;

        if (refundAmount > 0) {
            // Queue refund via pull pattern â€” recipient claims via claimRefund()
            pendingRefunds[buyer][paymentToken] += refundAmount;
            // Emit MarketplaceOfferRefundQueued for off-chain indexing and frontend updates
            emit MarketplaceOfferRefundQueued(loanId, offerId, buyer, refundAmount);
        }

        emit MarketplaceOfferExpired(loanId, offerId);
    }

    /// @notice Counter an offer
    function counterMarketplaceOffer(
        uint256 tokenId, 
        uint256 offerId, 
        uint256 counterAmount,
        // New expiry duration for the counter-offer
        // New expiry duration for counter-offer
        uint256 counterDuration
    ) 
        external 
        whenNotPaused 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[tokenId];
        uint256 loanId = listing.loanId;
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[tokenId][offerId];
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];

        if (!listing.active) revert NotListed();
        // Only the listing seller can manage this listing
        if (listing.seller != msg.sender) revert NotSeller();
        // Verify offer record exists
        if (offer.buyer == address(0)) revert OfferNotFound();
        // Offer not in the expected state for this operation
        if (offer.status != MarketplaceOfferStatus.PENDING) revert InvalidOfferStatus();
        // Prevent countering time-expired offers (would revive them with new expiry)
        if (block.timestamp >= offer.expiresAt + _pauseElapsed(offer.pauseSnapshot)) revert OfferExpired();
        // Offer amount must be non-zero
        if (counterAmount == 0) revert InvalidOffer();
        // Duration below minimum (prevents instant-expire offers)
        if (counterDuration < MIN_OFFER_DURATION) revert OfferDurationTooShort();

        // Calculate max allowed expiry (maturity - buffer)
        uint256 maxExpiry = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback: for very short loans, freeze only at maturity itself
            : loan.maturityTimestamp;
        
        // Reject if marketplace is frozen (within buffer period)
        if (block.timestamp >= maxExpiry + _pauseElapsed(loan.pauseSnapshot)) revert MarketplaceFrozen();
        
        // Reject if counter duration extends past the buffer (no silent capping)
        uint256 newExpiry = block.timestamp + counterDuration;
        // Offer must expire before marketplace freeze point
        if (newExpiry > maxExpiry + _pauseElapsed(loan.pauseSnapshot)) revert OfferDurationTooLong();

        offer.status = MarketplaceOfferStatus.COUNTERED;
        // Store the seller's counter-offer price
        offer.counterAmount = counterAmount;
        // Reset expiration for the counter-offer period
        offer.expiresAt = newExpiry;
        // Reset pause snapshot to current total since the new expiry baseline is now
        offer.pauseSnapshot = totalPausedDuration;

        emit MarketplaceCounterOffer(loanId, offerId, counterAmount);
    }

    /// @notice Accept an offer
    function acceptMarketplaceOffer(uint256 tokenId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[tokenId];
        uint256 loanId = listing.loanId;
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[tokenId][offerId];

        if (!listing.active) revert NotListed();
        // Only the listing seller can manage this listing
        if (listing.seller != msg.sender) revert NotSeller();
        // Verify offer record exists
        if (offer.buyer == address(0)) revert OfferNotFound();
        // Offer not in the expected state for this operation
        if (offer.status != MarketplaceOfferStatus.PENDING) revert InvalidOfferStatus();
        
        // Prevent accepting time-expired offers
        if (block.timestamp >= offer.expiresAt + _pauseElapsed(offer.pauseSnapshot)) revert OfferExpired();

        // Verify loan is still active (stale listing protection)
        Loan storage loan = loans[loanId];
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        
        // Block acceptance if within maturity buffer (marketplace frozen)
        uint256 freezeTime = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback: for very short loans, freeze only at maturity itself
            : loan.maturityTimestamp;
        // Operations blocked within MATURITY_BUFFER of loan maturity
        if (block.timestamp >= freezeTime + _pauseElapsed(loan.pauseSnapshot)) revert MarketplaceFrozen();

        address buyer = offer.buyer;
        // Cache seller address for events and transfers
        address seller = listing.seller;
        // Cache offer price for events and transfers
        uint256 price = offer.amount;
        // Cache payment token for transfer routing
        address paymentToken = offer.paymentToken;

        offer.status = MarketplaceOfferStatus.ACCEPTED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;
        // Deactivate listing â€” prevents double-sale and further offers
        listing.active = false;
        _refundOtherOffers(tokenId, loanId, offerId);
        // Reset offer counter AFTER refunds (must read nonce first)
        marketplaceOfferNonce[tokenId] = 0;
        // Reset active offer counter at finalization (Sherlock #13)
        activeOfferCount[tokenId] = 0;

        IERC20(paymentToken).safeTransfer(seller, price);
        // Transfer the position NFT and update loan record
        _executePositionTransfer(loanId, seller, buyer, listing.positionType);

        emit MarketplaceOfferAccepted(loanId, offerId, buyer, seller, price);
        // Emit PositionSold for off-chain indexing and frontend updates
        emit PositionSold(loanId, seller, buyer, price);
    }

    /// @notice Accept a counter offer
    function acceptMarketplaceCounterOffer(uint256 tokenId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[tokenId];
        uint256 loanId = listing.loanId;
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[tokenId][offerId];

        if (!listing.active) revert NotListed();
        // Only the offer maker can cancel/accept their offer
        if (offer.buyer != msg.sender) revert NotBuyer();
        // Offer not in the expected state for this operation
        if (offer.status != MarketplaceOfferStatus.COUNTERED) revert InvalidOfferStatus();
        
        // Prevent accepting time-expired counter-offers
        if (block.timestamp >= offer.expiresAt + _pauseElapsed(offer.pauseSnapshot)) revert OfferExpired();

        // Verify loan is still active (stale listing protection)
        Loan storage loan = loans[loanId];
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        
        // Block acceptance if within maturity buffer (marketplace frozen)
        uint256 freezeTime = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback: for very short loans, freeze only at maturity itself
            : loan.maturityTimestamp;
        // Operations blocked within MATURITY_BUFFER of loan maturity
        if (block.timestamp >= freezeTime + _pauseElapsed(loan.pauseSnapshot)) revert MarketplaceFrozen();

        address buyer = offer.buyer;
        // Cache seller address for events and transfers
        address seller = listing.seller;
        // Cache counter-offer price for payment settlement
        uint256 counterPrice = offer.counterAmount;
        // Cache escrowed amount to determine payment delta
        uint256 escrowedAmount = offer.escrowedAmount;
        // Cache payment token for transfer routing
        address paymentToken = offer.paymentToken;

        offer.status = MarketplaceOfferStatus.ACCEPTED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;
        // Deactivate listing â€” prevents double-sale and further offers
        listing.active = false;
        _refundOtherOffers(tokenId, loanId, offerId);
        // Reset offer counter AFTER refunds (must read nonce first)
        marketplaceOfferNonce[tokenId] = 0;
        // Reset active offer counter at finalization (Sherlock #13)
        activeOfferCount[tokenId] = 0;

        if (counterPrice > escrowedAmount) {
            // Calculate how much more buyer needs to pay
            uint256 additionalAmount = counterPrice - escrowedAmount;
            // Pull additional payment from buyer into contract escrow
            IERC20(paymentToken).safeTransferFrom(buyer, address(this), additionalAmount);
            // Transfer payment to seller
            IERC20(paymentToken).safeTransfer(seller, counterPrice);
        // Counter is lower than escrow â€” refund excess to buyer
        } else if (counterPrice < escrowedAmount) {
            // Calculate excess to refund to buyer
            uint256 refundAmount = escrowedAmount - counterPrice;
            // Transfer payment to seller
            IERC20(paymentToken).safeTransfer(seller, counterPrice);
            // Refund excess escrow to buyer
            IERC20(paymentToken).safeTransfer(buyer, refundAmount);
        // Exact match â€” no additional payment or refund needed
        } else {
            // Transfer payment to seller
            IERC20(paymentToken).safeTransfer(seller, counterPrice);
        }

        _executePositionTransfer(loanId, seller, buyer, listing.positionType);

        emit MarketplaceOfferAccepted(loanId, offerId, buyer, seller, counterPrice);
        // Emit PositionSold for off-chain indexing and frontend updates
        emit PositionSold(loanId, seller, buyer, counterPrice);
    }

    /// @notice Buy a position at the asking price with slippage protection
    /// @param tokenId Position NFT token ID to purchase
    /// @param maxPrice Maximum price the buyer is willing to pay (reverts if listing price exceeds this)
    /// @param expectedPaymentToken Expected payment token address (reverts if listing uses different token)
    function buyPosition(uint256 tokenId, uint256 maxPrice, address expectedPaymentToken) external whenNotPaused nonReentrant {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[tokenId];
        uint256 loanId = listing.loanId;
        
        if (!listing.active) revert NotListed();
        // Seller cannot make offers on their own listing
        if (msg.sender == listing.seller) revert CannotBuyOwnPosition();
        // Slippage protection: revert if seller updated price above buyer's limit
        if (listing.askingPrice > maxPrice) revert PriceExceedsMaximum();
        // Slippage protection: revert if seller changed the payment token
        if (listing.paymentToken != expectedPaymentToken) revert PaymentTokenMismatch();

        Loan storage loan = loans[loanId];
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        
        // Block purchase if within maturity buffer (marketplace frozen)
        uint256 freezeTime = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback: for very short loans, freeze only at maturity itself
            : loan.maturityTimestamp;
        // Operations blocked within MATURITY_BUFFER of loan maturity
        if (block.timestamp >= freezeTime + _pauseElapsed(loan.pauseSnapshot)) revert MarketplaceFrozen();

        address buyer = msg.sender;
        // Cache seller address for events and transfers
        address seller = listing.seller;
        // Cache asking price for events and transfers
        uint256 price = listing.askingPrice;
        // Cache payment token for transfer routing
        address paymentToken = listing.paymentToken;

        listing.active = false;
        _refundOtherOffers(tokenId, loanId, 0);
        // Reset offer counter AFTER refunds (must read nonce first)
        marketplaceOfferNonce[tokenId] = 0;
        // Reset active offer counter at finalization (Sherlock #13)
        activeOfferCount[tokenId] = 0;

        IERC20(paymentToken).safeTransferFrom(buyer, seller, price);
        // Transfer the position NFT and update loan record
        _executePositionTransfer(loanId, seller, buyer, listing.positionType);

        emit PositionSold(loanId, seller, buyer, price);
    }

    // ============================================================================
    // INTERNAL HELPERS
    // ============================================================================

    function _executePositionTransfer(
        uint256 loanId,
        address from,
        address to,
        // "borrower" or "lender" â€” determines which NFT to transfer
        string memory positionType
    ) internal {
        // Route to borrower or lender transfer logic
        if (_compareStrings(positionType, "borrower")) {
            // Transfer borrower position: update loan + move NFT
            _transferBorrowerPosition(loanId, from, to);
        // Lender position â€” route to lender transfer
        } else {
            // Transfer lender position: update loan + move NFT
            _transferLenderPosition(loanId, from, to);
        }
    }

    /// @notice Get the current NFT owner of a position
    /// @dev Used for stale listing detection — checks who actually owns the Position NFT
    /// @param loanId Loan ID
    /// @param positionType "borrower" or "lender"
    /// @return owner Current owner of the position NFT
    function _getPositionOwner(uint256 loanId, string memory positionType) internal view returns (address owner) {
        bool isBorrower = _compareStrings(positionType, "borrower");
        uint256 tokenId = isBorrower 
            ? positionNFT.getBorrowerTokenId(loanId)
            : positionNFT.getLenderTokenId(loanId);
        return positionNFT.ownerOf(tokenId);
    }

    function _refundOtherOffers(uint256 tokenId, uint256 loanId, uint256 excludeOfferId) internal {
        // Get total offer count to determine loop iteration bounds
        uint256 offerCount = marketplaceOfferNonce[tokenId];
        
        for (uint256 i = 1; i <= offerCount; i++) {
            // Skip the accepted offer â€” its escrow was already transferred
            if (i == excludeOfferId) continue;
            
            MarketplaceOffer storage offer = marketplaceOffers[tokenId][i];
            
            if (offer.status == MarketplaceOfferStatus.PENDING || 
                // Include COUNTERED offers in the refund loop
            offer.status == MarketplaceOfferStatus.COUNTERED) {
                
                uint256 refundAmount = offer.escrowedAmount;
                // Cache buyer address for refund transfer
                address buyer = offer.buyer;
                // Cache payment token for transfer routing
                address paymentToken = offer.paymentToken;
                
                offer.status = MarketplaceOfferStatus.CANCELLED;
                // Clear escrow balance before transfer (CEI pattern)
                offer.escrowedAmount = 0;
                
                if (refundAmount > 0) {
                    // Queue refund via pull pattern â€” recipient claims via claimRefund()
                    pendingRefunds[buyer][paymentToken] += refundAmount;
                    // Emit MarketplaceOfferRefundQueued for off-chain indexing and frontend updates
                    emit MarketplaceOfferRefundQueued(loanId, i, buyer, refundAmount);
                }
            }
        }
    }

    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        // Compare strings by hashing â€” Solidity has no native string equality
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /// @notice Get auction details
    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        // Return full auction struct
        return auctions[auctionId];
    }

    /// @notice Get loan details
    function getLoan(uint256 loanId) external view returns (Loan memory) {
        // Return full loan struct
        return loans[loanId];
    }

    /// @notice Get marketplace listing
    function getMarketplaceListing(uint256 tokenId) external view returns (MarketplaceListing memory) {
        // Return full listing struct
        return marketplaceListings[tokenId];
    }

    /// @notice Get marketplace offer
    function getMarketplaceOffer(uint256 tokenId, uint256 offerId) 
        external 
        view 
        returns (MarketplaceOffer memory) 
    {
        // Return full offer struct
        return marketplaceOffers[tokenId][offerId];
    }

    /// @notice Get number of offers for a listing
    function getMarketplaceOfferCount(uint256 tokenId) external view returns (uint256) {
        // Return total offer count for this listing
        return marketplaceOfferNonce[tokenId];
    }

    /// @notice Check if a position is listed
    function isPositionListed(uint256 tokenId) external view returns (bool) {
        // Return full listing struct
        return marketplaceListings[tokenId].active;
    }

    /// @notice Get borrower position NFT owner
    function getBorrowerPositionOwner(uint256 loanId) external view returns (address) {
        // Derive borrower NFT token ID: loanId * 2 (even numbers)
        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);
        // Attempt to read NFT owner â€” may revert if token was burned
        try positionNFT.ownerOf(tokenId) returns (address owner) {
            // Return the NFT owner address
            return owner;
        // Handle case where NFT does not exist (burned or never minted)
        } catch {
            // Return the NFT owner address
            return address(0);
        }
    }

    /// @notice Get lender position NFT owner
    function getLenderPositionOwner(uint256 loanId) external view returns (address) {
        // Derive lender NFT token ID: loanId * 2 + 1 (odd numbers)
        uint256 tokenId = positionNFT.getLenderTokenId(loanId);
        // Attempt to read NFT owner â€” may revert if token was burned
        try positionNFT.ownerOf(tokenId) returns (address owner) {
            // Return the NFT owner address
            return owner;
        // Handle case where NFT does not exist (burned or never minted)
        } catch {
            // Return the NFT owner address
            return address(0);
        }
    }

    /// @notice Get pending refund amount
    function getPendingRefund(address user, address token) external view returns (uint256) {
        // Read from nested mapping: user â†’ token â†’ pending refund
        return pendingRefunds[user][token];
    }
}
