// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ClawStrategy} from "../src/ClawStrategy.sol";

/// @notice Deployment script for ClawStrategy on Base Sepolia
/// @dev Uses Base Sepolia v4 contract addresses from v4-contracts/README.md
///      - RPC: https://sepolia-preconf.base.org
///      - Requires env vars:
///          PRIVATE_KEY  - deployer EOA private key (uint / hex)
///          OWNER        - owner address for ClawStrategy
contract ClawStrategyLaunch is Script {
    /// @notice Clanker v4 on Base Sepolia
    address public constant CLANKER = 0xE85A59c628F7d27878ACeB4bf3b35733630083a9;

    /// @notice ClankerFeeLocker on Base Sepolia
    address public constant FEE_LOCKER = 0x42A95190B4088C88Dd904d930c79deC1158bF09D;

    /// @notice Uniswap V4Router04 on Base Sepolia
    address public constant ROUTER = 0x00000000000044a361Ae3cAc094c9D1b14Eece97;

    /// @notice Canonical WETH on Base (same on Base Sepolia)
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    function run() public {
        // Load deployer private key & owner from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");

        vm.startBroadcast(deployerPrivateKey);

        ClawStrategy strategy = new ClawStrategy(
            CLANKER,
            FEE_LOCKER,
            ROUTER,
            WETH,
            owner
        );

        vm.stopBroadcast();

        console2.log("ClawStrategy deployed at:", address(strategy));
        console2.log("Owner:", owner);
    }
}
