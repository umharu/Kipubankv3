// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title KipuBankV3
 * @notice Decentralized bank that accepts ETH and ERC20 tokens, automatically converting 
 * all deposits to USDC using Uniswap V2
 * @dev Integrates Uniswap V2 for automatic swaps and maintains a capacity limit (bankCap)
 * @author maximilian0.eth
 */
contract KipuBankV3 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========== STATE VARIABLES ==========
    
    /// @notice Contract owner address
    address public owner;
    
    /// @notice Maximum amount of USDC the bank can store
    uint256 public bankCap;
    
    /// @notice Total USDC balance in the bank
    uint256 public totalBalance;
    
    /// @notice Individual USDC balance for each user
    mapping(address => uint256) public balances;
    
    /// @notice Uniswap V2 Router for executing swaps
    IUniswapV2Router02 public immutable UNISWAP_ROUTER;
    
    /// @notice USDC token address
    address public immutable USDC;
    
    /// @notice WETH token address (Wrapped ETH)
    address public immutable WETH;

    // ========== EVENTS ==========
    
    /// @notice Emitted when a user deposits tokens
    event Deposit(address indexed user, address indexed token, uint256 amountIn, uint256 usdcAmount);
    
    /// @notice Emitted when a user withdraws USDC
    event Withdraw(address indexed user, uint256 amount);
    
    /// @notice Emitted when the bank limit is updated
    event BankCapUpdated(uint256 newCap);
    
    /// @notice Emitted when a swap is executed
    event SwapExecuted(address indexed tokenIn, uint256 amountIn, uint256 usdcOut);

    // ========== ERRORS ==========
    
    error OnlyOwner();
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error BankCapExceeded();
    error TransferFailed();
    error InvalidToken();
    error SlippageTooHigh();
    error DirectETHTransferNotAllowed();

    // ========== MODIFIERS ==========
    
    /**
     * @notice Restricts access to owner only
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    // ========== CONSTRUCTOR ==========
    
    /**
     * @notice Initializes the KipuBankV3 contract
     * @param _uniswapRouter Uniswap V2 router address
     * @param _usdc USDC token address
     * @param _bankCap Maximum amount of USDC the bank can store
     */
    constructor(address _uniswapRouter, address _usdc, uint256 _bankCap) {
        if (_uniswapRouter == address(0) || _usdc == address(0)) revert ZeroAddress();
        if (_bankCap == 0) revert ZeroAmount();
        
        owner = msg.sender;
        UNISWAP_ROUTER = IUniswapV2Router02(_uniswapRouter);
        USDC = _usdc;
        WETH = UNISWAP_ROUTER.WETH();
        bankCap = _bankCap;
    }

    // ========== INTERNAL FUNCTIONS ==========
    
    /**
     * @notice Internal function to check if caller is owner
     */
    function _checkOwner() internal view {
        if (msg.sender != owner) revert OnlyOwner();
    }

    // ========== DEPOSIT FUNCTIONS ==========
    
    /**
     * @notice Deposits native ETH and converts it to USDC
     * @dev ETH is first converted to WETH and then swapped for USDC
     */
    function depositEth() external payable nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        
        // Create path: ETH -> WETH -> USDC
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        
        // Calculate minimum expected USDC (with 1% slippage)
        uint256[] memory amountsOut = UNISWAP_ROUTER.getAmountsOut(msg.value, path);
        uint256 minUsdcOut = (amountsOut[1] * 99) / 100;
        
        // Verify it doesn't exceed bank cap
        if (totalBalance + minUsdcOut > bankCap) revert BankCapExceeded();
        
        // Execute ETH to USDC swap
        uint256[] memory amounts = UNISWAP_ROUTER.swapExactETHForTokens{value: msg.value}(
            minUsdcOut,
            path,
            address(this),
            block.timestamp + 300 // 5 minutes deadline
        );
        
        uint256 usdcReceived = amounts[1];
        
        // Update balances
        balances[msg.sender] += usdcReceived;
        totalBalance += usdcReceived;
        
        emit Deposit(msg.sender, address(0), msg.value, usdcReceived);
        emit SwapExecuted(WETH, msg.value, usdcReceived);
    }
    
    /**
     * @notice Deposits USDC directly without swap
     * @param amount Amount of USDC to deposit
     */
    function depositUsdc(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (totalBalance + amount > bankCap) revert BankCapExceeded();
        
        // Transfer USDC from user to contract
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update balances
        balances[msg.sender] += amount;
        totalBalance += amount;
        
        emit Deposit(msg.sender, USDC, amount, amount);
    }
    
    /**
     * @notice Deposits any ERC20 token and converts it to USDC
     * @param token Token address to deposit
     * @param amount Amount of tokens to deposit
     * @dev Token must have a direct pair with USDC on Uniswap V2
     */
    function depositToken(address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (token == USDC) revert InvalidToken(); // Use depositUsdc for USDC
        
        // Transfer token from user to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve router to spend the token
        IERC20(token).safeIncreaseAllowance(address(UNISWAP_ROUTER), amount);
        
        // Create path: Token -> USDC
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = USDC;
        
        // Calculate minimum expected USDC (with 1% slippage)
        uint256[] memory amountsOut = UNISWAP_ROUTER.getAmountsOut(amount, path);
        uint256 minUsdcOut = (amountsOut[1] * 99) / 100;
        
        // Verify it doesn't exceed bank cap
        if (totalBalance + minUsdcOut > bankCap) revert BankCapExceeded();
        
        // Execute swap
        uint256[] memory amounts = UNISWAP_ROUTER.swapExactTokensForTokens(
            amount,
            minUsdcOut,
            path,
            address(this),
            block.timestamp + 300 // 5 minutes deadline
        );
        
        uint256 usdcReceived = amounts[1];
        
        // Update balances
        balances[msg.sender] += usdcReceived;
        totalBalance += usdcReceived;
        
        emit Deposit(msg.sender, token, amount, usdcReceived);
        emit SwapExecuted(token, amount, usdcReceived);
    }

    // ========== WITHDRAWAL FUNCTIONS ==========
    
    /**
     * @notice Withdraws USDC from the bank
     * @param amount Amount of USDC to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (balances[msg.sender] < amount) revert InsufficientBalance();
        
        // Update balances
        balances[msg.sender] -= amount;
        totalBalance -= amount;
        
        // Transfer USDC to user
        IERC20(USDC).safeTransfer(msg.sender, amount);
        
        emit Withdraw(msg.sender, amount);
    }
    
    /**
     * @notice Withdraws all USDC balance from user
     */
    function withdrawAll() external nonReentrant {
        uint256 balance = balances[msg.sender];
        if (balance == 0) revert ZeroAmount();
        
        // Update balances
        balances[msg.sender] = 0;
        totalBalance -= balance;
        
        // Transfer USDC to user
        IERC20(USDC).safeTransfer(msg.sender, balance);
        
        emit Withdraw(msg.sender, balance);
    }

    // ========== OWNER FUNCTIONS ==========
    
    /**
     * @notice Updates the bank's maximum capacity
     * @param newCap New capacity limit
     */
    function updateBankCap(uint256 newCap) external onlyOwner {
        if (newCap == 0) revert ZeroAmount();
        bankCap = newCap;
        emit BankCapUpdated(newCap);
    }
    
    /**
     * @notice Transfers contract ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    // ========== VIEW FUNCTIONS ==========
    
    /**
     * @notice Gets a user's balance
     * @param user User address
     * @return User's USDC balance
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }
    
    /**
     * @notice Estimates how much USDC would be received for an ETH deposit
     * @param ethAmount Amount of ETH to deposit
     * @return Estimated amount of USDC to receive
     */
    function estimateEthToUsdc(uint256 ethAmount) external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        
        uint256[] memory amountsOut = UNISWAP_ROUTER.getAmountsOut(ethAmount, path);
        return amountsOut[1];
    }
    
    /**
     * @notice Estimates how much USDC would be received for a token deposit
     * @param token Token address
     * @param amount Token amount
     * @return Estimated amount of USDC to receive
     */
    function estimateTokenToUsdc(address token, uint256 amount) external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = USDC;
        
        uint256[] memory amountsOut = UNISWAP_ROUTER.getAmountsOut(amount, path);
        return amountsOut[1];
    }
    
    /**
     * @notice Checks available space in the bank
     * @return Amount of USDC that can still be deposited
     */
    function availableCapacity() external view returns (uint256) {
        return bankCap - totalBalance;
    }

    // ========== FALLBACK ==========
    
    /**
     * @notice Rejects direct ETH transfers
     * @dev Users must use depositEth() instead
     */
    receive() external payable {
        revert DirectETHTransferNotAllowed();
    }
}