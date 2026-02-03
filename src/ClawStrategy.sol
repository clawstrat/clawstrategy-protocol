// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// IERC20Burnable doesn't exist in OZ v5, using interface directly

import {IClanker} from "./interfaces/IClanker.sol";
import {IClankerFeeLocker} from "./interfaces/IClankerFeeLocker.sol";
import {IClankerLpLocker} from "./interfaces/IClankerLpLocker.sol";
import {IClankerToken} from "./interfaces/IClankerToken.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @notice Simple interface for burnable ERC20 tokens
interface IERC20Burnable {
    function burn(uint256 amount) external;
}

/// @title ClawStrategy
/// @notice Contract to manage token launches via Clanker, distribute fees, and handle burns
contract ClawStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Basis points constant (10000 = 100%)
    uint256 public constant BPS = 10_000;

    /// @notice Clanker system addresses
    IClanker public immutable clanker;
    IClankerFeeLocker public immutable feeLocker;
    IPoolManager public immutable poolManager;
    IWETH public immutable weth;

    /// @notice Core mappings
    mapping(address token => address agent) public tokenToAgent;
    mapping(address agent => address[] tokens) public agentToTokens;
    mapping(address token => TokenConfig config) public tokenConfigs;

    /// @notice Fee accumulation
    mapping(address token => uint256 wethAccumulated) public wethFees;
    mapping(address token => uint256 tokenAccumulated) public tokenFees;

    /// @notice Burn cooldown for WETH
    mapping(address token => uint256 lastBurnBlock) public lastBurnBlock;

    /// @notice Token configuration
    struct TokenConfig {
        address agent;
        uint256 claimPercent; // basis points (e.g., 7000 = 70%)
        uint256 burnPercent;  // basis points (e.g., 3000 = 30%)
        bool isActive;
    }

    /// @notice Custom errors
    error InvalidFeeConfig();
    error TokenNotActive();
    error NotAgent();
    error CooldownActive();
    error InsufficientWETH();
    error NoFeesToClaim();
    error NoTokensToBurn();

    /// @notice Events
    event TokenLaunched(
        address indexed token,
        address indexed agent,
        uint256 claimPercent,
        uint256 burnPercent
    );
    event FeesCollected(address indexed token, uint256 wethAmount, uint256 tokenAmount);
    event FeesDistributed(
        address indexed token,
        uint256 wethForClaim,
        uint256 wethForBurn,
        uint256 tokenForClaim,
        uint256 tokenForBurn
    );
    event AgentFeeClaimed(
        address indexed token,
        address indexed agent,
        uint256 wethAmount,
        uint256 tokenAmount
    );
    event BurnedWithWETH(address indexed token, uint256 wethAmount, uint256 tokenAmount);
    event BurnedWithToken(address indexed token, uint256 tokenAmount);

    /// @notice Constructor
    /// @param _clanker Clanker contract address
    /// @param _feeLocker ClankerFeeLocker contract address
    /// @param _poolManager Uniswap V4 PoolManager address
    /// @param _weth WETH contract address
    /// @param _owner Owner address
    constructor(
        address _clanker,
        address _feeLocker,
        address _poolManager,
        address _weth,
        address _owner
    ) Ownable(_owner) {
        clanker = IClanker(_clanker);
        feeLocker = IClankerFeeLocker(_feeLocker);
        poolManager = IPoolManager(_poolManager);
        weth = IWETH(_weth);
    }

    /// @notice Get all tokens for an agent
    /// @param agent Agent address
    /// @return Array of token addresses
    function getAgentTokens(address agent) external view returns (address[] memory) {
        return agentToTokens[agent];
    }

    /// @notice Get token configuration
    /// @param token Token address
    /// @return TokenConfig struct
    function getTokenConfig(address token) external view returns (TokenConfig memory) {
        return tokenConfigs[token];
    }

    // ============ TOKEN LAUNCH FUNCTIONS ============

    /// @notice Deploy token via Clanker and setup configuration
    /// @param deploymentConfig Clanker deployment configuration
    /// @param agent Agent address
    /// @param claimPercent Fee percentage for agent claim (basis points)
    /// @param burnPercent Fee percentage for burn (basis points)
    /// @return tokenAddress Deployed token address
    function deployTokenViaClanker(
        IClanker.DeploymentConfig memory deploymentConfig,
        address agent,
        uint256 claimPercent,
        uint256 burnPercent
    ) external payable onlyOwner nonReentrant returns (address tokenAddress) {
        // Validate fee config
        if (claimPercent + burnPercent != BPS) revert InvalidFeeConfig();

        // Deploy token via Clanker
        tokenAddress = clanker.deployToken{value: msg.value}(deploymentConfig);

        // Set ClawStrategy as admin of token (for burn permission)
        IClankerToken(tokenAddress).updateAdmin(address(this));

        // Store mappings
        tokenToAgent[tokenAddress] = agent;
        agentToTokens[agent].push(tokenAddress);
        tokenConfigs[tokenAddress] = TokenConfig({
            agent: agent,
            claimPercent: claimPercent,
            burnPercent: burnPercent,
            isActive: true
        });

        emit TokenLaunched(tokenAddress, agent, claimPercent, burnPercent);
    }

    // ============ POOLKEY HELPER ============

    /// @notice Get PoolKey for a token from Clanker system
    /// @param token Token address
    /// @return poolKey PoolKey struct
    function getPoolKey(address token) internal view returns (PoolKey memory) {
        IClanker.DeploymentInfo memory deploymentInfo = clanker.tokenDeploymentInfo(token);
        address locker = deploymentInfo.locker;
        IClankerLpLocker.TokenRewardInfo memory rewardInfo =
            IClankerLpLocker(locker).tokenRewards(token);
        return rewardInfo.poolKey;
    }

    // ============ FEE COLLECTION & DISTRIBUTION ============

    /// @notice Collect fees from locker and distribute according to config
    /// @param token Token address
    function collectAndDistributeFees(address token) external nonReentrant {
        TokenConfig memory config = tokenConfigs[token];
        if (!config.isActive) revert TokenNotActive();

        // Get locker from deployment info
        IClanker.DeploymentInfo memory deploymentInfo = clanker.tokenDeploymentInfo(token);
        address locker = deploymentInfo.locker;

        // Trigger collection from pool
        IClankerLpLocker(locker).collectRewards(token);

        // Claim WETH fees from fee locker
        uint256 wethBefore = weth.balanceOf(address(this));
        try feeLocker.claim(address(this), address(weth)) {} catch {}
        uint256 wethReceived = weth.balanceOf(address(this)) - wethBefore;

        // Claim token fees from fee locker
        uint256 tokenBefore = IERC20(token).balanceOf(address(this));
        try feeLocker.claim(address(this), token) {} catch {}
        uint256 tokenReceived = IERC20(token).balanceOf(address(this)) - tokenBefore;

        emit FeesCollected(token, wethReceived, tokenReceived);

        // Distribute according to config
        uint256 wethForClaim = (wethReceived * config.claimPercent) / BPS;
        uint256 wethForBurn = wethReceived - wethForClaim;
        uint256 tokenForClaim = (tokenReceived * config.claimPercent) / BPS;
        uint256 tokenForBurn = tokenReceived - tokenForClaim;

        // Accumulate for agent claim
        wethFees[token] += wethForClaim;
        tokenFees[token] += tokenForClaim;

        // Accumulate burn amounts (can be burned later)
        // Note: For now, we accumulate burn amounts separately
        // They can be burned via burnWithWETH or burnWithToken

        emit FeesDistributed(token, wethForClaim, wethForBurn, tokenForClaim, tokenForBurn);
    }

    // ============ AGENT CLAIM ============

    /// @notice Agent claims accumulated fees
    /// @param token Token address
    function claimAgentFee(address token) external nonReentrant {
        TokenConfig memory config = tokenConfigs[token];
        if (msg.sender != config.agent) revert NotAgent();

        uint256 wethAmount = wethFees[token];
        uint256 tokenAmount = tokenFees[token];

        if (wethAmount == 0 && tokenAmount == 0) revert NoFeesToClaim();

        // Reset accumulated amounts
        wethFees[token] = 0;
        tokenFees[token] = 0;

        // Transfer to agent
        if (wethAmount > 0) {
            IERC20(address(weth)).safeTransfer(config.agent, wethAmount);
        }
        if (tokenAmount > 0) {
            IERC20(token).safeTransfer(config.agent, tokenAmount);
        }

        emit AgentFeeClaimed(token, config.agent, wethAmount, tokenAmount);
    }

    // ============ SWAP FUNCTION ============

    /// @notice Swap WETH for token using PoolManager
    /// @param poolKey PoolKey for the swap
    /// @param token Token address to receive
    /// @param wethAmount Amount of WETH to swap
    /// @return tokenAmount Amount of tokens received
    function _swapWETHForToken(
        PoolKey memory poolKey,
        address token,
        uint256 wethAmount
    ) internal returns (uint256 tokenAmount) {
        address wethAddress = address(weth);
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == wethAddress;

        // Build swap params
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(wethAmount), // Negative = exact input
            sqrtPriceLimitX96: 0 // No price limit
        });

        // Record balance before
        uint256 tokenBefore = IERC20(token).balanceOf(address(this));

        // Approve WETH to pool manager
        SafeERC20.forceApprove(IERC20(address(weth)), address(poolManager), wethAmount);

        // Execute swap
        BalanceDelta delta = poolManager.swap(poolKey, swapParams, "");

        // Determine swap outcomes
        int128 deltaOut = delta.amount0() < 0 ? delta.amount1() : delta.amount0();

        // Pay the input token (WETH)
        poolManager.sync(Currency.wrap(wethAddress));
        Currency.wrap(wethAddress).transfer(address(poolManager), wethAmount);
        poolManager.settle();

        // Take out the converted token
        poolManager.take(Currency.wrap(token), address(this), uint256(uint128(deltaOut)));

        // Calculate amount received
        uint256 tokenAfter = IERC20(token).balanceOf(address(this));
        tokenAmount = tokenAfter - tokenBefore;

        return tokenAmount;
    }

    // ============ BURN FUNCTIONS ============

    /// @notice Burn tokens using WETH (1 ETH per call, with cooldown)
    /// @param token Token address
    function burnWithWETH(address token) external nonReentrant {
        TokenConfig memory config = tokenConfigs[token];
        if (msg.sender != config.agent) revert NotAgent();
        if (block.number <= lastBurnBlock[token]) revert CooldownActive();

        uint256 wethAmount = 1e18; // 1 ETH
        if (weth.balanceOf(address(this)) < wethAmount) revert InsufficientWETH();

        // Get PoolKey from locker
        PoolKey memory poolKey = getPoolKey(token);

        // Swap WETH → token
        uint256 tokenAmount = _swapWETHForToken(poolKey, token, wethAmount);

        // Burn token
        IERC20Burnable(token).burn(tokenAmount);

        // Update last burn block
        lastBurnBlock[token] = block.number;

        emit BurnedWithWETH(token, wethAmount, tokenAmount);
    }

    /// @notice Burn accumulated token fees
    /// @param token Token address
    function burnWithToken(address token) external nonReentrant {
        TokenConfig memory config = tokenConfigs[token];
        if (msg.sender != config.agent) revert NotAgent();

        uint256 amount = tokenFees[token];
        if (amount == 0) revert NoTokensToBurn();

        // Reset accumulated amount
        tokenFees[token] = 0;

        // Burn token
        IERC20Burnable(token).burn(amount);

        emit BurnedWithToken(token, amount);
    }
}

