// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev OpenZeppelin upgradeable proxy initialization (replaces constructor)
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
/// @dev Owner-restricted access control for admin functions
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
/// @dev Mutex guard preventing reentrant external calls
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
/// @dev Emergency pause mechanism — halts all state-changing operations
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
/// @dev Standard ERC-20 token interface for fee collection
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/// @dev Safe ERC-20 wrappers handling non-standard return values
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
/// @dev Standard ERC-721 interface for NFT ownership verification
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @dev Interface for the underlying permissionless NFTLoanProtocol contract
import "./interfaces/INFTLoanProtocol.sol";

/**
 * @title NFTListingService
 * @author Bitcoin Yield Curve
 * @notice Commercial listing service for NFT-collateralized lending with curated collections
 * @dev This is the BUSINESS LAYER - separate from the permissionless protocol
 * 
 * Ã¢â€¢â€Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢â€”
 * Ã¢â€¢â€˜                   NFT LISTING SERVICE - CURATED ACCESS                    Ã¢â€¢â€˜
 * Ã¢â€¢Â Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â£
 * Ã¢â€¢â€˜  This contract provides a SAFE, CURATED way to interact with the          Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  underlying NFTLoanProtocol. Only whitelisted NFT collections and         Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  loan tokens can be used.                                                 Ã¢â€¢â€˜
 * Ã¢â€¢â€˜                                                                           Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  Benefits of using NFTListingService:                                     Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  Ã¢Å“â€œ Collection whitelist - only vetted NFT collections accepted            Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  Ã¢Å“â€œ Loan token whitelist - only legitimate stablecoins                     Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  Ã¢Å“â€œ Front-end integration with official website                            Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  Ã¢Å“â€œ Customer support and dispute resolution                                Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  Ã¢Å“â€œ Compliance with applicable regulations                                 Ã¢â€¢â€˜
 * Ã¢â€¢â€˜                                                                           Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  The underlying NFTLoanProtocol is permissionless and accepts ANY NFT.    Ã¢â€¢â€˜
 * Ã¢â€¢â€˜  Users who bypass this service assume all risk.                           Ã¢â€¢â€˜
 * Ã¢â€¢Å¡Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
 * 
 * FEE MODEL:
 * - Auction listing fee: Flat fee in loan token (e.g., $10 USDC) at auction creation
 * - Marketplace listing fee: Flat fee to list a position for sale
 * - All fees go directly to treasury
 */
