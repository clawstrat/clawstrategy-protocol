// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Script to encode lockerData for ClankerLpLockerFeeConversion with 1 feePreference entry
contract EncodeLockerData is Script {
    enum FeeIn {
        Both,      // 0: Receive both WETH and Token
        Paired,    // 1: Only receive WETH (swap Token → WETH)
        Clanker    // 2: Only receive Token (swap WETH → Token)
    }

    struct LpFeeConversionInfo {
        FeeIn[] feePreference;
    }

    function run() public pure {
        // Create struct with 1 feePreference = Both
        FeeIn[] memory feePreference = new FeeIn[](1);
        feePreference[0] = FeeIn.Both;  // STRATEGY receives both WETH and Token

        LpFeeConversionInfo memory info = LpFeeConversionInfo({
            feePreference: feePreference
        });

        bytes memory encoded = abi.encode(info);
        
        console2.log("=== Encoded lockerData for 1 entry (FeeIn.Both) ===");
        console2.logBytes(encoded);
        console2.log("\nCopy hex value above and paste into ClawStrategyDeployToken.s.sol");
    }
}

