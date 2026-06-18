// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/TestSetup.sol";

/**
 * @title PositionNFTTests
 * @notice Unit tests for PositionNFT (ERC-721 loan position tokens)
 * @dev Covers: token ID encoding/decoding, mint/burn, protocolTransfer,
 *      setLoanMetadata, tokenURI/SVG, initialization/immutability,
 *      onlyLoanProtocol access control, owner-only admin, ERC721 overrides
 *
 * API NOTE: `loanProtocol` is set ONCE in initialize(address) and is immutable
 * thereafter. There is NO setLoanProtocol function (the old tests for it have
 * been removed and replaced with immutability/initialization coverage).
 */

// ============================================================================
// TOKEN ID ENCODING / DECODING
// ============================================================================

contract TokenIdEncodingTest is TestSetup {

    function test_getBorrowerTokenId() public {
        assertEq(positionNFT.getBorrowerTokenId(1), 2);
        assertEq(positionNFT.getBorrowerTokenId(0), 0);
        assertEq(positionNFT.getBorrowerTokenId(100), 200);
    }

    function test_getLenderTokenId() public {
        assertEq(positionNFT.getLenderTokenId(1), 3);
        assertEq(positionNFT.getLenderTokenId(0), 1);
        assertEq(positionNFT.getLenderTokenId(100), 201);
    }

    function test_getLoanId() public {
        // Borrower token (even)
        assertEq(positionNFT.getLoanId(2), 1);
        assertEq(positionNFT.getLoanId(200), 100);
        // Lender token (odd)
        assertEq(positionNFT.getLoanId(3), 1);
        assertEq(positionNFT.getLoanId(201), 100);
    }

    function test_getPositionType() public {
        // Even = BORROWER
        assertEq(uint(positionNFT.getPositionType(2)), uint(IPositionNFT.PositionType.BORROWER));
        assertEq(uint(positionNFT.getPositionType(0)), uint(IPositionNFT.PositionType.BORROWER));
        // Odd = LENDER
        assertEq(uint(positionNFT.getPositionType(3)), uint(IPositionNFT.PositionType.LENDER));
        assertEq(uint(positionNFT.getPositionType(1)), uint(IPositionNFT.PositionType.LENDER));
    }

    function test_roundTrip_borrower() public {
        uint256 loanId = 42;
        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);
        assertEq(positionNFT.getLoanId(tokenId), loanId);
        assertEq(uint(positionNFT.getPositionType(tokenId)), uint(IPositionNFT.PositionType.BORROWER));
    }

    function test_roundTrip_lender() public {
        uint256 loanId = 42;
        uint256 tokenId = positionNFT.getLenderTokenId(loanId);
        assertEq(positionNFT.getLoanId(tokenId), loanId);
        assertEq(uint(positionNFT.getPositionType(tokenId)), uint(IPositionNFT.PositionType.LENDER));
    }
}

// ============================================================================
// MINT / BURN (via protocol flow)
// ============================================================================

contract PositionNFTMintBurnTest is TestSetup {

    function test_mintOnFinalize_borrowerAndLender() public {
        uint256 loanId = _createActiveLoan();

        uint256 borrowerTokenId = positionNFT.getBorrowerTokenId(loanId);
        uint256 lenderTokenId = positionNFT.getLenderTokenId(loanId);

        // Both tokens minted
        assertTrue(positionNFT.exists(borrowerTokenId));
        assertTrue(positionNFT.exists(lenderTokenId));

        // Correct owners
        assertEq(positionNFT.ownerOf(borrowerTokenId), borrower);
        assertEq(positionNFT.ownerOf(lenderTokenId), lender);
    }

    function test_burnOnRepay() public {
        uint256 loanId = _createActiveLoan();

        uint256 borrowerTokenId = positionNFT.getBorrowerTokenId(loanId);
        uint256 lenderTokenId = positionNFT.getLenderTokenId(loanId);

        // Repay
        loanToken.mint(borrower, DEFAULT_MAX_REPAYMENT);
        vm.startPrank(borrower);
        loanToken.approve(address(protocol), DEFAULT_MAX_REPAYMENT);
        protocol.repayLoan(loanId);
        vm.stopPrank();

        // Both tokens burned
        assertFalse(positionNFT.exists(borrowerTokenId));
        assertFalse(positionNFT.exists(lenderTokenId));
    }

    function test_burnOnDefault() public {
        uint256 loanId = _createActiveLoan();

        uint256 borrowerTokenId = positionNFT.getBorrowerTokenId(loanId);
        uint256 lenderTokenId = positionNFT.getLenderTokenId(loanId);

        // Default
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD + 1);
        vm.prank(lender);
        protocol.claimCollateral(loanId);

        // Both tokens burned
        assertFalse(positionNFT.exists(borrowerTokenId));
        assertFalse(positionNFT.exists(lenderTokenId));
    }

    function test_exists_nonexistent() public {
        assertFalse(positionNFT.exists(9999));
    }
}

