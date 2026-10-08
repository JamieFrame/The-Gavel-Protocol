// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/TestSetup.sol";
import "../utils/NFTTestSetup.sol";

// ============================================================================
// SR2 — independent reproduction of known issue KI-3
// ============================================================================
//
// KI-3  repayLoan pushes the repayment from the borrower directly to the current holder
//       of the lender position NFT. If the loan token refuses a transfer TO that holder,
//       every repayment reverts, and after maturity plus the grace period the holder
//       takes the full collateral with claimCollateral (which never moves the loan token).
//
// Whether a token refuses a transfer to a blocked address depends on the token. The two
// loan tokens on Arbitrum One were read from their Sourcify-verified implementations:
//
//   USDC   proxy 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
//          impl  0x86E721b43d4ECFa71119Dd38c0f938A75Fdb57B3 (FiatTokenV2_2)
//          role  blacklister()            function blacklist(address) / unBlacklist(address)
//          view  isBlacklisted(address)
//          transfer / transferFrom check msg.sender, from AND to
//          -> a blocked holder cannot be paid: KI-3 applies.
//
//   USD₮0  proxy 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
//          impl  0x3263cd783823d04a6b9819517e0e6840d37ca3f4 (ArbitrumExtensionV2 / TetherToken)
//          role  owner()                  function addToBlockedList(address) / removeFromBlockedList(address)
//          view  isBlocked(address)
//          _beforeTokenTransfer checks `from` only; transferFrom checks msg.sender only
//          -> a blocked holder CAN be paid; the repayment is frozen in the holder's
//             address (and can be destroyed by the owner via destroyBlockedFunds).
//             KI-3 does not apply. Both behaviours are asserted below.
//
//   cbBTC  proxy 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf
//          impl  0x7458bfdc30034eb860b265e6068121d18fa5aa72 (FiatTokenV2_1, Circle codebase)
//          role  blacklister(); same blocklist surface and transfer checks as USDC.
//          Used as collateral on the raw LoanProtocol only (cases 10-12).
//
// Cases 10-15 extend the runbook's list (operator request, 2026-10-08):
//   10-12  cbBTC collateral: holder blocked on the loan token only; holder blocked on the
//          collateral; borrower blocked on the collateral.
//   13     a blocked borrower moves the borrower position to an unblocked address.
//   14     the loan token's issuer pauses the whole token (USDC); USD₮0 has no such pause.
//   15     the holder sends the lender position to the loan token's own address: repayment
//          reverts on BOTH tokens and no one can claim (griefing at the holder's cost, no gain).
//
// Every case runs against BOTH stacks (LoanProtocol + PositionNFT, NFTLoanProtocol +
// NFTPositionNFT) and BOTH loan tokens:
//
//   SR2_<Stack>_<Token>        cases 1-15, local deployment, mock tokens that mirror the
//                              verified transfer checks of each token exactly.
//   SR2Fork_<Stack>_<Token>    cases 1-3 and 10-15, Arbitrum One fork: the live protocol proxies and
//                              the live tokens. An address is blocked by pranking the
//                              token's own blocklist role on the local fork. Nothing is
//                              sent to the network. Skipped unless ARB_RPC_URL is set;
//                              the fork block defaults to SR2_FORK_BLOCK and can be
//                              overridden with SR2_FORK_BLOCK (needs an archive endpoint
//                              once the block is old).
// ============================================================================

interface ISR2Market {
    function GRACE_PERIOD() external view returns (uint256);
    function owner() external view returns (address);
    function pause() external;
    function unpause() external;
    function placeBid(uint256, uint256) external;
    function finalizeAuction(uint256) external;
    function repayLoan(uint256) external;
    function claimCollateral(uint256) external;
    function listPosition(uint256, string calldata, address, uint256, uint256) external;
    function buyPosition(uint256, uint256, address) external;
}

interface ISR2PositionNFT {
    function ownerOf(uint256) external view returns (address);
    function transferFrom(address, address, uint256) external;
    function getLenderTokenId(uint256) external view returns (uint256);
    function getBorrowerTokenId(uint256) external view returns (uint256);
}

interface ISR2ERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

interface ISR2Mintable {
    function mint(address, uint256) external;
}

/// @dev USDC (FiatTokenV2_2) and cbBTC (FiatTokenV2_1) blocklist and pause surface
interface ISR2USDC {
    function blacklister() external view returns (address);
    function blacklist(address) external;
    function isBlacklisted(address) external view returns (bool);
    function pauser() external view returns (address);
    function pause() external;
}

/// @dev USD₮0 (TetherToken / WithBlockedList) blocklist surface
interface ISR2USDT0 {
    function owner() external view returns (address);
    function addToBlockedList(address) external;
    function isBlocked(address) external view returns (bool);
}

// ============================================================================
// Mock tokens: the transfer checks of the verified implementations, nothing more
// ============================================================================

