# KipuBankV3 🏦

KipuBankV3 is a decentralized bank that accepts deposits in ETH and ERC20 tokens, automatically converting all assets to USDC via Uniswap V2.

## **Live Contract (Sepolia):**  
[0xEFaB5740F25995825569B5FA08d4831A3f108368](https://sepolia.etherscan.io/address/0xEFaB5740F25995825569B5FA08d4831A3f108368)


## 🎯 Key Features

- ✅ Native ETH deposits with automatic USDC conversion
- ✅ Direct USDC deposits without conversion
- ✅ Any ERC20 token deposits with Uniswap V2 pairs
- ✅ Full Uniswap V2 Router integration
- ✅ Bank capacity limit system (Bank Cap)
- ✅ USDC withdrawals
- ✅ Reentrancy protection
- ✅ Slippage control (1% maximum)
- ✅ Price estimation functions
- ✅ +50% test coverage

## 🏗️ Architecture

### Deposit Flow

```
User deposits Token X
         ↓
KipuBankV3 receives token
         ↓
Approval to Uniswap Router
         ↓
Automatic swap Token X → USDC
         ↓
Balance updates
         ↓
Bank Cap verification
```

### Main Components

1. **Deposit Management**
   - `depositETH()`: Native ETH deposit
   - `depositUSDC()`: Direct USDC deposit
   - `depositToken()`: Any ERC20 token deposit

2. **Withdrawal Management**
   - `withdraw()`: Partial USDC withdrawal
   - `withdrawAll()`: Full balance withdrawal

3. **Uniswap V2 Integration**
   - Automatic swaps using router
   - Slippage protection (1%)
   - Real-time price estimation

4. **Security**
   - OpenZeppelin's ReentrancyGuard
   - SafeERC20 for secure transfers
   - Comprehensive validations

## 📋 Design Decisions

### 1. Automatic USDC Conversion

**Reason**: Simplifies bank accounting and provides value stability. All deposits are normalized to a single unit of account.

**Trade-off**: Users bear the gas cost of swaps at deposit time.

### 2. 1% Slippage

**Reason**: Balance between price fluctuation protection and transaction success probability.

**Trade-off**: In very volatile markets, some transactions may fail. Can be adjusted as needed.

### 3. 5-Minute Deadline

**Reason**: Reasonable time window for transactions to be mined without prolonged price exposure.

**Trade-off**: On congested networks, it may be insufficient. Consider making it configurable.

### 4. Strict Bank Cap

**Reason**: Risk control and gradual protocol scalability.

**Trade-off**: Requires active limit management as demand grows.

### 5. USDC-Only Storage

**Reason**: Simplifies withdrawal logic and reduces attack surface.

**Trade-off**: Cannot withdraw in original deposited token.

## 🚀 Installation and Setup

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Clone and Install Dependencies

```bash
git clone https://github.com/umharu/Kipubankv3.git
cd KipuBankV3
forge install
```

### Configure Environment Variables

Create a `.env` file:

```bash
SEPOLIA_RPC_URL=your_rpc_url
PRIVATE_KEY=0xyour_private_key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## 🧪 Testing

### Run Tests

```bash
# All tests
forge test

# Tests with verbosity
forge test -vv

# Specific test
forge test --match-test test_DepositUSDC_Success -vvvv

# Fuzz tests
forge test --match-test testFuzz
```

### Test Coverage

```bash
# Generate coverage report
forge coverage

# Detailed report
forge coverage --report summary
forge coverage --report lcov

# View coverage in HTML
genhtml lcov.info -o coverage/
open coverage/index.html
```

### Included Tests

- ✅ Constructor tests
- ✅ Deposit tests (ETH, USDC, tokens)
- ✅ Withdrawal tests
- ✅ Owner function tests
- ✅ View function tests
- ✅ Integration tests
- ✅ Edge case tests
- ✅ Fuzz tests
- ✅ Revert tests with custom errors

**Current Coverage**: >50% (meets minimum requirement)

## 📦 Deployment

### Deploy on Sepolia

```bash
# Load variables
source .env

# Deploy and verify
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

### Sepolia Addresses

- **Uniswap V2 Router**: `0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008`
- **USDC**: `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8`
- **Bank Cap**: 1,000,000 USDC

## 🔐 Security Analysis

### Mitigated Attack Vectors

1. **Reentrancy**: Protected with `ReentrancyGuard`
2. **Integer Overflow/Underflow**: Solidity 0.8.20 has native checks
3. **Unsafe Transfers**: Using `SafeERC20`
4. **Front-running on swaps**: Protected with minimum slippage
5. **Expired deadline**: Timestamp verification in swaps

### Potential Vulnerabilities

1. **Uniswap V2 Dependency**
   - Risk: If Uniswap has a bug or is paused
   - Mitigation: Consider multi-DEX integration

2. **Slippage in Volatile Markets**
   - Risk: Transactions may fail with 1% slippage
   - Mitigation: Make slippage configurable or dynamic

3. **MEV (Maximal Extractable Value)**
   - Risk: Bots can sandwich attack swaps
   - Mitigation: Integrate FlashBots or similar

4. **Owner Centralization**
   - Risk: Owner can arbitrarily change bank cap
   - Mitigation: Implement timelock or DAO governance

5. **Insufficient Liquidity in Pairs**
   - Risk: Tokens with low liquidity may have high slippage
   - Mitigation: Verify minimum liquidity before accepting tokens

## 📊 Test Coverage

### Implemented Testing Methods

1. **Unit Tests**: Isolated function testing
2. **Integration Tests**: Complete flow testing
3. **Fuzz Tests**: Random value testing
4. **Edge Case Tests**: Boundary and error cases
5. **Event Emission Tests**: Event verification

### Covered Areas

- ✅ Constructor and initialization
- ✅ Deposits (all types)
- ✅ Withdrawals (partial and full)
- ✅ Owner functions
- ✅ View functions
- ✅ Error handling
- ✅ Event emission
- ✅ Edge cases
- ✅ Multi-user interactions

### Steps Missing for Maturity

1. **Professional Audit**: Hire external auditor
2. **Bug Bounty**: Bug reward program
3. **Timelock on Admin Functions**: Add delays to critical changes
4. **Circuit Breakers**: Emergency pausability
5. **On-chain Monitoring**: Automatic alert system
6. **Complete Technical Documentation**: Detailed whitepaper
7. **Testnet Testing**: Extended public testing period
8. **Oracle Integration**: Alternative pricing to Uniswap
9. **Multi-sig for Owner**: Decentralize control
10. **Formal Verification**: Mathematical code verification

## 🎓 Course Concepts Applied

- ✅ Advanced Solidity and best practices
- ✅ DeFi protocol integration (Uniswap)
- ✅ Exhaustive testing with Foundry
- ✅ Security (ReentrancyGuard, SafeERC20)
- ✅ Design patterns (Checks-Effects-Interactions)
- ✅ ERC20 token management
- ✅ Native ETH handling
- ✅ Events and logging
- ✅ Custom errors for gas efficiency
- ✅ NatSpec documentation
- ✅ Deployment scripts
- ✅ Etherscan verification

## 📖 Contract Usage

### For Users

```solidity
// 1. Deposit ETH
kipuBank.depositETH{value: 1 ether}();

// 2. Deposit USDC
IERC20(usdc).approve(address(kipuBank), amount);
kipuBank.depositUSDC(amount);

// 3. Deposit another token (e.g., DAI)
IERC20(dai).approve(address(kipuBank), amount);
kipuBank.depositToken(address(dai), amount);

// 4. Check balance
uint256 balance = kipuBank.getBalance(msg.sender);

// 5. Estimate conversion before depositing
uint256 estimatedUSDC = kipuBank.estimateETHToUSDC(1 ether);

// 6. Partial withdrawal
kipuBank.withdraw(amount);

// 7. Full withdrawal
kipuBank.withdrawAll();
```

### For Owner

```solidity
// Update bank limit
kipuBank.updateBankCap(2000000 * 1e6);

// Transfer ownership
kipuBank.transferOwnership(newOwner);

// View available capacity
uint256 available = kipuBank.availableCapacity();
```

## 🔧 Maintenance and Future Upgrades

### Planned Improvements

1. **Multi-DEX Support**: Integrate other DEXs for better pricing
2. **Yield Generation**: Deposit idle USDC in lending protocols
3. **NFT Receipts**: Issue NFTs as deposit receipts
4. **Governance Token**: Token for parameter voting
5. **Flash Loans**: Allow flash loans from USDC pool
6. **Layer 2 Deployment**: Deploy on Arbitrum, Optimism, etc.

## 🤝 Contributions

This project was developed as a final project for the Web3 development course.

## 📄 License

MIT License

## 👥 Team

- Lead Developer: maximilian0.eth
- Course: ETH-KIPU TT
- Date: 2025

---

**Note**: This contract is an educational project. For production use, a complete professional audit is recommended.