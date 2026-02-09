// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ClawStrategy} from "../src/ClawStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Script for agent to perform operations: claim fees, burn with WETH, burn with token
/// @dev Requires env vars:
///      PRIVATE_KEY - agent EOA private key
///      TOKEN       - token address
///      OPERATION   - operation to perform: "claim", "burn_weth", "burn_token", "info"
contract AgentOperations is Script {
    /// @notice Address of ClawStrategy (from env)
    address public STRATEGY;

    /// @notice Canonical WETH on Base
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    function run() public {
        // Load from env
        uint256 agentPrivateKey = vm.envUint("PRIVATE_KEY");
        STRATEGY = vm.envAddress("STRATEGY");
        address token = vm.envAddress("TOKEN");
        string memory operation = vm.envString("OPERATION");

        address agent = vm.addr(agentPrivateKey);

        console2.log("=== Agent Operations ===");
        console2.log("Agent:", agent);
        console2.log("Token:", token);
        console2.log("Strategy:", STRATEGY);
        console2.log("Operation:", operation);
        console2.log("");

        ClawStrategy strategy = ClawStrategy(payable(STRATEGY));

        // Show info before operation
        _showInfo(strategy, token, agent);

        // Execute operation
        if (keccak256(bytes(operation)) == keccak256(bytes("claim"))) {
            _claimFees(agentPrivateKey, strategy, token, agent);
        } else if (keccak256(bytes(operation)) == keccak256(bytes("burn_weth"))) {
            _burnWithWETH(agentPrivateKey, strategy, token);
        } else if (keccak256(bytes(operation)) == keccak256(bytes("burn_token"))) {
            _burnWithToken(agentPrivateKey, strategy, token);
        } else if (keccak256(bytes(operation)) == keccak256(bytes("info"))) {
            // Info already shown above
            console2.log("Info displayed. No action taken.");
        } else {
            revert("Invalid operation. Use: claim, burn_weth, burn_token, or info");
        }
    }

    /// @notice Show current state info
    function _showInfo(ClawStrategy strategy, address token, address agent) internal view {
        // Get config
        ClawStrategy.TokenConfig memory config = strategy.getTokenConfig(token);

        console2.log("=== Token Config ===");
        console2.log("Agent:", config.agent);
        console2.log("Claim Percent:", config.claimPercent, "bps");
        console2.log("Burn Percent:", config.burnPercent, "bps");
        console2.log("Is Active:", config.isActive);
        console2.log("");

        // Get accumulated fees
        uint256 wethFees = strategy.wethFees(token);
        uint256 tokenFees = strategy.tokenFees(token);
        uint256 wethBurnPool = strategy.wethBurnPool(token);
        uint256 tokenBurnPool = strategy.tokenBurnPool(token);

        console2.log("=== Accumulated Fees (Claimable) ===");
        console2.log("WETH fees:", wethFees);
        console2.log("Token fees:", tokenFees);
        console2.log("");

        console2.log("=== Burn Pools ===");
        console2.log("WETH burn pool:", wethBurnPool);
        console2.log("Token burn pool:", tokenBurnPool);
        console2.log("");

        // Get burn config
        uint256 burnCooldown = strategy.burnCooldownBlocks();
        uint256 burnAmount = strategy.burnAmountWeth();
        uint256 lastBurn = strategy.lastBurnBlock(token);

        console2.log("=== Burn Config ===");
        console2.log("Cooldown blocks:", burnCooldown);
        console2.log("Burn amount WETH:", burnAmount);
        console2.log("Last burn block:", lastBurn);
        console2.log("Current block:", block.number);
        console2.log("Blocks until next burn:", 
            lastBurn + burnCooldown > block.number 
                ? lastBurn + burnCooldown - block.number 
                : 0
        );
        console2.log("");

        // Get agent balances
        uint256 agentWeth = IERC20(WETH).balanceOf(agent);
        uint256 agentToken = IERC20(token).balanceOf(agent);

        console2.log("=== Agent Balances ===");
        console2.log("WETH balance:", agentWeth);
        console2.log("Token balance:", agentToken);
        console2.log("");
    }

    /// @notice Claim accumulated fees
    function _claimFees(
        uint256 agentPrivateKey,
        ClawStrategy strategy,
        address token,
        address agent
    ) internal {
        console2.log("=== Claiming Fees ===");

        uint256 wethBefore = IERC20(WETH).balanceOf(agent);
        uint256 tokenBefore = IERC20(token).balanceOf(agent);

        vm.startBroadcast(agentPrivateKey);
        
        try strategy.claimAgentFee(token) {
            console2.log("Claim successful!");
        } catch Error(string memory reason) {
            console2.log("Claim failed:", reason);
            vm.stopBroadcast();
            return;
        } catch {
            console2.log("Claim failed: Unknown error");
            vm.stopBroadcast();
            return;
        }

        vm.stopBroadcast();

        uint256 wethAfter = IERC20(WETH).balanceOf(agent);
        uint256 tokenAfter = IERC20(token).balanceOf(agent);

        console2.log("WETH claimed:", wethAfter - wethBefore);
        console2.log("Token claimed:", tokenAfter - tokenBefore);
        console2.log("");
    }

    /// @notice Burn tokens using WETH from burn pool
    function _burnWithWETH(
        uint256 agentPrivateKey,
        ClawStrategy strategy,
        address token
    ) internal {
        console2.log("=== Burning with WETH ===");

        uint256 wethBurnBefore = strategy.wethBurnPool(token);
        uint256 burnAmount = strategy.burnAmountWeth();

        // Check cooldown
        uint256 lastBurn = strategy.lastBurnBlock(token);
        uint256 cooldown = strategy.burnCooldownBlocks();
        if (block.number <= lastBurn + cooldown) {
            console2.log("ERROR: Cooldown active!");
            console2.log("Blocks until next burn:", lastBurn + cooldown - block.number);
            return;
        }

        vm.startBroadcast(agentPrivateKey);

        try strategy.burnWithWETH(token) {
            console2.log("Burn with WETH successful!");
        } catch Error(string memory reason) {
            console2.log("Burn failed:", reason);
            vm.stopBroadcast();
            return;
        } catch {
            console2.log("Burn failed: Unknown error");
            vm.stopBroadcast();
            return;
        }

        vm.stopBroadcast();

        uint256 wethBurnAfter = strategy.wethBurnPool(token);
        console2.log("WETH burn pool after:", wethBurnAfter);
        console2.log("WETH used for burn:", wethBurnBefore - wethBurnAfter);
        console2.log("");
    }

    /// @notice Burn accumulated tokens from burn pool
    function _burnWithToken(
        uint256 agentPrivateKey,
        ClawStrategy strategy,
        address token
    ) internal {
        console2.log("=== Burning with Token ===");

        uint256 tokenBurnBefore = strategy.tokenBurnPool(token);

        console2.log("Token burn pool before:", tokenBurnBefore);

        if (tokenBurnBefore == 0) {
            console2.log("ERROR: No tokens in burn pool!");
            return;
        }

        vm.startBroadcast(agentPrivateKey);

        try strategy.burnWithToken(token) {
            console2.log("Burn with Token successful!");
        } catch Error(string memory reason) {
            console2.log("Burn failed:", reason);
            vm.stopBroadcast();
            return;
        } catch {
            console2.log("Burn failed: Unknown error");
            vm.stopBroadcast();
            return;
        }

        vm.stopBroadcast();

        uint256 tokenBurnAfter = strategy.tokenBurnPool(token);
        console2.log("Token burn pool after:", tokenBurnAfter);
        console2.log("Tokens burned:", tokenBurnBefore - tokenBurnAfter);
        console2.log("");
    }
}

