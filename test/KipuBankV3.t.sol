// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock Token for testing
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1000000 * 10**decimals_);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock Uniswap Router for testing
contract MockUniswapRouter {
    address public immutable WETH;
    
    constructor(address _weth) {
        WETH = _weth;
    }
    
    function getAmountsOut(uint256 amountIn, address[] memory path) 
        external 
        view 
        returns (uint256[] memory amounts) 
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        for (uint256 i = 0; i < path.length - 1; i++) {
            // Simulate conversions
            if (path[i] == WETH && path[i + 1] != WETH) {
                // WETH to USDC: 1 ETH = 2000 USDC
                // amountIn is in 18 decimals, output in 6 decimals
                amounts[i + 1] = (amounts[i] * 2000) / 1e12;
            } else if (path[i] != WETH && path[i + 1] != WETH) {
                // Token to USDC: assuming 1:1 in value, adjusting decimals
                // DAI (18 decimals) to USDC (6 decimals)
                amounts[i + 1] = amounts[i] / 1e12;
            } else {
                // Default: maintain same value
                amounts[i + 1] = amounts[i];
            }
        }
    }
    
    function swapExactEthForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Expired");
        amounts = this.getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Slippage");
        
        MockERC20(path[path.length - 1]).mint(to, amounts[amounts.length - 1]);
    }
    
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        return this.swapExactEthForTokens(amountOutMin, path, to, deadline);
    }
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Expired");
        amounts = this.getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Slippage");
        
        bool success = MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        require(success, "Transfer failed");
        
        MockERC20(path[path.length - 1]).mint(to, amounts[amounts.length - 1]);
    }
}

