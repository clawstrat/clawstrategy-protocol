// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerLpLocker} from "../../src/interfaces/IClankerLpLocker.sol";
import {IClanker} from "../../src/interfaces/IClanker.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract MockLocker is IClankerLpLocker {
    mapping(address token => TokenRewardInfo) internal _tokenRewards;

    function tokenRewards(address token) external view returns (TokenRewardInfo memory) {
        return _tokenRewards[token];
    }

    function setTokenRewards(address token, TokenRewardInfo memory info) external {
        _tokenRewards[token] = info;
    }

    function collectRewards(address) external {
        // Mock implementation
    }

    function collectRewardsWithoutUnlock(address) external {
        // Mock implementation
    }

    function placeLiquidity(
        IClanker.LockerConfig memory,
        IClanker.PoolConfig memory,
        PoolKey memory,
        uint256,
        address
    ) external returns (uint256) {
        return 1;
    }

    function updateRewardRecipient(address, uint256, address) external {
        // Mock implementation
    }

    function updateRewardAdmin(address, uint256, address) external {
        // Mock implementation
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

