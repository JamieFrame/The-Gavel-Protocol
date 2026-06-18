// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Import actual contracts
import "../../contracts/NFTLoanProtocol.sol";
import "../../contracts/NFTPositionNFT.sol";

// ============================================================================
// MOCK ERC20 FOR TESTING (same as TestSetup)
// ============================================================================

contract MockERC20NFT is Test {
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
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "Allowance");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// ============================================================================
// MOCK ERC721 FOR TESTING
// ============================================================================

contract TestMockERC721 is Test {
    string public name;
    string public symbol;
    
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _approvals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
    
    function mint(address to, uint256 tokenId) external {
        _owners[tokenId] = to;
        _balances[to]++;
        emit Transfer(address(0), to, tokenId);
    }
    
    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: nonexistent token");
        return owner;
    }
    
    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }
    
    function approve(address to, uint256 tokenId) external {
        require(msg.sender == _owners[tokenId] || _operatorApprovals[_owners[tokenId]][msg.sender], "Not authorized");
        _approvals[tokenId] = to;
        emit Approval(_owners[tokenId], to, tokenId);
    }
    
    function getApproved(uint256 tokenId) external view returns (address) {
        return _approvals[tokenId];
    }
    
    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    
    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }
    
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_owners[tokenId] == from, "Not owner");
        require(
            msg.sender == from || 
            msg.sender == _approvals[tokenId] || 
            _operatorApprovals[from][msg.sender],
            "Not authorized"
        );
        _owners[tokenId] = to;
        _balances[from]--;
        _balances[to]++;
        _approvals[tokenId] = address(0);
        emit Transfer(from, to, tokenId);
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        // Check ERC721Receiver
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                require(retval == IERC721Receiver.onERC721Received.selector, "Non-receiver");
            } catch {
                revert("Non-receiver");
            }
        }
    }
    
    function tokenURI(uint256 /* tokenId */) external pure returns (string memory) {
        return '{"name":"Mock NFT","image":"https://example.com/nft.png"}';
    }
    
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd || interfaceId == 0x01ffc9a7 || interfaceId == 0x5b5e139f;
    }
}

// ============================================================================
// MINIMAL ERC1967 PROXY
// ============================================================================

