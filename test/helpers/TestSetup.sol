// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Import actual contracts
import "../../contracts/LoanProtocol.sol";
import "../../contracts/PositionNFT.sol";

// ============================================================================
// MOCK ERC20 FOR TESTING
// ============================================================================

contract TestMockERC20 is Test {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "ERC20: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "ERC20: insufficient balance");
        if (msg.sender != from) {
            require(allowance[from][msg.sender] >= amount, "ERC20: insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// ============================================================================
// MINIMAL ERC1967 PROXY FOR TESTING
// ============================================================================

contract ERC1967Proxy {
    bytes32 private constant _IMPLEMENTATION_SLOT = 
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    constructor(address implementation, bytes memory data) {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, implementation)
        }
        if (data.length > 0) {
            (bool success,) = implementation.delegatecall(data);
            require(success, "Proxy: init failed");
        }
    }
    
    fallback() external payable {
        assembly {
            let impl := sload(_IMPLEMENTATION_SLOT)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

// ============================================================================
// BASE TEST SETUP
// ============================================================================

/**
 * @title TestSetup
 * @notice Base test contract that deploys LoanProtocol + PositionNFT via proxies
 * @dev All unit test contracts inherit from this
 *
 * Deployed contracts:
 *   - protocol: LoanProtocol (upgradeable proxy)
 *   - positionNFT: PositionNFT (upgradeable proxy)
 *   - collateralToken: MockERC20 "WBTC" (8 decimals)
 *   - loanToken: MockERC20 "USDC" (6 decimals)
 *
 * Test actors:
 *   - deployer (this contract) = protocol owner
 *   - borrower:  funded with 100 WBTC
 *   - lender:    funded with 10M USDC
 *   - lender2:   funded with 10M USDC
 *   - buyer:     funded with 10M USDC
 *   - attacker:  unfunded
 */
abstract contract TestSetup is Test {
    
    // Contracts
    LoanProtocol public protocol;
    PositionNFT public positionNFT;
    TestMockERC20 public collateralToken;  // WBTC (8 decimals)
    TestMockERC20 public loanToken;        // USDC (6 decimals)
    
    // Test actors
    address public borrower  = makeAddr("borrower");
    address public lender    = makeAddr("lender");
    address public lender2   = makeAddr("lender2");
    address public buyer     = makeAddr("buyer");
    address public attacker  = makeAddr("attacker");
    
    // Default test values
    uint256 public constant DEFAULT_COLLATERAL   = 1e8;         // 1 WBTC
    uint256 public constant DEFAULT_LOAN_AMOUNT   = 50_000e6;    // 50K USDC
    uint256 public constant DEFAULT_MAX_REPAYMENT = 55_000e6;    // 55K USDC (10% max interest)
    uint256 public constant DEFAULT_LOAN_DURATION = 30 days;
    uint256 public constant DEFAULT_AUCTION_DURATION = 1 days;
    uint256 public constant DEFAULT_BID_STEP      = 100e6;       // 100 USDC step
    
    // Protocol constants (mirror from contract)
    uint256 public constant MIN_AUCTION_DURATION = 10 minutes;
    uint256 public constant MAX_AUCTION_DURATION = 7 days;
    uint256 public constant MIN_LOAN_DURATION    = 10 minutes;
    uint256 public constant MAX_LOAN_DURATION    = 10950 days;
    uint256 public constant GRACE_PERIOD         = 10 minutes;
    uint256 public constant FINALIZATION_WINDOW  = 1 hours;
    uint256 public constant MIN_BID_STEP         = 1;
    uint256 public constant MIN_OFFER_DURATION   = 5 minutes;
    uint256 public constant MATURITY_BUFFER      = 5 minutes;
    uint256 public constant MAX_OFFERS_PER_LISTING = 50;
    
    function setUp() public virtual {
        // Deploy mock tokens
        collateralToken = new TestMockERC20("Wrapped Bitcoin", "WBTC", 8);
        loanToken = new TestMockERC20("USD Coin", "USDC", 6);
        
        // Deploy implementations
        LoanProtocol protocolImpl = new LoanProtocol();
        PositionNFT nftImpl = new PositionNFT();
        
        // Deploy PositionNFT proxy (initialize with placeholder, update after protocol deploy)
        ERC1967Proxy nftProxy = new ERC1967Proxy(
            address(nftImpl),
            abi.encodeCall(PositionNFT.initialize, (address(1))) // temp address
        );
        positionNFT = PositionNFT(address(nftProxy));
        
        // Deploy LoanProtocol proxy
        ERC1967Proxy protocolProxy = new ERC1967Proxy(
            address(protocolImpl),
            abi.encodeCall(LoanProtocol.initialize, (address(positionNFT)))
        );
        protocol = LoanProtocol(address(protocolProxy));
        
        // Authorize protocol in PositionNFT
        positionNFT.setLoanProtocol(address(protocol));
        
        // Fund test actors
        collateralToken.mint(borrower, 100e8);   // 100 WBTC
        loanToken.mint(lender,  10_000_000e6);   // 10M USDC
        loanToken.mint(lender2, 10_000_000e6);   // 10M USDC
        loanToken.mint(buyer,   10_000_000e6);   // 10M USDC
        
        // Approve protocol for all actors
        vm.prank(borrower);
        collateralToken.approve(address(protocol), type(uint256).max);
        
        vm.prank(lender);
        loanToken.approve(address(protocol), type(uint256).max);
        
        vm.prank(lender2);
        loanToken.approve(address(protocol), type(uint256).max);
        
        vm.prank(buyer);
        loanToken.approve(address(protocol), type(uint256).max);
    }
    
    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================
    
    /// @dev Borrower deposits collateral and creates an auction
    function _depositAndCreateAuction() internal returns (uint256 auctionId) {
        return _depositAndCreateAuction(
            DEFAULT_COLLATERAL,
            DEFAULT_LOAN_AMOUNT,
            DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION,
            DEFAULT_AUCTION_DURATION,
            DEFAULT_BID_STEP
        );
    }
    
    function _depositAndCreateAuction(
        uint256 collateral,
        uint256 loanAmount,
        uint256 maxRepayment,
        uint256 loanDuration,
        uint256 auctionDuration,
        uint256 bidStep
    ) internal returns (uint256 auctionId) {
        vm.startPrank(borrower);
        protocol.depositCollateral(address(collateralToken), collateral);
        auctionId = protocol.createAuction(
            address(collateralToken),
            collateral,
            address(loanToken),
            loanAmount,
            maxRepayment,
            loanDuration,
            auctionDuration,
            bidStep
        );
        vm.stopPrank();
    }
    
    /// @dev Creates auction + lender places bid at maxRepayment
    function _createAuctionWithBid() internal returns (uint256 auctionId) {
        auctionId = _depositAndCreateAuction();
        vm.prank(lender);
        protocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
    }
    
    /// @dev Full flow: deposit → auction → bid → warp → finalize → active loan
    function _createActiveLoan() internal returns (uint256 loanId) {
        loanId = _createAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        protocol.finalizeAuction(loanId);
    }
    
    /// @dev Full flow: create active loan → warp past maturity + grace → default
    function _createDefaultedLoan() internal returns (uint256 loanId) {
        loanId = _createActiveLoan();
        LoanProtocol.Loan memory loan = protocol.getLoan(loanId);
        vm.warp(loan.maturityTimestamp + GRACE_PERIOD + 1);
        vm.prank(lender);
        protocol.claimCollateral(loanId);
    }
}
