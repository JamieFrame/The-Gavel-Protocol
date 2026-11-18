// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/TestSetup.sol";
import "../utils/NFTTestSetup.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

// ============================================================================
// SR3 — independent reproduction of known issue KI-4
// ============================================================================
//
// KI-4  NFTLoanProtocol accepts any ERC-721 as collateral, including Gavel's own position
//       NFTs. If the lender position of loan X is collateral for loan Y and X is repaid,
//       repayLoan pushes X's repayment to the current holder of that position (the
//       NFTLoanProtocol itself, which does not account for it) and burns the position.
//       Loan Y can then never settle: its repayLoan and claimCollateral both revert when
//       they try to transfer the burned token.
//
// Both settlement reverts surface ERC721NonexistentToken(tokenId) of the burned position,
// raised by OpenZeppelin ERC721Upgradeable v5.0.0 (lib/openzeppelin-contracts-upgradeable at tag
// v5.0.0, via the @openzeppelin/contracts-upgradeable/ remapping) inside the position contract's
// transferFrom:
//   - NFTPositionNFT: NFTLoanProtocol is its loanProtocol, so transferFrom takes the
//     approval-free branch, _transfer, which reverts ERC721NonexistentToken.
//   - PositionNFT (LoanProtocol stack): the standard branch, _update -> _checkAuthorized,
//     which reverts ERC721NonexistentToken.
//
// Cases (runbook SR3, Phase 1):
//   1  reported path: X repaid while Y is active
//   1b case 1, then markDefault(Y) after grace: Y shows DEFAULTED but still cannot settle
//   2 third-party early repayment: Y matures before X; X's borrower repays early
//   3  control: Y repaid first; both loans settle
//   4  cross-stack: a LoanProtocol lender position pledged in NFTLoanProtocol
//   5  X defaults instead (a: Y repaid; b: Y defaults)
//   6  X's borrower position pledged for Y
//   7  case 1 on an Arbitrum One fork against the live proxies (SR3Fork_PositionAsCollateral).
//      Skipped unless ARB_RPC_URL is set; the fork block defaults to SR3_FORK_BLOCK and can be
//      overridden with SR3_FORK_BLOCK (needs an archive endpoint once the block is old).
//      Nothing is sent to the network.
//   8  reporter comparison: the reporter's scenario (zero interest, 10,000 principal on X and Y,
//      two accounts on one side, an independent lender on Y) rebuilt in this file's terms
// ============================================================================

abstract contract SR3Constants {
    uint256 internal constant Y_LOAN = 10_000e6;
    uint256 internal constant Y_REPAY = 10_500e6;
    uint256 internal constant Y_BID_STEP = 100e6;
    uint256 internal constant Y_AUCTION_DURATION = 1 days;

    function _nonexistent(uint256 tokenId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId);
    }
}

// ============================================================================
// Local deployment (cases 1-6)
// ============================================================================

