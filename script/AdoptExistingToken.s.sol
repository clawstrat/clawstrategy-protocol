// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ClawStrategy} from "../src/ClawStrategy.sol";

/// @notice Script to adopt an existing Clanker token into ClawStrategy
/// @dev Steps to use:
///      1. Deploy token via Clanker UI normally
///      2. Update reward recipient to ClawStrategy address via Clanker UI
///      3. Run this script to adopt the token
contract AdoptExistingToken is Script {
    /// @notice ClawStrategy contract address (from env)
    address public STRATEGY;

    /// @notice Token to adopt (from env)
    address public TOKEN_TO_ADOPT;

    /// @notice Agent to manage fees for this token (from env)
    address public AGENT;

    /// @notice Fee config: 70% claim, 30% burn (auto-calculated)
    uint256 public constant AGENT_FEE_BPS = 7_000;

    function run() public {
        // Load from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        STRATEGY = vm.envAddress("STRATEGY");
        TOKEN_TO_ADOPT = vm.envAddress("TOKEN");
        AGENT = vm.envAddress("AGENT");
        
        console2.log("=== Adopting Existing Token ===");
        console2.log("Strategy:", STRATEGY);
        console2.log("Token:", TOKEN_TO_ADOPT);
        console2.log("Agent:", AGENT);
        console2.log("Agent Fee BPS:", AGENT_FEE_BPS);
        console2.log("Burn Fee BPS:", 10_000 - AGENT_FEE_BPS);
        
        vm.startBroadcast(deployerPrivateKey);

        ClawStrategy strategy = ClawStrategy(payable(STRATEGY));
        
        // Adopt the token
        strategy.adoptToken(TOKEN_TO_ADOPT, AGENT, AGENT_FEE_BPS);

        vm.stopBroadcast();

        console2.log("\n=== Token Adopted Successfully! ===");
        console2.log("Token can now:");
        console2.log("- Collect fees automatically");
        console2.log("- Agent can claim fees via claimAgentFee()");
        console2.log("- Agent can burn tokens via burnWithWETH() or burnWithToken()");
    }
}

