// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev OpenZeppelin upgradeable proxy initialization (replaces constructor)
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
/// @dev Owner-restricted access control for admin functions
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
/// @dev Emergency pause mechanism — halts all state-changing operations
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
/// @dev Mutex guard preventing reentrant external calls
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
/// @dev Standard ERC-20 token interface
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/// @dev Safe ERC-20 wrappers handling non-standard return values
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Interface for the borrower/lender Position NFT contract
import "./interfaces/IPositionNFT.sol";

/**
 * @title LoanProtocol
 * @author Bitcoin Yield Curve
 * @notice Core lending protocol with oracle-free competitive bidding auctions and integrated marketplace
 * @dev Phase 1 EVM implementation - Arbitrum/Base deployment
 * 
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  WARNING: PERMISSIONLESS PROTOCOL - USE AT YOUR OWN RISK                  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚Â£
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  This protocol accepts ANY ERC20 token. There is NO whitelist.            ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  Malicious or worthless tokens can be used as collateral or loan tokens.  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“                                                                           ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  For curated, vetted token listings, use the ListingService contract      ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  which provides token whitelisting and additional safety checks.          ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“                                                                           ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  Users interacting directly with this protocol assume ALL risk.           ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“                                                                           ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  UNSUPPORTED TOKEN TYPES:                                                 ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  - Fee-on-transfer tokens                                                 ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  - Rebasing tokens                                                        ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“  - Tokens with transfer blocklists                                        ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‹Å“
 * ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚Â
 * 
 * SECURITY FEATURES:
 * - All state-changing functions use ReentrancyGuard
 * - Follows Checks-Effects-Interactions pattern throughout
 * - No price oracles - market determines rates via auction
 * - NFT positions enable secondary market liquidity
 * - Pull-based refunds prevent DoS on auction bidding
 * - Push-based refunds for marketplace (buyer-only risk)
 * - Fixed grace period (not admin-configurable)
 * - Integrated marketplace - no external contract trust needed
 * 
 * BID STEP POLICY:
 * - Each auction has a configurable bidStep (absolute amount in loan token decimals)
 * - Subsequent bids must be at least bidStep lower than current bid
 * - Default minimum step is 1 wei (for direct protocol users)
 * - ListingService can set higher steps for orderly markets (e.g., $0.25 for USDC)
 */