contract SR3_PositionAsCollateral is NFTTestSetup, SR3Constants {
    address internal lenderY = makeAddr("lenderY");

    function setUp() public override {
        super.setUp();
        loanToken.mint(lenderY, 10_000_000e6);
        vm.prank(lenderY);
        loanToken.approve(address(nftProtocol), type(uint256).max);
        vm.prank(borrower);
        loanToken.approve(address(nftProtocol), type(uint256).max);
    }

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------

    /// @dev `pledger` pledges `tokenId` of `collection` as collateral for loan Y, funded by lenderY
    function _pledgeForY(address collection, uint256 tokenId, address pledger, uint256 yDuration)
        internal
        returns (uint256 y)
    {
        vm.startPrank(pledger);
        IERC721(collection).setApprovalForAll(address(nftProtocol), true);
        y = nftProtocol.createAuction(
            collection, tokenId, address(loanToken), Y_LOAN, Y_REPAY, yDuration, Y_AUCTION_DURATION, Y_BID_STEP
        );
        vm.stopPrank();
        vm.prank(lenderY);
        nftProtocol.placeBid(y, Y_REPAY);
        vm.warp(nftProtocol.getAuction(y).auctionEnd + 1);
        nftProtocol.finalizeAuction(y);
        assertEq(IERC721(collection).ownerOf(tokenId), address(nftProtocol), "pledged position not held");
        assertEq(uint8(nftProtocol.getLoan(y).status), uint8(NFTLoanProtocol.LoanStatus.ACTIVE));
    }

    /// @dev Loan X (borrower -> lender); the lender pledges X's lender position for loan Y
    function _setupLenderPledge(uint256 yDuration) internal returns (uint256 x, uint256 y, uint256 xLenderTok) {
        x = _createActiveNFTLoan();
        xLenderTok = nftPositionNFT.getLenderTokenId(x);
        assertEq(nftPositionNFT.ownerOf(xLenderTok), lender);
        y = _pledgeForY(address(nftPositionNFT), xLenderTok, lender, yDuration);
    }

    function _graceEnd(uint256 loanId) internal view returns (uint256) {
        return nftProtocol.getLoan(loanId).maturityTimestamp + GRACE_PERIOD;
    }

    function _status(uint256 loanId) internal view returns (uint8) {
        return uint8(nftProtocol.getLoan(loanId).status);
    }

    /// @dev Y can be neither repaid (now) nor claimed (after its maturity plus grace)
    function _assertYUnsettleable(uint256 y, address yBorrower, uint256 burnedTok) internal {
        uint256 yBorrowerCash = loanToken.balanceOf(yBorrower);
        vm.prank(yBorrower);
        vm.expectRevert(_nonexistent(burnedTok));
        nftProtocol.repayLoan(y);
        assertEq(loanToken.balanceOf(yBorrower), yBorrowerCash, "Y repayment did not unwind");

        vm.warp(_graceEnd(y));
        vm.prank(lenderY);
        vm.expectRevert(_nonexistent(burnedTok));
        nftProtocol.claimCollateral(y);

        assertEq(_status(y), uint8(NFTLoanProtocol.LoanStatus.ACTIVE), "Y settled");
    }

    // ------------------------------------------------------------------------
    // Case 1 — reported path
    // ------------------------------------------------------------------------

    function test_case1_reportedPath_XRepaid_YUnsettleable() public {
        uint256 lenderYStart = loanToken.balanceOf(lenderY);
        (uint256 x, uint256 y, uint256 tok) = _setupLenderPledge(30 days);
        uint256 protoBefore = loanToken.balanceOf(address(nftProtocol));
        uint256 lenderBefore = loanToken.balanceOf(lender);
        assertEq(nftProtocol.getLoan(x).repaymentAmount, DEFAULT_MAX_REPAYMENT);

        vm.prank(borrower);
        nftProtocol.repayLoan(x);

        // X settled for its borrower...
        assertEq(_status(x), uint8(NFTLoanProtocol.LoanStatus.REPAID));
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), borrower, "X collateral not returned");
        // ...but its repayment went to the holder of X's lender position: the protocol itself
        assertEq(
            loanToken.balanceOf(address(nftProtocol)) - protoBefore, DEFAULT_MAX_REPAYMENT, "X repayment not trapped"
        );
        assertEq(loanToken.balanceOf(lender), lenderBefore, "X's lender was paid");

        // The pledged position is burned
        vm.expectRevert(_nonexistent(tok));
        nftPositionNFT.ownerOf(tok);

        _assertYUnsettleable(y, lender, tok);

        // The trapped repayment is still in the protocol; Y's lender is out of the principal
        assertEq(loanToken.balanceOf(address(nftProtocol)) - protoBefore, DEFAULT_MAX_REPAYMENT);
        assertEq(loanToken.balanceOf(lenderY), lenderYStart - Y_LOAN, "lenderY balance");

        emit log("KI-4 reported path");
        emit log_named_decimal_uint("  X repayment trapped in NFTLoanProtocol (USDC)", DEFAULT_MAX_REPAYMENT, 6);
        emit log_named_decimal_uint("  Y principal lent and not recoverable (USDC)", Y_LOAN, 6);
    }

    /// @dev Case 1b: markDefault (permissionless after grace) moves a stuck Y from ACTIVE to
    ///      DEFAULTED, but Y still cannot settle and nothing moves.
    function test_case1b_markDefault_YDefaultedButUnsettleable() public {
        (uint256 x, uint256 y, uint256 tok) = _setupLenderPledge(30 days);
        uint256 yLenderTok = nftPositionNFT.getLenderTokenId(y);
        uint256 yBorrowerTok = nftPositionNFT.getBorrowerTokenId(y);

        vm.prank(borrower);
        nftProtocol.repayLoan(x);

        vm.warp(_graceEnd(y));
        uint256 protoBefore = loanToken.balanceOf(address(nftProtocol));
        uint256 lenderYBefore = loanToken.balanceOf(lenderY);
        uint256 lenderBefore = loanToken.balanceOf(lender);

        // Anyone may mark Y defaulted once its grace period has ended
        vm.prank(attacker);
        nftProtocol.markDefault(y);
        assertEq(_status(y), uint8(NFTLoanProtocol.LoanStatus.DEFAULTED), "Y not DEFAULTED");

        // Y's lender still cannot claim: the collateral transfer reverts on the burned position
        vm.prank(lenderY);
        vm.expectRevert(_nonexistent(tok));
        nftProtocol.claimCollateral(y);

        // Y's borrower cannot repay either (status is no longer ACTIVE)
        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.LoanNotActive.selector);
        nftProtocol.repayLoan(y);

        // Nothing moved
        assertEq(_status(y), uint8(NFTLoanProtocol.LoanStatus.DEFAULTED));
        assertEq(loanToken.balanceOf(address(nftProtocol)), protoBefore, "protocol balance moved");
        assertEq(loanToken.balanceOf(lenderY), lenderYBefore, "lenderY balance moved");
        assertEq(loanToken.balanceOf(lender), lenderBefore, "Y borrower balance moved");
        assertEq(nftPositionNFT.ownerOf(yLenderTok), lenderY, "Y lender position moved");
        assertEq(nftPositionNFT.ownerOf(yBorrowerTok), lender, "Y borrower position moved");
    }

    // ------------------------------------------------------------------------
    // Case 2 — third-party early repayment
    // ------------------------------------------------------------------------

    function test_case2_thirdPartyEarlyRepay_bricksShorterLoan() public {
        (uint256 x, uint256 y, uint256 tok) = _setupLenderPledge(7 days);
        assertLt(nftProtocol.getLoan(y).maturityTimestamp, nftProtocol.getLoan(x).maturityTimestamp, "Y not shorter");
        uint256 protoBefore = loanToken.balanceOf(address(nftProtocol));

        // X's borrower, a third party to Y, repays X early
        vm.prank(borrower);
        nftProtocol.repayLoan(x);
        assertEq(loanToken.balanceOf(address(nftProtocol)) - protoBefore, DEFAULT_MAX_REPAYMENT, "not trapped");

        _assertYUnsettleable(y, lender, tok);
    }

    // ------------------------------------------------------------------------
    // Case 3 — control: Y repaid first
    // ------------------------------------------------------------------------

    function test_case3_control_YRepaidFirst() public {
        (uint256 x, uint256 y, uint256 tok) = _setupLenderPledge(7 days);
        uint256 protoBefore = loanToken.balanceOf(address(nftProtocol));
        uint256 lenderYBefore = loanToken.balanceOf(lenderY);

        vm.prank(lender);
        nftProtocol.repayLoan(y);
        assertEq(loanToken.balanceOf(lenderY), lenderYBefore + Y_REPAY, "lenderY not paid");
        assertEq(nftPositionNFT.ownerOf(tok), lender, "position not returned");

        uint256 lenderBefore = loanToken.balanceOf(lender);
        vm.prank(borrower);
        nftProtocol.repayLoan(x);
        assertEq(loanToken.balanceOf(lender), lenderBefore + DEFAULT_MAX_REPAYMENT, "lender not paid");
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), borrower);
        assertEq(loanToken.balanceOf(address(nftProtocol)), protoBefore, "funds left in protocol");
        assertEq(_status(x), uint8(NFTLoanProtocol.LoanStatus.REPAID));
        assertEq(_status(y), uint8(NFTLoanProtocol.LoanStatus.REPAID));
    }

    // ------------------------------------------------------------------------
    // Case 4 — cross-stack: a LoanProtocol lender position pledged in NFTLoanProtocol
    // ------------------------------------------------------------------------

    function _deployLoanStack() internal returns (LoanProtocol lp, PositionNFT pnft, TestMockERC20 wbtc) {
        wbtc = new TestMockERC20("Wrapped Bitcoin", "WBTC", 8);
        LoanProtocol lpImpl = new LoanProtocol();
        PositionNFT pnftImpl = new PositionNFT();
        ERC1967Proxy pnftProxy = new ERC1967Proxy(address(pnftImpl), "");
        pnft = PositionNFT(address(pnftProxy));
        ERC1967Proxy lpProxy =
            new ERC1967Proxy(address(lpImpl), abi.encodeCall(LoanProtocol.initialize, (address(pnft))));
        lp = LoanProtocol(address(lpProxy));
        pnft.initialize(address(lp));
    }

    function test_case4_crossStack_LoanProtocolPositionPledged() public {
        (LoanProtocol lp, PositionNFT pnft, TestMockERC20 wbtc) = _deployLoanStack();

        // Loan X on LoanProtocol: 1 WBTC collateral, same loan token
        wbtc.mint(borrower, 1e8);
        vm.startPrank(borrower);
        wbtc.approve(address(lp), type(uint256).max);
        loanToken.approve(address(lp), type(uint256).max);
        lp.depositCollateral(address(wbtc), 1e8);
        uint256 x = lp.createAuction(
            address(wbtc),
            1e8,
            address(loanToken),
            DEFAULT_LOAN_AMOUNT,
            DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION,
            DEFAULT_AUCTION_DURATION,
            DEFAULT_BID_STEP
        );
        vm.stopPrank();
        vm.startPrank(lender);
        loanToken.approve(address(lp), type(uint256).max);
        lp.placeBid(x, DEFAULT_MAX_REPAYMENT);
        vm.stopPrank();
        vm.warp(vm.getBlockTimestamp() + DEFAULT_AUCTION_DURATION + 1);
        lp.finalizeAuction(x);
        uint256 tok = pnft.getLenderTokenId(x);
        assertEq(pnft.ownerOf(tok), lender);

        // X's LoanProtocol lender position pledged for loan Y in NFTLoanProtocol
        uint256 y = _pledgeForY(address(pnft), tok, lender, 30 days);

        uint256 protoBefore = loanToken.balanceOf(address(nftProtocol));
        uint256 lenderBefore = loanToken.balanceOf(lender);
        uint256 wbtcBefore = wbtc.balanceOf(borrower);

        vm.prank(borrower);
        lp.repayLoan(x);

        assertEq(wbtc.balanceOf(borrower), wbtcBefore + 1e8, "X collateral not returned");
        assertEq(
            loanToken.balanceOf(address(nftProtocol)) - protoBefore,
            DEFAULT_MAX_REPAYMENT,
            "X repayment not trapped in NFTLoanProtocol"
        );
        assertEq(loanToken.balanceOf(lender), lenderBefore, "X's lender was paid");

        vm.expectRevert(_nonexistent(tok));
        pnft.ownerOf(tok);

        _assertYUnsettleable(y, lender, tok);
    }

    // ------------------------------------------------------------------------
    // Case 5 — X defaults instead of being repaid
    // ------------------------------------------------------------------------

    /// @dev X's lender position pledged for a 60-day Y; X runs past its grace period unpaid.
    ///      While Y is active, nobody can claim X: the holder of X's lender position is the protocol.
    function _setupXDefaultWhileYActive() internal returns (uint256 x, uint256 y, uint256 tok) {
        (x, y, tok) = _setupLenderPledge(60 days);
        vm.warp(_graceEnd(x));
        assertLt(vm.getBlockTimestamp(), nftProtocol.getLoan(y).maturityTimestamp, "Y no longer in term");

        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.GracePeriodExpired.selector);
        nftProtocol.repayLoan(x);

        vm.prank(lender);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.claimCollateral(x);
        vm.prank(lenderY);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.claimCollateral(x);

        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), address(nftProtocol), "X collateral moved");
    }

    function test_case5a_XDefaults_YRepaid_YBorrowerClaimsX() public {
        (uint256 x, uint256 y, uint256 tok) = _setupXDefaultWhileYActive();
        uint256 protoBefore = loanToken.balanceOf(address(nftProtocol));
        uint256 lenderYBefore = loanToken.balanceOf(lenderY);

        vm.prank(lender);
        nftProtocol.repayLoan(y);
        assertEq(loanToken.balanceOf(lenderY), lenderYBefore + Y_REPAY, "lenderY not paid");
        assertEq(nftPositionNFT.ownerOf(tok), lender, "position not returned to Y's borrower");

        vm.prank(lender);
        nftProtocol.claimCollateral(x);
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), lender, "X collateral not claimed");
        assertEq(_status(x), uint8(NFTLoanProtocol.LoanStatus.DEFAULTED));
        assertEq(_status(y), uint8(NFTLoanProtocol.LoanStatus.REPAID));
        assertEq(loanToken.balanceOf(address(nftProtocol)), protoBefore, "funds left in protocol");
    }

    function test_case5b_XDefaults_YDefaults_YLenderClaimsX() public {
        (uint256 x, uint256 y, uint256 tok) = _setupXDefaultWhileYActive();
        uint256 protoBefore = loanToken.balanceOf(address(nftProtocol));

        vm.warp(_graceEnd(y));
        vm.prank(lenderY);
        nftProtocol.claimCollateral(y);
        assertEq(nftPositionNFT.ownerOf(tok), lenderY, "position not to Y's lender");

        vm.prank(lenderY);
        nftProtocol.claimCollateral(x);
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), lenderY, "X collateral not claimed");
        assertEq(_status(x), uint8(NFTLoanProtocol.LoanStatus.DEFAULTED));
        assertEq(_status(y), uint8(NFTLoanProtocol.LoanStatus.DEFAULTED));
        assertEq(loanToken.balanceOf(address(nftProtocol)), protoBefore, "funds left in protocol");
    }

    // ------------------------------------------------------------------------
    // Case 6 — X's borrower position pledged for Y
    // ------------------------------------------------------------------------

    function test_case6_borrowerPositionPledged() public {
        uint256 lenderYStart = loanToken.balanceOf(lenderY);
        uint256 x = _createActiveNFTLoan();
        uint256 bTok = nftPositionNFT.getBorrowerTokenId(x);
        assertEq(nftPositionNFT.ownerOf(bTok), borrower);
        uint256 y = _pledgeForY(address(nftPositionNFT), bTok, borrower, 60 days);
        uint256 protoBefore = loanToken.balanceOf(address(nftProtocol));

        // While Y is active, X cannot be repaid: only the holder of the borrower position repays
        vm.prank(borrower);
        vm.expectRevert(NFTLoanProtocol.Unauthorized.selector);
        nftProtocol.repayLoan(x);

        // X defaults; its lender claims, which burns the pledged borrower position
        vm.warp(_graceEnd(x));
        assertLt(vm.getBlockTimestamp(), nftProtocol.getLoan(y).maturityTimestamp, "Y no longer in term");
        vm.prank(lender);
        nftProtocol.claimCollateral(x);
        assertEq(mockNFT.ownerOf(DEFAULT_NFT_TOKEN_ID), lender, "X collateral not claimed");
        vm.expectRevert(_nonexistent(bTok));
        nftPositionNFT.ownerOf(bTok);

        // Y can no longer settle
        _assertYUnsettleable(y, borrower, bTok);

        // Nothing trapped in the protocol; Y's lender is out of the principal
        assertEq(loanToken.balanceOf(address(nftProtocol)), protoBefore, "funds trapped");
        assertEq(loanToken.balanceOf(lenderY), lenderYStart - Y_LOAN, "lenderY balance");
    }

    // ------------------------------------------------------------------------
    // Case 8 — reporter comparison (ForkProof, GAVEL-NLP-01)
    // ------------------------------------------------------------------------
    //
    // The reporter's scenario rebuilt here, not copied: zero interest (principal = maximum
    // repayment = 10,000 on X and on Y); accounts a1 and a2 act together (a1 borrows on X against
    // an ordinary ERC-721; a2 lends on X, pledges X's lender position for Y and borrows on Y);
    // lenderY, independent, funds Y. Reported figures: Y's lender loses 10,000; the pair nets 0;
    // 10,000 (X's repayment) is trapped in NFTLoanProtocol.

    uint256 internal constant ZERO_INTEREST_PRINCIPAL = 10_000e6;

    function _int(uint256 v) internal pure returns (int256) {
        return int256(v);
    }

    function test_case8_reporterComparison_zeroInterest() public {
        address a1 = makeAddr("sr3-a1");
        address a2 = makeAddr("sr3-a2");
        uint256 p = ZERO_INTEREST_PRINCIPAL;
        uint256 ordinaryTok = 101;

        mockNFT.mint(a1, ordinaryTok);
        loanToken.mint(a1, 1_000_000e6);
        loanToken.mint(a2, 1_000_000e6);
        vm.startPrank(a1);
        mockNFT.setApprovalForAll(address(nftProtocol), true);
        loanToken.approve(address(nftProtocol), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(a2);
        nftPositionNFT.setApprovalForAll(address(nftProtocol), true);
        loanToken.approve(address(nftProtocol), type(uint256).max);
        vm.stopPrank();

        uint256 a1Start = loanToken.balanceOf(a1);
        uint256 a2Start = loanToken.balanceOf(a2);
        uint256 lenderYStart = loanToken.balanceOf(lenderY);
        uint256 protoStart = loanToken.balanceOf(address(nftProtocol));
        uint256 t0 = vm.getBlockTimestamp();

        // Loan X: a1 borrows from a2 at zero interest. A floor bid (= principal) ends the auction
        // at once, so it is finalised without a time warp.
        vm.prank(a1);
        uint256 x = nftProtocol.createAuction(
            address(mockNFT), ordinaryTok, address(loanToken), p, p, 7 days, Y_AUCTION_DURATION, Y_BID_STEP
        );
        vm.prank(a2);
        nftProtocol.placeBid(x, p);
        nftProtocol.finalizeAuction(x);
        assertEq(nftProtocol.getLoan(x).repaymentAmount, p, "X not zero interest");
        uint256 l = nftPositionNFT.getLenderTokenId(x);
        assertEq(nftPositionNFT.ownerOf(l), a2);

        // Loan Y: a2 pledges X's lender position L; lenderY funds Y at zero interest
        vm.prank(a2);
        uint256 y = nftProtocol.createAuction(
            address(nftPositionNFT), l, address(loanToken), p, p, 30 days, Y_AUCTION_DURATION, Y_BID_STEP
        );
        vm.prank(lenderY);
        nftProtocol.placeBid(y, p);
        nftProtocol.finalizeAuction(y);
        assertEq(nftProtocol.getLoan(y).repaymentAmount, p, "Y not zero interest");
        assertEq(nftPositionNFT.ownerOf(l), address(nftProtocol), "L not held as Y's collateral");
        assertEq(_status(y), uint8(NFTLoanProtocol.LoanStatus.ACTIVE));

        // a1 repays X early: X's repayment goes to the holder of L (the protocol) and L is burned
        vm.prank(a1);
        nftProtocol.repayLoan(x);
        assertFalse(nftPositionNFT.exists(l), "L not burned");
        assertEq(mockNFT.ownerOf(ordinaryTok), a1, "X collateral not returned");

        // Y is still active and no time has passed: a2's repayLoan(Y) reverts on the burned L
        assertEq(vm.getBlockTimestamp(), t0, "time moved");
        assertEq(_status(y), uint8(NFTLoanProtocol.LoanStatus.ACTIVE));
        vm.prank(a2);
        vm.expectRevert(_nonexistent(l));
        nftProtocol.repayLoan(y);

        // After maturity plus grace, lenderY's claimCollateral(Y) reverts on the burned L
        vm.warp(_graceEnd(y));
        vm.prank(lenderY);
        vm.expectRevert(_nonexistent(l));
        nftProtocol.claimCollateral(y);

        int256 a1Net = _int(loanToken.balanceOf(a1)) - _int(a1Start);
        int256 a2Net = _int(loanToken.balanceOf(a2)) - _int(a2Start);
        uint256 lenderYLoss = lenderYStart - loanToken.balanceOf(lenderY);
        uint256 trapped = loanToken.balanceOf(address(nftProtocol)) - protoStart;

        assertEq(a1Net + a2Net, 0, "pair net not zero");
        assertEq(lenderYLoss, p, "lenderY loss");
        assertEq(trapped, p, "trapped amount");

        emit log("KI-4 reporter comparison (zero interest)");
        emit log_named_decimal_int("  a1 net (USDC)", a1Net, 6);
        emit log_named_decimal_int("  a2 net (USDC)", a2Net, 6);
        emit log_named_decimal_int("  a1 + a2 net (USDC)", a1Net + a2Net, 6);
        emit log_named_decimal_uint("  independent lender's loss on Y (USDC)", lenderYLoss, 6);
        emit log_named_decimal_uint("  trapped in NFTLoanProtocol (USDC)", trapped, 6);
    }
}