/// @dev Mirrors FiatTokenV2_2 (USDC) and FiatTokenV2_1 (cbBTC): msg.sender, from and to are
///      all checked, and the pauser can pause every transfer and approval.
contract SR2MockUSDC {
    string public constant name = "USD Coin";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;
    address public blacklister;
    address public pauser;
    bool public paused;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) internal blacklisted;

    constructor() {
        blacklister = msg.sender;
        pauser = msg.sender;
        // FiatTokenV2_2.initializeV2_2 blacklists the token's own address; live USDC and cbBTC
        // both report isBlacklisted(self) == true
        blacklisted[address(this)] = true;
    }

    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "Blacklistable: account is blacklisted");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Pausable: paused");
        _;
    }

    function pause() external {
        require(msg.sender == pauser, "Pausable: caller is not the pauser");
        paused = true;
    }

    function blacklist(address account) external {
        require(msg.sender == blacklister, "Blacklistable: caller is not the blacklister");
        blacklisted[account] = true;
    }

    function isBlacklisted(address account) external view returns (bool) {
        return blacklisted[account];
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 value)
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(spender)
        returns (bool)
    {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value)
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        returns (bool)
    {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value)
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(from)
        notBlacklisted(to)
        returns (bool)
    {
        require(allowance[from][msg.sender] >= value, "ERC20: transfer amount exceeds allowance");
        allowance[from][msg.sender] -= value;
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "ERC20: transfer amount exceeds balance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
    }
}

