// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/// @title Uniswap V4 Swap Router
/// @notice A simple, stateless router for execution of swaps against Uniswap v4 Pools
interface IUniswapV4Router04 {
    /// @notice Single pool, exact input swap - swap the specified amount of input tokens for as many output tokens as possible, on a single pool
    /// @param amountIn the amount of input tokens to swap
    /// @param amountOutMin the minimum amount of output tokens that must be received for the transaction not to revert
    /// @param zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    /// @param poolKey the pool to swap through
    /// @param hookData the data to be passed to the hook
    /// @param receiver the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice Singe pool, exact output swap; swap as few input tokens as possible for the specified amount of output tokens, on a single pool
    /// @param amountOut the amount of output tokens to receive
    /// @param amountInMax the maximum amount of input tokens that can be spent for the transaction not to revert
    /// @param zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    /// @param poolKey the pool to swap through
    /// @param hookData the data to be passed to the hook
    /// @param receiver the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice General-purpose single-pool swap interface
    /// @param amountSpecified the amount of tokens to be swapped, negative for exact input swaps and positive for exact output swaps
    /// @param amountLimit the minimum amount of output tokens for exact input swaps, the maximum amount of input tokens for exact output swaps
    /// @param zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    /// @param poolKey the pool to swap through
    /// @param hookData the data to be passed to the hook
    /// @param receiver the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swap(
        int256 amountSpecified,
        uint256 amountLimit,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice Public view function to be used instead of msg.sender, as the contract performs self-reentrancy and at
    /// times msg.sender == address(this). Instead msgSender() returns the initiator of the lock
    function msgSender() external view returns (address);
}

