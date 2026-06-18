// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/NFTTestSetup.sol";

/**
 * @title NFTPositionNFTTests
 * @notice Unit tests for NFTPositionNFT (ERC-721 position tokens for NFT-collateralized loans)
 * @dev Covers: token ID encoding/decoding, mint/burn (via protocol flow), onlyLoanProtocol
 *      access control, initialization + immutability (loanProtocol set once in initialize),
 *      owner-only admin (setBaseURI), cacheCollateralImage, tokenURI / on-chain metadata,
 *      loanMetadata view, and ERC721 / enumerable interface support.
 *
 * API NOTE: NFTPositionNFT has NO setLoanProtocol. `loanProtocol` is assigned once in
 * initialize(address) and is effectively immutable thereafter. Tests assert immutability
 * via the OZ v5 Initializable guard (second initialize reverts InvalidInitialization()).
 */

// ============================================================================
// TOKEN ID ENCODING / DECODING
// ============================================================================

contract NFTPositionTokenIdTest is NFTTestSetup {

    function test_getBorrowerTokenId() public {
        assertEq(nftPositionNFT.getBorrowerTokenId(1), 2);
        assertEq(nftPositionNFT.getBorrowerTokenId(0), 0);
        assertEq(nftPositionNFT.getBorrowerTokenId(100), 200);
    }

    function test_getLenderTokenId() public {
        assertEq(nftPositionNFT.getLenderTokenId(1), 3);
        assertEq(nftPositionNFT.getLenderTokenId(0), 1);
    }

    function test_getLoanId() public {
        assertEq(nftPositionNFT.getLoanId(2), 1);
        assertEq(nftPositionNFT.getLoanId(3), 1);
        assertEq(nftPositionNFT.getLoanId(200), 100);
    }

    function test_getPositionType() public {
        assertEq(uint(nftPositionNFT.getPositionType(2)), uint(INFTPositionNFT.PositionType.BORROWER));
        assertEq(uint(nftPositionNFT.getPositionType(3)), uint(INFTPositionNFT.PositionType.LENDER));
    }
}

// ============================================================================
// MINT / BURN (via protocol flow)
// ============================================================================

contract NFTPositionMintBurnTest is NFTTestSetup {

    function test_mintOnFinalize() public {
        uint256 loanId = _createActiveNFTLoan();

        uint256 bTokenId = nftPositionNFT.getBorrowerTokenId(loanId);
        uint256 lTokenId = nftPositionNFT.getLenderTokenId(loanId);

        assertTrue(nftPositionNFT.exists(bTokenId));
        assertTrue(nftPositionNFT.exists(lTokenId));
        assertEq(nftPositionNFT.ownerOf(bTokenId), borrower);
        assertEq(nftPositionNFT.ownerOf(lTokenId), lender);
    }

    function test_burnOnRepay() public {
        uint256 loanId = _createActiveNFTLoan();

        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(nftProtocol), DEFAULT_MAX_REPAYMENT);
        nftProtocol.repayLoan(loanId);
        vm.stopPrank();

        uint256 bTokenId = nftPositionNFT.getBorrowerTokenId(loanId);
        uint256 lTokenId = nftPositionNFT.getLenderTokenId(loanId);

        assertFalse(nftPositionNFT.exists(bTokenId));
        assertFalse(nftPositionNFT.exists(lTokenId));
    }

    function test_exists_nonexistent() public {
        assertFalse(nftPositionNFT.exists(9999));
    }
}

// ============================================================================
// ACCESS CONTROL (onlyLoanProtocol)
// ============================================================================

contract NFTPositionAccessControlTest is NFTTestSetup {

    function test_mintBorrower_onlyProtocol_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(NFTPositionNFT.OnlyLoanProtocol.selector);
        nftPositionNFT.mintBorrowerPosition(1, attacker);
    }

    function test_mintLender_onlyProtocol_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(NFTPositionNFT.OnlyLoanProtocol.selector);
        nftPositionNFT.mintLenderPosition(1, attacker);
    }

    function test_burn_onlyProtocol_reverts() public {
        uint256 loanId = _createActiveNFTLoan();
        uint256 tokenId = nftPositionNFT.getBorrowerTokenId(loanId);

        vm.prank(attacker);
        vm.expectRevert(NFTPositionNFT.OnlyLoanProtocol.selector);
        nftPositionNFT.burn(tokenId);
    }

    function test_setLoanMetadata_onlyProtocol_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(NFTPositionNFT.OnlyLoanProtocol.selector);
        nftPositionNFT.setLoanMetadata(1, address(1), 1, address(2), 50000e6, 55000e6, 0);
    }

    function test_mintBorrower_ownerIsNotProtocol_reverts() public {
        // Even the contract owner (this test contract / deployer) is not the protocol,
        // so privileged mint must revert for it too.
        vm.expectRevert(NFTPositionNFT.OnlyLoanProtocol.selector);
        nftPositionNFT.mintBorrowerPosition(1, address(this));
    }
}

// ============================================================================
// ADMIN FUNCTIONS (owner-only setBaseURI, open cacheCollateralImage)
// ============================================================================

contract NFTPositionAdminTest is NFTTestSetup {

    function test_setBaseURI() public {
        nftPositionNFT.setBaseURI("https://api.example.com/nft/");
        assertEq(nftPositionNFT.baseURI(), "https://api.example.com/nft/");
    }

    function test_setBaseURI_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert();
        nftPositionNFT.setBaseURI("malicious");
    }

    function test_owner_isDeployer() public {
        // Owner is set to msg.sender of initialize(), i.e. this test contract.
        assertEq(nftPositionNFT.owner(), address(this));
    }

    function test_cacheCollateralImage_anyoneCanCache() public {
        vm.prank(attacker);
        nftPositionNFT.cacheCollateralImage(1, "ipfs://QmABC123");
        assertEq(nftPositionNFT.cachedCollateralImages(1), "ipfs://QmABC123");
    }
}

