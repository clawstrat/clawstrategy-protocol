// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IClanker} from "../src/interfaces/IClanker.sol";

/// @notice Script to deploy token DIRECTLY via Clanker (not through ClawStrategy)
/// @dev This creates a token that can be tested with adoptToken() function
contract DeployTokenDirectViaClanker is Script {
    /// @notice Clanker system addresses on Base Sepolia
    address public constant CLANKER = 0xE85A59c628F7d27878ACeB4bf3b35733630083a9;
    address public constant LOCKER = 0x824bB048a5EC6e06a09aEd115E9eEA4618DC2c8f;
    address public constant HOOK = 0x11b51DBC2f7F683b81CeDa83DC0078D57bA328cc;
    address public constant MEV_MODULE = 0x8CBD6694A9DFc0eF4D1cd333e013B88E7003E10A;
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    /// @notice Your wallet address (from env)
    address public YOUR_WALLET;

    /// @notice Token configuration
    string public constant TOKEN_NAME = "Test Adopt Token";
    string public constant TOKEN_SYMBOL = "TADOPT";

    /// @notice Launch ETH amount
    uint256 public constant LAUNCH_ETH = 0 ether; // 0 for testing

    function run() public {
        // Load from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        YOUR_WALLET = vm.envAddress("YOUR_WALLET");

        console2.log("=== Deploying Token Direct via Clanker ===");
        console2.log("This token will be deployed OUTSIDE ClawStrategy");
        console2.log("You can then test adoptToken() with it");
        console2.log("");
        console2.log("Token Name:", TOKEN_NAME);
        console2.log("Token Symbol:", TOKEN_SYMBOL);
        console2.log("Initial Recipient:", YOUR_WALLET);
        console2.log("Launch ETH:", LAUNCH_ETH);

        vm.startBroadcast(deployerPrivateKey);

        // Build TokenConfig
        IClanker.TokenConfig memory tokenConfig = IClanker.TokenConfig({
            tokenAdmin: YOUR_WALLET, // You will be admin initially
            name: TOKEN_NAME,
            symbol: TOKEN_SYMBOL,
            salt: keccak256(abi.encode(TOKEN_NAME, TOKEN_SYMBOL, block.timestamp)),
            image: "",
            metadata: "",
            context: "test-adopt",
            originatingChainId: block.chainid
        });

        // Build PoolConfig
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

        // LockerConfig: 100% to YOUR_WALLET initially
        IClanker.LockerConfig memory lockerConfig;
        lockerConfig.locker = LOCKER;
        lockerConfig.rewardAdmins = new address[](1);
        lockerConfig.rewardRecipients = new address[](1);
        lockerConfig.rewardBps = new uint16[](1);
        lockerConfig.tickLower = new int24[](1);
        lockerConfig.tickUpper = new int24[](1);
        lockerConfig.positionBps = new uint16[](1);
        lockerConfig.lockerData = hex"0000000000000000000000000000000000000000000000000000000000000020"
            hex"0000000000000000000000000000000000000000000000000000000000000020"
            hex"0000000000000000000000000000000000000000000000000000000000000001"
            hex"0000000000000000000000000000000000000000000000000000000000000000";

        // Set yourself as both admin and recipient
        lockerConfig.rewardAdmins[0] = YOUR_WALLET;
        lockerConfig.rewardRecipients[0] = YOUR_WALLET;
        lockerConfig.rewardBps[0] = uint16(10_000); // 100%
        
        // Position config
        lockerConfig.tickLower[0] = -230400;
        lockerConfig.tickUpper[0] = -120000;
        lockerConfig.positionBps[0] = uint16(10_000);

        // MEV config (Sniper Auction V2)
        IClanker.MevModuleConfig memory mevConfig = IClanker.MevModuleConfig({
            mevModule: MEV_MODULE,
            mevModuleData: hex"00000000000000000000000000000000000000000000000000000000000a2c99"
                           hex"000000000000000000000000000000000000000000000000000000000000a2c9"
                           hex"000000000000000000000000000000000000000000000000000000000000000f"
        });

        // No extensions
        IClanker.ExtensionConfig[] memory extensions = new IClanker.ExtensionConfig[](0);

        IClanker.DeploymentConfig memory config = IClanker.DeploymentConfig({
            tokenConfig: tokenConfig,
            poolConfig: poolConfig,
            lockerConfig: lockerConfig,
            mevModuleConfig: mevConfig,
            extensionConfigs: extensions
        });

        // Deploy directly via Clanker
        IClanker clanker = IClanker(CLANKER);
        address tokenAddress = clanker.deployToken{value: LAUNCH_ETH}(config);

        vm.stopBroadcast();

        console2.log("\n=== Token Deployed Successfully! ===");
        console2.log("Token Address:", tokenAddress);
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Update reward recipient to ClawStrategy:");
        console2.log("   cast send", LOCKER);
        console2.log("   'updateRewardRecipient(address,uint256,address)'");
        console2.log("   ", tokenAddress, "0 $STRATEGY_ADDRESS");
        console2.log("   --rpc-url base-sepolia --private-key $PRIVATE_KEY");
        console2.log("");
        console2.log("2. Then run AdoptExistingToken script:");
        console2.log("   Set TOKEN_TO_ADOPT =", tokenAddress);
        console2.log("   forge script script/AdoptExistingToken.s.sol --broadcast");
        console2.log("");
        console2.log("3. Verify token was adopted:");
        console2.log("   cast call $STRATEGY 'tokenConfigs(address)'", tokenAddress);
    }
}

