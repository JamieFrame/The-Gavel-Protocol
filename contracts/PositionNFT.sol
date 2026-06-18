// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
/// @dev ERC-721 extension for on-chain enumeration of all tokens
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
/// @dev Owner-restricted access control for admin functions
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
/// @dev OpenZeppelin upgradeable proxy initialization (replaces constructor)
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
/// @dev Utility for uint256-to-string and address-to-hex conversion (SVG rendering)
import "@openzeppelin/contracts/utils/Strings.sol";
/// @dev Base64 encoding for on-chain data URI generation
import "@openzeppelin/contracts/utils/Base64.sol";

import "./interfaces/IPositionNFT.sol";

/**
 * @title PositionNFT
 * @author Bitcoin Yield Curve
 * @notice ERC-721 tokens representing loan positions (borrower/lender)
 * @dev Token IDs encode both loan ID and position type:
 *      - Borrower: loanId * 2
 *      - Lender: loanId * 2 + 1
 */
contract PositionNFT is 
        // Upgradeable proxy pattern — replaces constructor with initialize()
    Initializable,
        // Core ERC-721 token functionality (minting, burning, transfers)
    ERC721Upgradeable, 
        // On-chain enumeration: totalSupply(), tokenOfOwnerByIndex()
    ERC721EnumerableUpgradeable,
        // Owner-only admin functions (setBaseURI)
    OwnableUpgradeable,
        // Interface for LoanProtocol integration (mint, burn, transfer)
    IPositionNFT 
{
    /// @dev Enable .toString() on uint256 for SVG text rendering
    using Strings for uint256;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice The LoanProtocol contract authorized to mint/burn
    address public loanProtocol;

    /// @notice Base URI for metadata (optional, we use on-chain metadata)
    string public baseURI;

    /// @notice Loan data for metadata generation
    struct LoanMetadata {
        /// @dev ERC-20 token locked as collateral
        address collateralToken;
        /// @dev Amount of collateral token locked
        uint256 collateralAmount;
        /// @dev ERC-20 token borrowed (e.g., USDC)
        address loanToken;
        /// @dev Principal amount borrowed
        uint256 loanAmount;
        /// @dev Total amount due at maturity (principal + interest)
        uint256 repaymentAmount;
        /// @dev Unix timestamp when loan is due for repayment
        uint256 maturityTimestamp;
        /// @dev Flag to distinguish initialized metadata from empty defaults
        bool exists;
    }

    /// @notice Metadata for each loan (populated on mint)
    mapping(uint256 => LoanMetadata) public loanMetadata;

    // ============================================================================
    // ERRORS
    // ============================================================================

    error OnlyLoanProtocol();
    /// @dev TokenDoesNotExist: Token ID has not been minted or has been burned
    error TokenDoesNotExist();
    /// @dev ZeroAddress: Provided where a valid address is required
    error ZeroAddress();

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier onlyLoanProtocol() {
        // Only the authorized protocol contract can call this function
        if (msg.sender != loanProtocol) revert OnlyLoanProtocol();
        // Continue to the modified function body
        _;
    }

    // ============================================================================
    // INITIALIZER
    // ============================================================================

    /// @notice Initialize the NFT contract
    /// @param _loanProtocol Address of the LoanProtocol contract
    function initialize(address _loanProtocol) external initializer {
        // Reject zero address to prevent permanently locked state
        if (_loanProtocol == address(0)) revert ZeroAddress();

        __ERC721_init("Bitcoin Yield Curve Position", "BYCP");
        // Initialize enumerable extension for on-chain token listing
        __ERC721Enumerable_init();
        // Set deployer as initial owner
        __Ownable_init(msg.sender);

        loanProtocol = _loanProtocol;
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /// @notice Set base URI for external metadata
    /// @param _baseURI New base URI
    function setBaseURI(string calldata _baseURI) external onlyOwner {
        // Update base URI for external metadata resolution
        baseURI = _baseURI;
    }

    // ============================================================================
    // PROTOCOL FUNCTIONS (HIGH SECURITY)
    // ============================================================================

    /// @notice Mint a borrower position NFT
    /// @param loanId The loan ID
    /// @param to Recipient address
    /// @return tokenId The minted token ID
    function mintBorrowerPosition(uint256 loanId, address to) 
        external 
        // Restrict to authorized protocol contract
        onlyLoanProtocol 
        returns (uint256 tokenId) 
    {
        // Derive borrower token ID: loanId * 2 (even)
        tokenId = getBorrowerTokenId(loanId);
        // Mint new position NFT to recipient (reverts if receiver rejects)
        _safeMint(to, tokenId);
    }

    /// @notice Mint a lender position NFT
    /// @param loanId The loan ID
    /// @param to Recipient address
    /// @return tokenId The minted token ID
    function mintLenderPosition(uint256 loanId, address to) 
        external 
        // Restrict to authorized protocol contract
        onlyLoanProtocol 
        returns (uint256 tokenId) 
    {
        // Derive lender token ID: loanId * 2 + 1 (odd)
        tokenId = getLenderTokenId(loanId);
        // Mint new position NFT to recipient (reverts if receiver rejects)
        _safeMint(to, tokenId);
    }

    /// @notice Store loan metadata for NFT display
    /// @param loanId The loan ID
    /// @param collateralToken Collateral token address
    /// @param collateralAmount Amount of collateral
    /// @param loanToken Loan token address
    /// @param loanAmount Principal amount
    /// @param repaymentAmount Total repayment amount
    /// @param maturityTimestamp When loan matures
    function setLoanMetadata(
        uint256 loanId,
        address collateralToken,
        uint256 collateralAmount,
        address loanToken,
        uint256 loanAmount,
        uint256 repaymentAmount,
        // Unix timestamp when loan matures
        uint256 maturityTimestamp
    // Only callable by the authorized protocol contract
    ) external onlyLoanProtocol {
        // Store loan data on-chain for position NFT SVG rendering
        loanMetadata[loanId] = LoanMetadata({
            collateralToken: collateralToken,
            collateralAmount: collateralAmount,
            loanToken: loanToken,
            loanAmount: loanAmount,
            repaymentAmount: repaymentAmount,
            maturityTimestamp: maturityTimestamp,
            // // Mark metadata as initialized
            exists: true
        });
    }

    /// @notice Burn a position NFT
    /// @param tokenId Token to burn
    function burn(uint256 tokenId) external onlyLoanProtocol {
        // Destroy position NFT — loan has been resolved (repaid or defaulted)
        _burn(tokenId);
    }

    /// @notice Protocol-authorized transfer (bypasses approval)
    /// @param tokenId Token to transfer
    /// @param from Current owner
    /// @param to New owner
    function protocolTransfer(uint256 tokenId, address from, address to) 
        external 
        // Restrict to authorized protocol contract
        onlyLoanProtocol 
    {
        // Direct transfer bypassing approval (protocol-authorized only)
        _transfer(from, to, tokenId);
    }

    // ============================================================================
    // TOKEN ID ENCODING/DECODING
    // ============================================================================

    /// @notice Get borrower token ID from loan ID
    /// @dev Borrower tokens are even: loanId * 2
    function getBorrowerTokenId(uint256 loanId) public pure returns (uint256) {
        // Even IDs: borrower positions (0, 2, 4, 6, ...)
        return loanId * 2;
    }

    /// @notice Get lender token ID from loan ID
    /// @dev Lender tokens are odd: loanId * 2 + 1
    function getLenderTokenId(uint256 loanId) public pure returns (uint256) {
        // Odd IDs: lender positions (1, 3, 5, 7, ...)
        return loanId * 2 + 1;
    }

    /// @notice Get loan ID from token ID
    function getLoanId(uint256 tokenId) public pure returns (uint256) {
        // Reverse the encoding: integer division strips the position bit
        return tokenId / 2;
    }

    /// @notice Get position type from token ID
    function getPositionType(uint256 tokenId) public pure returns (PositionType) {
        // Even = borrower, odd = lender (lowest bit encodes position type)
        return tokenId % 2 == 0 ? PositionType.BORROWER : PositionType.LENDER;
    }

    /// @notice Check if token exists
    function exists(uint256 tokenId) public view returns (bool) {
        // Non-zero owner means token exists (minted and not burned)
        return _ownerOf(tokenId) != address(0);
    }

    // ============================================================================
    // METADATA (On-Chain SVG)
    // ============================================================================

    /// @notice Generate token URI with on-chain SVG
    /// @param tokenId Token to get URI for
    function tokenURI(uint256 tokenId) 
        public 
        view 
        // Override base ERC-721 tokenURI implementation
        override(ERC721Upgradeable) 
        returns (string memory) 
    {
        // Token must exist (minted and not yet burned)
        if (!exists(tokenId)) revert TokenDoesNotExist();

        uint256 loanId = getLoanId(tokenId);
        // Determine if this is a borrower or lender position
        PositionType posType = getPositionType(tokenId);
        // Load stored loan data for SVG rendering
        LoanMetadata memory meta = loanMetadata[loanId];

        string memory positionName = posType == PositionType.BORROWER ? "Borrower" : "Lender";
        // Set color based on position type (orange=borrower, green=lender)
        string memory positionColor = posType == PositionType.BORROWER ? "#FF6B35" : "#2ECC71";

        // Build SVG
        string memory svg = _buildSVG(loanId, positionName, positionColor, meta);

        // Build JSON metadata
        string memory json = string(abi.encodePacked(
            '{"name":"Bitcoin Yield Curve - ', positionName, ' Position #', loanId.toString(), '",',
            '"description":"', positionName, ' position for loan #', loanId.toString(), ' on Bitcoin Yield Curve Protocol",',
            // Base64-encode SVG for inline data URI in JSON metadata
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
            '"attributes":[',
                '{"trait_type":"Position Type","value":"', positionName, '"},',
                '{"trait_type":"Loan ID","value":', loanId.toString(), '},',
                '{"trait_type":"Principal","value":', meta.loanAmount.toString(), '},',
                '{"trait_type":"Repayment","value":', meta.repaymentAmount.toString(), '},',
                '{"trait_type":"Collateral Amount","value":', meta.collateralAmount.toString(), '},',
                '{"trait_type":"Maturity","value":', meta.maturityTimestamp.toString(), '}',
            // Close JSON attributes array and object
            ']}'
        ));

        return string(abi.encodePacked(
            // Return fully on-chain data URI — no IPFS or server dependency
            "data:application/json;base64,",
            // Base64-encode JSON for on-chain data URI (no external server needed)
            Base64.encode(bytes(json))
        ));
    }

    /// @notice Build SVG for position NFT
    function _buildSVG(
        uint256 loanId,
        string memory positionName,
        string memory color,
        // Stored loan data for rendering
        LoanMetadata memory meta
    ) internal pure returns (string memory) {
        // Calculate APR for display (rough estimate)
        uint256 interest = meta.repaymentAmount > meta.loanAmount 
            // Interest = repayment minus principal
            ? meta.repaymentAmount - meta.loanAmount 
            // No interest if repayment <= principal (shouldn't happen normally)
            : 0;
        
        return string(abi.encodePacked(
            // === SVG CANVAS: 400x500 dark gradient card with rounded corners ===
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 500">',
            // Define gradient fills for card background
            '<defs>',
                '<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
                    '<stop offset="0%" style="stop-color:#1a1a2e"/>',
                    '<stop offset="100%" style="stop-color:#16213e"/>',
                '</linearGradient>',
            '</defs>',
            // Card background with dark gradient and rounded corners
            '<rect width="400" height="500" fill="url(#bg)" rx="20"/>',
            // Protocol title at top of card
            '<text x="200" y="50" fill="#fff" font-family="Arial" font-size="24" text-anchor="middle" font-weight="bold">Bitcoin Yield Curve</text>',
            // Subtitle below protocol name
            '<text x="200" y="80" fill="#888" font-family="Arial" font-size="14" text-anchor="middle">Loan Position NFT</text>',
            // Position type colored banner (orange=borrower, green=lender)
            '<rect x="50" y="100" width="300" height="80" fill="', color, '" rx="10" opacity="0.2"/>',
            '<text x="200" y="135" fill="', color, '" font-family="Arial" font-size="28" text-anchor="middle" font-weight="bold">', positionName, '</text>',
            '<text x="200" y="165" fill="#fff" font-family="Arial" font-size="18" text-anchor="middle">Position #', loanId.toString(), '</text>',
            // Horizontal divider between banner and loan details
            '<line x1="50" y1="200" x2="350" y2="200" stroke="#333" stroke-width="1"/>',
            // Loan detail rows: label on left, value on right
            '<text x="70" y="240" fill="#888" font-family="Arial" font-size="12">PRINCIPAL</text>',
            '<text x="330" y="240" fill="#fff" font-family="Arial" font-size="16" text-anchor="end">', _formatAmount(meta.loanAmount), '</text>',
            '<text x="70" y="280" fill="#888" font-family="Arial" font-size="12">REPAYMENT</text>',
            '<text x="330" y="280" fill="#fff" font-family="Arial" font-size="16" text-anchor="end">', _formatAmount(meta.repaymentAmount), '</text>',
            '<text x="70" y="320" fill="#888" font-family="Arial" font-size="12">INTEREST</text>',
            '<text x="330" y="320" fill="#2ECC71" font-family="Arial" font-size="16" text-anchor="end">', _formatAmount(interest), '</text>',
            // Collateral amount row
            '<text x="70" y="360" fill="#888" font-family="Arial" font-size="12">COLLATERAL</text>',
            '<text x="330" y="360" fill="#fff" font-family="Arial" font-size="16" text-anchor="end">', _formatAmount(meta.collateralAmount), '</text>',
            // Bitcoin Yield Curve branded footer
            '<rect x="50" y="400" width="300" height="60" fill="#F7931A" rx="10" opacity="0.1"/>',
            '<text x="200" y="425" fill="#F7931A" font-family="Arial" font-size="12" text-anchor="middle">BITCOIN YIELD CURVE</text>',
            '<text x="200" y="445" fill="#888" font-family="Arial" font-size="10" text-anchor="middle">Oracle-Free Lending Protocol</text>',
            // Close SVG element
            '</svg>'
        ));
    }

    /// @notice Format amount for display (simplified)
    function _formatAmount(uint256 amount) internal pure returns (string memory) {
        // Short-circuit for zero amounts
        if (amount == 0) return "0";
        
        // For simplicity, just return the raw number
        // In production, would want proper decimal formatting
        return amount.toString();
    }

    // ============================================================================
    // REQUIRED OVERRIDES
    // ============================================================================

    /// @dev Required override: resolves diamond inheritance between ERC721 and ERC721Enumerable
    function _update(address to, uint256 tokenId, address auth)
        internal
        // Required override — resolves diamond inheritance between ERC-721 bases
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        // Delegate to parent implementation (resolves diamond inheritance)
        return super._update(to, tokenId, auth);
    }

    /// @dev Required override: resolves diamond inheritance for balance tracking
    function _increaseBalance(address account, uint128 value)
        internal
        // Required override — resolves diamond inheritance between ERC-721 bases
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        // Delegate to parent implementation (resolves diamond inheritance)
        super._increaseBalance(account, value);
    }

    /// @dev Required override: aggregates ERC-165 interface support from all bases
    function supportsInterface(bytes4 interfaceId)
        public
        view
        // Required override — resolves ERC-165 interface detection across bases
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, IERC165)
        returns (bool)
    {
        // Delegate to parent implementation (resolves diamond inheritance)
        return super.supportsInterface(interfaceId);
    }
}