/// @dev Mirrors TetherToken (USD₮0): only `from` (unless the owner sends) and, on
///      transferFrom, msg.sender are checked. The recipient is never checked.
contract SR2MockUSDT0 {
    string public constant name = unicode"USD₮0";
    string public constant symbol = unicode"USD₮0";
    uint8 public constant decimals = 6;
    address public owner;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public isBlocked;

    constructor() {
        owner = msg.sender;
    }

    function addToBlockedList(address user) external {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        isBlocked[user] = true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(!isBlocked[msg.sender], "Blocked: msg.sender is blocked");
        require(allowance[from][msg.sender] >= value, "ERC20: insufficient allowance");
        allowance[from][msg.sender] -= value;
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(!isBlocked[from] || msg.sender == owner, "TetherToken: from is blocked");
        require(to != address(this), "TetherToken: transfer to the contract address");
        require(balanceOf[from] >= value, "ERC20: transfer amount exceeds balance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
    }
}

// ============================================================================
// Base: hooks and helpers shared by every binding
// ============================================================================

abstract contract SR2Base is Test {
    uint256 internal constant SR2_COLLATERAL = 1e8; // 1 WBTC
    uint256 internal constant SR2_LOAN = 50_000e6;
    uint256 internal constant SR2_REPAY = 55_000e6;
    uint256 internal constant SR2_LOAN_DURATION = 30 days;
    uint256 internal constant SR2_AUCTION_DURATION = 1 days;
    uint256 internal constant SR2_BID_STEP = 100e6;
    uint256 internal constant SR2_ASK = 40_000e6;

    string internal constant USDC_BLOCKED = "Blacklistable: account is blacklisted";
    string internal constant USDT0_FROM_BLOCKED = "TetherToken: from is blocked";

    address internal sr2Lender = makeAddr("sr2-lender");
    address internal sr2Lender2 = makeAddr("sr2-lender2");
    address internal sr2Blocked = makeAddr("sr2-blocked");
    address internal sr2Clean = makeAddr("sr2-clean");
    address internal sr2Bidder = makeAddr("sr2-bidder");

    // ------------------------------------------------------------------------
    // Hooks
    // ------------------------------------------------------------------------

    /// @dev Token binding: true for a USDC-denominated loan, false for USD₮0
    function _loanIsUSDC() internal pure virtual returns (bool);

    // Environment binding (mock or fork)
    function _usdc() internal view virtual returns (address);
    function _usdt0() internal view virtual returns (address);
    function _cbbtc() internal view virtual returns (address);
    function _borrower() internal view virtual returns (address);
    function _fund(address token, address who, uint256 amount) internal virtual;

    // Stack binding (LoanProtocol or NFTLoanProtocol)
    function _market() internal view virtual returns (ISR2Market);
    function _pnft() internal view virtual returns (ISR2PositionNFT);
    function _openAuction(address loanToken) internal virtual returns (uint256 auctionId);
    function _collateralBalance(address who, uint256 loanId) internal view virtual returns (uint256);
    function _collateralAmount(uint256 loanId) internal view virtual returns (uint256);
    function _maturity(uint256 loanId) internal view virtual returns (uint256);
    function _repaymentAmount(uint256 loanId) internal view virtual returns (uint256);
    function _loanAmount(uint256 loanId) internal view virtual returns (uint256);

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------

    function _loanToken() internal view returns (address) {
        return _loanIsUSDC() ? _usdc() : _usdt0();
    }

    function _otherToken() internal view returns (address) {
        return _loanIsUSDC() ? _usdt0() : _usdc();
    }

    /// @dev Whether the loan token refuses a transfer to a blocked recipient
    function _blocksRecipient() internal pure returns (bool) {
        return _loanIsUSDC();
    }

    /// @dev Revert reason when a blocked address is the sender of a transfer
    function _senderBlockedReason() internal pure returns (bytes memory) {
        return bytes(_loanIsUSDC() ? USDC_BLOCKED : USDT0_FROM_BLOCKED);
    }

    /// @dev Block `who` on `token` by pranking the token's own blocklist role
    function _block(address token, address who) internal {
        if (token == _usdt0()) {
            vm.prank(ISR2USDT0(token).owner());
            ISR2USDT0(token).addToBlockedList(who);
            assertTrue(ISR2USDT0(token).isBlocked(who));
        } else {
            // USDC and cbBTC (Circle codebase)
            vm.prank(ISR2USDC(token).blacklister());
            ISR2USDC(token).blacklist(who);
            assertTrue(ISR2USDC(token).isBlacklisted(who));
        }
    }

    function _balance(address token, address who) internal view returns (uint256) {
        return ISR2ERC20(token).balanceOf(who);
    }

    function _lenderTokenId(uint256 loanId) internal view returns (uint256) {
        return _pnft().getLenderTokenId(loanId);
    }

    function _holder(uint256 loanId) internal view returns (address) {
        return _pnft().ownerOf(_lenderTokenId(loanId));
    }

    /// @dev Auction -> winning bid at SR2_REPAY by `lenderAddr` -> active loan. The borrower is
    ///      then funded and approved for the repayment, before any address is blocked.
    function _newLoan(address lenderAddr) internal returns (uint256 loanId) {
        loanId = _finaliseLoan(_openAuction(_loanToken()), lenderAddr);
    }

    function _finaliseLoan(uint256 auctionId, address lenderAddr) internal returns (uint256 loanId) {
        address token = _loanToken();
        loanId = auctionId;

        _fund(token, lenderAddr, SR2_LOAN);
        vm.startPrank(lenderAddr);
        ISR2ERC20(token).approve(address(_market()), type(uint256).max);
        _market().placeBid(loanId, SR2_REPAY);
        vm.stopPrank();

        vm.warp(block.timestamp + SR2_AUCTION_DURATION + 1);
        _market().finalizeAuction(loanId);
        assertEq(_holder(loanId), lenderAddr);

        _fund(token, _borrower(), SR2_REPAY);
        vm.prank(_borrower());
        ISR2ERC20(token).approve(address(_market()), type(uint256).max);
    }

    function _repay(uint256 loanId) internal {
        vm.prank(_borrower());
        _market().repayLoan(loanId);
    }

    function _expectRepayBlocked(uint256 loanId) internal {
        vm.prank(_borrower());
        vm.expectRevert(bytes(USDC_BLOCKED));
        _market().repayLoan(loanId);
    }

    /// @dev Repays and asserts the holder is paid in full and the collateral returns to the borrower
    function _repayAndAssertSettled(uint256 loanId) internal {
        address token = _loanToken();
        address holder = _holder(loanId);
        uint256 holderBefore = _balance(token, holder);
        uint256 collBefore = _collateralBalance(_borrower(), loanId);
        _repay(loanId);
        assertEq(_balance(token, holder), holderBefore + _repaymentAmount(loanId), "holder not paid");
        assertEq(
            _collateralBalance(_borrower(), loanId), collBefore + _collateralAmount(loanId), "collateral not returned"
        );
    }

    function _graceEnd(uint256 loanId) internal view returns (uint256) {
        return _maturity(loanId) + _market().GRACE_PERIOD();
    }
}

// ============================================================================
// Cases 1-3 (mock and fork)
// ============================================================================

abstract contract SR2CoreCases is SR2Base {
    /// Case 1 — control: nothing blocked, repayment settles
    function test_case1_control_repaySettles() public {
        uint256 loanId = _newLoan(sr2Lender);
        _repayAndAssertSettled(loanId);
    }

    /// Case 2 — the lender-position holder is blocked on the loan token
    function test_case2_blockedHolder_repay() public {
        uint256 loanId = _newLoan(sr2Lender);
        _block(_loanToken(), sr2Lender);

        uint256[3] memory at = [block.timestamp, _maturity(loanId), _graceEnd(loanId) - 1];
        for (uint256 i = 0; i < at.length; i++) {
            uint256 snap = vm.snapshotState();
            vm.warp(at[i]);
            if (_blocksRecipient()) {
                // USDC: every repayment reverts, from loan start to the last second of grace
                _expectRepayBlocked(loanId);
            } else {
                // USD₮0: the repayment reaches the blocked holder and the collateral returns
                _repayAndAssertSettled(loanId);
                // ... where it is frozen: the blocked holder cannot move it
                vm.prank(sr2Lender);
                vm.expectRevert(bytes(USDT0_FROM_BLOCKED));
                ISR2ERC20(_loanToken()).transfer(sr2Clean, 1);
            }
            vm.revertToState(snap);
        }
    }

    /// Case 3 — after the grace period the blocked holder takes the collateral (USDC);
    ///          with USD₮0 the borrower repays in the last second and keeps it
    function test_case3_seizureAfterGrace() public {
        uint256 loanId = _newLoan(sr2Lender);
        address token = _loanToken();
        _block(token, sr2Lender);

        uint256 borrowerColl = _collateralBalance(_borrower(), loanId);
        uint256 holderColl = _collateralBalance(sr2Lender, loanId);
        uint256 holderCash = _balance(token, sr2Lender);

        vm.warp(_graceEnd(loanId) - 1);
        if (_blocksRecipient()) {
            _expectRepayBlocked(loanId);

            vm.warp(_graceEnd(loanId));
            vm.prank(sr2Lender);
            _market().claimCollateral(loanId);

            assertEq(_collateralBalance(sr2Lender, loanId), holderColl + _collateralAmount(loanId));
            assertEq(_collateralBalance(_borrower(), loanId), borrowerColl);
            assertEq(_balance(token, sr2Lender), holderCash, "holder was paid");

            emit log("KI-3 seizure (USDC): borrower net position");
            emit log_named_decimal_uint("  loan amount kept (USDC)", _loanAmount(loanId), 6);
            emit log_named_decimal_uint("  repayment never paid (USDC)", _repaymentAmount(loanId), 6);
            emit log_named_uint("  collateral lost (units: sats, or 1 NFT)", _collateralAmount(loanId));
        } else {
            _repayAndAssertSettled(loanId);
            vm.warp(_graceEnd(loanId));
            vm.prank(sr2Lender);
            vm.expectRevert(bytes4(keccak256("LoanNotActive()")));
            _market().claimCollateral(loanId);
        }
    }
}

// ============================================================================
// Cases 4-9 (mock)
// ============================================================================

abstract contract SR2MoreCases is SR2Base {
    /// Case 4 — deliberate path: a clean lender moves the position to an already-blocked address
    function test_case4_deliberateTransferToBlockedAddress() public {
        _block(_loanToken(), sr2Blocked);
        uint256 loanId = _newLoan(sr2Lender);
        ISR2PositionNFT pnft = _pnft();
        uint256 lenderTokenId = _lenderTokenId(loanId);

        vm.prank(sr2Lender);
        pnft.transferFrom(sr2Lender, sr2Blocked, lenderTokenId);
        assertEq(_holder(loanId), sr2Blocked);

        if (_blocksRecipient()) {
            _expectRepayBlocked(loanId);
            vm.warp(_graceEnd(loanId) - 1);
            _expectRepayBlocked(loanId);

            uint256 before = _collateralBalance(sr2Blocked, loanId);
            vm.warp(_graceEnd(loanId));
            vm.prank(sr2Blocked);
            _market().claimCollateral(loanId);
            assertEq(_collateralBalance(sr2Blocked, loanId), before + _collateralAmount(loanId));
        } else {
            _repayAndAssertSettled(loanId);
        }
    }

    /// Case 5 — cure: the blocked holder moves the position to a clean address
    function test_case5_cureByTransferToCleanAddress() public {
        uint256 loanId = _newLoan(sr2Lender);
        _block(_loanToken(), sr2Lender);
        if (_blocksRecipient()) _expectRepayBlocked(loanId);
        ISR2PositionNFT pnft = _pnft();
        uint256 lenderTokenId = _lenderTokenId(loanId);

        vm.prank(sr2Lender);
        pnft.transferFrom(sr2Lender, sr2Clean, lenderTokenId);
        assertEq(_holder(loanId), sr2Clean);

        _repayAndAssertSettled(loanId);
    }

    /// Case 6 — pause: a standstill for both sides; deadlines freeze and resume after unpause
    function test_case6_pauseFreezesBothSides() public {
        uint256 loanId = _newLoan(sr2Lender);
        _block(_loanToken(), sr2Lender);
        uint256 grace = _market().GRACE_PERIOD();
        address owner = _market().owner();
        bytes4 paused = bytes4(keccak256("EnforcedPause()"));

        // Pause half-way through the grace period
        vm.warp(_maturity(loanId) + grace / 2);
        vm.prank(owner);
        _market().pause();

        // Well past the unpaused grace end, both paths are blocked by the pause
        vm.warp(_graceEnd(loanId) + 10 days);
        vm.prank(_borrower());
        vm.expectRevert(paused);
        _market().repayLoan(loanId);
        vm.prank(sr2Lender);
        vm.expectRevert(paused);
        _market().claimCollateral(loanId);

        vm.prank(owner);
        _market().unpause();
        uint256 resumedAt = block.timestamp;

        // The deadline did not advance: half the grace period remains
        vm.prank(sr2Lender);
        vm.expectRevert(bytes4(keccak256("GracePeriodNotEnded()")));
        _market().claimCollateral(loanId);

        if (_blocksRecipient()) {
            vm.warp(resumedAt + (grace - grace / 2) - 1);
            _expectRepayBlocked(loanId);
            vm.prank(sr2Lender);
            vm.expectRevert(bytes4(keccak256("GracePeriodNotEnded()")));
            _market().claimCollateral(loanId);

            // Case 3 still holds once the remaining grace has run
            uint256 before = _collateralBalance(sr2Lender, loanId);
            vm.warp(resumedAt + (grace - grace / 2));
            vm.prank(sr2Lender);
            _market().claimCollateral(loanId);
            assertEq(_collateralBalance(sr2Lender, loanId), before + _collateralAmount(loanId));
        } else {
            _repayAndAssertSettled(loanId);
        }
    }

    /// Case 7a — a blocked address cannot bid in the token that blocks it
    function test_case7_blockedBidderCannotPlaceBid() public {
        address token = _loanToken();
        uint256 auctionId = _openAuction(token);
        _fund(token, sr2Bidder, SR2_LOAN);
        vm.prank(sr2Bidder);
        ISR2ERC20(token).approve(address(_market()), type(uint256).max);
        _block(token, sr2Bidder);

        vm.prank(sr2Bidder);
        vm.expectRevert(_senderBlockedReason());
        _market().placeBid(auctionId, SR2_REPAY);
    }

    /// Case 7b — a blocked address CAN acquire a lender position through the marketplace when
    ///           the listing's payment token is a different token
    function test_case7_blockedBuyerAcquiresViaOtherPaymentToken() public {
        uint256 loanId = _newLoan(sr2Lender);
        address other = _otherToken();

        _fund(other, sr2Blocked, SR2_ASK);
        vm.prank(sr2Blocked);
        ISR2ERC20(other).approve(address(_market()), type(uint256).max);
        _block(_loanToken(), sr2Blocked);

        vm.prank(sr2Lender);
        _market().listPosition(loanId, "lender", other, SR2_ASK, 0);

        uint256 sellerBefore = _balance(other, sr2Lender);
        uint256 lenderTokenId = _lenderTokenId(loanId);
        vm.prank(sr2Blocked);
        _market().buyPosition(lenderTokenId, SR2_ASK, other);

        assertEq(_holder(loanId), sr2Blocked, "blocked address did not acquire the position");
        assertEq(_balance(other, sr2Lender), sellerBefore + SR2_ASK);

        if (_blocksRecipient()) _expectRepayBlocked(loanId);
        else _repayAndAssertSettled(loanId);
    }

    /// Case 7c — the same purchase in the loan token is refused for the blocked buyer
    function test_case7_blockedBuyerCannotPayInLoanToken() public {
        uint256 loanId = _newLoan(sr2Lender);
        address token = _loanToken();

        _fund(token, sr2Blocked, SR2_ASK);
        vm.prank(sr2Blocked);
        ISR2ERC20(token).approve(address(_market()), type(uint256).max);
        _block(token, sr2Blocked);

        vm.prank(sr2Lender);
        _market().listPosition(loanId, "lender", token, SR2_ASK, 0);

        uint256 lenderTokenId = _lenderTokenId(loanId);
        vm.prank(sr2Blocked);
        vm.expectRevert(_senderBlockedReason());
        _market().buyPosition(lenderTokenId, SR2_ASK, token);
        assertEq(_holder(loanId), sr2Lender);
    }

    /// Case 8 — isolation: a loan with an unblocked holder repays normally alongside
    function test_case8_isolation() public {
        uint256 affected = _newLoan(sr2Lender);
        uint256 unaffected = _newLoan(sr2Lender2);
        _block(_loanToken(), sr2Lender);

        _repayAndAssertSettled(unaffected);

        if (_blocksRecipient()) _expectRepayBlocked(affected);
        else _repayAndAssertSettled(affected);
    }

    /// Case 9 — a borrower blocked on the loan token cannot repay (the borrower's own
    ///          dependency, distinct from KI-3; true for both tokens)
    function test_case9_blockedBorrowerCannotRepay() public {
        uint256 loanId = _newLoan(sr2Lender);
        _block(_loanToken(), _borrower());

        vm.prank(_borrower());
        vm.expectRevert(_senderBlockedReason());
        _market().repayLoan(loanId);
    }
}

// ============================================================================
// Cases 13-15 (mock and fork, both stacks)
// ============================================================================

abstract contract SR2ExtraCases is SR2Base {
    /// Case 13 — a borrower blocked on the loan token moves the borrower position to an
    ///           unblocked address, which repays and receives the collateral
    function test_case13_blockedBorrowerMovesPosition() public {
        uint256 loanId = _newLoan(sr2Lender);
        address token = _loanToken();
        uint256 repayment = _repaymentAmount(loanId);
        uint256 collateral = _collateralAmount(loanId);
        _block(token, _borrower());

        vm.prank(_borrower());
        vm.expectRevert(_senderBlockedReason());
        _market().repayLoan(loanId);

        ISR2PositionNFT pnft = _pnft();
        uint256 borrowerTokenId = pnft.getBorrowerTokenId(loanId);
        vm.prank(_borrower());
        pnft.transferFrom(_borrower(), sr2Clean, borrowerTokenId);

        _fund(token, sr2Clean, repayment);
        vm.prank(sr2Clean);
        ISR2ERC20(token).approve(address(_market()), type(uint256).max);

        uint256 holderBefore = _balance(token, sr2Lender);
        uint256 collBefore = _collateralBalance(sr2Clean, loanId);
        vm.prank(sr2Clean);
        _market().repayLoan(loanId);
        assertEq(_balance(token, sr2Lender), holderBefore + repayment, "holder not paid");
        assertEq(_collateralBalance(sr2Clean, loanId), collBefore + collateral, "collateral not to new holder");
    }

    /// Case 14 — the issuer pauses the whole loan token (USDC): no USDC loan can be repaid,
    ///           while claimCollateral (which moves only collateral) still works.
    ///           USD₮0 has no token-wide pause.
    function test_case14_issuerPausesLoanToken() public {
        uint256 loanId = _newLoan(sr2Lender);
        address token = _loanToken();

        if (!_loanIsUSDC()) {
            address tetherOwner = ISR2USDT0(token).owner();
            vm.prank(tetherOwner);
            (bool ok,) = token.call(abi.encodeWithSignature("pause()"));
            assertFalse(ok, unicode"USD₮0 exposes pause()");
            _repayAndAssertSettled(loanId);
            return;
        }

        vm.warp(_maturity(loanId));
        address pauserRole = ISR2USDC(token).pauser();
        vm.prank(pauserRole);
        ISR2USDC(token).pause();

        vm.warp(_graceEnd(loanId) - 1);
        vm.prank(_borrower());
        vm.expectRevert(bytes("Pausable: paused"));
        _market().repayLoan(loanId);

        uint256 before = _collateralBalance(sr2Lender, loanId);
        vm.warp(_graceEnd(loanId));
        vm.prank(sr2Lender);
        _market().claimCollateral(loanId);
        assertEq(_collateralBalance(sr2Lender, loanId), before + _collateralAmount(loanId));
    }

    /// Case 15 — griefing without gain: the holder sends the lender position to the loan token's
    ///           own contract address, which every loan token here refuses to pay (USD₮0 by its
    ///           to != address(this) check, USDC because it blocklists itself). Repayment reverts
    ///           on BOTH tokens, and no one can ever claim: the collateral stays in the protocol.
    function test_case15_lenderPositionSentToTokenContract() public {
        uint256 loanId = _newLoan(sr2Lender);
        address token = _loanToken();
        ISR2PositionNFT pnft = _pnft();
        uint256 lenderTokenId = _lenderTokenId(loanId);

        vm.prank(sr2Lender);
        pnft.transferFrom(sr2Lender, token, lenderTokenId);
        assertEq(_holder(loanId), token);

        vm.prank(_borrower());
        vm.expectRevert(
            _loanIsUSDC() ? bytes(USDC_BLOCKED) : bytes("TetherToken: transfer to the contract address")
        );
        _market().repayLoan(loanId);

        // The former lender cannot claim, and the token contract never will
        vm.warp(_graceEnd(loanId));
        vm.prank(sr2Lender);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        _market().claimCollateral(loanId);
        assertGe(_collateralBalance(address(_market()), loanId), _collateralAmount(loanId), "collateral left");
    }
}

// ============================================================================
// Stack bindings
// ============================================================================

abstract contract SR2LoanStack is SR2Base {
    function _lp() internal view virtual returns (LoanProtocol);
    function _wbtc() internal view virtual returns (address);

    function _market() internal view override returns (ISR2Market) {
        return ISR2Market(address(_lp()));
    }

    function _pnft() internal view override returns (ISR2PositionNFT) {
        return ISR2PositionNFT(address(_lp().positionNFT()));
    }

    function _openAuction(address loanToken) internal override returns (uint256 auctionId) {
        auctionId = _openAuctionWith(_wbtc(), loanToken);
    }

    function _openAuctionWith(address collateral, address loanToken) internal returns (uint256 auctionId) {
        _fund(collateral, _borrower(), SR2_COLLATERAL);
        vm.startPrank(_borrower());
        ISR2ERC20(collateral).approve(address(_lp()), type(uint256).max);
        _lp().depositCollateral(collateral, SR2_COLLATERAL);
        auctionId = _lp().createAuction(
            collateral,
            SR2_COLLATERAL,
            loanToken,
            SR2_LOAN,
            SR2_REPAY,
            SR2_LOAN_DURATION,
            SR2_AUCTION_DURATION,
            SR2_BID_STEP
        );
        vm.stopPrank();
    }

    function _collateralBalance(address who, uint256) internal view override returns (uint256) {
        return _balance(_wbtc(), who);
    }

    function _collateralAmount(uint256 loanId) internal view override returns (uint256) {
        return _lp().getLoan(loanId).collateralAmount;
    }

    function _maturity(uint256 loanId) internal view override returns (uint256) {
        return _lp().getLoan(loanId).maturityTimestamp;
    }

    function _repaymentAmount(uint256 loanId) internal view override returns (uint256) {
        return _lp().getLoan(loanId).repaymentAmount;
    }

    function _loanAmount(uint256 loanId) internal view override returns (uint256) {
        return _lp().getLoan(loanId).loanAmount;
    }
}

abstract contract SR2NFTStack is SR2Base {
    uint256 private sr2NextNft = 1_000;
    mapping(uint256 => uint256) private sr2NftOf;

    function _nlp() internal view virtual returns (NFTLoanProtocol);
    function _collection() internal view virtual returns (TestMockERC721);

    function _market() internal view override returns (ISR2Market) {
        return ISR2Market(address(_nlp()));
    }

    function _pnft() internal view override returns (ISR2PositionNFT) {
        return ISR2PositionNFT(address(_nlp().positionNFT()));
    }

    function _openAuction(address loanToken) internal override returns (uint256 auctionId) {
        uint256 nftId = sr2NextNft++;
        _collection().mint(_borrower(), nftId);
        vm.startPrank(_borrower());
        _collection().setApprovalForAll(address(_nlp()), true);
        auctionId = _nlp().createAuction(
            address(_collection()),
            nftId,
            loanToken,
            SR2_LOAN,
            SR2_REPAY,
            SR2_LOAN_DURATION,
            SR2_AUCTION_DURATION,
            SR2_BID_STEP
        );
        vm.stopPrank();
        sr2NftOf[auctionId] = nftId;
    }

    /// @dev 1 if `who` holds this loan's collateral NFT, else 0
    function _collateralBalance(address who, uint256 loanId) internal view override returns (uint256) {
        return _collection().ownerOf(sr2NftOf[loanId]) == who ? 1 : 0;
    }

    function _collateralAmount(uint256) internal pure override returns (uint256) {
        return 1;
    }

    function _maturity(uint256 loanId) internal view override returns (uint256) {
        return _nlp().getLoan(loanId).maturityTimestamp;
    }

    function _repaymentAmount(uint256 loanId) internal view override returns (uint256) {
        return _nlp().getLoan(loanId).repaymentAmount;
    }

    function _loanAmount(uint256 loanId) internal view override returns (uint256) {
        return _nlp().getLoan(loanId).loanAmount;
    }
}

// ============================================================================
// Cases 10-12: cbBTC collateral (LoanProtocol only; mock and fork)
// ============================================================================

abstract contract SR2CollateralCases is SR2LoanStack {
    function _newCbbtcLoan(address lenderAddr) internal returns (uint256) {
        return _finaliseLoan(_openAuctionWith(_cbbtc(), _loanToken()), lenderAddr);
    }

    /// Case 10 — cbBTC collateral, holder blocked on the loan token only: KI-3 holds on USDC
    ///           (the holder still claims the cbBTC); USD₮0 repays normally
    function test_case10_cbBTC_holderBlockedOnLoanTokenOnly() public {
        uint256 loanId = _newCbbtcLoan(sr2Lender);
        _block(_loanToken(), sr2Lender);

        if (_blocksRecipient()) {
            _expectRepayBlocked(loanId);
            vm.warp(_graceEnd(loanId) - 1);
            _expectRepayBlocked(loanId);

            uint256 before = _balance(_cbbtc(), sr2Lender);
            vm.warp(_graceEnd(loanId));
            vm.prank(sr2Lender);
            _market().claimCollateral(loanId);
            assertEq(_balance(_cbbtc(), sr2Lender), before + SR2_COLLATERAL, "cbBTC not seized");
        } else {
            uint256 before = _balance(_cbbtc(), _borrower());
            _repay(loanId);
            assertEq(_balance(_cbbtc(), _borrower()), before + SR2_COLLATERAL);
        }
    }

    /// Case 11 — cbBTC collateral, holder blocked on the loan token AND on cbBTC: the claim
    ///           reverts, but moving the lender position to an unblocked address after the
    ///           grace period lets it claim. The incentive remains.
    function test_case11_cbBTC_holderBlockedOnCollateral() public {
        uint256 loanId = _newCbbtcLoan(sr2Lender);
        _block(_loanToken(), sr2Lender);
        _block(_cbbtc(), sr2Lender);

        if (_blocksRecipient()) {
            _expectRepayBlocked(loanId);
        } else {
            // USD₮0: the borrower can still repay; the holder's cbBTC status matters only on default
            uint256 snap = vm.snapshotState();
            uint256 collBefore = _balance(_cbbtc(), _borrower());
            _repay(loanId);
            assertEq(_balance(_cbbtc(), _borrower()), collBefore + SR2_COLLATERAL);
            vm.revertToState(snap);
        }

        vm.warp(_graceEnd(loanId));
        vm.prank(sr2Lender);
        vm.expectRevert(bytes(USDC_BLOCKED));
        _market().claimCollateral(loanId);

        ISR2PositionNFT pnft = _pnft();
        uint256 lenderTokenId = _lenderTokenId(loanId);
        vm.prank(sr2Lender);
        pnft.transferFrom(sr2Lender, sr2Clean, lenderTokenId);

        uint256 before = _balance(_cbbtc(), sr2Clean);
        vm.prank(sr2Clean);
        _market().claimCollateral(loanId);
        assertEq(_balance(_cbbtc(), sr2Clean), before + SR2_COLLATERAL, "routed claim failed");
    }

    /// Case 12 — cbBTC collateral, borrower blocked on cbBTC: the whole repayment reverts (the
    ///           loan-token payment unwinds with it), and the lender claims on default
    function test_case12_cbBTC_borrowerBlockedOnCollateral() public {
        uint256 loanId = _newCbbtcLoan(sr2Lender);
        _block(_cbbtc(), _borrower());
        uint256 holderCash = _balance(_loanToken(), sr2Lender);

        vm.prank(_borrower());
        vm.expectRevert(bytes(USDC_BLOCKED));
        _market().repayLoan(loanId);
        assertEq(_balance(_loanToken(), sr2Lender), holderCash, "payment did not unwind");

        uint256 before = _balance(_cbbtc(), sr2Lender);
        vm.warp(_graceEnd(loanId));
        vm.prank(sr2Lender);
        _market().claimCollateral(loanId);
        assertEq(_balance(_cbbtc(), sr2Lender), before + SR2_COLLATERAL);
    }
}

// ============================================================================
// Environment: local deployment with mock tokens (cases 1-15)
// ============================================================================

abstract contract SR2MockLoan is TestSetup, SR2LoanStack, SR2CoreCases, SR2MoreCases, SR2ExtraCases, SR2CollateralCases {
    SR2MockUSDC internal mockUSDC;
    SR2MockUSDT0 internal mockUSDT0;
    /// @dev cbBTC has the same blocklist checks as USDC (Circle codebase)
    SR2MockUSDC internal mockCbBTC;

    function setUp() public override {
        super.setUp();
        mockUSDC = new SR2MockUSDC();
        mockUSDT0 = new SR2MockUSDT0();
        mockCbBTC = new SR2MockUSDC();
    }

    function _cbbtc() internal view override returns (address) {
        return address(mockCbBTC);
    }

    function _lp() internal view override returns (LoanProtocol) {
        return protocol;
    }

    function _wbtc() internal view override returns (address) {
        return address(collateralToken);
    }

    function _usdc() internal view override returns (address) {
        return address(mockUSDC);
    }

    function _usdt0() internal view override returns (address) {
        return address(mockUSDT0);
    }

    function _borrower() internal view override returns (address) {
        return borrower;
    }

    function _fund(address token, address who, uint256 amount) internal override {
        ISR2Mintable(token).mint(who, amount);
    }
}

abstract contract SR2MockNFT is NFTTestSetup, SR2NFTStack, SR2CoreCases, SR2MoreCases, SR2ExtraCases {
    SR2MockUSDC internal mockUSDC;
    SR2MockUSDT0 internal mockUSDT0;

    function setUp() public override {
        super.setUp();
        mockUSDC = new SR2MockUSDC();
        mockUSDT0 = new SR2MockUSDT0();
    }

    /// @dev Unused: this stack takes NFT collateral
    function _cbbtc() internal pure override returns (address) {
        return address(0);
    }

    function _nlp() internal view override returns (NFTLoanProtocol) {
        return nftProtocol;
    }

    function _collection() internal view override returns (TestMockERC721) {
        return mockNFT;
    }

    function _usdc() internal view override returns (address) {
        return address(mockUSDC);
    }

    function _usdt0() internal view override returns (address) {
        return address(mockUSDT0);
    }

    function _borrower() internal view override returns (address) {
        return borrower;
    }

    function _fund(address token, address who, uint256 amount) internal override {
        ISR2Mintable(token).mint(who, amount);
    }
}

contract SR2_LoanProtocol_USDC is SR2MockLoan {
    function _loanIsUSDC() internal pure override returns (bool) {
        return true;
    }
}

contract SR2_LoanProtocol_USDT0 is SR2MockLoan {
    function _loanIsUSDC() internal pure override returns (bool) {
        return false;
    }
}

contract SR2_NFTLoanProtocol_USDC is SR2MockNFT {
    function _loanIsUSDC() internal pure override returns (bool) {
        return true;
    }
}

contract SR2_NFTLoanProtocol_USDT0 is SR2MockNFT {
    function _loanIsUSDC() internal pure override returns (bool) {
        return false;
    }
}

// ============================================================================
// Environment: Arbitrum One fork, live proxies and live tokens (cases 1-3)
// ============================================================================

abstract contract SR2Fork is SR2Base {
    /// @dev Block the fork results were recorded at (see the SR2 runbook outcome field)
    uint256 internal constant SR2_FORK_BLOCK = 512_825_781;

    // Addresses: gavel-protocol-docs/operational/v1/deployments/arbitrum_mainnet.md
    address internal constant LIVE_LOAN_PROTOCOL = 0xFCDd6Ef75638D8D19ad634004C234Ad18751fEf2;
    address internal constant LIVE_POSITION_NFT = 0xAD6Edb72409605a51dc6C990A09829616178A8f4;
    address internal constant LIVE_NFT_LOAN_PROTOCOL = 0x506e414c7D39639B2E9E318C46eD378AD51147eb;
    address internal constant LIVE_NFT_POSITION_NFT = 0x9A1728C87ac0456cCd882b5D5637e856be0fEec8;
    address internal constant ARB_WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address internal constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant ARB_USDT0 = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    // gavel-protocol-docs/canonical/overview.md
    address internal constant ARB_CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    address internal sr2ForkBorrower = makeAddr("sr2-borrower");

    function _selectFork() internal returns (bool) {
        string memory url = vm.envOr("ARB_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            vm.skip(true);
            return false;
        }
        uint256 forkBlock = vm.envOr("SR2_FORK_BLOCK", SR2_FORK_BLOCK);
        vm.createSelectFork(url, forkBlock);
        assertEq(block.chainid, 42161);
        // On Arbitrum, block.number returns the L1 block; record the L2 fork block instead
        emit log_named_uint("Arbitrum One fork block", forkBlock);
        return true;
    }

    function _usdc() internal pure override returns (address) {
        return ARB_USDC;
    }

    function _usdt0() internal pure override returns (address) {
        return ARB_USDT0;
    }

    function _cbbtc() internal pure override returns (address) {
        return ARB_CBBTC;
    }

    function _borrower() internal view override returns (address) {
        return sr2ForkBorrower;
    }

    function _fund(address token, address who, uint256 amount) internal override {
        deal(token, who, _balance(token, who) + amount);
    }
}

abstract contract SR2ForkLoan is SR2Fork, SR2LoanStack, SR2CoreCases, SR2ExtraCases, SR2CollateralCases {
    function setUp() public {
        if (!_selectFork()) return;
        assertEq(address(LoanProtocol(LIVE_LOAN_PROTOCOL).positionNFT()), LIVE_POSITION_NFT);
    }

    function _lp() internal pure override returns (LoanProtocol) {
        return LoanProtocol(LIVE_LOAN_PROTOCOL);
    }

    function _wbtc() internal pure override returns (address) {
        return ARB_WBTC;
    }
}

abstract contract SR2ForkNFT is SR2Fork, SR2NFTStack, SR2CoreCases, SR2ExtraCases {
    TestMockERC721 internal forkCollection;

    function setUp() public {
        if (!_selectFork()) return;
        assertEq(address(NFTLoanProtocol(LIVE_NFT_LOAN_PROTOCOL).positionNFT()), LIVE_NFT_POSITION_NFT);
        forkCollection = new TestMockERC721("SR2 Collateral", "SR2");
    }

    function _nlp() internal pure override returns (NFTLoanProtocol) {
        return NFTLoanProtocol(LIVE_NFT_LOAN_PROTOCOL);
    }

    function _collection() internal view override returns (TestMockERC721) {
        return forkCollection;
    }
}

contract SR2Fork_LoanProtocol_USDC is SR2ForkLoan {
    function _loanIsUSDC() internal pure override returns (bool) {
        return true;
    }
}

contract SR2Fork_LoanProtocol_USDT0 is SR2ForkLoan {
    function _loanIsUSDC() internal pure override returns (bool) {
        return false;
    }
}

contract SR2Fork_NFTLoanProtocol_USDC is SR2ForkNFT {
    function _loanIsUSDC() internal pure override returns (bool) {
        return true;
    }
}

contract SR2Fork_NFTLoanProtocol_USDT0 is SR2ForkNFT {
    function _loanIsUSDC() internal pure override returns (bool) {
        return false;
    }
}
