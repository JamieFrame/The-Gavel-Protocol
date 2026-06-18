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
/// @dev Standard ERC-721 interface for collateral NFT interaction
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
/// @dev ERC-721 metadata extension â€” used to read collateral NFT name/image
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "./interfaces/INFTPositionNFT.sol";

/**
 * @title NFTPositionNFT
 * @author Bitcoin Yield Curve
 * @notice ERC-721 tokens representing loan positions backed by NFT collateral
 * @dev Token IDs encode both loan ID and position type:
 *      - Borrower: loanId * 2
 *      - Lender: loanId * 2 + 1
 * 
 * SPECIAL FEATURE: Position NFTs display the underlying collateral NFT's image
 * in their metadata, allowing lenders to see exactly what backs their position.
 */
contract NFTPositionNFT is 
        // Upgradeable proxy pattern â€” replaces constructor with initialize()
    Initializable,
        // Core ERC-721 token functionality (minting, burning, transfers)
    ERC721Upgradeable, 
        // On-chain enumeration: totalSupply(), tokenOfOwnerByIndex()
    ERC721EnumerableUpgradeable,
        // Owner-only admin functions (setBaseURI)
    OwnableUpgradeable,
        // Interface for NFTLoanProtocol integration (mint, burn, transfer)
    INFTPositionNFT 
{
    /// @dev Enable .toString() on uint256 for SVG text rendering
    using Strings for uint256;
    /// @dev Enable .toHexString() on address for SVG text rendering
    using Strings for address;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice The NFTLoanProtocol contract authorized to mint/burn
    address public loanProtocol;

    /// @notice Base URI for metadata (optional, we use on-chain metadata)
    string public baseURI;

    /// @notice Loan data for metadata generation
    struct LoanMetadata {
        address collateralNFT;      // NFT collection address
        uint256 collateralTokenId;  // NFT token ID
        address loanToken;          // Loan token address
        uint256 loanAmount;         // Principal
        uint256 repaymentAmount;    // Total repayment
        uint256 maturityTimestamp;  // When loan is due
        /// @dev Flag to distinguish initialized metadata from empty defaults
        bool exists;
    }

    /// @notice Metadata for each loan (populated on mint)
    mapping(uint256 => LoanMetadata) public loanMetadata;

    /// @notice Cached collateral NFT images (optional - for gas efficiency)
    mapping(uint256 => string) public cachedCollateralImages;

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
    /// @param _loanProtocol Address of the NFTLoanProtocol contract
    function initialize(address _loanProtocol) external initializer {
        // Reject zero address to prevent permanently locked state
        if (_loanProtocol == address(0)) revert ZeroAddress();

        __ERC721_init("Bitcoin Yield Curve NFT Position", "BYCNP");
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

    /// @notice Cache collateral NFT image for gas efficiency
    /// @dev Can be called by anyone to pre-cache image data
    /// @param loanId The loan ID
    /// @param imageData The image data URL or IPFS hash
    function cacheCollateralImage(uint256 loanId, string calldata imageData) external {
        // Store pre-cached image data for gas-efficient metadata reads
        cachedCollateralImages[loanId] = imageData;
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
    /// @param collateralNFT Collateral NFT contract address
    /// @param collateralTokenId Collateral NFT token ID
    /// @param loanToken Loan token address
    /// @param loanAmount Principal amount
    /// @param repaymentAmount Total repayment amount
    /// @param maturityTimestamp When loan matures
    function setLoanMetadata(
        uint256 loanId,
        address collateralNFT,
        uint256 collateralTokenId,
        address loanToken,
        uint256 loanAmount,
        uint256 repaymentAmount,
        // Unix timestamp when loan matures
        uint256 maturityTimestamp
    // Only callable by the authorized protocol contract
    ) external onlyLoanProtocol {
        // Store loan data on-chain for position NFT SVG rendering
        loanMetadata[loanId] = LoanMetadata({
            collateralNFT: collateralNFT,
            collateralTokenId: collateralTokenId,
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
        // Destroy position NFT â€” loan has been resolved (repaid or defaulted)
        _burn(tokenId);
    }

    /// @notice Protocol-authorized transfer (bypasses approval)
    /// @param from Current owner
    /// @param to New owner
    /// @param tokenId Token to transfer
    function transferFrom(address from, address to, uint256 tokenId) 
        public 
        // Override transferFrom to allow protocol bypass of approval checks
        override(ERC721Upgradeable, IERC721) 
    {
        // Allow protocol to transfer without approval
        if (msg.sender == loanProtocol) {
            // Direct transfer bypassing approval (protocol-authorized only)
            _transfer(from, to, tokenId);
        // Non-protocol caller: require standard ERC-721 approval
        } else {
            // Standard ERC-721 transfer with approval check for non-protocol callers
            super.transferFrom(from, to, tokenId);
        }
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
    // METADATA (On-Chain SVG with Collateral NFT Display)
    // ============================================================================

    /// @notice Generate token URI with on-chain SVG featuring collateral NFT
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

        // Try to get collateral NFT info
        string memory collateralName = _getCollateralName(meta.collateralNFT, meta.collateralTokenId);
        // Fetch collateral NFT image (checks cache first, then tokenURI)
        string memory collateralImage = _getCollateralImage(loanId, meta.collateralNFT, meta.collateralTokenId);

        // Build SVG
        string memory svg = _buildSVG(
            loanId, 
            positionName, 
            positionColor, 
            meta,
            collateralName,
            // Collateral NFT image (from cache or tokenURI)
            collateralImage
        );

        // Build JSON metadata
        string memory json = _buildJSON(
            loanId,
            positionName,
            svg,
            meta,
            // Collateral NFT collection name + token ID
            collateralName
        );

        return string(abi.encodePacked(
            // Return fully on-chain data URI â€” no IPFS or server dependency
            "data:application/json;base64,",
            // Base64-encode JSON for on-chain data URI (no external server needed)
            Base64.encode(bytes(json))
        ));
    }

    /// @notice Get collateral NFT name
    function _getCollateralName(address nftContract, uint256 tokenId) internal view returns (string memory) {
        // Fallback for uninitialized metadata
        if (nftContract == address(0)) return "Unknown NFT";
        
        try IERC721Metadata(nftContract).name() returns (string memory name) {
            // Concatenate collection name with token ID
            return string(abi.encodePacked(name, " #", tokenId.toString()));
        // Handle revert (contract may not support ERC-721 metadata)
        } catch {
            // Fallback: use generic "NFT #" prefix if name() reverts
            return string(abi.encodePacked("NFT #", tokenId.toString()));
        }
    }

    /// @notice Get collateral NFT image
    function _getCollateralImage(
        uint256 loanId, 
        address nftContract, 
        // NFT token ID to fetch image for
        uint256 tokenId
    ) internal view returns (string memory) {
        // Check cache first
        if (bytes(cachedCollateralImages[loanId]).length > 0) {
            // Return pre-cached image data
            return cachedCollateralImages[loanId];
        }

        if (nftContract == address(0)) return "";

        // Try to get image from tokenURI
        try IERC721Metadata(nftContract).tokenURI(tokenId) returns (string memory uri) {
            // Note: In practice, you'd need to parse the JSON and extract the image
            // For on-chain display, we'll use a placeholder or the URI itself
            return uri;
        // Handle revert (contract may not support ERC-721 metadata)
        } catch {
            // Fallback: no image available
            return "";
        }
    }

    /// @notice Build SVG for position NFT with collateral display
    function _buildSVG(
        uint256 loanId,
        string memory positionName,
        string memory color,
        LoanMetadata memory meta,
        string memory collateralName,
        // Image param reserved for future on-chain collateral NFT display
        string memory /* collateralImage - reserved for future use */
    ) internal pure returns (string memory) {
        // Calculate interest: repayment minus principal (0 if no interest)
        uint256 interest = meta.repaymentAmount > meta.loanAmount 
            // Interest = repayment minus principal
            ? meta.repaymentAmount - meta.loanAmount 
            // No interest if repayment <= principal (shouldn't happen normally)
            : 0;

        return string(abi.encodePacked(
            // === SVG CANVAS: 400x550 dark gradient card with NFT collateral display ===
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 550">',
            // Define gradient fills for card background
            '<defs>',
                '<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
                    // Dark navy to dark blue gradient (card background)
                    '<stop offset="0%" style="stop-color:#1a1a2e"/>',
                    // Gradient endpoint color
                    '<stop offset="100%" style="stop-color:#16213e"/>',
                '</linearGradient>',
                // Bitcoin-orange gradient for NFT collateral frame
                '<linearGradient id="nftFrame" x1="0%" y1="0%" x2="100%" y2="100%">',
                    // Bitcoin orange gradient for NFT frame accent
                    '<stop offset="0%" style="stop-color:#F7931A"/>',
                    // Gradient endpoint (darker orange)
                    '<stop offset="100%" style="stop-color:#E8820C"/>',
                '</linearGradient>',
            // End gradient definitions
            '</defs>',
            // Card background with dark gradient and rounded corners
            '<rect width="400" height="550" fill="url(#bg)" rx="20"/>',
            
            // Header
            // Protocol title at top of card
            '<text x="200" y="40" fill="#fff" font-family="Arial" font-size="20" text-anchor="middle" font-weight="bold">Bitcoin Yield Curve</text>',
            // Subtitle: NFT-Collateralized Loan
            '<text x="200" y="60" fill="#888" font-family="Arial" font-size="12" text-anchor="middle">NFT-Collateralized Loan</text>',
            
            // Position type banner
            // Position type colored banner (orange=borrower, green=lender)
            '<rect x="50" y="75" width="300" height="50" fill="', color, '" rx="10" opacity="0.2"/>',
            // Display position type and loan number in banner
            '<text x="200" y="105" fill="', color, '" font-family="Arial" font-size="22" text-anchor="middle" font-weight="bold">', positionName, ' Position #', loanId.toString(), '</text>',
            
            // NFT Collateral display area
            // NFT Collateral display section with Bitcoin-orange frame
            '<rect x="50" y="140" width="300" height="120" fill="url(#nftFrame)" rx="10" opacity="0.1"/>',
            // Dark inner panel for collateral NFT info
            '<rect x="60" y="150" width="280" height="100" fill="#0d0d1a" rx="8"/>',
            // "COLLATERAL NFT" label in Bitcoin orange
            '<text x="200" y="190" fill="#F7931A" font-family="Arial" font-size="11" text-anchor="middle">COLLATERAL NFT</text>',
            // Display collateral NFT name (truncated to 30 chars, XML-escaped)
            '<text x="200" y="215" fill="#fff" font-family="Arial" font-size="14" text-anchor="middle" font-weight="bold">', _escapeXML(_truncateString(collateralName, 30)), '</text>',
            // Display shortened collateral contract address (0xABCD...EFGH)
            '<text x="200" y="235" fill="#666" font-family="Arial" font-size="10" text-anchor="middle">', _addressToShortString(meta.collateralNFT), '</text>',
            
            // Divider
            // Horizontal divider between collateral display and loan details
            '<line x1="50" y1="275" x2="350" y2="275" stroke="#333" stroke-width="1"/>',
            
            // Loan details
            // Loan detail rows: label on left, value on right
            '<text x="70" y="305" fill="#888" font-family="Arial" font-size="11">PRINCIPAL</text>',
            // Principal value (right-aligned)
            '<text x="330" y="305" fill="#fff" font-family="Arial" font-size="14" text-anchor="end">', _formatAmount(meta.loanAmount), '</text>',
            
            // Repayment amount row
            '<text x="70" y="335" fill="#888" font-family="Arial" font-size="11">REPAYMENT</text>',
            // Repayment value (right-aligned)
            '<text x="330" y="335" fill="#fff" font-family="Arial" font-size="14" text-anchor="end">', _formatAmount(meta.repaymentAmount), '</text>',
            
            // Interest amount row (in green)
            '<text x="70" y="365" fill="#888" font-family="Arial" font-size="11">INTEREST</text>',
            // Interest value in green (right-aligned)
            '<text x="330" y="365" fill="#2ECC71" font-family="Arial" font-size="14" text-anchor="end">', _formatAmount(interest), '</text>',
            
            // Maturity timestamp row
            '<text x="70" y="395" fill="#888" font-family="Arial" font-size="11">MATURITY</text>',
            // Maturity timestamp value (right-aligned)
            '<text x="330" y="395" fill="#fff" font-family="Arial" font-size="14" text-anchor="end">', _formatTimestamp(meta.maturityTimestamp), '</text>',
            
            // Footer
            // Bitcoin Yield Curve branded footer
            '<rect x="50" y="470" width="300" height="60" fill="#F7931A" rx="10" opacity="0.1"/>',
            // Protocol branding in footer
            '<text x="200" y="495" fill="#F7931A" font-family="Arial" font-size="11" text-anchor="middle">BITCOIN YIELD CURVE</text>',
            // Protocol tagline
            '<text x="200" y="515" fill="#888" font-family="Arial" font-size="9" text-anchor="middle">Oracle-Free NFT Lending Protocol</text>',
            
            '</svg>'
        ));
    }

    /// @notice Build JSON metadata
    function _buildJSON(
        uint256 loanId,
        string memory positionName,
        string memory svg,
        LoanMetadata memory meta,
        // Collateral NFT display name for JSON attributes
        string memory collateralName
    ) internal pure returns (string memory) {
        // Build concatenated string via abi.encodePacked
        return string(abi.encodePacked(
            '{"name":"Bitcoin Yield Curve - ', positionName, ' Position #', loanId.toString(), '",',
            // NFT description with position type and collateral info (JSON-escaped)
            '"description":"', positionName, ' position for NFT-collateralized loan #', loanId.toString(), '. Collateral: ', _escapeJSON(collateralName), '",',
            // Base64-encode SVG for inline data URI in JSON metadata
            // Embed base64-encoded SVG as the NFT image
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
            // ERC-721 metadata attributes for marketplace display
            '"attributes":[',
                // Position type attribute (Borrower or Lender)
                '{"trait_type":"Position Type","value":"', positionName, '"},',
                // Loan identifier attribute
                '{"trait_type":"Loan ID","value":', loanId.toString(), '},',
                // Collateral NFT name attribute (JSON-escaped)
                '{"trait_type":"Collateral NFT","value":"', _escapeJSON(collateralName), '"},',
                // Collateral contract address attribute
                '{"trait_type":"Collateral Contract","value":"', _addressToString(meta.collateralNFT), '"},',
                // Collateral token ID attribute
                '{"trait_type":"Collateral Token ID","value":', meta.collateralTokenId.toString(), '},',
                // Loan principal attribute
                '{"trait_type":"Principal","value":', meta.loanAmount.toString(), '},',
                // Total repayment attribute
                '{"trait_type":"Repayment","value":', meta.repaymentAmount.toString(), '},',
                // Maturity date attribute (Unix timestamp for marketplace date display)
                '{"trait_type":"Maturity","display_type":"date","value":', meta.maturityTimestamp.toString(), '}',
            // Close JSON attributes array and object
            ']}'
        ));
    }

    /// @notice Format amount for display
    function _formatAmount(uint256 amount) internal pure returns (string memory) {
        // Short-circuit for zero amounts
        if (amount == 0) return "0";
        // Return raw numeric string (frontend handles decimal formatting)
        // Return raw number as string (frontend handles decimal formatting)
        return amount.toString();
    }

    /// @notice Format timestamp for display
    function _formatTimestamp(uint256 timestamp) internal pure returns (string memory) {
        // Return "N/A" for uninitialized timestamps
        if (timestamp == 0) return "N/A";
        // Return as Unix timestamp - frontend can format
        // Return Unix timestamp as string (frontend formats to human-readable date)
        return timestamp.toString();
    }

    /// @notice Truncate string to max length
    function _truncateString(string memory str, uint256 maxLen) internal pure returns (string memory) {
        // Convert string to bytes for length check and character access
        bytes memory strBytes = bytes(str);
        // No truncation needed if string fits
        if (strBytes.length <= maxLen) return str;
        
        bytes memory truncated = new bytes(maxLen);
        // Copy characters from original string into truncated buffer
        for (uint256 i = 0; i < maxLen - 3; i++) {
            // Copy characters up to truncation point
            truncated[i] = strBytes[i];
        }
        // Append "..." suffix to indicate truncation
        // Append "..." ellipsis to indicate truncated string
        truncated[maxLen - 3] = '.';
        truncated[maxLen - 2] = '.';
        truncated[maxLen - 1] = '.';
        // Return truncated string with "..." suffix
        return string(truncated);
    }

    /// @notice Escape special XML/SVG characters to prevent injection
    /// @dev Replaces &, <, >, ", ' with XML entities. Applied to user-controllable strings
    ///      (e.g. collateral NFT names) before embedding in SVG markup.
    function _escapeXML(string memory str) internal pure returns (string memory) {
        bytes memory input = bytes(str);
        // Worst case: every char becomes "&amp;" (5 chars), so allocate 5x
        bytes memory output = new bytes(input.length * 5);
        uint256 outputLen = 0;
        
        for (uint256 i = 0; i < input.length; i++) {
            bytes1 char = input[i];
            if (char == '&') {
                output[outputLen++] = '&';
                output[outputLen++] = 'a';
                output[outputLen++] = 'm';
                output[outputLen++] = 'p';
                output[outputLen++] = ';';
            } else if (char == '<') {
                output[outputLen++] = '&';
                output[outputLen++] = 'l';
                output[outputLen++] = 't';
                output[outputLen++] = ';';
            } else if (char == '>') {
                output[outputLen++] = '&';
                output[outputLen++] = 'g';
                output[outputLen++] = 't';
                output[outputLen++] = ';';
            } else if (char == '"') {
                output[outputLen++] = '&';
                output[outputLen++] = 'q';
                output[outputLen++] = 'u';
                output[outputLen++] = 'o';
                output[outputLen++] = 't';
                output[outputLen++] = ';';
            } else if (char == "'") {
                output[outputLen++] = '&';
                output[outputLen++] = 'a';
                output[outputLen++] = 'p';
                output[outputLen++] = 'o';
                output[outputLen++] = 's';
                output[outputLen++] = ';';
            } else {
                output[outputLen++] = char;
            }
        }
        
        // Trim output to actual length
        bytes memory trimmed = new bytes(outputLen);
        for (uint256 i = 0; i < outputLen; i++) {
            trimmed[i] = output[i];
        }
        return string(trimmed);
    }

    /// @notice Escape special JSON characters to prevent injection
    /// @dev Replaces \, ", and control characters. Applied to user-controllable strings
    ///      before embedding in JSON metadata.
    function _escapeJSON(string memory str) internal pure returns (string memory) {
        bytes memory input = bytes(str);
        // Worst case: every char becomes a 2-char escape sequence
        bytes memory output = new bytes(input.length * 2);
        uint256 outputLen = 0;
        
        for (uint256 i = 0; i < input.length; i++) {
            bytes1 char = input[i];
            if (char == '"' || char == '\\') {
                output[outputLen++] = '\\';
                output[outputLen++] = char;
            } else if (uint8(char) < 0x20) {
                // Skip control characters (newlines, tabs, etc.)
                continue;
            } else {
                output[outputLen++] = char;
            }
        }
        
        bytes memory trimmed = new bytes(outputLen);
        for (uint256 i = 0; i < outputLen; i++) {
            trimmed[i] = output[i];
        }
        return string(trimmed);
    }

    /// @notice Convert address to string
    function _addressToString(address addr) internal pure returns (string memory) {
        // Convert address to full 42-character hex string (0x...)
        return Strings.toHexString(uint160(addr), 20);
    }

    /// @notice Convert address to short string (0x1234...5678)
    function _addressToShortString(address addr) internal pure returns (string memory) {
        // Get full hex string to extract prefix and suffix
        string memory full = Strings.toHexString(uint160(addr), 20);
        // Convert hex string to bytes for character extraction
        bytes memory fullBytes = bytes(full);
        
        // Return "0x" + first 4 chars + "..." + last 4 chars (13 bytes total)
        bytes memory result = new bytes(13);
        // Copy prefix chars, "...", and suffix chars to build short address
        // Copy "0x" prefix
        result[0] = fullBytes[0]; // 0
        // Copy 'x' from "0x" prefix
        result[1] = fullBytes[1]; // x
        result[2] = fullBytes[2];
        result[3] = fullBytes[3];
        result[4] = fullBytes[4];
        result[5] = fullBytes[5];
        // Insert "..." separator between prefix and suffix
        result[6] = '.';
        result[7] = '.';
        result[8] = '.';
        // Copy last 4 hex characters as suffix
        result[9] = fullBytes[38];
        result[10] = fullBytes[39];
        result[11] = fullBytes[40];
        result[12] = fullBytes[41];
        
        return string(result);
    }

    // ============================================================================
    // REQUIRED OVERRIDES
    // ============================================================================

    /// @dev Required override: resolves diamond inheritance between ERC721 and ERC721Enumerable
    function _update(address to, uint256 tokenId, address auth)
        internal
        // Required override â€” resolves diamond inheritance between ERC-721 bases
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        // Delegate to parent implementation (resolves diamond inheritance)
        return super._update(to, tokenId, auth);
    }

    /// @dev Required override: resolves diamond inheritance for balance tracking
    function _increaseBalance(address account, uint128 value)
        internal
        // Required override â€” resolves diamond inheritance between ERC-721 bases
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        // Delegate to parent implementation (resolves diamond inheritance)
        super._increaseBalance(account, value);
    }

    /// @dev Required override: aggregates ERC-165 interface support from all bases
    function supportsInterface(bytes4 interfaceId)
        public
        view
        // Required override â€” resolves ERC-165 interface detection across bases
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, IERC165)
        returns (bool)
    {
        // Delegate to parent implementation (resolves diamond inheritance)
        return super.supportsInterface(interfaceId);
    }
}