// ============================================================================
// INITIALIZATION / IMMUTABILITY
// ============================================================================

contract PositionNFTInitTest is TestSetup {

    function test_initialize_setsCorrectState() public {
        // loanProtocol is set once at init and is the deployed protocol
        assertEq(positionNFT.loanProtocol(), address(protocol));
        assertEq(positionNFT.name(), "Bitcoin Yield Curve Position");
        assertEq(positionNFT.symbol(), "BYCP");
        // Test contract (deployer) is the owner
        assertEq(positionNFT.owner(), address(this));
    }

    function test_loanProtocol_returnsInitValue() public {
        // loanProtocol() getter returns the address fixed at initialization
        assertEq(positionNFT.loanProtocol(), address(protocol));
    }

    function test_initialize_secondCall_reverts() public {
        // loanProtocol is immutable after init: re-initializing must revert.
        // OZ v5 Initializable uses the InvalidInitialization() custom error.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        positionNFT.initialize(makeAddr("newProtocol"));
    }

    function test_initialize_secondCall_doesNotChangeLoanProtocol() public {
        // A failed re-init must not mutate the immutable loanProtocol.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        positionNFT.initialize(makeAddr("newProtocol"));
        assertEq(positionNFT.loanProtocol(), address(protocol));
    }

    function test_initialize_zeroProtocol_reverts() public {
        // Deploy an uninitialized proxy, then initialize with address(0): the
        // ZeroAddress revert bubbles up directly (not wrapped by the proxy ctor).
        PositionNFT impl = new PositionNFT();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        PositionNFT pn = PositionNFT(address(proxy));
        vm.expectRevert(PositionNFT.ZeroAddress.selector);
        pn.initialize(address(0));
    }

    function test_initialize_freshDeploy_setsProtocol() public {
        // A fresh proxy initialized with an arbitrary protocol address records it.
        address freshProtocol = makeAddr("freshProtocol");
        PositionNFT impl = new PositionNFT();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PositionNFT.initialize, (freshProtocol))
        );
        PositionNFT fresh = PositionNFT(address(proxy));
        assertEq(fresh.loanProtocol(), freshProtocol);
        assertEq(fresh.owner(), address(this));
    }
}

// ============================================================================
// ACCESS CONTROL (onlyLoanProtocol)
// ============================================================================

contract PositionNFTAccessControlTest is TestSetup {

    function test_mintBorrowerPosition_onlyProtocol_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(PositionNFT.OnlyLoanProtocol.selector);
        positionNFT.mintBorrowerPosition(1, attacker);
    }

    function test_mintLenderPosition_onlyProtocol_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(PositionNFT.OnlyLoanProtocol.selector);
        positionNFT.mintLenderPosition(1, attacker);
    }

    function test_burn_onlyProtocol_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);

        vm.prank(attacker);
        vm.expectRevert(PositionNFT.OnlyLoanProtocol.selector);
        positionNFT.burn(tokenId);
    }

    function test_protocolTransfer_onlyProtocol_reverts() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);

        vm.prank(attacker);
        vm.expectRevert(PositionNFT.OnlyLoanProtocol.selector);
        positionNFT.protocolTransfer(tokenId, borrower, attacker);
    }

    function test_setLoanMetadata_onlyProtocol_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(PositionNFT.OnlyLoanProtocol.selector);
        positionNFT.setLoanMetadata(1, address(1), 1e8, address(2), 50000e6, 55000e6, 0);
    }

    function test_owner_cannotMint() public {
        // Even the owner (this test contract) is not the loanProtocol.
        vm.expectRevert(PositionNFT.OnlyLoanProtocol.selector);
        positionNFT.mintBorrowerPosition(1, address(this));
    }
}

