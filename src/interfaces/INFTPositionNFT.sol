// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title INFTPositionNFT
 * @notice Interface for NFTPositionNFT contract
 */
interface INFTPositionNFT is IERC721 {
    // ============================================================================
    // ENUMS
    // ============================================================================

    enum PositionType {
        BORROWER,
        LENDER
    }

    // ============================================================================
    // PROTOCOL FUNCTIONS
    // ============================================================================

    /// @notice Mint a borrower position NFT
    /// @param loanId The loan ID
    /// @param to Recipient address
    /// @return tokenId The minted token ID
    function mintBorrowerPosition(uint256 loanId, address to) external returns (uint256 tokenId);

    /// @notice Mint a lender position NFT
    /// @param loanId The loan ID
    /// @param to Recipient address
    /// @return tokenId The minted token ID
    function mintLenderPosition(uint256 loanId, address to) external returns (uint256 tokenId);

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
        uint256 maturityTimestamp
    ) external;

    /// @notice Burn a position NFT
    /// @param tokenId Token to burn
    function burn(uint256 tokenId) external;

    // ============================================================================
    // TOKEN ID FUNCTIONS
    // ============================================================================

    /// @notice Get borrower token ID from loan ID
    /// @param loanId The loan ID
    /// @return tokenId The borrower token ID
    function getBorrowerTokenId(uint256 loanId) external pure returns (uint256 tokenId);

    /// @notice Get lender token ID from loan ID
    /// @param loanId The loan ID
    /// @return tokenId The lender token ID
    function getLenderTokenId(uint256 loanId) external pure returns (uint256 tokenId);

    /// @notice Get loan ID from token ID
    /// @param tokenId The token ID
    /// @return loanId The loan ID
    function getLoanId(uint256 tokenId) external pure returns (uint256 loanId);

    /// @notice Get position type from token ID
    /// @param tokenId The token ID
    /// @return positionType The position type (BORROWER or LENDER)
    function getPositionType(uint256 tokenId) external pure returns (PositionType positionType);

    /// @notice Check if token exists
    /// @param tokenId The token ID
    /// @return exists True if token exists
    function exists(uint256 tokenId) external view returns (bool);
}
