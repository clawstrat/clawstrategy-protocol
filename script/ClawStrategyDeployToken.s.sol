// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ClawStrategy} from "../src/ClawStrategy.sol";
import {IClanker} from "../src/interfaces/IClanker.sol";

/// @notice Script to deploy the first token via ClawStrategy already deployed on Base Sepolia
/// @dev Uses reasonable default config + fixed agent, just set PRIVATE_KEY env.
contract ClawStrategyDeployToken is Script {
    /// @notice Address of ClawStrategy (from env)
    address payable public STRATEGY;

    /// @notice Agent to receive fee / burn rights for this token (from env)
    address public AGENT;

    /// @notice Default token info
    string public constant TOKEN_NAME = "ClawStrategy Agent Alpha";
    string public constant TOKEN_SYMBOL = "CLAWA";

    /// @notice Default fee config: 70% claim (30% burn is auto-calculated)
    uint256 public constant AGENT_FEE_BPS = 7_000;

    /// @notice Amount of ETH to launch the pool (can be adjusted if needed)
    /// @dev Should use > 0 when launching for real, 0 for debugging to save gas.
    uint256 public constant LAUNCH_ETH = 0 ether;

    /// @notice Clanker v4.1 system address on Base Sepolia (mirror config from your tx)
    /// @dev Uses StaticFeeV2 + LpLockerFeeConversion + SniperAuctionV2 same as ClawStrat main.
    address public constant LOCKER = 0x824bB048a5EC6e06a09aEd115E9eEA4618DC2c8f; // ClankerLpLockerFeeConversion (Base Sepolia)
    address public constant HOOK = 0x11b51DBC2f7F683b81CeDa83DC0078D57bA328cc;   // ClankerHookStaticFeeV2 (Base Sepolia)
    address public constant MEV_MODULE = 0x8CBD6694A9DFc0eF4D1cd333e013B88E7003E10A; // ClankerSniperAuctionV2 (Base Sepolia)
    address public constant WETH = 0x4200000000000000000000000000000000000006;  // Canonical WETH

    function run() public {
        // Load from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        STRATEGY = payable(vm.envAddress("STRATEGY"));
        AGENT = vm.envAddress("AGENT");

        vm.startBroadcast(deployerPrivateKey);

        // Build TokenConfig
        IClanker.TokenConfig memory tokenConfig = IClanker.TokenConfig({
            tokenAdmin: STRATEGY,
            name: TOKEN_NAME,
            symbol: TOKEN_SYMBOL,
            salt: keccak256(abi.encode(TOKEN_NAME, TOKEN_SYMBOL, AGENT, block.timestamp)),
            image: "",
            metadata: "",
            context: "clawstrategy",
            originatingChainId: block.chainid
        });

        // Build PoolConfig (token/WETH pool), mirror config:
        // tickSpacing: 200, tickIfToken0IsClanker: -230400, poolData as in your tx
        IClanker.PoolConfig memory poolConfig = IClanker.PoolConfig({
            hook: HOOK,
            pairedToken: WETH,
            tickIfToken0IsClanker: -230400,
            tickSpacing: 200,
            poolData: hex"0000000000000000000000000000000000000000000000000000000000000020"
                hex"0000000000000000000000000000000000000000000000000000000000000000"
                hex"0000000000000000000000000000000000000000000000000000000000000060"
                hex"0000000000000000000000000000000000000000000000000000000000000080"
                hex"0000000000000000000000000000000000000000000000000000000000000000"
                hex"0000000000000000000000000000000000000000000000000000000000000040"
                hex"0000000000000000000000000000000000000000000000000000000000000271"
                hex"0000000000000000000000000000000000000000000000000000000000002710"
        });

        // LockerConfig: 100% LP fee to ClawStrategy (only 1 reward entry)
        IClanker.LockerConfig memory lockerConfig;
        lockerConfig.locker = LOCKER;
        lockerConfig.rewardAdmins = new address[](1);
        lockerConfig.rewardRecipients = new address[](1);
        lockerConfig.rewardBps = new uint16[](1);
        lockerConfig.tickLower = new int24[](1);
        lockerConfig.tickUpper = new int24[](1);
        lockerConfig.positionBps = new uint16[](1);
        // New lockerData: encoded for 1 feePreference (FeeIn.Both)
        lockerConfig.lockerData = hex"0000000000000000000000000000000000000000000000000000000000000020"
            hex"0000000000000000000000000000000000000000000000000000000000000020"
            hex"0000000000000000000000000000000000000000000000000000000000000001"
            hex"0000000000000000000000000000000000000000000000000000000000000000";

        // 1 reward entry: 100% to STRATEGY, receive both WETH and Token (FeeIn.Both)
        lockerConfig.rewardAdmins[0] = STRATEGY;
        lockerConfig.rewardRecipients[0] = STRATEGY;
        lockerConfig.rewardBps[0] = uint16(10_000);
        
        // Position config: 1 range [-230400, -120000], 100% liquidity
        lockerConfig.tickLower[0] = -230400;
        lockerConfig.tickUpper[0] = -120000;
        lockerConfig.positionBps[0] = uint16(10_000);

        // Mev module (config from mainnet, may need adjustment for Sepolia)
        IClanker.MevModuleConfig memory mevConfig = IClanker.MevModuleConfig({
            mevModule: MEV_MODULE,
            mevModuleData: hex"00000000000000000000000000000000000000000000000000000000000a2c99"
                           hex"000000000000000000000000000000000000000000000000000000000000a2c9"
                           hex"000000000000000000000000000000000000000000000000000000000000000f"
        });

        // Don't use extensions for the first token
        IClanker.ExtensionConfig[] memory extensions = new IClanker.ExtensionConfig[](0);

        IClanker.DeploymentConfig memory config = IClanker.DeploymentConfig({
            tokenConfig: tokenConfig,
            poolConfig: poolConfig,
            lockerConfig: lockerConfig,
            mevModuleConfig: mevConfig,
            extensionConfigs: extensions
        });

        ClawStrategy strategy = ClawStrategy(STRATEGY);

        address token = strategy.deployTokenViaClanker{value: LAUNCH_ETH}(
            config,
            AGENT,
            AGENT_FEE_BPS
        );

        vm.stopBroadcast();

        console2.log("New Clanker token deployed via ClawStrategy:", token);
        console2.log("Agent:", AGENT);
        console2.log("Name:", TOKEN_NAME);
        console2.log("Symbol:", TOKEN_SYMBOL);
        console2.log("Agent Fee BPS:", AGENT_FEE_BPS);
        console2.log("Burn BPS (auto-calculated):", 10_000 - AGENT_FEE_BPS);
        console2.log("Launch ETH (wei):", LAUNCH_ETH);
    }
}


