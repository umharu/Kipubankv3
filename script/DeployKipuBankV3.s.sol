// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";

/**
 * @title Deploy Script for KipuBankV3
 * @notice Script to deploy KipuBankV3 on different networks
 * @dev Uses environment variables for private key
 */
contract DeployScript is Script {
    // Sepolia network addresses
    address constant UNISWAP_ROUTER_SEPOLIA = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address constant USDC_SEPOLIA = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;

    // Bank configuration parameters
    uint256 constant BANK_CAP = 1000000 * 1e6; // 1 Million USDC

    /**
     * @notice Main deployment function
     * @dev Reads PRIVATE_KEY from environment variables
     */
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy KipuBankV3 contract
        KipuBankV3 bank = new KipuBankV3(UNISWAP_ROUTER_SEPOLIA, USDC_SEPOLIA, BANK_CAP);

        vm.stopBroadcast();

        // Log deployment information
        _logDeploymentInfo(bank);
    }

    /**
     * @notice Internal function to log deployment details
     * @param bank Deployed KipuBankV3 contract instance
     */
    function _logDeploymentInfo(KipuBankV3 bank) internal view {
        console.log("==============================================");
        console.log("KipuBankV3 Deployment Successful!");
        console.log("==============================================");
        console.log("Contract Address:", address(bank));
        console.log("Owner:", bank.owner());
        console.log("Bank Cap:", bank.bankCap());
        console.log("Uniswap Router:", address(bank.UNISWAP_ROUTER()));
        console.log("USDC:", bank.USDC());
        console.log("WETH:", bank.WETH());
        console.log("==============================================");
        console.log("");
        console.log("Next Steps:");
        console.log("1. Verify contract on Etherscan");
        console.log("2. Test deposit functions");
        console.log("3. Update README with contract address");
        console.log("==============================================");
    }
}