contract NFTListingService is 
        // Upgradeable proxy pattern — replaces constructor with initialize()
    Initializable, 
        // Single-owner access control for admin and fee management
    OwnableUpgradeable, 
        // Emergency circuit breaker — halts auction creation and listings
    PausableUpgradeable,
        // Mutex lock preventing reentrant calls during fee collection
    ReentrancyGuardUpgradeable 
{
    /// @dev Attach safe transfer wrappers to all IERC20 instances
    using SafeERC20 for IERC20;

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    /// @notice Maximum auction listing fee (in USDC with 6 decimals)
    uint256 public constant MAX_AUCTION_LISTING_FEE = 1000_000_000; // $1000 max

    /// @notice Maximum marketplace listing fee
    uint256 public constant MAX_MARKETPLACE_LISTING_FEE = 100_000_000; // $100 max

    /// @notice Maximum collections per batch whitelist operation
    uint256 public constant MAX_BATCH_SIZE = 50;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice The NFTLoanProtocol contract
    INFTLoanProtocol public loanProtocol;

    /// @notice Flat fee to create an auction (in loan token, e.g., USDC)
    uint256 public auctionListingFee;

    /// @notice Flat fee to list a position on marketplace
    uint256 public marketplaceListingFee;

    /// @notice Treasury address for fee collection
    address public treasury;

    /// @notice Whitelisted NFT collections (curated list of safe collections)
    mapping(address => bool) public collectionWhitelist;

    /// @notice Whitelisted loan tokens (curated list of stablecoins)
    mapping(address => bool) public loanTokenWhitelist;

    /// @notice Track which auctions were created through listing service
    mapping(uint256 => bool) public listedAuctions;

    /// @notice Collection metadata for display
    struct CollectionInfo {
        /// @dev Human-readable collection name
        string name;
        /// @dev Collection ticker symbol
        string symbol;
        /// @dev Whether collection has been verified by admin
        bool isVerified;
        /// @dev Unix timestamp when collection was whitelisted
        uint256 addedAt;
    }

    /// @notice Collection metadata
    mapping(address => CollectionInfo) public collectionInfo;

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @param auctionId Auction ID created in NFTLoanProtocol
    /// @param borrower Address creating the auction
    /// @param collectionAddress Whitelisted NFT collection used as collateral
    /// @param tokenId NFT token ID locked as collateral
    /// @param loanToken Whitelisted loan token requested
    /// @param loanAmount Principal amount requested
    /// @param fee Auction listing fee collected (flat, in loan token)
    /// @param bidStep Minimum bid improvement for this auction
    event ListedAuctionCreated(
        // auction identifier
        uint256 indexed auctionId,
        // auction borrower
        address indexed borrower,
        // whitelisted NFT collection
        address indexed collectionAddress,
        // NFT token ID
        uint256 tokenId,
        // loan token address
        address loanToken,
        // principal requested
        uint256 loanAmount,
        // listing fee collected
        uint256 fee,
        // minimum bid improvement
        uint256 bidStep
    );

    /// @param auctionId Auction whose fee was collected (0 if not yet known)
    /// @param token Fee token (loan token)
    /// @param amount Fee amount collected
    event AuctionFeeCollected(
        // auction identifier
        uint256 indexed auctionId,
        // fee token address
        address indexed token,
        // token amount
        uint256 amount
    );

    /// @param loanId Loan whose position is being listed
    /// @param token Payment token used for fee
    /// @param amount Fee amount collected
    /// @param seller Address paying the listing fee
    event MarketplaceListingFeeCollected(
        // loan identifier
        uint256 indexed loanId,
        // fee token address
        address indexed token,
        // token amount
        uint256 amount,
        // position seller paying fee
        address indexed seller
    );

    /// @param token Token withdrawn
    /// @param recipient Treasury address receiving fees
    /// @param amount Amount withdrawn
    event FeesWithdrawn(
        // fee token address
        address indexed token,
        // treasury receiving fees
        address indexed recipient,
        // token amount
        uint256 amount
    );

    event AuctionListingFeeUpdated(uint256 oldFee, uint256 newFee);
    /// @notice Emitted when admin updates the marketplace listing fee
    event MarketplaceListingFeeUpdated(uint256 oldFee, uint256 newFee);
    /// @notice Emitted when admin updates the treasury address
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    /// @notice Emitted when an NFT collection is added/removed from whitelist
    event CollectionWhitelistUpdated(address indexed collection, bool whitelisted);
    /// @notice Emitted when a loan token is added/removed from whitelist
    event LoanTokenWhitelistUpdated(address indexed token, bool whitelisted);
    /// @notice Emitted when collection metadata (name, symbol, verified) is updated
    event CollectionInfoUpdated(address indexed collection, string name, string symbol, bool isVerified);

    // ============================================================================
    // ERRORS
    // ============================================================================

    /// @dev FeeTooHigh: Fee exceeds maximum allowed cap
    error FeeTooHigh();
    /// @dev ZeroAddress: Provided where a valid address is required
    error ZeroAddress();
    /// @dev InvalidToken: Token address is zero
    error InvalidToken();
    /// @dev CollectionNotWhitelisted: NFT collection not on the curated whitelist
    error CollectionNotWhitelisted();
    /// @dev LoanTokenNotWhitelisted: Loan token not on the curated whitelist
    error LoanTokenNotWhitelisted();
    /// @dev NotNFTOwner: Caller does not own the specified NFT
    error NotNFTOwner();
    /// @dev NotListedAuction: Auction was not created through this NFTListingService
    error NotListedAuction();
    /// @dev BatchTooLarge: Array exceeds MAX_BATCH_SIZE (50) — prevents gas limit issues
    error BatchTooLarge();
    /// @dev ArrayLengthMismatch: Input arrays have different lengths
    error ArrayLengthMismatch();

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier validCollection(address collection) {
        // Reject zero address
        if (collection == address(0)) revert ZeroAddress();
        // Collection not on curated whitelist
        if (!collectionWhitelist[collection]) revert CollectionNotWhitelisted();
        // Continue to the modified function body
        _;
    }

    modifier validLoanToken(address token) {
        // Reject zero token address
        if (token == address(0)) revert InvalidToken();
        // Loan token not on curated whitelist
        if (!loanTokenWhitelist[token]) revert LoanTokenNotWhitelisted();
        // Continue to the modified function body
        _;
    }

    // ============================================================================
    // INITIALIZER
    // ============================================================================

    /// @notice Initialize the listing service
    /// @param _loanProtocol NFTLoanProtocol contract address
    /// @param _treasury Treasury address for fees
    /// @param _auctionListingFee Initial auction listing fee (flat amount)
    function initialize(
        address _loanProtocol,
        address _treasury,
        uint256 _auctionListingFee
    ) external initializer {
        // Reject zero address
        if (_loanProtocol == address(0)) revert ZeroAddress();
        // Reject zero address
        if (_treasury == address(0)) revert ZeroAddress();
        // Fee exceeds maximum allowed cap
        if (_auctionListingFee > MAX_AUCTION_LISTING_FEE) revert FeeTooHigh();

        __Ownable_init(msg.sender);
        // Initialize pause mechanism as unpaused
        __Pausable_init();
        // Initialize reentrancy guard
        __ReentrancyGuard_init();

        loanProtocol = INFTLoanProtocol(_loanProtocol);
        // Set initial treasury address
        treasury = _treasury;
        // Set initial auction listing fee
        auctionListingFee = _auctionListingFee;
        marketplaceListingFee = 0; // Default to free marketplace listings
    }

    // ============================================================================
    // ADMIN FUNCTIONS - COLLECTION WHITELISTING
    // ============================================================================

    /// @notice Add or remove an NFT collection from whitelist
    /// @param collection NFT collection address
    /// @param whitelisted Whether to whitelist
    function setCollectionWhitelist(address collection, bool whitelisted) external onlyOwner {
        // Reject zero address
        if (collection == address(0)) revert ZeroAddress();
        // Update collection whitelist mapping
        collectionWhitelist[collection] = whitelisted;
        // Emit CollectionWhitelistUpdated for off-chain indexing
        emit CollectionWhitelistUpdated(collection, whitelisted);
    }

    /// @notice Batch update collection whitelist
    /// @param collections Array of collection addresses
    /// @param whitelisted Array of whitelist statuses
    function batchSetCollectionWhitelist(
        address[] calldata collections,
        bool[] calldata whitelisted
    ) external onlyOwner {
        // Input arrays must have matching lengths
        if (collections.length != whitelisted.length) revert ArrayLengthMismatch();
        // Array exceeds maximum batch size
        if (collections.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < collections.length; i++) {
            // Reject zero address
            if (collections[i] == address(0)) revert ZeroAddress();
            // Update whitelist for each collection in batch
            collectionWhitelist[collections[i]] = whitelisted[i];
            // Emit CollectionWhitelistUpdated for off-chain indexing
            emit CollectionWhitelistUpdated(collections[i], whitelisted[i]);
        }
    }

    /// @notice Set collection metadata
    /// @param collection NFT collection address
    /// @param name Collection name
    /// @param symbol Collection symbol
    /// @param isVerified Whether collection is verified
    function setCollectionInfo(
        address collection,
        string calldata name,
        string calldata symbol,
        bool isVerified
    ) external onlyOwner {
        // Reject zero address
        if (collection == address(0)) revert ZeroAddress();
        
        collectionInfo[collection] = CollectionInfo({
            // Store display name
            name: name,
            // Store symbol
            symbol: symbol,
            // Store verification status
            isVerified: isVerified,
            // Record when collection was whitelisted
            addedAt: block.timestamp
        });

        emit CollectionInfoUpdated(collection, name, symbol, isVerified);
    }

    // ============================================================================
    // ADMIN FUNCTIONS - LOAN TOKEN WHITELISTING
    // ============================================================================

    /// @notice Add or remove a loan token from whitelist
    /// @param token Token address
    /// @param whitelisted Whether to whitelist
    function setLoanTokenWhitelist(address token, bool whitelisted) external onlyOwner {
        // Reject zero token address
        if (token == address(0)) revert InvalidToken();
        // Update loan token whitelist mapping
        loanTokenWhitelist[token] = whitelisted;
        // Emit LoanTokenWhitelistUpdated for off-chain indexing
        emit LoanTokenWhitelistUpdated(token, whitelisted);
    }

    /// @notice Batch update loan token whitelist
    /// @param tokens Array of token addresses
    /// @param whitelisted Array of whitelist statuses
    function batchSetLoanTokenWhitelist(
        address[] calldata tokens,
        bool[] calldata whitelisted
    ) external onlyOwner {
        // Input arrays must have matching lengths
        if (tokens.length != whitelisted.length) revert ArrayLengthMismatch();
        // Array exceeds maximum batch size
        if (tokens.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < tokens.length; i++) {
            // Reject zero token address
            if (tokens[i] == address(0)) revert InvalidToken();
            // Update whitelist for each token in batch
            loanTokenWhitelist[tokens[i]] = whitelisted[i];
            // Emit LoanTokenWhitelistUpdated for off-chain indexing
            emit LoanTokenWhitelistUpdated(tokens[i], whitelisted[i]);
        }
    }

    // ============================================================================
    // ADMIN FUNCTIONS - FEES
    // ============================================================================

    /// @notice Update auction listing fee
    /// @param newFee New fee amount (flat fee in loan token decimals)
    function setAuctionListingFee(uint256 newFee) external onlyOwner {
        // Fee exceeds maximum allowed cap
        if (newFee > MAX_AUCTION_LISTING_FEE) revert FeeTooHigh();
        // Emit AuctionListingFeeUpdated for off-chain indexing
        emit AuctionListingFeeUpdated(auctionListingFee, newFee);
        // Update auction listing fee in storage
        auctionListingFee = newFee;
    }

    /// @notice Update marketplace listing fee
    /// @param newFee New fee amount
    function setMarketplaceListingFee(uint256 newFee) external onlyOwner {
        // Fee exceeds maximum allowed cap
        if (newFee > MAX_MARKETPLACE_LISTING_FEE) revert FeeTooHigh();
        // Emit MarketplaceListingFeeUpdated for off-chain indexing
        emit MarketplaceListingFeeUpdated(marketplaceListingFee, newFee);
        // Update marketplace listing fee in storage
        marketplaceListingFee = newFee;
    }

    /// @notice Update treasury address
    /// @param newTreasury New treasury address
    function setTreasury(address newTreasury) external onlyOwner {
        // Reject zero address
        if (newTreasury == address(0)) revert ZeroAddress();
        // Emit TreasuryUpdated for off-chain indexing
        emit TreasuryUpdated(treasury, newTreasury);
        // Update treasury address in storage
        treasury = newTreasury;
    }

    // ============================================================================
    // ADMIN FUNCTIONS - PAUSE
    // ============================================================================

    /// @notice Pause the service
    function pause() external onlyOwner {
        // Activate emergency pause
        _pause();
    }

    /// @notice Unpause the service
    function unpause() external onlyOwner {
        // Deactivate emergency pause
        _unpause();
    }

    // ============================================================================
    // CORE FUNCTIONS - AUCTION CREATION
    // ============================================================================

    /**
     * @notice Create an auction through the listing service (with whitelist checks)
     * @dev User must approve NFTLoanProtocol (not this contract) to transfer their NFT
     *      User must also approve this contract for the listing fee in loan token
     * @param collateralNFT NFT collection address (must be whitelisted)
     * @param collateralTokenId NFT token ID to use as collateral
     * @param loanToken Token to borrow (must be whitelisted)
     * @param loanAmount Amount to borrow
     * @param maxRepayment Maximum repayment amount
     * @param loanDuration Loan duration in seconds
     * @param auctionDuration Auction duration in seconds
     * @param bidStep Minimum bid improvement for this auction
     * @return auctionId The created auction ID
     */
    function createListedAuction(
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
        validCollection(collateralNFT)
        validLoanToken(loanToken)
        returns (uint256 auctionId) 
    {
        // Verify user owns the NFT
        if (IERC721(collateralNFT).ownerOf(collateralTokenId) != msg.sender) {
            // Caller does not own the specified NFT
            revert NotNFTOwner();
        }

        // Collect listing fee (flat fee in loan token)
        if (auctionListingFee > 0) {
            // Transfer fee directly from caller to treasury
            IERC20(loanToken).safeTransferFrom(msg.sender, treasury, auctionListingFee);
            // Emit AuctionFeeCollected for off-chain indexing
            emit AuctionFeeCollected(0, loanToken, auctionListingFee); // auctionId not known yet
        }

        // Create the auction - NFTLoanProtocol will transfer NFT directly from borrower
        // User must have approved NFTLoanProtocol (not this contract) for the NFT
        auctionId = loanProtocol.createAuctionFor(
            msg.sender,  // The borrower
            collateralNFT,
            collateralTokenId,
            loanToken,
            loanAmount,
            maxRepayment,
            loanDuration,
            auctionDuration,
            bidStep
        );

        // Track this auction
        listedAuctions[auctionId] = true;

        emit ListedAuctionCreated(
            auctionId,
            msg.sender,
            collateralNFT,
            collateralTokenId,
            loanToken,
            loanAmount,
            auctionListingFee,
            bidStep
        );
    }


    // ============================================================================
    // CORE FUNCTIONS - MARKETPLACE LISTING WITH FEE
    // ============================================================================

    /**
     * @notice List a position on the marketplace with optional listing fee
     * @dev Seller must approve this contract for the listing fee amount in payment token
     * @param loanId The loan ID to list
     * @param positionType "borrower" or "lender"
     * @param paymentToken Token for payment (e.g., USDC)
     * @param askingPrice Asking price for the position
     */
    function listPositionWithFee(
        uint256 loanId,
        string calldata positionType,
        address paymentToken,
        uint256 askingPrice
    ) external whenNotPaused nonReentrant {
        // Collect flat listing fee if enabled
        if (marketplaceListingFee > 0) {
            // Transfer fee directly from caller to treasury
            IERC20(paymentToken).safeTransferFrom(msg.sender, treasury, marketplaceListingFee);
            // Emit MarketplaceListingFeeCollected for off-chain indexing
            emit MarketplaceListingFeeCollected(loanId, paymentToken, marketplaceListingFee, msg.sender);
        }

        // List the position on the protocol on behalf of the seller
        // Note: Seller must have approved NFTListingService as an operator via
        // nftLoanProtocol.setOperatorApproval(nftListingServiceAddress, true)
        loanProtocol.listPositionFor(loanId, msg.sender, positionType, paymentToken, askingPrice);
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /// @notice Check if a collection is whitelisted
    /// @param collection Collection address
    /// @return whitelisted True if whitelisted
    function isCollectionWhitelisted(address collection) external view returns (bool whitelisted) {
        // Return whitelist status for this collection
        return collectionWhitelist[collection];
    }

    /// @notice Check if a loan token is whitelisted
    /// @param token Token address
    /// @return whitelisted True if whitelisted
    function isLoanTokenWhitelisted(address token) external view returns (bool whitelisted) {
        // Return whitelist status for this loan token
        return loanTokenWhitelist[token];
    }

    /// @notice Check if an auction was created through listing service
    /// @param auctionId The auction ID
    /// @return listed True if created through this service
    function isListedAuction(uint256 auctionId) external view returns (bool listed) {
        // Return whether auction was created via NFTListingService
        return listedAuctions[auctionId];
    }

    /// @notice Get collection info
    /// @param collection Collection address
    /// @return info Collection metadata
    function getCollectionInfo(address collection) external view returns (CollectionInfo memory info) {
        // Return full collection metadata struct
        return collectionInfo[collection];
    }

    /// @notice Get current fee configuration
    /// @return auctionFee_ Auction listing fee
    /// @return marketplaceFee_ Marketplace listing fee
    function getFeeConfiguration() external view returns (uint256 auctionFee_, uint256 marketplaceFee_) {
        // Return both fee settings as a tuple
        return (auctionListingFee, marketplaceListingFee);
    }
}
