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
/// @dev Standard ERC-20 token interface
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/// @dev Safe ERC-20 wrappers handling non-standard return values
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Interface for the underlying permissionless LoanProtocol contract
import "./interfaces/ILoanProtocol.sol";

/**
 * @title ListingService
 * @author Bitcoin Yield Curve
 * @notice Commercial listing service that provides curated token whitelisting and fee collection
 * @dev This is the BUSINESS LAYER - separate from the permissionless protocol
 * 
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                      LISTING SERVICE - CURATED ACCESS                     ║
 * ╠═══════════════════════════════════════════════════════════════════════════╣
 * ║  This contract provides a SAFE, CURATED way to interact with the          ║
 * ║  underlying LoanProtocol. Only whitelisted tokens can be used.            ║
 * ║                                                                           ║
 * ║  Benefits of using ListingService:                                        ║
 * ║  ✓ Token whitelist - only vetted, legitimate tokens accepted              ║
 * ║  ✓ Front-end integration with official website                            ║
 * ║  ✓ Customer support and dispute resolution                                ║
 * ║  ✓ Compliance with applicable regulations                                 ║
 * ║                                                                           ║
 * ║  The underlying LoanProtocol is permissionless and accepts ANY token.     ║
 * ║  Users who bypass this service assume all risk.                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 * 
 * FEE MODEL:
 * - Auction listing fee: 0.1% of collateral, paid in collateral token at auction creation
 * - Marketplace listing fee: Flat fee (e.g., $5) to list a position for sale, paid in payment token
 * - All fees go directly to treasury
 */
