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

/// @dev Interface for the underlying permissionless LoanProtocol contract
import "./interfaces/ILoanProtocol.sol";

/**
 * @title ListingService
 * @author Bitcoin Yield Curve
 * @notice Commercial listing service that provides curated token whitelisting
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
 */
contract ListingService is
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

    /// @notice Maximum tokens per batch whitelist operation
    uint256 public constant MAX_BATCH_SIZE = 50;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice The LoanProtocol contract
    ILoanProtocol public loanProtocol;

    /// @notice Whitelisted collateral tokens (curated list of safe tokens)
    mapping(address => bool) public collateralWhitelist;

    /// @notice Whitelisted loan tokens (curated list of stablecoins)
    mapping(address => bool) public loanTokenWhitelist;

    /// @notice Per-loan-token minimum bid step (in loan token base units).
    /// @dev Set at whitelist time. Required to be > 0 whenever a token is whitelisted.
    ///      A user calling createListedAuction with bidStep == 0 substitutes this value;
    ///      a user calling with bidStep > 0 must meet or exceed this value, otherwise
    ///      the call reverts with BidStepBelowTokenMinimum. Resolves Sherlock #15: a single
    ///      MIN_BID_STEP at the protocol layer is economically meaningless across tokens
    ///      with vastly different prices and decimals (e.g. WBTC 8d ~$70k vs DAI 18d ~$1).
    mapping(address => uint256) public loanTokenMinBidSteps;

    /// @notice Track which auctions were created through listing service
    mapping(uint256 => bool) public listedAuctions;

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @param auctionId Auction ID created in LoanProtocol
    /// @param borrower Address creating the auction
    /// @param collateralToken Whitelisted collateral token used
    /// @param collateralAmount Amount of collateral locked
    /// @param loanToken Whitelisted loan token requested
    /// @param loanAmount Principal amount requested
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
        // minimum bid improvement
        uint256 bidStep
    );

    /// @notice Emitted when a collateral token is added/removed from whitelist
    event CollateralTokenUpdated(address indexed token, bool whitelisted);
    /// @notice Emitted when a loan token is added/removed from whitelist
    event LoanTokenUpdated(address indexed token, bool whitelisted);

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
    /// @dev TokenNotWhitelisted: Token not on the curated whitelist — use raw protocol instead
    error TokenNotWhitelisted();
    /// @dev InsufficientCollateral: User has insufficient collateral deposited in LoanProtocol
    error InsufficientCollateral();
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
    function initialize(address _loanProtocol) external initializer {
        // Reject zero address
        if (_loanProtocol == address(0)) revert ZeroAddress();

        __Ownable_init(msg.sender);
        // Initialize pause mechanism as unpaused
        __Pausable_init();
        // Initialize reentrancy guard
        __ReentrancyGuard_init();

        loanProtocol = ILoanProtocol(_loanProtocol);
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

    /// @notice Add or remove a loan token from whitelist with its minimum bid step
    /// @dev Only whitelisted stablecoins can be borrowed through this service.
    ///      When whitelisting (whitelisted=true), minBidStep must be > 0. This forces the
    ///      admin to set a token-specific economic floor that reflects the token's decimals
    ///      and price (resolves Sherlock #15). When unwhitelisting (whitelisted=false),
    ///      minBidStep is ignored and the stored value is cleared.
    /// @param token Token address (stablecoin)
    /// @param whitelisted Whether to whitelist
    /// @param minBidStep Minimum bid step in loan token base units (required > 0 if whitelisting)
    function setLoanTokenWhitelist(address token, bool whitelisted, uint256 minBidStep)
        external
        onlyOwner
        validToken(token)
    {
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

    /// @notice Batch whitelist multiple loan tokens with per-token minimum bid steps
    /// @dev When whitelisting (whitelisted=true), every minBidStep must be > 0.
    ///      When unwhitelisting, minBidSteps is still required as a parallel array but
    ///      its values are ignored and the stored values are cleared.
    /// @param tokens Array of token addresses (max 50)
    /// @param minBidSteps Parallel array of per-token minimum bid steps
    /// @param whitelisted Whether to whitelist all (or remove all from whitelist)
    function batchSetLoanTokenWhitelist(
        address[] calldata tokens,
        uint256[] calldata minBidSteps,
        bool whitelisted
    )
        external
        onlyOwner
    {
        // Array exceeds maximum batch size
        if (tokens.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        // Parallel arrays must have matching lengths
        if (tokens.length != minBidSteps.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < tokens.length; i++) {
            // Reject zero token address
            if (tokens[i] == address(0)) revert InvalidToken();
            if (whitelisted) {
                // Reject whitelist with zero min bid step
                if (minBidSteps[i] == 0) revert MinBidStepRequired();
                loanTokenWhitelist[tokens[i]] = true;
                loanTokenMinBidSteps[tokens[i]] = minBidSteps[i];
            } else {
                // Unwhitelist clears both the flag and the configured floor
                loanTokenWhitelist[tokens[i]] = false;
                loanTokenMinBidSteps[tokens[i]] = 0;
            }
            // Emit LoanTokenUpdated for off-chain indexing
            emit LoanTokenUpdated(tokens[i], whitelisted);
        }
    }

    // ============================================================================
    // ADMIN FUNCTIONS - PAUSE
    // ============================================================================

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
            effectiveBidStep      // Token-specific minimum enforced above
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
            effectiveBidStep
        );
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /// @notice Check if an auction was created through listing service
    /// @param auctionId The auction ID
    /// @return listed True if created through this service
    function isListedAuction(uint256 auctionId) external view returns (bool listed) {
        // Return whether auction was created via ListingService
        return listedAuctions[auctionId];
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
}
