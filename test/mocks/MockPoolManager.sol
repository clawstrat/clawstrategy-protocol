// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Simplified mock - implements only functions needed for testing
// Note: This doesn't implement full IPoolManager interface to avoid conflicts
contract MockPoolManager {
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    mapping(Currency => uint256) public balances;
    bool public unlocked;

    function lock(bytes calldata) external returns (bytes32) {
        unlocked = false;
        return bytes32(0);
    }

    function unlock(bytes32) external {
        unlocked = true;
    }

    function swap(PoolKey memory, SwapParams memory params, bytes calldata)
        external
        returns (BalanceDelta delta)
    {
        // Mock swap: return negative amount0 and positive amount1 (or vice versa)
        // For simplicity, assume 1:1 swap ratio
        uint256 amountIn = uint256(-params.amountSpecified);
        
        // If zeroForOne: amount0 is negative (input), amount1 is positive (output)
        // If !zeroForOne: amount1 is negative (input), amount0 is positive (output)
        int128 amount0 = params.zeroForOne ? -int128(int256(amountIn)) : int128(int256(amountIn));
        int128 amount1 = params.zeroForOne ? int128(int256(amountIn)) : -int128(int256(amountIn));
        
        return toBalanceDelta(amount0, amount1);
    }

    function settle() external payable {
        // Mock settle
    }

    function take(Currency currency, address to, uint256 amount) external {
        // Mock take - transfer currency from this contract to recipient
        address currencyAddr = Currency.unwrap(currency);
        if (currencyAddr != address(0)) {
            IERC20(currencyAddr).transfer(to, amount);
        }
    }

    function sync(Currency) external {
        // Mock sync
    }

    function balanceOf(address, Currency) external view returns (uint256) {
        return 0;
    }
}