// ============================================================================
// PRIVILEGED OPS VIA AUTHORIZED CALLER (loanProtocol)
// ============================================================================

contract PositionNFTPrivilegedOpsTest is TestSetup {

    /// @dev Deploy a fresh NFT whose loanProtocol is an EOA we control, so we
    ///      can exercise the privileged functions directly via vm.prank.
    function _freshNFTWithCaller(address caller) internal returns (PositionNFT nft) {
        PositionNFT impl = new PositionNFT();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PositionNFT.initialize, (caller))
        );
        nft = PositionNFT(address(proxy));
    }

    function test_mintBorrowerPosition_byProtocol_succeeds() public {
        address caller = makeAddr("protocolEOA");
        PositionNFT nft = _freshNFTWithCaller(caller);

        vm.prank(caller);
        uint256 tokenId = nft.mintBorrowerPosition(7, borrower);

        assertEq(tokenId, nft.getBorrowerTokenId(7));
        assertEq(nft.ownerOf(tokenId), borrower);
        assertTrue(nft.exists(tokenId));
    }

    function test_mintLenderPosition_byProtocol_succeeds() public {
        address caller = makeAddr("protocolEOA");
        PositionNFT nft = _freshNFTWithCaller(caller);

        vm.prank(caller);
        uint256 tokenId = nft.mintLenderPosition(7, lender);

        assertEq(tokenId, nft.getLenderTokenId(7));
        assertEq(nft.ownerOf(tokenId), lender);
    }

    function test_burn_byProtocol_succeeds() public {
        address caller = makeAddr("protocolEOA");
        PositionNFT nft = _freshNFTWithCaller(caller);

        vm.startPrank(caller);
        uint256 tokenId = nft.mintBorrowerPosition(7, borrower);
        nft.burn(tokenId);
        vm.stopPrank();

        assertFalse(nft.exists(tokenId));
    }

    function test_protocolTransfer_byProtocol_succeeds() public {
        address caller = makeAddr("protocolEOA");
        PositionNFT nft = _freshNFTWithCaller(caller);

        vm.startPrank(caller);
        uint256 tokenId = nft.mintBorrowerPosition(7, borrower);
        // Protocol transfer bypasses approval entirely.
        nft.protocolTransfer(tokenId, borrower, attacker);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), attacker);
    }

    function test_setLoanMetadata_byProtocol_succeeds() public {
        address caller = makeAddr("protocolEOA");
        PositionNFT nft = _freshNFTWithCaller(caller);

        vm.prank(caller);
        nft.setLoanMetadata(
            7,
            address(collateralToken),
            DEFAULT_COLLATERAL,
            address(loanToken),
            DEFAULT_LOAN_AMOUNT,
            DEFAULT_MAX_REPAYMENT,
            block.timestamp + DEFAULT_LOAN_DURATION
        );

        (
            address collToken,
            uint256 collAmount,
            address lnToken,
            uint256 lnAmount,
            uint256 repayAmount,
            uint256 maturity,
            bool exists_
        ) = nft.loanMetadata(7);

        assertTrue(exists_);
        assertEq(collToken, address(collateralToken));
        assertEq(collAmount, DEFAULT_COLLATERAL);
        assertEq(lnToken, address(loanToken));
        assertEq(lnAmount, DEFAULT_LOAN_AMOUNT);
        assertEq(repayAmount, DEFAULT_MAX_REPAYMENT);
        assertEq(maturity, block.timestamp + DEFAULT_LOAN_DURATION);
    }
}

