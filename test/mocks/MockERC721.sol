// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC721
 * @notice Mock NFT collection for testing the NFT lending protocol
 * @dev Includes minting functions and customizable base URI
 */
contract MockERC721 is ERC721, ERC721Enumerable, Ownable {
    uint256 private _tokenIdCounter;
    string private _baseTokenURI;

    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) Ownable(msg.sender) {
        _baseTokenURI = "https://api.example.com/nft/";
    }

    /// @notice Mint a single NFT to an address
    /// @param to Recipient address
    /// @return tokenId The minted token ID
    function mint(address to) external returns (uint256 tokenId) {
        tokenId = ++_tokenIdCounter;
        _safeMint(to, tokenId);
    }

    /// @notice Mint multiple NFTs to an address
    /// @param to Recipient address
    /// @param count Number of NFTs to mint
    /// @return tokenIds Array of minted token IDs
    function mintBatch(address to, uint256 count) external returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = ++_tokenIdCounter;
            _safeMint(to, tokenId);
            tokenIds[i] = tokenId;
        }
    }

    /// @notice Set the base URI for token metadata
    /// @param baseURI New base URI
    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    /// @notice Get the base URI
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice Get the current token count
    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter;
    }

    // ============================================================================
    // Required Overrides
    // ============================================================================

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
