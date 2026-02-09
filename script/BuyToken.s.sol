// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {IClanker} from "../src/interfaces/IClanker.sol";
import {IClankerLpLocker} from "../src/interfaces/IClankerLpLocker.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {IUniswapV4Router04} from "../src/interfaces/IUniswapV4Router04.sol";

/// @notice Script to buy token using WETH via Uniswap V4Router04
/// @dev Requires env vars:
///      PRIVATE_KEY - buyer EOA private key
///      TOKEN       - token address to buy
///      AMOUNT_ETH  - amount of ETH to spend (in wei, e.g., 1000000000000000000 for 1 ETH)
contract BuyToken is Script {
    using SafeERC20 for IERC20;

    /// @notice Clanker v4 on Base Sepolia
    address public constant CLANKER = 0xE85A59c628F7d27878ACeB4bf3b35733630083a9;

    /// @notice Uniswap V4Router04 on Base Sepolia
    address public constant ROUTER = 0x00000000000044a361Ae3cAc094c9D1b14Eece97;

    /// @notice Canonical WETH on Base
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    function run() public {
        uint256 buyerPrivateKey = vm.envUint("PRIVATE_KEY");
        address token = vm.envAddress("TOKEN");
        uint256 amountEth = vm.envUint("AMOUNT_ETH");

        address buyer = vm.addr(buyerPrivateKey);

        console2.log("=== Buy Token Script ===");
        console2.log("Buyer:", buyer);
        console2.log("Token:", token);
        console2.log("Amount ETH:", amountEth);

        vm.startBroadcast(buyerPrivateKey);

        // 1. Get PoolKey from Clanker
        PoolKey memory poolKey = _getPoolKey(token);

        console2.log("Pool Currency0:", Currency.unwrap(poolKey.currency0));
        console2.log("Pool Currency1:", Currency.unwrap(poolKey.currency1));

        // 2. Wrap ETH to WETH
        uint256 wethBefore = IERC20(WETH).balanceOf(buyer);
        IWETH(WETH).deposit{value: amountEth}();
        uint256 wethAfter = IERC20(WETH).balanceOf(buyer);
        console2.log("WETH wrapped:", wethAfter - wethBefore);

        // 3. Approve WETH to router
        IERC20(WETH).forceApprove(ROUTER, amountEth);

        // 4. Record token balance before swap
        uint256 tokenBefore = IERC20(token).balanceOf(buyer);

        // 5. Swap WETH → Token
        uint256 tokenReceived = _swapWETHForToken(poolKey, token, amountEth);

        // 6. Verify token balance
        uint256 tokenAfter = IERC20(token).balanceOf(buyer);
        console2.log("Token balance before:", tokenBefore);
        console2.log("Token balance after:", tokenAfter);
        console2.log("Token received:", tokenReceived);

        vm.stopBroadcast();

        console2.log("=== Buy Successful ===");
    }

    /// @notice Get PoolKey for a token from Clanker system
    function _getPoolKey(address token) internal view returns (PoolKey memory) {
        IClanker.DeploymentInfo memory deploymentInfo = 
            IClanker(CLANKER).tokenDeploymentInfo(token);
        address locker = deploymentInfo.locker;
        IClankerLpLocker.TokenRewardInfo memory rewardInfo =
            IClankerLpLocker(locker).tokenRewards(token);
        return rewardInfo.poolKey;
    }

    /// @notice Swap WETH for token using V4Router04
    function _swapWETHForToken(
        PoolKey memory poolKey,
        address token,
        uint256 wethAmount
    ) internal returns (uint256 tokenAmount) {
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == WETH;

        console2.log("Swapping...");
        console2.log("zeroForOne:", zeroForOne);
        console2.log("amountSpecified:", wethAmount);

        // Execute swap - exact input, single pool
        // Note: WETH already wrapped and approved in run()
        BalanceDelta delta = IUniswapV4Router04(ROUTER).swapExactTokensForTokens(
            wethAmount,          // amountIn
            0,                   // amountOutMin (accept any amount for testing)
            zeroForOne,          // direction
            poolKey,             // pool to swap through
            bytes(""),           // hookData
            msg.sender,          // receiver
            block.timestamp + 1000 // deadline - add buffer for onchain execution
        );

        // Calculate tokens received from delta
        // For exact input swaps, the output is the opposite side
        int128 deltaOut = zeroForOne ? delta.amount1() : delta.amount0();
        // deltaOut is positive for tokens received by us, so directly cast it
        tokenAmount = uint256(int256(deltaOut));

        console2.log("Tokens received:", tokenAmount);

        return tokenAmount;
    }

    /// @notice Allow script to receive ETH
    receive() external payable {}
}

