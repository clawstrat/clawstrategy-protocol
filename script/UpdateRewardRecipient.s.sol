// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IClankerLpLocker} from "../src/interfaces/IClankerLpLocker.sol";

/// @notice Script to update reward recipient for a Clanker token
/// @dev This is step 2 after deploying token directly via Clanker
contract UpdateRewardRecipient is Script {
    /// @notice Locker address on Base Sepolia
    address public constant LOCKER = 0x824bB048a5EC6e06a09aEd115E9eEA4618DC2c8f;

    /// @notice ClawStrategy address (from env)
    address public STRATEGY;

    /// @notice Token to update (from env)
    address public TOKEN;

    /// @notice Reward index (usually 0)
    uint256 public constant REWARD_INDEX = 0;

    function run() public {
        // Load from env
        uint256 privateKey = vm.envUint("AGENT_PRIVATE_KEY");
        STRATEGY = vm.envAddress("STRATEGY");
        TOKEN = vm.envAddress("TOKEN");

        console2.log("=== Updating Reward Recipient ===");
        console2.log("Locker:", LOCKER);
        console2.log("Token:", TOKEN);
        console2.log("Reward Index:", REWARD_INDEX);
        console2.log("New Recipient:", STRATEGY);

        // Query current recipient
        IClankerLpLocker locker = IClankerLpLocker(LOCKER);
        IClankerLpLocker.TokenRewardInfo memory info = locker.tokenRewards(TOKEN);
        
        console2.log("\nCurrent Recipients:");
        for (uint256 i = 0; i < info.rewardRecipients.length; i++) {
            console2.log("  Index", i, ":", info.rewardRecipients[i]);
            console2.log("  BPS:", info.rewardBps[i]);
        }

        console2.log("\nCurrent Admins:");
        for (uint256 i = 0; i < info.rewardAdmins.length; i++) {
            console2.log("  Index", i, ":", info.rewardAdmins[i]);
        }

        vm.startBroadcast(privateKey);

        // Update reward recipient
        locker.updateRewardRecipient(TOKEN, REWARD_INDEX, STRATEGY);

        vm.stopBroadcast();

        console2.log("\n=== Reward Recipient Updated! ===");
        console2.log("Recipient at index", REWARD_INDEX, "is now:", STRATEGY);
        console2.log("");
        console2.log("Next step: Run AdoptExistingToken script");
        console2.log("  forge script script/AdoptExistingToken.s.sol \\");
        console2.log("    --rpc-url base-sepolia \\");
        console2.log("    --broadcast");
    }
}