// ============================================================================
// ADMIN FUNCTIONS (owner-only)
// ============================================================================

contract PositionNFTAdminTest is TestSetup {

    function test_setBaseURI() public {
        positionNFT.setBaseURI("https://api.example.com/token/");
        assertEq(positionNFT.baseURI(), "https://api.example.com/token/");
    }

    function test_setBaseURI_nonOwner_reverts() public {
        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount(attacker)
        positionNFT.setBaseURI("malicious");
    }
}

// ============================================================================
// METADATA / TOKEN URI
// ============================================================================

contract PositionNFTMetadataTest is TestSetup {

    function test_tokenURI_borrower() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = positionNFT.getBorrowerTokenId(loanId);

        string memory uri = positionNFT.tokenURI(tokenId);
        // URI should be a data: URI with base64-encoded JSON
        assertTrue(bytes(uri).length > 0);
        // Starts with "data"
        bytes memory uriBytes = bytes(uri);
        assertEq(uriBytes[0], "d");
        assertEq(uriBytes[1], "a");
        assertEq(uriBytes[2], "t");
        assertEq(uriBytes[3], "a");
    }

    function test_tokenURI_lender() public {
        uint256 loanId = _createActiveLoan();
        uint256 tokenId = positionNFT.getLenderTokenId(loanId);

        string memory uri = positionNFT.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0);
    }

    function test_tokenURI_nonexistent_reverts() public {
        vm.expectRevert(PositionNFT.TokenDoesNotExist.selector);
        positionNFT.tokenURI(9999);
    }

    function test_loanMetadata_populated() public {
        uint256 loanId = _createActiveLoan();

        (
            address collToken,
            uint256 collAmount,
            address lnToken,
            uint256 lnAmount,
            uint256 repayAmount,
            uint256 maturity,
            bool exists_
        ) = positionNFT.loanMetadata(loanId);

        assertTrue(exists_);
        assertEq(collToken, address(collateralToken));
        assertEq(collAmount, DEFAULT_COLLATERAL);
        assertEq(lnToken, address(loanToken));
        assertEq(lnAmount, DEFAULT_LOAN_AMOUNT);
        assertEq(repayAmount, DEFAULT_MAX_REPAYMENT);
        assertGt(maturity, 0);
    }

    function test_loanMetadata_unset_defaultsEmpty() public {
        // Metadata for a loan that was never created is the empty default.
        (, , , , , , bool exists_) = positionNFT.loanMetadata(123456);
        assertFalse(exists_);
    }
}

// ============================================================================
// ERC-721 INTERFACE
// ============================================================================

contract PositionNFTInterfaceTest is TestSetup {

    function test_supportsInterface_ERC721() public {
        // ERC721 interface ID = 0x80ac58cd
        assertTrue(positionNFT.supportsInterface(0x80ac58cd));
    }

    function test_supportsInterface_ERC721Enumerable() public {
        // ERC721Enumerable interface ID = 0x780e9d63
        assertTrue(positionNFT.supportsInterface(0x780e9d63));
    }

    function test_supportsInterface_ERC165() public {
        // ERC165 interface ID = 0x01ffc9a7
        assertTrue(positionNFT.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_unsupported() public {
        // Random/unsupported interface id returns false.
        assertFalse(positionNFT.supportsInterface(0xffffffff));
    }

    function test_totalSupply_afterMint() public {
        assertEq(positionNFT.totalSupply(), 0);

        _createActiveLoan();

        // 2 tokens minted (borrower + lender)
        assertEq(positionNFT.totalSupply(), 2);
    }

    function test_balanceOf() public {
        _createActiveLoan();

        assertEq(positionNFT.balanceOf(borrower), 1);
        assertEq(positionNFT.balanceOf(lender), 1);
        assertEq(positionNFT.balanceOf(attacker), 0);
    }
}