contract LoanProtocol is 
        // Upgradeable proxy pattern — replaces constructor with initialize()
    Initializable, 
        // Single-owner access control for pause/unpause admin functions
    OwnableUpgradeable, 
        // Emergency circuit breaker — halts all user-facing operations
    PausableUpgradeable, 
        // Mutex lock preventing reentrant calls on state-changing functions
    ReentrancyGuardUpgradeable 
{
    //
    // ┌──────────────────────────────────────────────────────────────────┐
    // │                    ARCHITECTURE OVERVIEW                         │
    // │                                                                  │
    // │  Oracle-Free Design:                                             │
    // │    No price oracles. Interest rates are discovered through       │
    // │    competitive reverse Dutch auctions where lenders bid lower    │
    // │    repayment amounts. The market determines fair rates.          │
    // │                                                                  │
    // │  Position NFTs:                                                  │
    // │    Both borrower and lender receive ERC-721 tokens that          │
    // │    represent their loan positions. These can be traded on        │
    // │    the integrated marketplace, enabling secondary market         │
    // │    liquidity for loan positions.                                 │
    // │                                                                  │
    // │  Pull-Based Refunds:                                             │
    // │    Outbid lenders and rejected offer-makers do not receive       │
    // │    immediate refunds. Instead, funds are queued in               │
    // │    pendingRefunds mapping and claimed via claimRefund().          │
    // │    This prevents DoS attacks where a malicious contract          │
    // │    reverts on receive to block auction bidding.                  │
    // │                                                                  │
    // │  CEI Pattern:                                                    │
    // │    All state-changing functions follow Checks-Effects-            │
    // │    Interactions to prevent reentrancy. Combined with             │
    // │    ReentrancyGuard for defense-in-depth.                        │
    // │                                                                  │
    // │  Marketplace Freeze:                                             │
    // │    The integrated marketplace freezes MATURITY_BUFFER before     │
    // │    loan maturity to prevent last-second position transfers       │
    // │    that could interfere with repayment or default claims.        │
    // │                                                                  │
    // │  Two-Layer Model:                                                │
    // │    This contract is permissionless (any ERC-20 pair).            │
    // │    ListingService wraps it with token whitelisting and fees      │
    // │    for curated, safer user experience.                          │
    // └──────────────────────────────────────────────────────────────────┘
    //
    /// @dev Attach safe transfer wrappers to all IERC20 instances in this contract
    using SafeERC20 for IERC20;

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    uint256 public constant MIN_AUCTION_DURATION = 10 minutes;  // TESTNET: reduced from 1 day
    /// @notice Cap on bidding period — prevents indefinitely open auctions
    uint256 public constant MAX_AUCTION_DURATION = 7 days;
    /// @notice Minimum loan term — prevents trivially short loans
    uint256 public constant MIN_LOAN_DURATION = 10 minutes;    // TESTNET: reduced from 7 days
    /// @notice Maximum loan term (~30 years) — enables full yield curve coverage
    uint256 public constant MAX_LOAN_DURATION = 10950 days; // ~30 years for full yield curve
    /// @notice Post-maturity repayment window before lender can seize collateral
    uint256 public constant GRACE_PERIOD = 10 minutes;         // TESTNET: reduced from 24 hours
    /// @notice Window after auction ends during which finalize() can be called
    uint256 public constant FINALIZATION_WINDOW = 1 hours;     // TESTNET: reduced from 7 days
    /// @notice Basis points denominator: 10000 = 100%
    uint256 public constant BPS_DENOMINATOR = 10000;
    /// @notice Absolute floor for bid step (1 unit of loan token)
    uint256 public constant MIN_BID_STEP = 1; // Minimum bid step (1 wei) - can be customized per auction
    /// @notice Minimum marketplace offer validity period
    uint256 public constant MIN_OFFER_DURATION = 5 minutes;  // TESTNET: reduced from 1 day
    /// @notice Safety buffer — marketplace freezes this long before loan maturity
    uint256 public constant MATURITY_BUFFER = 5 minutes;     // TESTNET: reduced from 1 day
    /// @notice Gas-safety cap on offers per listing — bounds _refundOtherOffers loop
    uint256 public constant MAX_OFFERS_PER_LISTING = 50;     // Prevent gas DoS via unbounded refund loops

    // ============================================================================
    // ENUMS
    // ============================================================================

    enum AuctionStatus { 
        OPEN,           // Accepting bids
        FINALIZED,      // Loan created
        CANCELLED,      // No bids or borrower cancelled
        EXPIRED         // Had bids but not finalized within window - funds can be reclaimed
    }

    enum LoanStatus { 
        ACTIVE,         // Loan in progress
        REPAID,         // Borrower repaid
        DEFAULTED       // Lender claimed collateral
    }

    enum MarketplaceOfferStatus {
        PENDING,        // Awaiting seller response
        ACCEPTED,       // Trade executed
        REJECTED,       // Seller rejected
        COUNTERED,      // Seller made counter-offer
        CANCELLED,      // Buyer cancelled
        EXPIRED         // Offer expired without response
    }

    // ============================================================================
    // STRUCTS
    // ============================================================================

    struct Auction {
        /// @dev Loan recipient — receives funds, must repay at maturity
        address borrower;
        address collateralFrom;     // Address whose collateral balance was debited
        /// @dev ERC-20 token locked as collateral for this auction
        address collateralToken;
        /// @dev Amount of collateral tokens locked in the protocol
        uint256 collateralAmount;
        /// @dev ERC-20 token being borrowed (typically a stablecoin like USDC)
        address loanToken;
        /// @dev Principal amount requested by borrower
        uint256 loanAmount;
        /// @dev Maximum repayment cap — starting bid in the reverse Dutch auction
        uint256 maxRepayment;
        /// @dev Duration of resulting loan in seconds after finalization
        uint256 loanDuration;
        /// @dev Unix timestamp when bidding period closes
        uint256 auctionEnd;
        /// @dev Current winning bidder (lowest repayment offer)
        address currentBidder;
        /// @dev Current best bid — lowest repayment amount offered by a lender
        uint256 currentBid;
        /// @dev Total number of valid bids received
        uint256 bidCount;
        /// @dev Current lifecycle state: OPEN → FINALIZED/CANCELLED/EXPIRED
        AuctionStatus status;
        uint256 bidStep;  // Minimum bid improvement required (absolute amount in loan token decimals)
    }

    struct Loan {
        /// @dev Current borrower — updated on marketplace position transfer
        address borrower;
        /// @dev ERC-20 token locked as collateral
        address collateralToken;
        /// @dev Amount of collateral locked in the protocol
        uint256 collateralAmount;
        /// @dev ERC-20 token that was lent to the borrower
        address loanToken;
        /// @dev Original principal amount
        uint256 loanAmount;
        /// @dev Total amount due at maturity (principal + interest from winning bid)
        uint256 repaymentAmount;
        /// @dev Unix timestamp when loan becomes due
        uint256 maturityTimestamp;
        /// @dev Current lender — updated on marketplace position transfer
        address lender;
        /// @dev Current lifecycle state: ACTIVE → REPAID/DEFAULTED
        LoanStatus status;
    }

    struct MarketplaceListing {
        /// @dev Position owner who created the listing
        address seller;
        string positionType;    // "borrower" or "lender"
        address paymentToken;   // Token for payment (usually stablecoin)
        /// @dev Listed price in payment token units
        uint256 askingPrice;
        /// @dev Unix timestamp when listing was created
        uint256 listedAt;
        /// @dev Whether listing is live (false after sale/unlist)
        bool active;
    }

    struct MarketplaceOffer {
        /// @dev Offer maker — receives position if accepted
        address buyer;
        /// @dev Original offer amount in payment tokens
        uint256 amount;
        uint256 escrowedAmount; // Funds held in escrow
        /// @dev Lifecycle: PENDING/ACCEPTED/REJECTED/COUNTERED/CANCELLED/EXPIRED
        MarketplaceOfferStatus status;
        /// @dev Seller counter-offer price (0 if not countered)
        uint256 counterAmount;
        /// @dev Unix timestamp when offer was submitted
        uint256 createdAt;
        uint256 expiresAt;      // When offer expires if not acted upon
        address paymentToken;   // Token used for offer (for refunds after unlisting)
    }

    // ============================================================================
    // STATE VARIABLES - CORE PROTOCOL
    // ============================================================================

    /// @notice Position NFT contract for minting borrower/lender positions
    IPositionNFT public positionNFT;

    /// @notice Counter for auction/loan IDs
    uint256 public loanNonce;

    /// @notice User collateral balances: user => token => amount
    mapping(address => mapping(address => uint256)) public collateralBalances;

    /// @notice All auctions by ID
    mapping(uint256 => Auction) public auctions;

    /// @notice All loans by ID (created after auction finalization)
    mapping(uint256 => Loan) public loans;

    /// @notice Track if lender has claimed from expired auction: auctionId => claimed
    mapping(uint256 => bool) public expiredAuctionLenderClaimed;
    
    /// @notice Track if borrower has claimed from expired auction: auctionId => claimed
    mapping(uint256 => bool) public expiredAuctionBorrowerClaimed;

    /// @notice Pending refunds for outbid lenders (pull pattern): user => token => amount
    mapping(address => mapping(address => uint256)) public pendingRefunds;

    /// @notice Operator approvals: owner => operator => approved
    /// @dev Allows approved operators (e.g., ListingService) to create auctions
    ///      and list positions on behalf of the collateral owner
    mapping(address => mapping(address => bool)) public operatorApprovals;

    // ============================================================================
    // STATE VARIABLES - INTEGRATED MARKETPLACE
    // ============================================================================

    /// @notice Marketplace listings by loan ID
    mapping(uint256 => MarketplaceListing) public marketplaceListings;

    /// @notice Marketplace offers: loanId => offerId => Offer
    mapping(uint256 => mapping(uint256 => MarketplaceOffer)) public marketplaceOffers;

    /// @notice Offer counter per loan
    mapping(uint256 => uint256) public marketplaceOfferNonce;

    // ============================================================================
    // EVENTS - CORE PROTOCOL
    // ============================================================================

    /// @param user Address that deposited collateral
    /// @param token ERC-20 token deposited
    /// @param amount Amount deposited
    event CollateralDeposited(
        // user who deposited/withdrew
        address indexed user, 
        // ERC-20 token address
        address indexed token, 
        // amount deposited/withdrawn
        uint256 amount
    );
    
    /// @param user Address that withdrew collateral
    /// @param token ERC-20 token withdrawn
    /// @param amount Amount withdrawn
    event CollateralWithdrawn(
        // user who deposited/withdrew
        address indexed user, 
        // ERC-20 token address
        address indexed token, 
        // amount deposited/withdrawn
        uint256 amount
    );
    
    /// @param auctionId Unique auction identifier
    /// @param borrower Address requesting the loan
    /// @param collateralToken Token locked as collateral
    /// @param collateralAmount Amount of collateral locked
    /// @param loanToken Token being borrowed
    /// @param loanAmount Principal amount requested
    /// @param maxRepayment Maximum repayment cap (starting bid)
    /// @param loanDuration Duration of the resulting loan in seconds
    /// @param auctionEnd Timestamp when bidding closes
    event AuctionCreated(
        // auction identifier
        uint256 indexed auctionId, 
        // loan borrower
        address indexed borrower, 
        // collateral token address
        address collateralToken,
        // collateral amount locked
        uint256 collateralAmount,
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
        // total repayment offered
        uint256 repaymentAmount,
        // sequential bid number
        uint256 bidNumber
    );

    /// @param user Address that was outbid and can claim refund
    /// @param token Loan token to be refunded
    /// @param amount Refund amount (equals loanAmount)
    /// @param auctionId Auction where user was outbid
    event RefundAvailable(
        // user who deposited/withdrew
        address indexed user,
        // ERC-20 token address
        address indexed token,
        // refund amount
        uint256 amount,
        // auction identifier
        uint256 indexed auctionId
    );

    /// @param user Address claiming their refund
    /// @param token Token being refunded
    /// @param amount Amount refunded
    event RefundClaimed(
        // user who deposited/withdrew
        address indexed user,
        // ERC-20 token address
        address indexed token,
        // refund amount
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
        // loan lender
        address indexed lender,
        // winning bid repayment amount
        uint256 finalRepayment
    );
    
    event AuctionExpiredNoBids(uint256 indexed auctionId);
    
    /// @param auctionId Expired auction ID
    /// @param borrower Auction borrower
    /// @param lender Winning bidder whose funds are locked
    event AuctionExpiredNotFinalized(
        // auction identifier
        uint256 indexed auctionId,
        // loan borrower
        address indexed borrower,
        // loan lender
        address indexed lender
    );
    
    /// @param auctionId Expired auction ID
    /// @param claimant Address claiming funds
    /// @param isLender True if claimant is the lender
    /// @param amount Amount returned to claimant
    event ExpiredAuctionClaimed(
        // auction identifier
        uint256 indexed auctionId,
        // address claiming funds
        address indexed claimant,
        // true if claimant is lender
        bool isLender,
        // amount returned
        uint256 amount
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
    /// @param lender Address that claimed collateral
    /// @param collateralAmount Amount of collateral seized
    event LoanDefaulted(
        // loan identifier
        uint256 indexed loanId, 
        // loan lender
        address indexed lender,
        // collateral amount
        uint256 collateralAmount
    );

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
        // payment token for the listing
        address paymentToken,
        // listing price
        uint256 askingPrice
    );

    event PositionUnlisted(uint256 indexed loanId);

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
        // offer amount escrowed
        uint256 amount
    );

    /// @notice Emitted when buyer cancels their offer and reclaims escrow
    event MarketplaceOfferCancelled(uint256 indexed loanId, uint256 indexed offerId);

    event MarketplaceOfferRejected(uint256 indexed loanId, uint256 indexed offerId);

    /// @param loanId Loan ID of the listing
    /// @param offerId Offer being countered
    /// @param counterAmount Seller counter price
    event MarketplaceCounterOffer(
        // loan identifier
        uint256 indexed loanId, 
        // offer identifier
        uint256 indexed offerId, 
        // seller counter-offer price
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
        // refund amount
        uint256 amount
    );

    /// @param user Address claiming refund
    /// @param token Payment token refunded
    /// @param amount Amount refunded
    event MarketplaceRefundClaimed(
        // user who deposited/withdrew
        address indexed user, 
        // ERC-20 token address
        address indexed token, 
        // refund amount
        uint256 amount
    );

    // ============================================================================
    // ERRORS
    // ============================================================================

    // Core Protocol Errors
    error ZeroAddress();
    /// @dev InvalidToken: Token address is zero or otherwise invalid
    error InvalidToken();
    /// @dev SameToken: Collateral and loan tokens must be different
    error SameToken();
    /// @dev InvalidAmount: Zero amount provided for deposit, collateral, or loan
    error InvalidAmount();
    /// @dev InvalidRepayment: maxRepayment is less than loanAmount (would imply negative interest)
    error InvalidRepayment();
    /// @dev InvalidDuration: Duration outside allowed bounds [MIN, MAX]
    error InvalidDuration();
    /// @dev InsufficientCollateral: User lacks enough deposited collateral for the auction
    error InsufficientCollateral();
    /// @dev InsufficientBalance: Withdrawal exceeds available collateral balance
    error InsufficientBalance();
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

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier validToken(address token) {
        // Validate token address
        if (token == address(0)) revert InvalidToken();
        // Continue to the modified function body
        _;
    }

    // ============================================================================
    // INITIALIZER
    // ============================================================================

    /// @notice Initialize the protocol
    /// @param _positionNFT PositionNFT contract address
    function initialize(address _positionNFT) external initializer {
        // Reject zero address to prevent permanently locked funds
        if (_positionNFT == address(0)) revert ZeroAddress();

        __Ownable_init(msg.sender);
        // Initialize emergency pause mechanism as unpaused
        __Pausable_init();
        // Initialize reentrancy guard mutex as unlocked
        __ReentrancyGuard_init();

        positionNFT = IPositionNFT(_positionNFT);
    }

    // ============================================================================
    // ADMIN FUNCTIONS (MINIMAL - FOR OWNERSHIP RENOUNCEMENT)
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
    // OPERATOR APPROVALS
    // ============================================================================

    /// @notice Approve or revoke an operator to act on your collateral
    /// @dev Users must approve ListingService before using fee-based listings.
    ///      Similar to ERC20 approve() — grants permission to create auctions
    ///      and list positions on your behalf.
    /// @param operator Address to approve/revoke (e.g., ListingService contract)
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
    // COLLATERAL MANAGEMENT
    // ============================================================================

    /// @notice Deposit collateral tokens
    /// @param token Token address to deposit
    /// @param amount Amount to deposit
    function depositCollateral(address token, uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
        // Validate token address is non-zero
        validToken(token) 
    {
        // Reject zero amounts — meaningless for deposits and loans
        if (amount == 0) revert InvalidAmount();

        // Effects
        collateralBalances[msg.sender][token] += amount;

        // Interactions
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit CollateralDeposited(msg.sender, token, amount);
    }

    /// @notice Withdraw available collateral
    /// @param token Token address to withdraw
    /// @param amount Amount to withdraw
    function withdrawCollateral(address token, uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Reject zero amounts — meaningless for deposits and loans
        if (amount == 0) revert InvalidAmount();
        // Verify caller has enough deposited collateral to withdraw
        if (collateralBalances[msg.sender][token] < amount) {
            // Ensure user has sufficient deposited balance
            revert InsufficientBalance();
        }

        // Effects
        collateralBalances[msg.sender][token] -= amount;

        // Interactions
        IERC20(token).safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, token, amount);
    }

    // ============================================================================
    // AUCTION CREATION
    // ============================================================================

    /// @notice Create a new loan auction
    /// @param collateralToken Token to use as collateral
    /// @param collateralAmount Amount of collateral
    /// @param loanToken Token to borrow (stablecoin)
    /// @param loanAmount Amount to borrow
    /// @param maxRepayment Maximum total repayment (caps interest rate)
    /// @param loanDuration Loan duration in seconds
    /// @param auctionDuration Auction duration in seconds
    /// @param bidStep Minimum bid improvement required (0 = use MIN_BID_STEP default)
    /// @return auctionId The ID of the created auction
    function createAuction(
        address collateralToken,
        uint256 collateralAmount,
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
        returns (uint256 auctionId) 
    {
        // Delegate to internal auction creation with validated parameters
        return _createAuction(
            msg.sender,  // borrower is the caller
            msg.sender,  // collateral comes from caller's balance
            collateralToken,
            collateralAmount,
            loanToken,
            loanAmount,
            maxRepayment,
            loanDuration,
            auctionDuration,
            bidStep
        );
    }

    /// @notice Create a new loan auction on behalf of another address
    /// @dev Allows ListingService or other approved contracts to create auctions for users
    /// @param borrower Address that will be the borrower (receives loan, must repay)
    /// @param collateralFrom Address whose deposited collateral will be used
    /// @param collateralToken Token to use as collateral
    /// @param collateralAmount Amount of collateral
    /// @param loanToken Token to borrow (stablecoin)
    /// @param loanAmount Amount to borrow
    /// @param maxRepayment Maximum total repayment (caps interest rate)
    /// @param loanDuration Loan duration in seconds
    /// @param auctionDuration Auction duration in seconds
    /// @param bidStep Minimum bid improvement required (0 = use MIN_BID_STEP default)
    /// @return auctionId The ID of the created auction
    function createAuctionFor(
        address borrower,
        address collateralFrom,
        address collateralToken,
        uint256 collateralAmount,
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
        returns (uint256 auctionId) 
    {
        // Reject zero address to prevent permanently locked funds
        if (borrower == address(0)) revert ZeroAddress();
        // Reject zero address to prevent permanently locked funds
        if (collateralFrom == address(0)) revert ZeroAddress();
        
        // SECURITY: Caller must be the collateral owner OR an approved operator.
        // Prevents attackers from creating auctions using other users' deposited funds.
        if (msg.sender != collateralFrom && !operatorApprovals[collateralFrom][msg.sender]) {
            // Caller lacks required permission for this action
            revert Unauthorized();
        }
        
        return _createAuction(
            borrower,
            collateralFrom,
            collateralToken,
            collateralAmount,
            loanToken,
            loanAmount,
            maxRepayment,
            loanDuration,
            auctionDuration,
            bidStep
        );
    }

    /// @dev Internal function to create auction
    function _createAuction(
        address borrower,
        address collateralFrom,
        address collateralToken,
        uint256 collateralAmount,
        address loanToken,
        uint256 loanAmount,
        uint256 maxRepayment,
        uint256 loanDuration,
        uint256 auctionDuration,
        uint256 bidStep
    ) 
        internal
        returns (uint256 auctionId) 
    {
        // Validations
        if (collateralToken == address(0) || loanToken == address(0)) revert InvalidToken();
        // Collateral and loan tokens must differ
        if (collateralToken == loanToken) revert SameToken();
        // Reject zero amounts — meaningless for deposits and loans
        if (collateralAmount == 0 || loanAmount == 0) revert InvalidAmount();
        // maxRepayment must be >= loanAmount (non-negative interest only)
        if (maxRepayment < loanAmount) revert InvalidRepayment();
        
        if (auctionDuration < MIN_AUCTION_DURATION || auctionDuration > MAX_AUCTION_DURATION) {
            // Duration outside protocol limits
            revert InvalidDuration();
        }
        // Validate loan duration within allowed bounds
        if (loanDuration < MIN_LOAN_DURATION || loanDuration > MAX_LOAN_DURATION) {
            // Duration outside protocol limits
            revert InvalidDuration();
        }
        
        // Check collateral balance
        if (collateralBalances[collateralFrom][collateralToken] < collateralAmount) {
            // Ensure sufficient deposited collateral to back this auction
            revert InsufficientCollateral();
        }

        // Determine effective bid step (use MIN_BID_STEP if 0 or below minimum)
        uint256 effectiveBidStep = bidStep < MIN_BID_STEP ? MIN_BID_STEP : bidStep;

        // Effects
        auctionId = ++loanNonce;
        
        // Lock collateral
        collateralBalances[collateralFrom][collateralToken] -= collateralAmount;

        auctions[auctionId] = Auction({
            borrower: borrower,
            collateralFrom: collateralFrom,
            collateralToken: collateralToken,
            collateralAmount: collateralAmount,
            loanToken: loanToken,
            loanAmount: loanAmount,
            maxRepayment: maxRepayment,
            loanDuration: loanDuration,
            // Set auction deadline relative to current block timestamp
            auctionEnd: block.timestamp + auctionDuration,
            // No bidder yet — set on first bid
            currentBidder: address(0),
            // Start at maxRepayment — bids compete downward from this ceiling
            currentBid: maxRepayment, // Start at max, bids go lower
            // Zero bids initially
            bidCount: 0,
            // Auction starts in OPEN state, accepting bids
            status: AuctionStatus.OPEN,
            // Per-auction bid step (configurable, minimum enforced above)
            bidStep: effectiveBidStep
        });

        emit AuctionCreated(
            auctionId,
            borrower,
            collateralToken,
            collateralAmount,
            loanToken,
            loanAmount,
            maxRepayment,
            loanDuration,
            // Pass calculated auction end timestamp to event
            block.timestamp + auctionDuration
        );
    }

    /// @notice Cancel an auction before any bids
    /// @param auctionId Auction to cancel
    function cancelAuction(uint256 auctionId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        
        if (auction.borrower == address(0)) revert AuctionNotFound();
        // Only OPEN auctions can accept bids or be finalized
        if (auction.status != AuctionStatus.OPEN) revert AuctionNotOpen();
        // Only the auction creator (borrower) can cancel
        if (msg.sender != auction.borrower) revert NotBorrower();
        // Cannot cancel — existing bids create obligations to bidders
        if (auction.bidCount > 0) revert HasBids();

        // Effects
        auction.status = AuctionStatus.CANCELLED;
        
        // Return collateral to the original depositor (collateralFrom), not borrower
        collateralBalances[auction.collateralFrom][auction.collateralToken] += auction.collateralAmount;

        emit AuctionCancelled(auctionId);
    }

    // ============================================================================
    // AUCTION BIDDING
    // ============================================================================

    /// @notice Place a bid on an auction (descending price auction)
    /// @dev Bids must be at least bidStep lower than current bid (auction-specific).
    /// @param auctionId Auction to bid on
    /// @param repaymentAmount Proposed total repayment (principal + interest)
    function placeBid(uint256 auctionId, uint256 repaymentAmount) 
        external 
        whenNotPaused
        nonReentrant 
    {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        
        if (auction.borrower == address(0)) revert AuctionNotFound();
        // Only OPEN auctions can accept bids or be finalized
        if (auction.status != AuctionStatus.OPEN) revert AuctionNotOpen();
        // Bidding window has closed — no more bids accepted
        if (block.timestamp >= auction.auctionEnd) revert AuctionEnded();
        
        // Prevent self-bidding
        if (msg.sender == auction.borrower) revert Unauthorized();
        
        // Bid must be at least the loan amount (no negative interest)
        if (repaymentAmount < auction.loanAmount) revert BidTooLow();
        
        if (auction.bidCount == 0) {
            // First bid: can bid up to maxRepayment
            if (repaymentAmount > auction.maxRepayment) revert BidTooHigh();
        // Subsequent bids: must beat current bid by at least bidStep
        } else {
            // Subsequent bids: must be at least bidStep lower than current bid
            // Calculate the maximum valid bid (current bid minus step)
            uint256 maxValidBid = auction.currentBid > auction.bidStep 
                // Calculate max valid bid: current best minus step size
                ? auction.currentBid - auction.bidStep 
                // Fallback to 0 if subtraction would underflow
                : 0;
            
            // If step would push below loan amount, allow any bid >= loanAmount and < currentBid
            if (maxValidBid < auction.loanAmount) {
                // Near-zero interest scenario - require strictly lower
                if (repaymentAmount >= auction.currentBid) revert BidTooHigh();
            } else {
                // Normal case - require minimum step improvement
                if (repaymentAmount > maxValidBid) revert BidTooHigh();
            }
        }
        
        // Store previous bidder info for pull-based refund
        address previousBidder = auction.currentBidder;
        // Cache in memory to save gas on repeated storage reads
        address loanToken = auction.loanToken;
        // Cache loan amount in memory for gas efficiency
        uint256 loanAmount = auction.loanAmount;
        // Determine if there is a previous bidder who needs a refund
        bool hasPreviousBid = auction.bidCount > 0 && previousBidder != address(0);
        
        // Effects first (CEI pattern)
        auction.currentBidder = msg.sender;
        // Record new winning bid (lowest repayment = best for borrower)
        auction.currentBid = repaymentAmount;
        // Increment bid counter for auction analytics
        auction.bidCount++;
        
        // Credit previous bidder's refund (pull pattern - they claim later)
        if (hasPreviousBid) {
            // Queue refund via pull pattern — recipient claims via claimRefund()
            pendingRefunds[previousBidder][loanToken] += loanAmount;
            // Emit RefundAvailable for off-chain indexing and frontend updates
            emit RefundAvailable(previousBidder, loanToken, loanAmount, auctionId);
        }
        
        // Interactions: Transfer loan amount from new bidder to contract (escrow)
        IERC20(loanToken).safeTransferFrom(msg.sender, address(this), loanAmount);

        emit BidPlaced(auctionId, msg.sender, repaymentAmount, auction.bidCount);
    }

    /// @notice Claim pending refunds from being outbid (pull pattern)
    /// @param token The loan token to claim refund for
    function claimRefund(address token) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Read pending refund balance for this user/token pair
        uint256 amount = pendingRefunds[msg.sender][token];
        // No pending refund balance for this user/token pair
        if (amount == 0) revert NoRefundAvailable();
        
        // Effects
        pendingRefunds[msg.sender][token] = 0;
        
        // Interactions
        IERC20(token).safeTransfer(msg.sender, amount);
        
        emit RefundClaimed(msg.sender, token, amount);
    }

    // ============================================================================
    // AUCTION FINALIZATION
    // ============================================================================

    /// @notice Finalize an auction after it ends (within finalization window)
    /// @param auctionId Auction to finalize
    function finalizeAuction(uint256 auctionId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        
        if (auction.borrower == address(0)) revert AuctionNotFound();
        // Only OPEN auctions can accept bids or be finalized
        if (auction.status != AuctionStatus.OPEN) revert AuctionNotOpen();
        // Auction must have ended before finalization or expiry claims
        if (block.timestamp < auction.auctionEnd) revert AuctionStillOpen();
        
        // Check finalization window
        if (block.timestamp > auction.auctionEnd + FINALIZATION_WINDOW) {
            // Window closed — use claimExpiredAuction() instead
            revert FinalizationWindowExpired();
        }
        
        // Handle no bids case
        if (auction.bidCount == 0) {
            // Mark auction as cancelled — collateral will be returned
            auction.status = AuctionStatus.CANCELLED;
            // Return collateral to original depositor
            collateralBalances[auction.collateralFrom][auction.collateralToken] += auction.collateralAmount;
            // Emit AuctionExpiredNoBids for off-chain indexing and frontend updates
            emit AuctionExpiredNoBids(auctionId);
            // Exit early — no further processing needed
            return;
        }
        
        // Cache values before state changes
        address borrower = auction.borrower;
        // Cache winning bidder as lender for the new loan
        address lender = auction.currentBidder;
        // Cache collateral token address before state update
        address collateralToken = auction.collateralToken;
        // Cache collateral amount before state update
        uint256 collateralAmount = auction.collateralAmount;
        // Cache in memory to save gas on repeated storage reads
        address loanToken = auction.loanToken;
        // Cache loan amount in memory for gas efficiency
        uint256 loanAmount = auction.loanAmount;
        // Cache repayment amount before state update
        uint256 repaymentAmount = auction.currentBid;
        // Cache loan duration before state update
        uint256 duration = auction.loanDuration;
        
        // Effects: Update auction status
        auction.status = AuctionStatus.FINALIZED;
        
        // Create loan record
        loans[auctionId] = Loan({
            borrower: borrower,
            collateralToken: collateralToken,
            collateralAmount: collateralAmount,
            loanToken: loanToken,
            loanAmount: loanAmount,
            repaymentAmount: repaymentAmount,
            // Calculate absolute maturity: now + loan duration
            maturityTimestamp: block.timestamp + duration,
            lender: lender,
            // Loan starts in ACTIVE state
            status: LoanStatus.ACTIVE
        });
        
        // Mint position NFTs
        positionNFT.mintBorrowerPosition(auctionId, borrower);
        // Mint lender position NFT — holder receives repayment or claims collateral
        positionNFT.mintLenderPosition(auctionId, lender);

        // Store loan metadata for NFT display (on-chain SVG rendering)
        positionNFT.setLoanMetadata(
            auctionId,
            collateralToken,
            collateralAmount,
            loanToken,
            loanAmount,
            repaymentAmount,
            // Pass calculated maturity timestamp to NFT metadata
            block.timestamp + duration
        );
        
        // Transfer loan amount to borrower
        IERC20(loanToken).safeTransfer(borrower, loanAmount);
        
        emit AuctionFinalized(auctionId, auctionId, lender, repaymentAmount);
    }

    /// @notice Claim funds from an expired auction (not finalized in time)
    /// @param auctionId Auction to claim from
    function claimExpiredAuction(uint256 auctionId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        
        if (auction.borrower == address(0)) revert AuctionNotFound();
        // BUG FIX: Allow both OPEN and EXPIRED status so both lender AND borrower can claim
        // Previously only checked for OPEN, which blocked the second claimer after status changed
        if (auction.status != AuctionStatus.OPEN && auction.status != AuctionStatus.EXPIRED) {
            // Only OPEN auctions can accept bids or be finalized
            revert AuctionNotOpen();
        }
        // Auction must have ended before finalization or expiry claims
        if (block.timestamp < auction.auctionEnd) revert AuctionStillOpen();
        // Verify finalization window has expired before allowing expiry claims
        if (block.timestamp <= auction.auctionEnd + FINALIZATION_WINDOW) {
            // Cannot claim as expired while finalization still possible
            revert FinalizationWindowActive();
        }
        // No bids were placed — nothing to claim
        if (auction.bidCount == 0) revert NoBids();
        
        bool isBorrower = msg.sender == auction.borrower;
        // Check if claimant is the winning bidder (lender)
        bool isLender = msg.sender == auction.currentBidder;
        
        if (!isBorrower && !isLender) revert Unauthorized();
        
        // Mark as expired on first claim
        if (auction.status == AuctionStatus.OPEN) {
            // Mark auction expired — both parties can reclaim funds
            auction.status = AuctionStatus.EXPIRED;
            // Emit AuctionExpiredNotFinalized for off-chain indexing and frontend updates
            emit AuctionExpiredNotFinalized(auctionId, auction.borrower, auction.currentBidder);
        }
        
        if (isLender) {
            // Prevent double-claiming from expired auctions
            if (expiredAuctionLenderClaimed[auctionId]) revert AlreadyClaimed();
            // Mark lender claim as complete (prevents double-claim)
            expiredAuctionLenderClaimed[auctionId] = true;
            
            // Return escrowed loan amount to lender
            IERC20(auction.loanToken).safeTransfer(msg.sender, auction.loanAmount);
            // Emit ExpiredAuctionClaimed for off-chain indexing and frontend updates
            emit ExpiredAuctionClaimed(auctionId, msg.sender, true, auction.loanAmount);
        }
        
        if (isBorrower) {
            // Prevent double-claiming from expired auctions
            if (expiredAuctionBorrowerClaimed[auctionId]) revert AlreadyClaimed();
            // Mark borrower claim as complete (prevents double-claim)
            expiredAuctionBorrowerClaimed[auctionId] = true;
            
            // Return collateral to original depositor's balance
            collateralBalances[auction.collateralFrom][auction.collateralToken] += auction.collateralAmount;
            // Emit ExpiredAuctionClaimed for off-chain indexing and frontend updates
            emit ExpiredAuctionClaimed(auctionId, auction.collateralFrom, false, auction.collateralAmount);
        }
    }

    // ============================================================================
    // LOAN RESOLUTION
    // ============================================================================

    /// @notice Repay a loan in full
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
        // Too late to repay — grace period has ended
        if (block.timestamp >= loan.maturityTimestamp + GRACE_PERIOD) revert GracePeriodExpired();
        
        // Verify caller owns borrower position NFT
        uint256 borrowerTokenId = positionNFT.getBorrowerTokenId(loanId);
        // Caller lacks required permission for this action
        if (positionNFT.ownerOf(borrowerTokenId) != msg.sender) revert Unauthorized();
        
        // Cache values
        address collateralToken = loan.collateralToken;
        // Cache collateral amount before state update
        uint256 collateralAmount = loan.collateralAmount;
        // Cache loan token address before state changes
        address loanToken = loan.loanToken;
        // Cache repayment amount before state update
        uint256 repaymentAmount = loan.repaymentAmount;
        
        // Get lender's current address (NFT owner, not stored address)
        uint256 lenderTokenId = positionNFT.getLenderTokenId(loanId);
        // Resolve current owner from NFT (may differ from stored loan.lender)
        address lender = positionNFT.ownerOf(lenderTokenId);
        
        // Effects
        loan.status = LoanStatus.REPAID;
        
        // Burn position NFTs
        positionNFT.burn(borrowerTokenId);
        // Burn position NFT — loan is resolved, position no longer exists
        positionNFT.burn(lenderTokenId);
        
        // Transfer repayment to lender
        IERC20(loanToken).safeTransferFrom(msg.sender, lender, repaymentAmount);
        
        // Return collateral to borrower
        IERC20(collateralToken).safeTransfer(msg.sender, collateralAmount);
        
        emit LoanRepaid(loanId, msg.sender, repaymentAmount);
    }

    /// @notice Claim collateral from a defaulted loan
    /// @param loanId Loan to claim from
    function claimCollateral(uint256 loanId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        
        if (loan.borrower == address(0)) revert LoanNotFound();
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        // Cannot claim collateral before loan maturity
        if (block.timestamp < loan.maturityTimestamp) revert LoanNotMatured();
        // Must wait for grace period to end before default claim
        if (block.timestamp < loan.maturityTimestamp + GRACE_PERIOD) revert GracePeriodNotEnded();
        
        // Verify caller owns lender position NFT
        uint256 lenderTokenId = positionNFT.getLenderTokenId(loanId);
        // Caller lacks required permission for this action
        if (positionNFT.ownerOf(lenderTokenId) != msg.sender) revert Unauthorized();
        
        // Cache values
        address collateralToken = loan.collateralToken;
        // Cache collateral amount before state update
        uint256 collateralAmount = loan.collateralAmount;
        
        // Effects
        loan.status = LoanStatus.DEFAULTED;
        
        // Burn position NFTs
        positionNFT.burn(positionNFT.getBorrowerTokenId(loanId));
        // Burn position NFT — loan is resolved, position no longer exists
        positionNFT.burn(lenderTokenId);
        
        // Transfer collateral to lender
        IERC20(collateralToken).safeTransfer(msg.sender, collateralAmount);
        
        emit LoanDefaulted(loanId, msg.sender, collateralAmount);
    }

    // ============================================================================
    // NFT POSITION TRANSFERS (INTERNAL - FOR MARKETPLACE)
    // ============================================================================

    /// @notice Transfer borrower position
    /// @dev Only callable internally by marketplace functions
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
        
        // Update loan record
        loan.borrower = to;
        
        // Transfer NFT via protocol-authorized function (bypasses ERC721 approval)
        positionNFT.protocolTransfer(tokenId, from, to);
        
        emit BorrowerPositionTransferred(loanId, from, to);
    }

    /// @notice Transfer lender position
    /// @dev Only callable internally by marketplace functions
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
        
        // Update loan record
        loan.lender = to;
        
        // Transfer NFT via protocol-authorized function (bypasses ERC721 approval)
        positionNFT.protocolTransfer(tokenId, from, to);
        
        emit LenderPositionTransferred(loanId, from, to);
    }

    // ============================================================================
    // INTEGRATED MARKETPLACE - LISTINGS
    // ============================================================================

    /// @notice List a position for sale on the marketplace
    /// @param loanId Loan ID of the position
    /// @param positionType "borrower" or "lender"
    /// @param paymentToken Token for payment (usually stablecoin)
    /// @param askingPrice Price in payment tokens
    function listPosition(
        uint256 loanId,
        string calldata positionType,
        address paymentToken,
        uint256 askingPrice
    ) external whenNotPaused {
        // Delegate to internal listing logic
        _listPosition(loanId, msg.sender, positionType, paymentToken, askingPrice);
    }

    /// @notice List a position for sale on behalf of the position owner
    /// @dev Caller must be an approved operator (via setOperatorApproval)
    /// @param loanId Loan ID of the position
    /// @param seller The position owner who is listing
    /// @param positionType "borrower" or "lender"
    /// @param paymentToken Token for payment
    /// @param askingPrice Price in payment tokens
    function listPositionFor(
        uint256 loanId,
        address seller,
        string calldata positionType,
        address paymentToken,
        uint256 askingPrice
    ) external whenNotPaused {
        // Reject zero address to prevent permanently locked funds
        if (seller == address(0)) revert ZeroAddress();
        // SECURITY: Caller must be seller or approved operator
        if (msg.sender != seller && !operatorApprovals[seller][msg.sender]) {
            // Caller lacks required permission for this action
            revert Unauthorized();
        }
        // Delegate to internal listing logic
        _listPosition(loanId, seller, positionType, paymentToken, askingPrice);
    }

    /// @dev Internal listing logic
    function _listPosition(
        uint256 loanId,
        address seller,
        string calldata positionType,
        address paymentToken,
        uint256 askingPrice
    ) internal {
        // Cannot create duplicate listings
        if (marketplaceListings[loanId].active) revert AlreadyListed();
        // Listing price must be non-zero
        if (askingPrice == 0) revert InvalidPrice();
        // Reject zero address to prevent permanently locked funds
        if (paymentToken == address(0)) revert ZeroAddress();

        // Validate position type and ownership
        bool isBorrower = _compareStrings(positionType, "borrower");
        // Check if this is a lender position
        bool isLender = _compareStrings(positionType, "lender");
        // Must be exactly "borrower" or "lender"
        if (!isBorrower && !isLender) revert InvalidPositionType();

        // Verify seller owns the position
        uint256 tokenId = isBorrower 
            // If borrower: use even token ID; otherwise: use odd token ID
            ? positionNFT.getBorrowerTokenId(loanId)
            // Lender token ID for the position
            : positionNFT.getLenderTokenId(loanId);
        
        if (positionNFT.ownerOf(tokenId) != seller) revert NotPositionOwner();

        // Verify loan is still active
        Loan storage loan = loans[loanId];
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        
        // Block listing if within maturity buffer (marketplace frozen)
        uint256 freezeTime = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback to 0 if subtraction would underflow
            : 0;
        // Operations blocked within MATURITY_BUFFER of loan maturity
        if (block.timestamp >= freezeTime) revert MarketplaceFrozen();

        marketplaceListings[loanId] = MarketplaceListing({
            seller: seller,
            positionType: positionType,
            // Cache listing payment token for refund routing
            paymentToken: paymentToken,
            askingPrice: askingPrice,
            // Record listing creation timestamp
            listedAt: block.timestamp,
            // Listing starts as active
            active: true
        });

        emit PositionListed(loanId, seller, positionType, paymentToken, askingPrice);
    }

    /// @notice Remove a listing from the marketplace
    /// @dev Automatically refunds all pending offers
    /// @param loanId Loan ID to unlist
    function unlistPosition(uint256 loanId) external whenNotPaused nonReentrant {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[loanId];
        // Position must be actively listed
        if (!listing.active) revert NotListed();
        // Only the listing seller can manage this listing
        if (listing.seller != msg.sender) revert NotSeller();

        listing.active = false;

        // Refund all pending offers (pass 0 since no offer is being accepted)
        _refundOtherOffers(loanId, 0);

        emit PositionUnlisted(loanId);
    }

    /// @notice Update listing price
    /// @param loanId Loan ID
    /// @param newPrice New asking price
    function updateListingPrice(uint256 loanId, uint256 newPrice) external whenNotPaused {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[loanId];
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
    // INTEGRATED MARKETPLACE - OFFERS (WITH ESCROW)
    // ============================================================================

    /// @notice Make an offer on a listed position (with escrow and expiration)
    /// @param loanId Loan ID
    /// @param offerAmount Offer amount (will be escrowed)
    /// @param offerDuration How long the offer is valid (minimum 1 day)
    /// @return offerId The created offer ID
    function makeMarketplaceOffer(uint256 loanId, uint256 offerAmount, uint256 offerDuration) 
        external 
        whenNotPaused 
        nonReentrant
        returns (uint256 offerId) 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[loanId];
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        
        if (!listing.active) revert NotListed();
        // Offer amount must be non-zero
        if (offerAmount == 0) revert InvalidOffer();
        // Seller cannot make offers on their own listing
        if (msg.sender == listing.seller) revert CannotBuyOwnPosition();
        // Duration below minimum (prevents instant-expire offers)
        if (offerDuration < MIN_OFFER_DURATION) revert OfferDurationTooShort();
        
        // Calculate max allowed expiry (maturity - buffer)
        uint256 maxExpiry = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback to 0 if subtraction would underflow
            : 0;
        
        // Reject if marketplace is frozen (within buffer period)
        if (block.timestamp >= maxExpiry) revert MarketplaceFrozen();
        
        // Reject if offer duration extends past the buffer (no silent capping)
        uint256 requestedExpiry = block.timestamp + offerDuration;
        // Offer must expire before marketplace freeze point
        if (requestedExpiry > maxExpiry) revert OfferDurationTooLong();

        // Prevent gas DoS: cap total offers to bound _refundOtherOffers loop
        if (marketplaceOfferNonce[loanId] >= MAX_OFFERS_PER_LISTING) revert TooManyOffers();

        offerId = ++marketplaceOfferNonce[loanId];

        marketplaceOffers[loanId][offerId] = MarketplaceOffer({
            buyer: msg.sender,
            amount: offerAmount,
            // Full offer amount held in escrow until resolution
            escrowedAmount: offerAmount,
            // Offer starts in PENDING state, awaiting seller response
            status: MarketplaceOfferStatus.PENDING,
            // No counter-offer initially
            counterAmount: 0,
            createdAt: block.timestamp,
            // Set offer expiration deadline
            expiresAt: requestedExpiry,
            // Cache listing payment token for refund routing
            paymentToken: listing.paymentToken
        });

        // Escrow the offer amount
        IERC20(listing.paymentToken).safeTransferFrom(msg.sender, address(this), offerAmount);

        emit MarketplaceOfferMade(loanId, offerId, msg.sender, offerAmount);
    }

    /// @notice Cancel an offer and get refund (buyer only)
    /// @param loanId Loan ID
    /// @param offerId Offer ID
    function cancelMarketplaceOffer(uint256 loanId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[loanId][offerId];
        
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
        
        // Effects
        offer.status = MarketplaceOfferStatus.CANCELLED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;

        // Return escrowed funds (push-based - safe because buyer is msg.sender)
        if (refundAmount > 0) {
            // Push tokens to caller (safe — caller is msg.sender)
            IERC20(paymentToken).safeTransfer(msg.sender, refundAmount);
        }

        emit MarketplaceOfferCancelled(loanId, offerId);
    }

    /// @notice Reject an offer (seller only) - queues refund for buyer
    /// @param loanId Loan ID
    /// @param offerId Offer ID
    function rejectMarketplaceOffer(uint256 loanId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[loanId];
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[loanId][offerId];

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
        
        // Effects
        offer.status = MarketplaceOfferStatus.REJECTED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;

        // Queue refund for buyer (pull-based - prevents DoS from malicious buyer contracts)
        if (refundAmount > 0) {
            // Queue refund via pull pattern — recipient claims via claimRefund()
            pendingRefunds[buyer][paymentToken] += refundAmount;
            // Emit MarketplaceOfferRefundQueued for off-chain indexing and frontend updates
            emit MarketplaceOfferRefundQueued(loanId, offerId, buyer, refundAmount);
        }

        emit MarketplaceOfferRejected(loanId, offerId);
    }

    /// @notice Expire an offer that has passed its expiration time (callable by anyone)
    /// @dev Queues refund for the buyer - permissionless cleanup function
    /// @param loanId Loan ID
    /// @param offerId Offer ID
    function expireMarketplaceOffer(uint256 loanId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[loanId][offerId];

        if (offer.buyer == address(0)) revert OfferNotFound();
        // Verify offer is in PENDING state
        if (offer.status != MarketplaceOfferStatus.PENDING && 
            // Also allow COUNTERED offers to be cancelled/expired
            offer.status != MarketplaceOfferStatus.COUNTERED) {
            // Offer not in the expected state for this operation
            revert InvalidOfferStatus();
        }
        // Offer has not yet reached its expiration timestamp
        if (block.timestamp < offer.expiresAt) revert OfferNotExpired();

        uint256 refundAmount = offer.escrowedAmount;
        // Cache buyer address for refund transfer
        address buyer = offer.buyer;
        // Cache payment token for transfer routing
        address paymentToken = offer.paymentToken;
        
        // Effects
        offer.status = MarketplaceOfferStatus.EXPIRED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;

        // Queue refund for buyer (pull-based)
        if (refundAmount > 0) {
            // Queue refund via pull pattern — recipient claims via claimRefund()
            pendingRefunds[buyer][paymentToken] += refundAmount;
            // Emit MarketplaceOfferRefundQueued for off-chain indexing and frontend updates
            emit MarketplaceOfferRefundQueued(loanId, offerId, buyer, refundAmount);
        }

        emit MarketplaceOfferExpired(loanId, offerId);
    }

    /// @notice Counter an offer (seller only) - resets expiry
    /// @dev Does NOT change escrow - buyer decides whether to accept counter
    /// @param loanId Loan ID
    /// @param offerId Offer ID
    /// @param counterAmount Counter offer amount
    /// @param counterDuration New expiry duration for the counter offer (minimum 1 day)
    function counterMarketplaceOffer(
        uint256 loanId, 
        uint256 offerId, 
        uint256 counterAmount,
        uint256 counterDuration
    ) 
        external 
        whenNotPaused 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[loanId];
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[loanId][offerId];
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];

        if (!listing.active) revert NotListed();
        // Only the listing seller can manage this listing
        if (listing.seller != msg.sender) revert NotSeller();
        // Verify offer record exists
        if (offer.buyer == address(0)) revert OfferNotFound();
        // Offer not in the expected state for this operation
        if (offer.status != MarketplaceOfferStatus.PENDING) revert InvalidOfferStatus();
        // Offer amount must be non-zero
        if (counterAmount == 0) revert InvalidOffer();
        // Duration below minimum (prevents instant-expire offers)
        if (counterDuration < MIN_OFFER_DURATION) revert OfferDurationTooShort();

        // Calculate max allowed expiry (maturity - buffer)
        uint256 maxExpiry = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback to 0 if subtraction would underflow
            : 0;
        
        // Reject if marketplace is frozen (within buffer period)
        if (block.timestamp >= maxExpiry) revert MarketplaceFrozen();
        
        // Reject if counter duration extends past the buffer (no silent capping)
        uint256 newExpiry = block.timestamp + counterDuration;
        // Offer must expire before marketplace freeze point
        if (newExpiry > maxExpiry) revert OfferDurationTooLong();

        offer.status = MarketplaceOfferStatus.COUNTERED;
        // Store the seller's counter-offer price
        offer.counterAmount = counterAmount;
        // Reset expiration for the counter-offer period
        offer.expiresAt = newExpiry;

        emit MarketplaceCounterOffer(loanId, offerId, counterAmount);
    }

    /// @notice Accept an offer (seller accepts buyer's original offer)
    /// @dev Automatically refunds all other pending offers
    /// @param loanId Loan ID
    /// @param offerId Offer ID
    function acceptMarketplaceOffer(uint256 loanId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[loanId];
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[loanId][offerId];

        if (!listing.active) revert NotListed();
        // Only the listing seller can manage this listing
        if (listing.seller != msg.sender) revert NotSeller();
        // Verify offer record exists
        if (offer.buyer == address(0)) revert OfferNotFound();
        // Offer not in the expected state for this operation
        if (offer.status != MarketplaceOfferStatus.PENDING) revert InvalidOfferStatus();
        
        // Prevent accepting time-expired offers
        if (block.timestamp >= offer.expiresAt) revert OfferExpired();

        // Verify loan is still active (stale listing protection)
        Loan storage loan = loans[loanId];
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        
        // Block acceptance if within maturity buffer (marketplace frozen)
        uint256 freezeTime = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback to 0 if subtraction would underflow
            : 0;
        // Operations blocked within MATURITY_BUFFER of loan maturity
        if (block.timestamp >= freezeTime) revert MarketplaceFrozen();

        address buyer = offer.buyer;
        // Cache seller address for events and transfers
        address seller = listing.seller;
        // Cache offer price for events and transfers
        uint256 price = offer.amount;
        // Cache payment token for transfer routing
        address paymentToken = offer.paymentToken;
        
        // Effects
        offer.status = MarketplaceOfferStatus.ACCEPTED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;
        // Deactivate listing — prevents double-sale and further offers
        listing.active = false;

        // Refund all other pending/countered offers
        _refundOtherOffers(loanId, offerId);

        // Transfer escrowed payment to seller
        IERC20(paymentToken).safeTransfer(seller, price);

        // Transfer position
        _executePositionTransfer(loanId, seller, buyer, listing.positionType);

        emit MarketplaceOfferAccepted(loanId, offerId, buyer, seller, price);
        // Emit PositionSold for off-chain indexing and frontend updates
        emit PositionSold(loanId, seller, buyer, price);
    }

    /// @notice Accept a counter offer (buyer accepts seller's counter)
    /// @dev Buyer must have approved additional funds if counter > original offer
    /// @param loanId Loan ID
    /// @param offerId Offer ID
    function acceptMarketplaceCounterOffer(uint256 loanId, uint256 offerId) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[loanId];
        // Load marketplace offer from storage
        MarketplaceOffer storage offer = marketplaceOffers[loanId][offerId];

        if (!listing.active) revert NotListed();
        // Only the offer maker can cancel/accept their offer
        if (offer.buyer != msg.sender) revert NotBuyer();
        // Offer not in the expected state for this operation
        if (offer.status != MarketplaceOfferStatus.COUNTERED) revert InvalidOfferStatus();
        
        // Prevent accepting time-expired counter-offers
        if (block.timestamp >= offer.expiresAt) revert OfferExpired();

        // Verify loan is still active (stale listing protection)
        Loan storage loan = loans[loanId];
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        
        // Block acceptance if within maturity buffer (marketplace frozen)
        uint256 freezeTime = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback to 0 if subtraction would underflow
            : 0;
        // Operations blocked within MATURITY_BUFFER of loan maturity
        if (block.timestamp >= freezeTime) revert MarketplaceFrozen();

        address buyer = offer.buyer;
        // Cache seller address for events and transfers
        address seller = listing.seller;
        // Cache counter-offer price for payment settlement
        uint256 counterPrice = offer.counterAmount;
        // Cache escrowed amount to determine payment delta
        uint256 escrowedAmount = offer.escrowedAmount;
        // Cache payment token for transfer routing
        address paymentToken = offer.paymentToken;
        
        // Effects
        offer.status = MarketplaceOfferStatus.ACCEPTED;
        // Clear escrow balance before transfer (CEI pattern)
        offer.escrowedAmount = 0;
        // Deactivate listing — prevents double-sale and further offers
        listing.active = false;

        // Refund all other pending/countered offers
        _refundOtherOffers(loanId, offerId);

        // Handle payment difference
        if (counterPrice > escrowedAmount) {
            // Buyer needs to pay more
            uint256 additionalAmount = counterPrice - escrowedAmount;
            // Pull additional payment from buyer into contract escrow
            IERC20(paymentToken).safeTransferFrom(buyer, address(this), additionalAmount);
            // Transfer payment to seller
            IERC20(paymentToken).safeTransfer(seller, counterPrice);
        } else if (counterPrice < escrowedAmount) {
            // Refund excess to buyer (push is safe since buyer is msg.sender)
            uint256 refundAmount = escrowedAmount - counterPrice;
            // Transfer payment to seller
            IERC20(paymentToken).safeTransfer(seller, counterPrice);
            // Transfer tokens to recipient
            IERC20(paymentToken).safeTransfer(buyer, refundAmount);
        } else {
            // Exact match
            IERC20(paymentToken).safeTransfer(seller, counterPrice);
        }

        // Transfer position
        _executePositionTransfer(loanId, seller, buyer, listing.positionType);

        emit MarketplaceOfferAccepted(loanId, offerId, buyer, seller, counterPrice);
        // Emit PositionSold for off-chain indexing and frontend updates
        emit PositionSold(loanId, seller, buyer, counterPrice);
    }

    // ============================================================================
    // INTEGRATED MARKETPLACE - DIRECT PURCHASE
    // ============================================================================

    /// @notice Buy a position at the asking price
    /// @dev Automatically refunds all pending offers
    /// @param loanId Loan ID to purchase
    function buyPosition(uint256 loanId) external whenNotPaused nonReentrant {
        // Load marketplace listing from storage
        MarketplaceListing storage listing = marketplaceListings[loanId];
        
        if (!listing.active) revert NotListed();
        // Seller cannot make offers on their own listing
        if (msg.sender == listing.seller) revert CannotBuyOwnPosition();

        // Verify loan is still active (stale listing protection)
        Loan storage loan = loans[loanId];
        // Loan must be ACTIVE for this operation
        if (loan.status != LoanStatus.ACTIVE) revert LoanNotActive();
        
        // Block purchase if within maturity buffer (marketplace frozen)
        uint256 freezeTime = loan.maturityTimestamp > MATURITY_BUFFER 
            // Calculate freeze point: maturity minus safety buffer
            ? loan.maturityTimestamp - MATURITY_BUFFER 
            // Fallback to 0 if subtraction would underflow
            : 0;
        // Operations blocked within MATURITY_BUFFER of loan maturity
        if (block.timestamp >= freezeTime) revert MarketplaceFrozen();

        address buyer = msg.sender;
        // Cache seller address for events and transfers
        address seller = listing.seller;
        // Cache asking price for events and transfers
        uint256 price = listing.askingPrice;
        // Cache payment token for transfer routing
        address paymentToken = listing.paymentToken;
        
        // Effects
        listing.active = false;

        // Refund all pending offers (pass 0 since no offer is being accepted)
        _refundOtherOffers(loanId, 0);

        // Transfer payment from buyer to seller
        IERC20(paymentToken).safeTransferFrom(buyer, seller, price);

        // Transfer position
        _executePositionTransfer(loanId, seller, buyer, listing.positionType);

        emit PositionSold(loanId, seller, buyer, price);
    }

    // ============================================================================
    // INTERNAL HELPERS
    // ============================================================================

    /// @notice Execute position transfer based on position type
    function _executePositionTransfer(
        uint256 loanId,
        address seller,
        address buyer,
        string memory positionType
    ) internal {
        // Determine which position type is being operated on
        bool isBorrower = _compareStrings(positionType, "borrower");
        
        if (isBorrower) {
            // Transfer borrower position: update loan + move NFT
            _transferBorrowerPosition(loanId, seller, buyer);
        } else {
            // Transfer lender position: update loan + move NFT
            _transferLenderPosition(loanId, seller, buyer);
        }
    }

    /// @notice Compare two strings
    function _compareStrings(string memory a, string memory b) 
        internal 
        pure 
        returns (bool) 
    {
        // Compare strings by hashing — Solidity has no native string equality
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    /// @notice Refund all other pending/countered offers for a listing (pull-based)
    /// @dev Called when an offer is accepted or listing is unlisted
    function _refundOtherOffers(uint256 loanId, uint256 acceptedOfferId) internal {
        // Get total offer count to determine loop iteration bounds
        uint256 offerCount = marketplaceOfferNonce[loanId];
        
        for (uint256 i = 1; i <= offerCount; i++) {
            // Skip the accepted offer — its escrow was already transferred to seller
            if (i == acceptedOfferId) continue; // Skip the accepted offer
            
            MarketplaceOffer storage offer = marketplaceOffers[loanId][i];
            
            // Only refund offers that are still pending or countered
            if (offer.status == MarketplaceOfferStatus.PENDING || 
                offer.status == MarketplaceOfferStatus.COUNTERED) {
                
                uint256 refundAmount = offer.escrowedAmount;
                // Only process refund if there are escrowed funds to return
                if (refundAmount > 0) {
                    // Cache buyer address for refund transfer
                    address buyer = offer.buyer;
                    // Cache payment token for transfer routing
                    address paymentToken = offer.paymentToken;
                    
                    // Mark as cancelled and clear escrow
                    offer.status = MarketplaceOfferStatus.CANCELLED;
                    // Clear escrow balance before transfer (CEI pattern)
                    offer.escrowedAmount = 0;
                    
                    // Queue refund (pull-based)
                    pendingRefunds[buyer][paymentToken] += refundAmount;
                    
                    emit MarketplaceOfferRefundQueued(loanId, i, buyer, refundAmount);
                }
            }
        }
    }

    // ============================================================================
    // VIEW FUNCTIONS - CORE PROTOCOL
    // ============================================================================

    /// @notice Get full auction details
    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        // Return full auction struct as memory copy
        return auctions[auctionId];
    }

    /// @notice Get full loan details
    function getLoan(uint256 loanId) external view returns (Loan memory) {
        // Return full loan struct as memory copy
        return loans[loanId];
    }

    /// @notice Get current winning bid info
    function getCurrentBid(uint256 auctionId) external view returns (address bidder, uint256 amount) {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        // Return current winning bidder and bid amount
        return (auction.currentBidder, auction.currentBid);
    }

    /// @notice Get bid count for an auction
    function getBidCount(uint256 auctionId) external view returns (uint256) {
        // Return full auction struct as memory copy
        return auctions[auctionId].bidCount;
    }

    /// @notice Get user's collateral balance
    function getCollateralBalance(address user, address token) external view returns (uint256) {
        // Read from nested mapping: user → token → balance
        return collateralBalances[user][token];
    }

    /// @notice Get pending refund amount
    function getPendingRefund(address user, address token) external view returns (uint256) {
        // Read from nested mapping: user → token → pending refund
        return pendingRefunds[user][token];
    }

    /// @notice Get borrower position NFT owner
    function getBorrowerPositionOwner(uint256 loanId) external view returns (address) {
        // Derive borrower NFT token ID: loanId * 2 (even numbers)
        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);
        // Attempt to read NFT owner — may revert if token was burned
        try positionNFT.ownerOf(tokenId) returns (address owner) {
            // Return the NFT owner address
            return owner;
        // Handle case where NFT does not exist (burned or never minted)
        } catch {
            // NFT does not exist — return zero address
            return address(0);
        }
    }

    /// @notice Get lender position NFT owner
    function getLenderPositionOwner(uint256 loanId) external view returns (address) {
        // Derive lender NFT token ID: loanId * 2 + 1 (odd numbers)
        uint256 tokenId = positionNFT.getLenderTokenId(loanId);
        // Attempt to read NFT owner — may revert if token was burned
        try positionNFT.ownerOf(tokenId) returns (address owner) {
            // Return the NFT owner address
            return owner;
        // Handle case where NFT does not exist (burned or never minted)
        } catch {
            // NFT does not exist — return zero address
            return address(0);
        }
    }

    /// @notice Get time remaining on auction
    function getAuctionTimeRemaining(uint256 auctionId) external view returns (uint256) {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        if (auction.borrower == address(0)) return 0;
        if (auction.status != AuctionStatus.OPEN) return 0;
        if (block.timestamp >= auction.auctionEnd) return 0;
        // Return seconds remaining until auction ends
        return auction.auctionEnd - block.timestamp;
    }

    /// @notice Get time remaining on loan
    function getLoanTimeRemaining(uint256 loanId) external view returns (uint256) {
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        if (loan.borrower == address(0)) return 0;
        if (loan.status != LoanStatus.ACTIVE) return 0;
        if (block.timestamp >= loan.maturityTimestamp) return 0;
        // Return seconds remaining until loan maturity
        return loan.maturityTimestamp - block.timestamp;
    }

    /// @notice Check if loan is in grace period
    function isInGracePeriod(uint256 loanId) external view returns (bool) {
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        if (loan.status != LoanStatus.ACTIVE) return false;
        if (block.timestamp < loan.maturityTimestamp) return false;
        return block.timestamp < loan.maturityTimestamp + GRACE_PERIOD;
    }

    /// @notice Check if lender can claim collateral
    function canClaimCollateral(uint256 loanId) external view returns (bool) {
        // Load loan from storage (storage pointer for gas-efficient updates)
        Loan storage loan = loans[loanId];
        if (loan.status != LoanStatus.ACTIVE) return false;
        return block.timestamp >= loan.maturityTimestamp + GRACE_PERIOD;
    }

    /// @notice Get finalization time remaining
    function getFinalizationTimeRemaining(uint256 auctionId) external view returns (uint256) {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        if (auction.borrower == address(0)) return 0;
        if (auction.status != AuctionStatus.OPEN) return 0;
        if (block.timestamp < auction.auctionEnd) return 0;
        
        uint256 deadline = auction.auctionEnd + FINALIZATION_WINDOW;
        if (block.timestamp >= deadline) return 0;
        // Return seconds remaining in finalization window
        return deadline - block.timestamp;
    }

    /// @notice Check if auction can be finalized
    function canFinalize(uint256 auctionId) external view returns (bool) {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        if (auction.borrower == address(0)) return false;
        if (auction.status != AuctionStatus.OPEN) return false;
        if (block.timestamp < auction.auctionEnd) return false;
        // Check if finalization window has passed
        if (block.timestamp > auction.auctionEnd + FINALIZATION_WINDOW) return false;
        // Condition met — return true
        return true;
    }

    /// @notice Check if user can claim from expired auction
    function canClaimExpiredAuction(uint256 auctionId, address claimant) 
        external 
        view 
        returns (bool canClaim, bool isLender) 
    {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        
        if (auction.borrower == address(0)) return (false, false);
        if (auction.status != AuctionStatus.OPEN && auction.status != AuctionStatus.EXPIRED) {
            // Cannot claim — either wrong caller or already claimed
            return (false, false);
        }
        // Verify finalization window has expired before allowing expiry claims
        if (block.timestamp <= auction.auctionEnd + FINALIZATION_WINDOW) return (false, false);
        if (auction.bidCount == 0) return (false, false);
        
        bool isBorrower = claimant == auction.borrower;
        bool isLenderCheck = claimant == auction.currentBidder;
        
        if (isLenderCheck && !expiredAuctionLenderClaimed[auctionId]) {
            // Lender can claim — return true with isLender flag
            return (true, true);
        }
        // Route to borrower-side or lender-side logic
        if (isBorrower && !expiredAuctionBorrowerClaimed[auctionId]) {
            // Borrower can claim — return true without isLender flag
            return (true, false);
        }
        
        return (false, false);
    }

    /// @notice Calculate minimum valid bid for an auction
    /// @dev Returns loan amount (the absolute floor - no negative interest)
    function getMinimumBid(uint256 auctionId) external view returns (uint256) {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        if (auction.borrower == address(0)) return 0;
        if (auction.status != AuctionStatus.OPEN) return 0;
        
        // Minimum bid is always the loan amount (no negative interest)
        return auction.loanAmount;
    }

    /// @notice Calculate maximum valid bid for an auction
    /// @dev For first bid: maxRepayment. For subsequent: currentBid - bidStep
    function getMaximumBid(uint256 auctionId) external view returns (uint256) {
        // Load auction from storage (storage pointer for gas-efficient updates)
        Auction storage auction = auctions[auctionId];
        if (auction.borrower == address(0)) return 0;
        if (auction.status != AuctionStatus.OPEN) return 0;
        
        if (auction.bidCount == 0) {
            // First bid: any amount up to maxRepayment is valid
            return auction.maxRepayment;
        }
        
        // For subsequent bids, must be at least bidStep lower than current bid
        uint256 maxValidBid = auction.currentBid > auction.bidStep 
            // Calculate max valid bid: current best minus step size
            ? auction.currentBid - auction.bidStep 
            // Fallback to 0 if subtraction would underflow
            : 0;
        
        // If step would push below loan amount, allow up to currentBid - 1
        if (maxValidBid < auction.loanAmount) {
            // Check if any valid bid improvement is still possible
            if (auction.currentBid > auction.loanAmount) {
                // Near-floor: allow any strict improvement
                return auction.currentBid - 1;
            }
            return 0; // No valid bid possible
        }
        
        return maxValidBid;
    }

    /// @notice Get the bid step for an auction
    /// @param auctionId The auction ID
    /// @return The minimum bid improvement required (in loan token decimals)
    function getAuctionBidStep(uint256 auctionId) external view returns (uint256) {
        // Return full auction struct as memory copy
        return auctions[auctionId].bidStep;
    }

    // ============================================================================
    // VIEW FUNCTIONS - MARKETPLACE
    // ============================================================================

    /// @notice Get marketplace listing details
    function getMarketplaceListing(uint256 loanId) external view returns (MarketplaceListing memory) {
        // Return full listing struct as memory copy
        return marketplaceListings[loanId];
    }

    /// @notice Get marketplace offer details
    function getMarketplaceOffer(uint256 loanId, uint256 offerId) 
        external 
        view 
        returns (MarketplaceOffer memory) 
    {
        // Return full offer struct as memory copy
        return marketplaceOffers[loanId][offerId];
    }

    /// @notice Get number of offers for a listing
    function getMarketplaceOfferCount(uint256 loanId) external view returns (uint256) {
        // Return total offer count for this listing
        return marketplaceOfferNonce[loanId];
    }

    /// @notice Check if a position is listed
    function isPositionListed(uint256 loanId) external view returns (bool) {
        // Return full listing struct as memory copy
        return marketplaceListings[loanId].active;
    }
}