contract ListingService is 
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

    /// @notice Maximum auction listing fee cap in basis points
    uint256 public constant MAX_AUCTION_FEE_BPS = 100; // 1% max

    /// @notice Maximum marketplace listing fee (in USDC with 6 decimals)
    uint256 public constant MAX_MARKETPLACE_LISTING_FEE = 100_000_000; // $100 max

    /// @notice Maximum tokens per batch whitelist operation
    uint256 public constant MAX_BATCH_SIZE = 50;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice The LoanProtocol contract
    ILoanProtocol public loanProtocol;

    /// @notice Auction listing fee in basis points (10 = 0.10%)
    uint256 public auctionFeeBps;

    /// @notice Flat fee to list a position on marketplace (in payment token, e.g., USDC)
    /// @dev Default 0 (free listing). Can be set to e.g., 5_000_000 for $5 USDC
    uint256 public marketplaceListingFee;

    /// @notice Treasury address for fee collection
    address public treasury;

    /// @notice Whitelisted collateral tokens (curated list of safe tokens)
    mapping(address => bool) public collateralWhitelist;

    /// @notice Whitelisted loan tokens (curated list of stablecoins)
    mapping(address => bool) public loanTokenWhitelist;

    /// @notice Track which auctions were created through listing service
    mapping(uint256 => bool) public listedAuctions;

    /// @notice DEPRECATED - Auction fees now collected at creation, not finalization
    /// @dev Kept for storage layout compatibility on upgrades
    mapping(uint256 => bool) public auctionFeesCollected;

    /// @notice Accumulated marketplace fees per token (not yet withdrawn)
    /// @dev Auction fees go directly to treasury at creation; only marketplace fees accumulate here
    mapping(address => uint256) public accumulatedFees;

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @param auctionId Auction ID created in LoanProtocol
    /// @param borrower Address creating the auction
    /// @param collateralToken Whitelisted collateral token used
    /// @param collateralAmount Amount of collateral locked
    /// @param loanToken Whitelisted loan token requested
    /// @param loanAmount Principal amount requested
    /// @param fee Auction listing fee collected (in collateral token)
    /// @param bidStep Minimum bid improvement for this auction
    event ListedAuctionCreated(
        // auction identifier
        uint256 indexed auctionId,
        // auction borrower
        address indexed borrower,
        // whitelisted collateral token
        address collateralToken,
        // collateral locked in auction
        uint256 collateralAmount,
        // whitelisted loan token
        address loanToken,
        // principal requested
        uint256 loanAmount,
        // listing fee collected
        uint256 fee,
        // minimum bid improvement
        uint256 bidStep
    );

    /// @param auctionId Auction whose fee was collected
    /// @param token Fee token (collateral token)
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

    event AuctionFeeUpdated(uint256 oldFee, uint256 newFee);
    /// @notice Emitted when admin updates the marketplace listing fee
    event MarketplaceListingFeeUpdated(uint256 oldFee, uint256 newFee);
    /// @notice Emitted when admin updates the treasury address
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    /// @notice Emitted when a collateral token is added/removed from whitelist
    event CollateralTokenUpdated(address indexed token, bool whitelisted);
    /// @notice Emitted when a loan token is added/removed from whitelist
    event LoanTokenUpdated(address indexed token, bool whitelisted);

    // ============================================================================
    // ERRORS
    // ============================================================================

    /// @dev FeeTooHigh: Fee exceeds maximum allowed cap
    error FeeTooHigh();
    /// @dev ZeroAddress: Provided where a valid address is required
    error ZeroAddress();
    /// @dev InvalidToken: Token address is zero
    error InvalidToken();
    /// @dev TokenNotWhitelisted: Token not on the curated whitelist — use raw protocol instead
    error TokenNotWhitelisted();
    /// @dev InsufficientCollateral: User has insufficient collateral deposited in LoanProtocol
    error InsufficientCollateral();
    /// @dev NotListedAuction: Auction was not created through this ListingService
    error NotListedAuction();
    /// @dev FeeAlreadyCollected: Fee already collected for this auction
    error FeeAlreadyCollected();
    /// @dev AuctionNotFinalized: Auction has not yet been finalized
    error AuctionNotFinalized();
    /// @dev NoFeesToWithdraw: Zero accumulated fees for this token
    error NoFeesToWithdraw();
    /// @dev BatchTooLarge: Array exceeds MAX_BATCH_SIZE (50) — prevents gas limit issues
    error BatchTooLarge();
    /// @dev ArrayLengthMismatch: Input arrays have different lengths
    error ArrayLengthMismatch();

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier validToken(address token) {
        // Reject zero token address
        if (token == address(0)) revert InvalidToken();
        // Continue to the modified function body
        _;
    }

    // ============================================================================
    // INITIALIZER
    // ============================================================================

    /// @notice Initialize the listing service
    /// @param _loanProtocol LoanProtocol contract address
    /// @param _treasury Treasury address for fees
    /// @param _auctionFeeBps Initial auction fee in basis points (e.g., 10 = 0.1%)
    function initialize(
        address _loanProtocol,
        address _treasury,
        uint256 _auctionFeeBps
    ) external initializer {
        // Reject zero address
        if (_loanProtocol == address(0)) revert ZeroAddress();
        // Reject zero address
        if (_treasury == address(0)) revert ZeroAddress();
        // Fee exceeds maximum allowed cap
        if (_auctionFeeBps > MAX_AUCTION_FEE_BPS) revert FeeTooHigh();

        __Ownable_init(msg.sender);
        // Initialize pause mechanism as unpaused
        __Pausable_init();
        // Initialize reentrancy guard
        __ReentrancyGuard_init();

        loanProtocol = ILoanProtocol(_loanProtocol);
        // Update treasury address in storage
        treasury = _treasury;
        // Update the fee rate in storage
        auctionFeeBps = _auctionFeeBps;
        marketplaceListingFee = 0; // Default to free marketplace listings
    }

    // ============================================================================
    // ADMIN FUNCTIONS - TOKEN WHITELISTING
    // ============================================================================

    /// @notice Add or remove a collateral token from whitelist
    /// @dev Only whitelisted tokens can be used through this service
    /// @param token Token address
    /// @param whitelisted Whether to whitelist
    function setCollateralWhitelist(address token, bool whitelisted) 
        external 
        onlyOwner 
        validToken(token) 
    {
        // Update collateral whitelist mapping
        collateralWhitelist[token] = whitelisted;
        // Emit CollateralTokenUpdated for off-chain indexing
        emit CollateralTokenUpdated(token, whitelisted);
    }

    /// @notice Add or remove a loan token from whitelist
    /// @dev Only whitelisted stablecoins can be borrowed through this service
    /// @param token Token address (stablecoin)
    /// @param whitelisted Whether to whitelist
    function setLoanTokenWhitelist(address token, bool whitelisted) 
        external 
        onlyOwner 
        validToken(token) 
    {
        // Update loan token whitelist mapping
        loanTokenWhitelist[token] = whitelisted;
        // Emit LoanTokenUpdated for off-chain indexing
        emit LoanTokenUpdated(token, whitelisted);
    }

    /// @notice Batch whitelist multiple collateral tokens
    /// @param tokens Array of token addresses (max 50)
    /// @param whitelisted Whether to whitelist all
    function batchSetCollateralWhitelist(address[] calldata tokens, bool whitelisted) 
        external 
        onlyOwner 
    {
        // Array exceeds maximum batch size
        if (tokens.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            // Reject zero token address
            if (tokens[i] == address(0)) revert InvalidToken();
            // Update collateral whitelist mapping
            collateralWhitelist[tokens[i]] = whitelisted;
            // Emit CollateralTokenUpdated for off-chain indexing
            emit CollateralTokenUpdated(tokens[i], whitelisted);
        }
    }

    /// @notice Batch whitelist multiple loan tokens
    /// @param tokens Array of token addresses (max 50)
    /// @param whitelisted Whether to whitelist all
    function batchSetLoanTokenWhitelist(address[] calldata tokens, bool whitelisted) 
        external 
        onlyOwner 
    {
        // Array exceeds maximum batch size
        if (tokens.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            // Reject zero token address
            if (tokens[i] == address(0)) revert InvalidToken();
            // Update loan token whitelist mapping
            loanTokenWhitelist[tokens[i]] = whitelisted;
            // Emit LoanTokenUpdated for off-chain indexing
            emit LoanTokenUpdated(tokens[i], whitelisted);
        }
    }

    // ============================================================================
    // ADMIN FUNCTIONS - FEE MANAGEMENT
    // ============================================================================

    /// @notice Update auction listing fee percentage
    /// @param _feeBps New fee in basis points (max 1%)
    function setAuctionFee(uint256 _feeBps) external onlyOwner {
        // Fee exceeds maximum allowed cap
        if (_feeBps > MAX_AUCTION_FEE_BPS) revert FeeTooHigh();
        // Emit AuctionFeeUpdated for off-chain indexing
        emit AuctionFeeUpdated(auctionFeeBps, _feeBps);
        // Update the fee rate in storage
        auctionFeeBps = _feeBps;
    }

    /// @notice Update marketplace listing fee (flat fee in payment token)
    /// @param _fee New fee amount (e.g., 5_000_000 for $5 USDC, max $100)
    function setMarketplaceListingFee(uint256 _fee) external onlyOwner {
        // Fee exceeds maximum allowed cap
        if (_fee > MAX_MARKETPLACE_LISTING_FEE) revert FeeTooHigh();
        // Emit MarketplaceListingFeeUpdated for off-chain indexing
        emit MarketplaceListingFeeUpdated(marketplaceListingFee, _fee);
        // Update marketplace fee in storage
        marketplaceListingFee = _fee;
    }

    /// @notice Update treasury address
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) external onlyOwner {
        // Reject zero address
        if (_treasury == address(0)) revert ZeroAddress();
        // Emit TreasuryUpdated for off-chain indexing
        emit TreasuryUpdated(treasury, _treasury);
        // Update treasury address in storage
        treasury = _treasury;
    }

    /// @notice Pause the listing service
    function pause() external onlyOwner {
        // Activate emergency pause
        _pause();
    }

    /// @notice Unpause the listing service
    function unpause() external onlyOwner {
        // Deactivate emergency pause
        _unpause();
    }

    // ============================================================================
    // CORE FUNCTIONS - AUCTION CREATION
    // ============================================================================

    /**
     * @notice Create an auction through the listing service (with whitelist checks)
     * @dev User must have already deposited collateral directly to LoanProtocol.
     *      Auction listing fee (0.1% of collateral) is paid from user's wallet in collateral token.
     *      User must approve ListingService for the fee amount in collateral token.
     * @param collateralToken Token to use as collateral (must be whitelisted)
     * @param collateralAmount Amount of collateral for the auction (already deposited in protocol)
     * @param loanToken Token to borrow (must be whitelisted)
     * @param loanAmount Amount to borrow
     * @param maxRepayment Maximum repayment amount
     * @param loanDuration Loan duration in seconds
     * @param auctionDuration Auction duration in seconds
     * @param bidStep Minimum bid improvement for this auction (in loan token decimals)
     * @return auctionId The created auction ID
     */
    function createListedAuction(
        address collateralToken,
        uint256 collateralAmount,
        address loanToken,
        uint256 loanAmount,
        uint256 maxRepayment,
        uint256 loanDuration,
        uint256 auctionDuration,
        uint256 bidStep
    ) external whenNotPaused nonReentrant returns (uint256 auctionId) {
        // WHITELIST CHECKS - This is where the curation happens
        if (!collateralWhitelist[collateralToken]) revert TokenNotWhitelisted();
        // Only whitelisted tokens through ListingService
        if (!loanTokenWhitelist[loanToken]) revert TokenNotWhitelisted();

        // Verify user has sufficient collateral deposited in the protocol
        uint256 userBalance = loanProtocol.getCollateralBalance(msg.sender, collateralToken);
        // Verify user has deposited enough collateral in protocol
        if (userBalance < collateralAmount) revert InsufficientCollateral();

        // Calculate and collect auction listing fee (in collateral token from user's wallet)
        uint256 fee = (collateralAmount * auctionFeeBps) / 10000;
        // Only collect fee if non-zero (free listing when fee rate is 0)
        if (fee > 0) {
            // Transfer fee from borrower's wallet to treasury
            IERC20(collateralToken).safeTransferFrom(msg.sender, treasury, fee);
        }

        // Create the auction - full collateralAmount goes to the auction
        auctionId = loanProtocol.createAuctionFor(
            msg.sender,  // The borrower
            msg.sender,  // Collateral comes from borrower's deposited balance
            collateralToken,
            collateralAmount,
            loanToken,
            loanAmount,
            maxRepayment,
            loanDuration,
            auctionDuration,
            bidStep      // Pass through user's bid step choice
        );

        // Track this auction
        listedAuctions[auctionId] = true;

        emit ListedAuctionCreated(
            auctionId, 
            msg.sender, 
            collateralToken,
            collateralAmount,
            loanToken,
            loanAmount, 
            fee,
            bidStep
        );
    }

    /**
     * @notice Finalize a listed auction
     * @dev Anyone can call this after auction ends. Fee was already collected at creation.
     * @param auctionId The auction to finalize
     */

    // ============================================================================
    // CORE FUNCTIONS - MARKETPLACE LISTING WITH FEE
    // ============================================================================

    /**
     * @notice List a position on the marketplace with optional listing fee
     * @dev Seller must approve ListingService for the listing fee amount in payment token
     *      This is a wrapper around LoanProtocol.listPosition that collects a flat fee
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
            // Transfer fee from seller to treasury
            IERC20(paymentToken).safeTransferFrom(msg.sender, treasury, marketplaceListingFee);
            // Emit MarketplaceListingFeeCollected for off-chain indexing
            emit MarketplaceListingFeeCollected(loanId, paymentToken, marketplaceListingFee, msg.sender);
        }
        
        // List the position on the protocol on behalf of the seller
        // Note: Seller must have approved ListingService as an operator via
        // loanProtocol.setOperatorApproval(listingServiceAddress, true)
        loanProtocol.listPositionFor(loanId, msg.sender, positionType, paymentToken, askingPrice);
    }

    // ============================================================================
    // CORE FUNCTIONS - FEE WITHDRAWAL
    // ============================================================================

    /**
     * @notice Withdraw accumulated fees to treasury
     * @param token Token to withdraw
     */
    function withdrawFees(address token) external nonReentrant {
        // Read accumulated fee balance for this token
        uint256 amount = accumulatedFees[token];
        // No accumulated fees for this token
        if (amount == 0) revert NoFeesToWithdraw();

        accumulatedFees[token] = 0;
        
        IERC20(token).safeTransfer(treasury, amount);

        emit FeesWithdrawn(token, treasury, amount);
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /// @notice Calculate auction fee for a given loan amount
    /// @param loanAmount Principal amount
    /// @return fee The fee amount
    function calculateAuctionFee(uint256 loanAmount) external view returns (uint256 fee) {
        // Calculate: principal × fee rate / 10000
        return (loanAmount * auctionFeeBps) / 10000;
    }

    /// @notice Get the marketplace listing fee
    /// @return fee The flat listing fee amount (in payment token decimals)
    function getMarketplaceListingFee() external view returns (uint256 fee) {
        // Return current flat listing fee
        return marketplaceListingFee;
    }

    /// @notice Check if an auction was created through listing service
    /// @param auctionId The auction ID
    /// @return listed True if created through this service
    function isListedAuction(uint256 auctionId) external view returns (bool listed) {
        // Return whether auction was created via ListingService
        return listedAuctions[auctionId];
    }

    /// @notice Get accumulated fees for a token
    /// @param token Token address
    /// @return amount Accumulated fee amount
    function getAccumulatedFees(address token) external view returns (uint256 amount) {
        // Return accumulated fee balance for this token
        return accumulatedFees[token];
    }

    /// @notice Check if a token is whitelisted as collateral
    /// @param token Token address
    /// @return whitelisted True if whitelisted
    function isCollateralWhitelisted(address token) external view returns (bool whitelisted) {
        // Return whitelist status for collateral token
        return collateralWhitelist[token];
    }

    /// @notice Check if a token is whitelisted as loan token
    /// @param token Token address
    /// @return whitelisted True if whitelisted
    function isLoanTokenWhitelisted(address token) external view returns (bool whitelisted) {
        // Return whitelist status for loan token
        return loanTokenWhitelist[token];
    }

    /// @notice Get current fee configuration
    /// @return auctionFeeBps_ Auction listing fee in basis points
    /// @return marketplaceListingFee_ Flat marketplace listing fee
    function getFeeConfiguration() external view returns (uint256 auctionFeeBps_, uint256 marketplaceListingFee_) {
        // Return current flat listing fee
        return (auctionFeeBps, marketplaceListingFee);
    }
}