contract ERC1967ProxyNFT {
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
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
// NFT BASE TEST SETUP
// ============================================================================

/**
 * @title NFTTestSetup
 * @notice Base test contract that deploys NFTLoanProtocol + NFTPositionNFT via proxies
 * @dev All NFT unit test contracts inherit from this
 *
 * Deployed contracts:
 *   - nftProtocol: NFTLoanProtocol (upgradeable proxy)
 *   - nftPositionNFT: NFTPositionNFT (upgradeable proxy)
 *   - mockNFT: MockERC721 "CryptoPunks" test collection
 *   - loanToken: MockERC20NFT "USDC" (6 decimals)
 *
 * Test actors:
 *   - deployer (this contract) = protocol owner
 *   - borrower:  owns NFT tokenIds 1-10, funded with USDC for fees
 *   - lender:    funded with 10M USDC
 *   - buyer:     funded with 10M USDC
 *   - attacker:  unfunded
 */
abstract contract NFTTestSetup is Test {
    
    // Contracts
    NFTLoanProtocol public nftProtocol;
    NFTPositionNFT public nftPositionNFT;
    TestMockERC721 public mockNFT;
    MockERC20NFT public loanToken;
    
    // Test actors
    address public borrower  = makeAddr("borrower");
    address public lender    = makeAddr("lender");
    address public buyer     = makeAddr("buyer");
    address public attacker  = makeAddr("attacker");
    
    // Default test values
    uint256 public constant DEFAULT_NFT_TOKEN_ID  = 1;
    uint256 public constant DEFAULT_LOAN_AMOUNT   = 50_000e6;    // 50K USDC
    uint256 public constant DEFAULT_MAX_REPAYMENT = 55_000e6;    // 55K USDC
    uint256 public constant DEFAULT_LOAN_DURATION = 30 days;
    uint256 public constant DEFAULT_AUCTION_DURATION = 1 days;
    uint256 public constant DEFAULT_BID_STEP      = 100e6;       // 100 USDC step
    
    // Protocol constants
    uint256 public constant MIN_AUCTION_DURATION = 1 days;
    uint256 public constant GRACE_PERIOD         = 1 days;
    uint256 public constant FINALIZATION_WINDOW  = 3 days;
    uint256 public constant MIN_OFFER_DURATION   = 1 days;
    uint256 public constant MATURITY_BUFFER      = 1 days;
    
    function setUp() public virtual {
        // Deploy mock tokens
        mockNFT = new TestMockERC721("CryptoPunks", "PUNK");
        loanToken = new MockERC20NFT("USD Coin", "USDC", 6);
        
        // Deploy implementations
        NFTLoanProtocol protocolImpl = new NFTLoanProtocol();
        NFTPositionNFT nftImpl = new NFTPositionNFT();
        
        // Deploy NFTPositionNFT proxy UNINITIALIZED. loanProtocol is fixed at initialize()
        // and immutable thereafter, so we initialize the NFT only after NFTLoanProtocol
        // exists — mirroring the real deployment's resolution of the circular reference.
        ERC1967ProxyNFT nftProxy = new ERC1967ProxyNFT(address(nftImpl), "");
        nftPositionNFT = NFTPositionNFT(address(nftProxy));

        // Deploy NFTLoanProtocol proxy
        ERC1967ProxyNFT protocolProxy = new ERC1967ProxyNFT(
            address(protocolImpl),
            abi.encodeCall(NFTLoanProtocol.initialize, (address(nftPositionNFT)))
        );
        nftProtocol = NFTLoanProtocol(address(protocolProxy));

        // Initialize NFTPositionNFT with the protocol address (one-time, immutable)
        nftPositionNFT.initialize(address(nftProtocol));
        
        // Mint NFTs to borrower
        for (uint256 i = 1; i <= 10; i++) {
            mockNFT.mint(borrower, i);
        }
        
        // Fund with USDC
        loanToken.mint(borrower, 1_000_000e6);
        loanToken.mint(lender,   10_000_000e6);
        loanToken.mint(buyer,    10_000_000e6);
        
        // Borrower approves protocol for NFT transfers
        vm.prank(borrower);
        mockNFT.setApprovalForAll(address(nftProtocol), true);
        
        // Lender approves protocol for USDC
        vm.prank(lender);
        loanToken.approve(address(nftProtocol), type(uint256).max);
        
        // Buyer approves protocol for USDC
        vm.prank(buyer);
        loanToken.approve(address(nftProtocol), type(uint256).max);
    }
    
    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================
    
    /// @dev Borrower creates an auction with default NFT collateral
    function _createNFTAuction() internal returns (uint256 auctionId) {
        return _createNFTAuction(DEFAULT_NFT_TOKEN_ID);
    }
    
    function _createNFTAuction(uint256 tokenId) internal returns (uint256 auctionId) {
        vm.prank(borrower);
        auctionId = nftProtocol.createAuction(
            address(mockNFT),
            tokenId,
            address(loanToken),
            DEFAULT_LOAN_AMOUNT,
            DEFAULT_MAX_REPAYMENT,
            DEFAULT_LOAN_DURATION,
            DEFAULT_AUCTION_DURATION,
            DEFAULT_BID_STEP
        );
    }
    
    /// @dev Creates auction + lender bids
    function _createNFTAuctionWithBid() internal returns (uint256 auctionId) {
        auctionId = _createNFTAuction();
        vm.prank(lender);
        nftProtocol.placeBid(auctionId, DEFAULT_MAX_REPAYMENT);
    }
    
    /// @dev Full flow: auction → bid → warp → finalize → active loan
    function _createActiveNFTLoan() internal returns (uint256 loanId) {
        loanId = _createNFTAuctionWithBid();
        vm.warp(block.timestamp + DEFAULT_AUCTION_DURATION + 1);
        nftProtocol.finalizeAuction(loanId);
    }
}
