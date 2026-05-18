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
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                   NFT LISTING SERVICE - CURATED ACCESS                    ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║  This contract provides a SAFE, CURATED way to interact with the          ║
 * ║  underlying NFTLoanProtocol. Only whitelisted NFT collections and         ║
 * ║  loan tokens can be used.                                                 ║
 * ║                                                                           ║
 * ║  Benefits of using NFTListingService:                                     ║
 * ║  ✓ Collection whitelist - only vetted NFT collections accepted            ║
 * ║  ✓ Loan token whitelist - only legitimate stablecoins                     ║
 * ║  ✓ Front-end integration with official website                            ║
 * ║  ✓ Customer support and dispute resolution                                ║
 * ║  ✓ Compliance with applicable regulations                                 ║
 * ║                                                                           ║
 * ║  The underlying NFTLoanProtocol is permissionless and accepts ANY NFT.    ║
 * ║  Users who bypass this service assume all risk.                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */
contract NFTListingService is
        // Upgradeable proxy pattern — replaces constructor with initialize()
    Initializable,
        // Single-owner access control for admin functions
    OwnableUpgradeable,
        // Emergency circuit breaker — halts auction creation
    PausableUpgradeable,
        // Mutex lock preventing reentrant external calls
    ReentrancyGuardUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @dev Prevent implementation contract from being initialized (proxy-only pattern)
    constructor() {
        _disableInitializers();
    }

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    /// @notice Maximum collections per batch whitelist operation
    uint256 public constant MAX_BATCH_SIZE = 50;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice The NFTLoanProtocol contract
    INFTLoanProtocol public loanProtocol;

    /// @notice Whitelisted NFT collections (curated list of safe collections)
    mapping(address => bool) public collectionWhitelist;

    /// @notice Whitelisted loan tokens (curated list of stablecoins)
    mapping(address => bool) public loanTokenWhitelist;

    /// @notice Per-loan-token minimum bid step (in loan token base units).
    /// @dev Set at whitelist time. Required to be > 0 whenever a token is whitelisted.
    ///      A user calling createListedAuction with bidStep == 0 substitutes this value;
    ///      a user calling with bidStep > 0 must meet or exceed this value, otherwise
    ///      the call reverts with BidStepBelowTokenMinimum. Resolves Sherlock #15: a single
    ///      MIN_BID_STEP at the protocol layer is economically meaningless across tokens
    ///      with vastly different prices and decimals.
    mapping(address => uint256) public loanTokenMinBidSteps;

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
        // minimum bid improvement
        uint256 bidStep
    );

    /// @notice Emitted when an NFT collection is added/removed from whitelist
    event CollectionWhitelistUpdated(address indexed collection, bool whitelisted);
    /// @notice Emitted when a loan token is added/removed from whitelist
    event LoanTokenWhitelistUpdated(address indexed token, bool whitelisted);
    /// @notice Emitted when collection metadata (name, symbol, verified) is updated
    event CollectionInfoUpdated(address indexed collection, string name, string symbol, bool isVerified);

    // ============================================================================
    // ERRORS
    // ============================================================================

    /// @dev ZeroAddress: Provided where a valid address is required
    error ZeroAddress();
    /// @dev InvalidToken: Token address is zero
    error InvalidToken();
    /// @dev MinBidStepRequired: cannot whitelist a loan token with a zero minBidStep.
    ///      Forces admin to set a meaningful economic floor at whitelist time.
    error MinBidStepRequired();
    /// @dev BidStepBelowTokenMinimum: caller-supplied bidStep is below the configured
    ///      per-token minimum. Use bidStep == 0 to accept the configured default.
    error BidStepBelowTokenMinimum();
    /// @dev CollectionNotWhitelisted: NFT collection not on the curated whitelist
    error CollectionNotWhitelisted();
    /// @dev LoanTokenNotWhitelisted: Loan token not on the curated whitelist
    error LoanTokenNotWhitelisted();
    /// @dev NotNFTOwner: Caller does not own the specified NFT
    error NotNFTOwner();
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
    function initialize(address _loanProtocol) external initializer {
        // Reject zero address
        if (_loanProtocol == address(0)) revert ZeroAddress();

        __Ownable_init(msg.sender);
        // Initialize pause mechanism as unpaused
        __Pausable_init();
        // Initialize reentrancy guard
        __ReentrancyGuard_init();

        loanProtocol = INFTLoanProtocol(_loanProtocol);
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

    /// @notice Add or remove a loan token from whitelist with its minimum bid step
    /// @dev When whitelisting (whitelisted=true), minBidStep must be > 0. This forces the
    ///      admin to set a token-specific economic floor that reflects the token's decimals
    ///      and price (resolves Sherlock #15). When unwhitelisting (whitelisted=false),
    ///      minBidStep is ignored and the stored value is cleared.
    /// @param token Token address
    /// @param whitelisted Whether to whitelist
    /// @param minBidStep Minimum bid step in loan token base units (required > 0 if whitelisting)
    function setLoanTokenWhitelist(
        address token,
        bool whitelisted,
        uint256 minBidStep
    ) external onlyOwner {
        // Reject zero token address
        if (token == address(0)) revert InvalidToken();
        if (whitelisted) {
            // Reject whitelist with zero min bid step - forces admin to set a meaningful floor
            if (minBidStep == 0) revert MinBidStepRequired();
            loanTokenWhitelist[token] = true;
            loanTokenMinBidSteps[token] = minBidStep;
        } else {
            // Unwhitelist clears both the flag and the configured floor
            loanTokenWhitelist[token] = false;
            loanTokenMinBidSteps[token] = 0;
        }
        // Emit LoanTokenWhitelistUpdated for off-chain indexing
        emit LoanTokenWhitelistUpdated(token, whitelisted);
    }

    /// @notice Batch update loan token whitelist with per-token minimum bid steps
    /// @dev For tokens being whitelisted (whitelisted[i]==true), the corresponding
    ///      minBidSteps[i] must be > 0. For tokens being unwhitelisted, minBidSteps[i]
    ///      is ignored and the stored value is cleared.
    /// @param tokens Array of token addresses
    /// @param minBidSteps Parallel array of per-token minimum bid steps
    /// @param whitelisted Parallel array of whitelist statuses
    function batchSetLoanTokenWhitelist(
        address[] calldata tokens,
        uint256[] calldata minBidSteps,
        bool[] calldata whitelisted
    ) external onlyOwner {
        // Input arrays must have matching lengths
        if (tokens.length != whitelisted.length) revert ArrayLengthMismatch();
        if (tokens.length != minBidSteps.length) revert ArrayLengthMismatch();
        // Array exceeds maximum batch size
        if (tokens.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < tokens.length; i++) {
            // Reject zero token address
            if (tokens[i] == address(0)) revert InvalidToken();
            if (whitelisted[i]) {
                // Reject whitelist with zero min bid step
                if (minBidSteps[i] == 0) revert MinBidStepRequired();
                loanTokenWhitelist[tokens[i]] = true;
                loanTokenMinBidSteps[tokens[i]] = minBidSteps[i];
            } else {
                // Unwhitelist clears both the flag and the configured floor
                loanTokenWhitelist[tokens[i]] = false;
                loanTokenMinBidSteps[tokens[i]] = 0;
            }
            // Emit LoanTokenWhitelistUpdated for off-chain indexing
            emit LoanTokenWhitelistUpdated(tokens[i], whitelisted[i]);
        }
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

        // Resolve effective bid step against per-token minimum (Sherlock #15).
        // bidStep == 0 means "use the curated default for this loan token";
        // any non-zero value must meet or exceed the configured minimum.
        uint256 tokenMin = loanTokenMinBidSteps[loanToken];
        uint256 effectiveBidStep;
        if (bidStep == 0) {
            effectiveBidStep = tokenMin;
        } else {
            if (bidStep < tokenMin) revert BidStepBelowTokenMinimum();
            effectiveBidStep = bidStep;
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
            effectiveBidStep      // Token-specific minimum enforced above
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
            effectiveBidStep
        );
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
}