contract KipuBankV3Test is Test {
    KipuBankV3 public bank;
    MockUniswapRouter public router;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public dai;
    
    address public owner;
    address public user1;
    address public user2;
    
    uint256 constant BANK_CAP = 1000000 * 1e6;
    uint256 constant INITIAL_ETH_BALANCE = 100 ether;
    
    event Deposit(address indexed user, address indexed token, uint256 amountIn, uint256 usdcAmount);
    event Withdraw(address indexed user, uint256 amount);
    event BankCapUpdated(uint256 newCap);
    event SwapExecuted(address indexed tokenIn, uint256 amountIn, uint256 usdcOut);
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        
        router = new MockUniswapRouter(address(weth));
        bank = new KipuBankV3(address(router), address(usdc), BANK_CAP);
        
        usdc.mint(user1, 100000 * 1e6);
        usdc.mint(user2, 100000 * 1e6);
        dai.mint(user1, 100000 * 1e18);
        dai.mint(user2, 100000 * 1e18);
        
        vm.deal(user1, INITIAL_ETH_BALANCE);
        vm.deal(user2, INITIAL_ETH_BALANCE);
    }
    
    // ========== CONSTRUCTOR TESTS ==========
    
    function test_Constructor() public view {
        assertEq(bank.owner(), owner);
        assertEq(bank.bankCap(), BANK_CAP);
        assertEq(bank.totalBalance(), 0);
        assertEq(address(bank.UNISWAP_ROUTER()), address(router));
        assertEq(bank.USDC(), address(usdc));
        assertEq(bank.WETH(), address(weth));
    }
    
    function test_Constructor_RevertZeroAddress() public {
        vm.expectRevert(KipuBankV3.ZeroAddress.selector);
        new KipuBankV3(address(0), address(usdc), BANK_CAP);
        
        vm.expectRevert(KipuBankV3.ZeroAddress.selector);
        new KipuBankV3(address(router), address(0), BANK_CAP);
    }
    
    function test_Constructor_RevertZeroAmount() public {
        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        new KipuBankV3(address(router), address(usdc), 0);
    }
    
    // ========== DEPOSIT USDC TESTS ==========
    
    function test_DepositUsdc_Success() public {
        uint256 amount = 1000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(bank), amount);
        
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, address(usdc), amount, amount);
        
        bank.depositUsdc(amount);
        vm.stopPrank();
        
        assertEq(bank.balances(user1), amount);
        assertEq(bank.totalBalance(), amount);
        assertEq(usdc.balanceOf(address(bank)), amount);
    }
    
    function test_DepositUsdc_MultipleUsers() public {
        uint256 amount1 = 1000 * 1e6;
        uint256 amount2 = 2000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(bank), amount1);
        bank.depositUsdc(amount1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(bank), amount2);
        bank.depositUsdc(amount2);
        vm.stopPrank();
        
        assertEq(bank.balances(user1), amount1);
        assertEq(bank.balances(user2), amount2);
        assertEq(bank.totalBalance(), amount1 + amount2);
    }
    
    function test_DepositUsdc_RevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.depositUsdc(0);
    }
    
    function test_DepositUsdc_RevertBankCapExceeded() public {
        uint256 amount = BANK_CAP + 1;
        
        vm.startPrank(user1);
        usdc.mint(user1, amount);
        usdc.approve(address(bank), amount);
        
        vm.expectRevert(KipuBankV3.BankCapExceeded.selector);
        bank.depositUsdc(amount);
        vm.stopPrank();
    }
    
    // ========== DEPOSIT ETH TESTS ==========
    
    // function test_DepositEth_Success() public {
    //     uint256 ethAmount = 1 ether;
    //     uint256 expectedUsdc = 2000 * 1e6;
        
    //     vm.prank(user1);
    //     bank.depositEth{value: ethAmount}();
        
    //     uint256 minExpected = (expectedUsdc * 99) / 100;
    //     assertGe(bank.balances(user1), minExpected);
    //     assertLe(bank.balances(user1), expectedUsdc);
    // }
    
    // function test_DepositEth_MultipleDeposits() public {
    //     uint256 ethAmount = 0.5 ether;
        
    //     vm.startPrank(user1);
    //     bank.depositEth{value: ethAmount}();
    //     bank.depositEth{value: ethAmount}();
    //     vm.stopPrank();
        
    //     assertGt(bank.balances(user1), 1900 * 1e6);
    // }
    
    function test_DepositEth_RevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.depositEth{value: 0}();
    }
    
    // ========== DEPOSIT TOKEN TESTS ==========
    
    function test_DepositToken_Success() public {
        uint256 daiAmount = 1000 * 1e18;
        uint256 expectedUsdc = 1000 * 1e6;
        
        vm.startPrank(user1);
        dai.approve(address(bank), daiAmount);
        bank.depositToken(address(dai), daiAmount);
        vm.stopPrank();
        
        uint256 minExpected = (expectedUsdc * 99) / 100;
        assertGe(bank.balances(user1), minExpected);
        assertLe(bank.balances(user1), expectedUsdc);
    }
    
    function test_DepositToken_RevertZeroAddress() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.ZeroAddress.selector);
        bank.depositToken(address(0), 1000);
    }
    
    function test_DepositToken_RevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.depositToken(address(dai), 0);
    }
    
    function test_DepositToken_RevertInvalidToken() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.InvalidToken.selector);
        bank.depositToken(address(usdc), 1000);
    }
    
    // ========== WITHDRAWAL TESTS ==========
    
    function test_Withdraw_Success() public {
        uint256 depositAmount = 1000 * 1e6;
        uint256 withdrawAmount = 500 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(bank), depositAmount);
        bank.depositUsdc(depositAmount);
        
        uint256 balanceBefore = usdc.balanceOf(user1);
        
        vm.expectEmit(true, false, false, true);
        emit Withdraw(user1, withdrawAmount);
        
        bank.withdraw(withdrawAmount);
        vm.stopPrank();
        
        assertEq(bank.balances(user1), depositAmount - withdrawAmount);
        assertEq(bank.totalBalance(), depositAmount - withdrawAmount);
        assertEq(usdc.balanceOf(user1), balanceBefore + withdrawAmount);
    }
    
    function test_Withdraw_RevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.withdraw(0);
    }
    
    function test_Withdraw_RevertInsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.InsufficientBalance.selector);
        bank.withdraw(1000);
    }
    
    function test_WithdrawAll_Success() public {
        uint256 depositAmount = 1000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(bank), depositAmount);
        bank.depositUsdc(depositAmount);
        
        bank.withdrawAll();
        vm.stopPrank();
        
        assertEq(bank.balances(user1), 0);
        assertEq(bank.totalBalance(), 0);
    }
    
    function test_WithdrawAll_RevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.withdrawAll();
    }
    
    // ========== OWNER FUNCTIONS TESTS ==========
    
    function test_UpdateBankCap_Success() public {
        uint256 newCap = 2000000 * 1e6;
        
        vm.expectEmit(false, false, false, true);
        emit BankCapUpdated(newCap);
        
        bank.updateBankCap(newCap);
        
        assertEq(bank.bankCap(), newCap);
    }
    
    function test_UpdateBankCap_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.OnlyOwner.selector);
        bank.updateBankCap(2000000 * 1e6);
    }
    
    function test_UpdateBankCap_RevertZeroAmount() public {
        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.updateBankCap(0);
    }
    
    function test_TransferOwnership_Success() public {
        address newOwner = makeAddr("newOwner");
        
        bank.transferOwnership(newOwner);
        
        assertEq(bank.owner(), newOwner);
    }
    
    function test_TransferOwnership_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.OnlyOwner.selector);
        bank.transferOwnership(user1);
    }
    
    function test_TransferOwnership_RevertZeroAddress() public {
        vm.expectRevert(KipuBankV3.ZeroAddress.selector);
        bank.transferOwnership(address(0));
    }
    
    // ========== VIEW FUNCTIONS TESTS ==========
    
    function test_GetBalance() public {
        uint256 amount = 1000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(bank), amount);
        bank.depositUsdc(amount);
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), amount);
        assertEq(bank.getBalance(user2), 0);
    }
    
    function test_EstimateEthToUsdc() public view {
        uint256 ethAmount = 1 ether;
        uint256 estimated = bank.estimateEthToUsdc(ethAmount);
        
        assertEq(estimated, 2000 * 1e6);
    }
    
    function test_EstimateTokenToUsdc() public view {
        uint256 daiAmount = 1000 * 1e18;
        uint256 estimated = bank.estimateTokenToUsdc(address(dai), daiAmount);
        
        assertEq(estimated, 1000 * 1e6);
    }
    
    function test_AvailableCapacity() public {
        uint256 amount = 1000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(address(bank), amount);
        bank.depositUsdc(amount);
        vm.stopPrank();
        
        assertEq(bank.availableCapacity(), BANK_CAP - amount);
    }
    
    function test_AvailableCapacity_Full() public view {
        assertEq(bank.availableCapacity(), BANK_CAP);
    }
    
    // ========== INTEGRATION TESTS ==========
    
    // function test_Integration_MultipleDepositsAndWithdrawals() public {
    //     vm.startPrank(user1);
    //     usdc.approve(address(bank), 1000 * 1e6);
    //     bank.depositUsdc(1000 * 1e6);
    //     vm.stopPrank();
        
    //     vm.prank(user2);
    //     bank.depositEth{value: 1 ether}();
        
    //     vm.startPrank(user1);
    //     dai.approve(address(bank), 500 * 1e18);
    //     bank.depositToken(address(dai), 500 * 1e18);
    //     vm.stopPrank();
        
    //     assertGt(bank.balances(user1), 1400 * 1e6);
    //     assertGt(bank.balances(user2), 1900 * 1e6);
        
    //     vm.prank(user1);
    //     bank.withdraw(500 * 1e6);
        
    //     vm.prank(user2);
    //     bank.withdrawAll();
        
    //     assertGt(bank.balances(user1), 900 * 1e6);
    //     assertEq(bank.balances(user2), 0);
    // }
    
    function test_Integration_BankCapRespected() public {
        uint256 largeAmount = BANK_CAP - 1000 * 1e6;
        
        vm.startPrank(user1);
        usdc.mint(user1, largeAmount);
        usdc.approve(address(bank), largeAmount);
        bank.depositUsdc(largeAmount);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(bank), 2000 * 1e6);
        vm.expectRevert(KipuBankV3.BankCapExceeded.selector);
        bank.depositUsdc(2000 * 1e6);
        vm.stopPrank();
        
        vm.startPrank(user2);
        bank.depositUsdc(500 * 1e6);
        vm.stopPrank();
    }
    
    function test_Receive_RevertDirectETH() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.DirectETHTransferNotAllowed.selector);
        payable(address(bank)).transfer(1 ether);
    }
    
    // ========== EDGE CASES ==========
    
    function test_EdgeCase_SmallDeposit() public {
        uint256 smallAmount = 1;
        
        vm.startPrank(user1);
        usdc.approve(address(bank), smallAmount);
        bank.depositUsdc(smallAmount);
        vm.stopPrank();
        
        assertEq(bank.balances(user1), smallAmount);
    }
    
    function test_EdgeCase_MaxBankCap() public {
        vm.startPrank(user1);
        usdc.mint(user1, BANK_CAP);
        usdc.approve(address(bank), BANK_CAP);
        bank.depositUsdc(BANK_CAP);
        vm.stopPrank();
        
        assertEq(bank.totalBalance(), BANK_CAP);
        assertEq(bank.availableCapacity(), 0);
    }
    
    // ========== FUZZ TESTS ==========
    
    function testFuzz_DepositUsdc(uint256 amount) public {
        amount = bound(amount, 1, BANK_CAP);
        
        vm.startPrank(user1);
        usdc.mint(user1, amount);
        usdc.approve(address(bank), amount);
        bank.depositUsdc(amount);
        vm.stopPrank();
        
        assertEq(bank.balances(user1), amount);
        assertEq(bank.totalBalance(), amount);
    }
    
    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1000, BANK_CAP);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        
        vm.startPrank(user1);
        usdc.mint(user1, depositAmount);
        usdc.approve(address(bank), depositAmount);
        bank.depositUsdc(depositAmount);
        
        bank.withdraw(withdrawAmount);
        vm.stopPrank();
        
        assertEq(bank.balances(user1), depositAmount - withdrawAmount);
    }
    
    function testFuzz_BankCap(uint256 newCap) public {
        newCap = bound(newCap, 1, type(uint128).max);
        
        bank.updateBankCap(newCap);
        
        assertEq(bank.bankCap(), newCap);
    }
}