// ============================================================================
// Arbitrum One fork, live proxies (case 7 = case 1)
// ============================================================================

interface ISR3ERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

contract SR3Fork_PositionAsCollateral is Test, SR3Constants {
    /// @dev Block the fork result was recorded at (see the SR3 runbook ledger, Phase 1)
    uint256 internal constant SR3_FORK_BLOCK = 523_600_498;

    // Addresses: as SR2 (gavel-protocol-docs/operational/v1/deployments/arbitrum_mainnet.md)
    address internal constant LIVE_NFT_LOAN_PROTOCOL = 0x506e414c7D39639B2E9E318C46eD378AD51147eb;
    address internal constant LIVE_NFT_POSITION_NFT = 0x9A1728C87ac0456cCd882b5D5637e856be0fEec8;
    address internal constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    uint256 internal constant X_LOAN = 50_000e6;
    uint256 internal constant X_REPAY = 55_000e6;

    NFTLoanProtocol internal nlp = NFTLoanProtocol(LIVE_NFT_LOAN_PROTOCOL);
    NFTPositionNFT internal pnft = NFTPositionNFT(LIVE_NFT_POSITION_NFT);
    TestMockERC721 internal collection;

    address internal xBorrower = makeAddr("sr3-borrower");
    address internal xLender = makeAddr("sr3-lender");
    address internal yLender = makeAddr("sr3-lenderY");

    function setUp() public {
        string memory url = vm.envOr("ARB_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            vm.skip(true);
            return;
        }
        uint256 forkBlock = vm.envOr("SR3_FORK_BLOCK", SR3_FORK_BLOCK);
        vm.createSelectFork(url, forkBlock);
        assertEq(block.chainid, 42161);
        // On Arbitrum, block.number returns the L1 block; record the L2 fork block instead
        emit log_named_uint("Arbitrum One fork block", forkBlock);
        assertEq(address(nlp.positionNFT()), LIVE_NFT_POSITION_NFT);
        collection = new TestMockERC721("SR3 Collateral", "SR3");
    }

    function _fund(address who, uint256 amount) internal {
        deal(ARB_USDC, who, ISR3ERC20(ARB_USDC).balanceOf(who) + amount);
        vm.prank(who);
        ISR3ERC20(ARB_USDC).approve(LIVE_NFT_LOAN_PROTOCOL, type(uint256).max);
    }

    function _usdc(address who) internal view returns (uint256) {
        return ISR3ERC20(ARB_USDC).balanceOf(who);
    }

    function test_case7_fork_reportedPath() public {
        // Loan X: mock collection collateral, live USDC
        collection.mint(xBorrower, 1);
        vm.startPrank(xBorrower);
        collection.setApprovalForAll(LIVE_NFT_LOAN_PROTOCOL, true);
        uint256 x = nlp.createAuction(address(collection), 1, ARB_USDC, X_LOAN, X_REPAY, 30 days, 1 days, 100e6);
        vm.stopPrank();
        _fund(xLender, X_LOAN);
        vm.prank(xLender);
        nlp.placeBid(x, X_REPAY);
        vm.warp(nlp.getAuction(x).auctionEnd + 1);
        nlp.finalizeAuction(x);
        uint256 tok = pnft.getLenderTokenId(x);
        assertEq(pnft.ownerOf(tok), xLender);

        // Loan Y: X's lender position pledged as collateral
        vm.startPrank(xLender);
        pnft.setApprovalForAll(LIVE_NFT_LOAN_PROTOCOL, true);
        uint256 y = nlp.createAuction(address(pnft), tok, ARB_USDC, Y_LOAN, Y_REPAY, 30 days, 1 days, Y_BID_STEP);
        vm.stopPrank();
        _fund(yLender, Y_LOAN);
        vm.prank(yLender);
        nlp.placeBid(y, Y_REPAY);
        vm.warp(nlp.getAuction(y).auctionEnd + 1);
        nlp.finalizeAuction(y);
        assertEq(pnft.ownerOf(tok), LIVE_NFT_LOAN_PROTOCOL);

        // X repaid while Y is active
        _fund(xBorrower, X_REPAY);
        uint256 protoBefore = _usdc(LIVE_NFT_LOAN_PROTOCOL);
        uint256 lenderBefore = _usdc(xLender);
        vm.prank(xBorrower);
        nlp.repayLoan(x);
        assertEq(_usdc(LIVE_NFT_LOAN_PROTOCOL) - protoBefore, X_REPAY, "X repayment not trapped");
        assertEq(_usdc(xLender), lenderBefore, "X's lender was paid");
        assertEq(collection.ownerOf(1), xBorrower);
        vm.expectRevert(_nonexistent(tok));
        pnft.ownerOf(tok);

        // Y can be neither repaid nor claimed
        _fund(xLender, Y_REPAY);
        vm.prank(xLender);
        vm.expectRevert(_nonexistent(tok));
        nlp.repayLoan(y);

        vm.warp(nlp.getLoan(y).maturityTimestamp + nlp.GRACE_PERIOD());
        vm.prank(yLender);
        vm.expectRevert(_nonexistent(tok));
        nlp.claimCollateral(y);
        assertEq(uint8(nlp.getLoan(y).status), uint8(NFTLoanProtocol.LoanStatus.ACTIVE));
        assertEq(_usdc(LIVE_NFT_LOAN_PROTOCOL) - protoBefore, X_REPAY);
    }
}