// ============================================================================
// INITIALIZATION / IMMUTABILITY
// ============================================================================

contract NFTPositionInitTest is NFTTestSetup {

    function test_initialize_setsCorrectState() public {
        assertEq(nftPositionNFT.loanProtocol(), address(nftProtocol));
        assertEq(nftPositionNFT.name(), "Bitcoin Yield Curve NFT Position");
        assertEq(nftPositionNFT.symbol(), "BYCNP");
    }

    /// @notice loanProtocol is set once and cannot be changed: re-initializing reverts.
    function test_initialize_secondCall_reverts() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        nftPositionNFT.initialize(makeAddr("newProtocol"));
    }

    /// @notice There is no setter for loanProtocol; immutability is enforced by the
    ///         initializer guard, so its value is fixed to the init argument forever.
    function test_loanProtocol_isImmutableValue() public {
        // Attempting to re-point the protocol via a fresh initialize reverts; the
        // stored value remains the original protocol address.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        nftPositionNFT.initialize(makeAddr("attackerProtocol"));
        assertEq(nftPositionNFT.loanProtocol(), address(nftProtocol));
    }

    function test_initialize_zeroProtocol_reverts() public {
        NFTPositionNFT impl = new NFTPositionNFT();
        vm.expectRevert();
        new ERC1967ProxyNFT(
            address(impl),
            abi.encodeCall(NFTPositionNFT.initialize, (address(0)))
        );
    }

    /// @notice A freshly deployed (uninitialized) proxy can be initialized exactly once,
    ///         setting loanProtocol to the provided value.
    function test_initialize_setsProvidedProtocol() public {
        address protoAddr = makeAddr("freshProtocol");
        NFTPositionNFT impl = new NFTPositionNFT();
        ERC1967ProxyNFT proxy = new ERC1967ProxyNFT(address(impl), "");
        NFTPositionNFT freshNFT = NFTPositionNFT(address(proxy));

        freshNFT.initialize(protoAddr);
        assertEq(freshNFT.loanProtocol(), protoAddr);
        assertEq(freshNFT.owner(), address(this));
    }
}

// ============================================================================
// METADATA / TOKEN URI
// ============================================================================

contract NFTPositionMetadataTest is NFTTestSetup {

    function test_tokenURI_borrower() public {
        uint256 loanId = _createActiveNFTLoan();
        uint256 tokenId = nftPositionNFT.getBorrowerTokenId(loanId);

        string memory uri = nftPositionNFT.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0);
        // Starts with data:application/json;base64,
        bytes memory uriBytes = bytes(uri);
        assertEq(uriBytes[0], "d");
        assertEq(uriBytes[1], "a");
        assertEq(uriBytes[2], "t");
        assertEq(uriBytes[3], "a");
    }

    function test_tokenURI_lender() public {
        uint256 loanId = _createActiveNFTLoan();
        uint256 tokenId = nftPositionNFT.getLenderTokenId(loanId);

        string memory uri = nftPositionNFT.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0);
    }

    function test_tokenURI_nonexistent_reverts() public {
        vm.expectRevert(NFTPositionNFT.TokenDoesNotExist.selector);
        nftPositionNFT.tokenURI(9999);
    }

    function test_loanMetadata_populated() public {
        uint256 loanId = _createActiveNFTLoan();

        (
            address collNFT,
            uint256 collTokenId,
            address lnToken,
            uint256 lnAmount,
            uint256 repayAmount,
            uint256 maturity,
            bool exists_
        ) = nftPositionNFT.loanMetadata(loanId);

        assertTrue(exists_);
        assertEq(collNFT, address(mockNFT));
        assertEq(collTokenId, DEFAULT_NFT_TOKEN_ID);
        assertEq(lnToken, address(loanToken));
        assertEq(lnAmount, DEFAULT_LOAN_AMOUNT);
        assertEq(repayAmount, DEFAULT_MAX_REPAYMENT);
        assertGt(maturity, 0);
    }

    function test_loanMetadata_unset_defaultsToEmpty() public {
        ( , , , , , , bool exists_) = nftPositionNFT.loanMetadata(9999);
        assertFalse(exists_);
    }
}

// ============================================================================
// ERC-721 INTERFACE
// ============================================================================

contract NFTPositionInterfaceTest is NFTTestSetup {

    function test_supportsInterface_ERC721() public {
        assertTrue(nftPositionNFT.supportsInterface(0x80ac58cd));
    }

    function test_supportsInterface_ERC721Enumerable() public {
        assertTrue(nftPositionNFT.supportsInterface(0x780e9d63));
    }

    function test_supportsInterface_ERC165() public {
        assertTrue(nftPositionNFT.supportsInterface(0x01ffc9a7));
    }

    function test_totalSupply() public {
        assertEq(nftPositionNFT.totalSupply(), 0);
        _createActiveNFTLoan();
        assertEq(nftPositionNFT.totalSupply(), 2);
    }

    function test_balanceOf() public {
        _createActiveNFTLoan();
        assertEq(nftPositionNFT.balanceOf(borrower), 1);
        assertEq(nftPositionNFT.balanceOf(lender), 1);
        assertEq(nftPositionNFT.balanceOf(attacker), 0);
    }
}
