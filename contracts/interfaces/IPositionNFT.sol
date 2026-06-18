// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IPositionNFT
 * @notice Interface for loan position NFT contract
 * @dev Extends ERC721 with protocol-specific functionality
 *      Updated with Security Fix M-3 (setLoanMetadata)
 */
interface IPositionNFT is IERC721 {
    
    enum PositionType {
        BORROWER,
        LENDER
    }

    // ============================================================================
    // PROTOCOL FUNCTIONS (callable only by LoanProtocol)
    // ============================================================================

    /// @notice Mint a borrower position NFT
    /// @param loanId The loan ID this position represents
    /// @param to Address to mint to
    /// @return tokenId The minted token ID
    function mintBorrowerPosition(uint256 loanId, address to) external returns (uint256 tokenId);

    /// @notice Mint a lender position NFT
    /// @param loanId The loan ID this position represents
    /// @param to Address to mint to
    /// @return tokenId The minted token ID
    function mintLenderPosition(uint256 loanId, address to) external returns (uint256 tokenId);

    /// @notice Store loan metadata for NFT display (Security Fix M-3)
    /// @param loanId The loan ID
    /// @param collateralToken Collateral ERC20 token address
    /// @param collateralAmount Amount of collateral locked
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
        uint256 maturityTimestamp
    ) external;

    /// @notice Burn a position NFT
    /// @param tokenId Token to burn
    function burn(uint256 tokenId) external;

    /// @notice Transfer by protocol (bypasses standard approval) - Security Fix C-3
    /// @param tokenId Token to transfer
    /// @param from Current owner
    /// @param to New owner
    function protocolTransfer(uint256 tokenId, address from, address to) external;

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /// @notice Get the borrower token ID for a loan
    /// @param loanId The loan ID
    /// @return tokenId The borrower position token ID
    function getBorrowerTokenId(uint256 loanId) external pure returns (uint256 tokenId);

    /// @notice Get the lender token ID for a loan
    /// @param loanId The loan ID
    /// @return tokenId The lender position token ID
    function getLenderTokenId(uint256 loanId) external pure returns (uint256 tokenId);

    /// @notice Get the loan ID from a token ID
    /// @param tokenId The token ID
    /// @return loanId The associated loan ID
    function getLoanId(uint256 tokenId) external pure returns (uint256 loanId);

    /// @notice Get the position type (borrower or lender)
    /// @param tokenId The token ID
    /// @return positionType The position type
    function getPositionType(uint256 tokenId) external pure returns (PositionType positionType);

    /// @notice Check if a token exists
    /// @param tokenId Token to check
    /// @return exists True if token exists
    function exists(uint256 tokenId) external view returns (bool);
}
