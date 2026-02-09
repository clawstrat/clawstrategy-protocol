// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// IERC20Burnable doesn't exist in OZ v5, using interface directly

import {IClanker} from "./interfaces/IClanker.sol";
import {IClankerFeeLocker} from "./interfaces/IClankerFeeLocker.sol";
import {IClankerLpLocker} from "./interfaces/IClankerLpLocker.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IUniswapV4Router04} from "./interfaces/IUniswapV4Router04.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/// ╔════════════════════════════════════════════════════════════════════════════════════╗
/// ║                                                                                    ║
/// ║  ██████╗██╗      █████╗ ██╗    ██╗ █████╗  ██████╗ ███████╗████████╗██████╗        ║
/// ║ ██╔════╝██║     ██╔══██╗██║    ██║██╔══██╗██╔════╝ ██╔════╝╚══██╔══╝██╔══██╗       ║
/// ║ ██║     ██║     ███████║██║ █╗ ██║███████║██║  ███╗███████╗   ██║   ██████╔╝       ║
/// ║ ██║     ██║     ██╔══██║██║███╗██║██╔══██║██║   ██║╚════██║   ██║   ██╔══██╗       ║
/// ║ ╚██████╗███████╗██║  ██║╚███╔███╔╝██║  ██║╚██████╔╝███████║   ██║   ██║  ██║       ║
/// ║  ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝       ║
/// ║                                                                                    ║
/// ║                    Claw Strategy Agent Contract                                    ║
/// ║                                                                                    ║
/// ╚════════════════════════════════════════════════════════════════════════════════════╝
///
/// @title ClawStrategyAgent
/// @author ClawStrategy Team
/// @notice Contract to manage token launches via Clanker, distribute fees, and handle burns
contract ClawStrategyAgent is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Basis points constant (10000 = 100%)
    uint256 public constant BPS = 10_000;
    address public constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    /// @notice Clanker system addresses
    IClanker public immutable clanker;
    IClankerFeeLocker public immutable feeLocker;
    IUniswapV4Router04 public immutable router;
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

    /// @notice Separate pools for burn amounts
    mapping(address token => uint256 wethAccumulated) public wethBurnPool;
    mapping(address token => uint256 tokenAccumulated) public tokenBurnPool;

    /// @notice Configurable parameters
    uint256 public maxAgentFeeBps = 7000; // Default: 70% max
    uint256 public burnCooldownBlocks = 5; // Default: 5 blocks
    uint256 public burnAmountWeth = 1 ether; // Default: 1 ETH

    /// @notice Token configuration
    struct TokenConfig {
        address agent;
        uint256 claimPercent; // basis points (e.g., 7000 = 70%)
        uint256 burnPercent; // basis points (e.g., 3000 = 30%)
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
    error ZeroAddress();
    error InvalidAmount();
    error SameAgent();
    error SameFeeConfig();
    error TokenAlreadyExists();
    error TokenNotDeployedViaClanker();

    /// @notice Events
    event TokenLaunched(
        address indexed token,
        address indexed agent,
        uint256 claimPercent,
        uint256 burnPercent
    );
    event FeesCollected(
        address indexed token,
        uint256 wethAmount,
        uint256 tokenAmount
    );
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
    event BurnedWithWETH(
        address indexed token,
        uint256 wethAmount,
        uint256 tokenAmount
    );
    event BurnedWithToken(address indexed token, uint256 tokenAmount);
    event MaxAgentFeeBpsUpdated(uint256 oldMax, uint256 newMax);
    event BurnCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event BurnAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event AgentUpdated(
        address indexed token,
        address indexed oldAgent,
        address indexed newAgent
    );
    event FeeConfigUpdated(
        address indexed token,
        uint256 oldClaimPercent,
        uint256 newClaimPercent,
        uint256 oldBurnPercent,
        uint256 newBurnPercent
    );
    event TokenActiveStatusUpdated(address indexed token, bool isActive);
    event EmergencyWithdraw(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event TokenAdopted(
        address indexed token,
        address indexed agent,
        uint256 claimPercent,
        uint256 burnPercent
    );

    /// @notice Constructor
    /// @param _clanker Clanker contract address
    /// @param _feeLocker ClankerFeeLocker contract address
    /// @param _router Uniswap V4Router04 address
    /// @param _weth WETH contract address
    /// @param _owner Owner address
    constructor(
        address _clanker,
        address _feeLocker,
        address _router,
        address _weth,
        address _owner
    ) Ownable(_owner) {
        clanker = IClanker(_clanker);
        feeLocker = IClankerFeeLocker(_feeLocker);
        router = IUniswapV4Router04(_router);
        weth = IWETH(_weth);

        // Approve WETH to router once during deployment for gas efficiency
        SafeERC20.forceApprove(IERC20(_weth), _router, type(uint256).max);
    }

    /// @notice Get all tokens for an agent
    /// @param agent Agent address
    /// @return Array of token addresses
    function getAgentTokens(
        address agent
    ) external view returns (address[] memory) {
        return agentToTokens[agent];
    }

    /// @notice Get token configuration
    /// @param token Token address
    /// @return TokenConfig struct
    function getTokenConfig(
        address token
    ) external view returns (TokenConfig memory) {
        return tokenConfigs[token];
    }

    // ============ CONFIGURATION FUNCTIONS ============

    /// @notice Set maximum agent fee percentage
    /// @param newMax New maximum fee in basis points
    function setMaxAgentFeeBps(uint256 newMax) external onlyOwner {
        require(newMax <= BPS, "Cannot exceed 100%");
        require(newMax >= 5000, "Must allow at least 50%");
        uint256 oldMax = maxAgentFeeBps;
        maxAgentFeeBps = newMax;
        emit MaxAgentFeeBpsUpdated(oldMax, newMax);
    }

    /// @notice Set burn cooldown period in blocks
    /// @param newCooldown New cooldown in blocks
    function setBurnCooldownBlocks(uint256 newCooldown) external onlyOwner {
        require(newCooldown >= 1, "Min 1 block");
        require(newCooldown <= 100, "Max 100 blocks");
        uint256 oldCooldown = burnCooldownBlocks;
        burnCooldownBlocks = newCooldown;
        emit BurnCooldownUpdated(oldCooldown, newCooldown);
    }

    /// @notice Set WETH amount to use per burn
    /// @param newAmount New burn amount in wei
    function setBurnAmountWeth(uint256 newAmount) external onlyOwner {
        require(newAmount > 0, "Must be > 0");
        require(newAmount <= 10 ether, "Max 10 ETH");
        uint256 oldAmount = burnAmountWeth;
        burnAmountWeth = newAmount;
        emit BurnAmountUpdated(oldAmount, newAmount);
    }

    /// @notice Pause the contract (emergency use only)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ TOKEN MANAGEMENT FUNCTIONS ============

    /// @notice Update agent for a token
    /// @param token Token address
    /// @param newAgent New agent address
    function updateAgent(address token, address newAgent) external onlyOwner {
        if (newAgent == address(0)) revert ZeroAddress();

        TokenConfig storage config = tokenConfigs[token];
        if (!config.isActive) revert TokenNotActive();

        address oldAgent = config.agent;
        if (oldAgent == newAgent) revert SameAgent();

        // Update agent mapping
        config.agent = newAgent;
        tokenToAgent[token] = newAgent;

        // Update agent tokens list
        address[] storage oldAgentTokens = agentToTokens[oldAgent];
        for (uint256 i = 0; i < oldAgentTokens.length; i++) {
            if (oldAgentTokens[i] == token) {
                oldAgentTokens[i] = oldAgentTokens[oldAgentTokens.length - 1];
                oldAgentTokens.pop();
                break;
            }
        }
        agentToTokens[newAgent].push(token);

        emit AgentUpdated(token, oldAgent, newAgent);
    }

    /// @notice Update fee configuration for a token
    /// @param token Token address
    /// @param newClaimPercent New claim percentage in basis points
    function updateFeeConfig(
        address token,
        uint256 newClaimPercent
    ) external onlyOwner {
        TokenConfig storage config = tokenConfigs[token];
        if (!config.isActive) revert TokenNotActive();

        // Validate new claim percent
        require(newClaimPercent <= maxAgentFeeBps, "Agent fee exceeds maximum");

        uint256 oldClaimPercent = config.claimPercent;
        uint256 oldBurnPercent = config.burnPercent;

        if (oldClaimPercent == newClaimPercent) revert SameFeeConfig();

        // Calculate new burn percent
        uint256 newBurnPercent = BPS - newClaimPercent;

        // Update config
        config.claimPercent = newClaimPercent;
        config.burnPercent = newBurnPercent;

        emit FeeConfigUpdated(
            token,
            oldClaimPercent,
            newClaimPercent,
            oldBurnPercent,
            newBurnPercent
        );
    }

    /// @notice Set token active status
    /// @param token Token address
    /// @param active New active status
    function setTokenActive(address token, bool active) external onlyOwner {
        TokenConfig storage config = tokenConfigs[token];
        require(config.agent != address(0), "Token not found");

        config.isActive = active;
        emit TokenActiveStatusUpdated(token, active);
    }

    // ============ TOKEN LAUNCH FUNCTIONS ============

    /// @notice Deploy token via Clanker and setup configuration in ClawStrategyAgent
    /// @param deploymentConfig Clanker deployment configuration
    /// @param agent Agent address
    /// @param agentFeeBps Fee percentage for agent claim (basis points)
    /// @return tokenAddress Deployed token address
    function deployTokenViaClanker(
        IClanker.DeploymentConfig memory deploymentConfig,
        address agent,
        uint256 agentFeeBps
    ) external payable onlyOwner nonReentrant returns (address tokenAddress) {
        // Validate agent fee against maximum
        require(agentFeeBps <= maxAgentFeeBps, "Agent fee exceeds maximum");

        // Auto-calculate burn percentage
        uint256 burnBps = BPS - agentFeeBps;

        // Deploy token via Clanker
        tokenAddress = clanker.deployToken{value: msg.value}(deploymentConfig);

        // Store mappings
        tokenToAgent[tokenAddress] = agent;
        agentToTokens[agent].push(tokenAddress);
        tokenConfigs[tokenAddress] = TokenConfig({
            agent: agent,
            claimPercent: agentFeeBps,
            burnPercent: burnBps,
            isActive: true
        });

        emit TokenLaunched(tokenAddress, agent, agentFeeBps, burnBps);
    }

    /// @notice Adopt an existing Clanker token that was deployed outside ClawStrategyAgent
    /// @dev Must be called AFTER updating reward recipient in Clanker locker to this contract
    /// @param token Token address to adopt
    /// @param agent Agent address for fee management
    /// @param agentFeeBps Fee percentage for agent claim (basis points)
    function adoptToken(
        address token,
        address agent,
        uint256 agentFeeBps
    ) external onlyOwner nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (agent == address(0)) revert ZeroAddress();

        // Check token doesn't already exist in system
        if (tokenConfigs[token].agent != address(0))
            revert TokenAlreadyExists();

        // Validate agent fee against maximum
        require(agentFeeBps <= maxAgentFeeBps, "Agent fee exceeds maximum");

        // Verify token was deployed via Clanker
        IClanker.DeploymentInfo memory deploymentInfo = clanker
            .tokenDeploymentInfo(token);
        if (deploymentInfo.token != token) revert TokenNotDeployedViaClanker();

        // Verify this contract is set as reward recipient
        // Get locker and check reward recipient
        address locker = deploymentInfo.locker;
        IClankerLpLocker.TokenRewardInfo memory rewardInfo = IClankerLpLocker(
            locker
        ).tokenRewards(token);

        // Check if this contract is one of the reward recipients
        bool isRecipient = false;
        for (uint256 i = 0; i < rewardInfo.rewardRecipients.length; i++) {
            if (rewardInfo.rewardRecipients[i] == address(this)) {
                isRecipient = true;
                break;
            }
        }
        require(isRecipient, "Contract must be reward recipient");

        // Auto-calculate burn percentage
        uint256 burnBps = BPS - agentFeeBps;

        // Store mappings
        tokenToAgent[token] = agent;
        agentToTokens[agent].push(token);
        tokenConfigs[token] = TokenConfig({
            agent: agent,
            claimPercent: agentFeeBps,
            burnPercent: burnBps,
            isActive: true
        });

        emit TokenAdopted(token, agent, agentFeeBps, burnBps);
    }

    // ============ POOLKEY HELPER ============

    /// @notice Get PoolKey for a token from Clanker system
    /// @param token Token address
    /// @return poolKey PoolKey struct
    function getPoolKey(address token) internal view returns (PoolKey memory) {
        IClanker.DeploymentInfo memory deploymentInfo = clanker
            .tokenDeploymentInfo(token);
        address locker = deploymentInfo.locker;
        IClankerLpLocker.TokenRewardInfo memory rewardInfo = IClankerLpLocker(
            locker
        ).tokenRewards(token);
        return rewardInfo.poolKey;
    }

    // ============ FEE COLLECTION & DISTRIBUTION ============

    /// @notice Internal function to collect and distribute fees if available
    /// @param token Token address
    function _collectAndDistributeIfAvailable(address token) internal {
        TokenConfig memory config = tokenConfigs[token];
        if (!config.isActive) return; // Skip if not active

        // Check if there are any fees available before collecting
        uint256 wethAvailable = feeLocker.availableFees(
            address(this),
            address(weth)
        );
        uint256 tokenAvailable = feeLocker.availableFees(address(this), token);

        // Early return if no fees available
        if (wethAvailable == 0 && tokenAvailable == 0) {
            return;
        }

        // Get locker from deployment info
        IClanker.DeploymentInfo memory deploymentInfo = clanker
            .tokenDeploymentInfo(token);
        address locker = deploymentInfo.locker;

        // Record balances before
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 tokenBefore = IERC20(token).balanceOf(address(this));

        // Trigger collection from pool (this will collect fees into feeLocker)
        try IClankerLpLocker(locker).collectRewards(token) {} catch {}
        // Claim WETH fees from fee locker
        if (wethAvailable > 0) {
            try feeLocker.claim(address(this), address(weth)) {} catch {}
        }

        // Claim token fees from fee locker
        if (tokenAvailable > 0) {
            try feeLocker.claim(address(this), token) {} catch {}
        }

        // Calculate received amounts
        uint256 wethReceived = weth.balanceOf(address(this)) - wethBefore;
        uint256 tokenReceived = IERC20(token).balanceOf(address(this)) -
            tokenBefore;

        // Early return if no fees collected (safety check)
        if (wethReceived == 0 && tokenReceived == 0) {
            return;
        }

        emit FeesCollected(token, wethReceived, tokenReceived);

        // Distribute according to config
        uint256 wethForClaim = (wethReceived * config.claimPercent) / BPS;
        uint256 wethForBurn = wethReceived - wethForClaim;
        uint256 tokenForClaim = (tokenReceived * config.claimPercent) / BPS;
        uint256 tokenForBurn = tokenReceived - tokenForClaim;

        // Accumulate for agent claim
        wethFees[token] += wethForClaim;
        tokenFees[token] += tokenForClaim;

        // Accumulate burn amounts in separate pools
        wethBurnPool[token] += wethForBurn;
        tokenBurnPool[token] += tokenForBurn;

        emit FeesDistributed(
            token,
            wethForClaim,
            wethForBurn,
            tokenForClaim,
            tokenForBurn
        );
    }

    // ============ AGENT CLAIM ============

    /// @notice Agent claims accumulated fees
    /// @param token Token address
    function claimAgentFee(address token) external nonReentrant whenNotPaused {
        TokenConfig memory config = tokenConfigs[token];
        if (msg.sender != config.agent) revert NotAgent();

        // Auto-collect fresh fees before claiming
        _collectAndDistributeIfAvailable(token);

        uint256 wethAmount = wethFees[token];
        uint256 tokenAmount = tokenFees[token];

        if (wethAmount == 0 && tokenAmount == 0) revert NoFeesToClaim();

        // Reset accumulated amounts
        wethFees[token] = 0;
        tokenFees[token] = 0;

        // Transfer to agent (only if amount > 0)
        if (wethAmount > 0) {
            IERC20(address(weth)).safeTransfer(config.agent, wethAmount);
        }
        if (tokenAmount > 0) {
            IERC20(token).safeTransfer(config.agent, tokenAmount);
        }

        emit AgentFeeClaimed(token, config.agent, wethAmount, tokenAmount);
    }

    // ============ SWAP FUNCTION ============

    /// @notice Buy and burn tokens using V4Router04
    /// @param poolKey PoolKey for the swap
    /// @param token Token address to burn
    /// @param wethAmount Amount of WETH to burn
    function _buyAndBurnTokens(
        PoolKey memory poolKey,
        address token,
        uint256 wethAmount
    ) internal {
        address wethAddress = address(weth);
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == wethAddress;

        // Execute swap - exact input, single pool
        // Tokens are sent directly to DEAD_ADDRESS (buy and burn in one step)
        BalanceDelta delta = router.swapExactTokensForTokens(
            wethAmount, // amountIn
            0, // amountOutMin (no slippage protection for burns)
            zeroForOne, // direction
            poolKey, // pool to swap through
            bytes(""), // hookData
            DEAD_ADDRESS, // receiver - tokens burned directly
            block.timestamp
        );

        // Calculate tokens burned from delta
        // For exact input swaps, the output is the opposite side
        int128 deltaOut = zeroForOne ? delta.amount1() : delta.amount0();

        uint256 tokenAmount = uint256(int256(deltaOut));

        emit BurnedWithWETH(token, wethAmount, tokenAmount);
    }

    // ============ BURN FUNCTIONS ============

    /// @notice Burn tokens using WETH from burn pool
    /// @param token Token address
    function burnWithWETH(address token) external nonReentrant whenNotPaused {
        TokenConfig memory config = tokenConfigs[token];
        if (msg.sender != config.agent) revert NotAgent();

        // Auto-collect fresh fees before burning
        _collectAndDistributeIfAvailable(token);

        // Check cooldown with configurable blocks
        require(
            block.number > lastBurnBlock[token] + burnCooldownBlocks,
            "Cooldown active"
        );

        // Determine WETH amount to burn:
        // - If pool has >= burnAmountWeth (1 ETH default): burn exactly burnAmountWeth
        // - If pool has < burnAmountWeth but > 0: burn all remaining
        uint256 poolBalance = wethBurnPool[token];
        if (poolBalance == 0) revert InsufficientWETH();

        uint256 wethAmount = poolBalance >= burnAmountWeth
            ? burnAmountWeth
            : poolBalance;

        // Deduct from burn pool
        wethBurnPool[token] -= wethAmount;

        // Get PoolKey from locker
        PoolKey memory poolKey = getPoolKey(token);

        // Swap WETH → token and burn (tokens sent directly to DEAD_ADDRESS)
        _buyAndBurnTokens(poolKey, token, wethAmount);

        // Update last burn block
        lastBurnBlock[token] = block.number;
    }

    /// @notice Burn accumulated token fees from burn pool
    /// @param token Token address
    function burnWithToken(address token) external nonReentrant whenNotPaused {
        TokenConfig memory config = tokenConfigs[token];
        if (msg.sender != config.agent) revert NotAgent();

        // Auto-collect fresh fees before burning
        _collectAndDistributeIfAvailable(token);

        // Use burn pool instead of claim pool
        uint256 amount = tokenBurnPool[token];
        if (amount == 0) revert NoTokensToBurn();

        // Reset burn pool
        tokenBurnPool[token] = 0;

        // Send tokens to dead address (permanent lock)
        SafeERC20.safeTransfer(IERC20(token), DEAD_ADDRESS, amount);

        emit BurnedWithToken(token, amount);
    }

    // ============ EMERGENCY FUNCTIONS ============

    /// @notice Emergency withdraw tokens/ETH from contract
    /// @param token Token address (address(0) for ETH)
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner whenPaused {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        if (token == address(0)) {
            // Withdraw ETH
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // Withdraw ERC20
            IERC20(token).safeTransfer(to, amount);
        }

        emit EmergencyWithdraw(token, to, amount);
    }

    /// @notice Allow contract to receive ETH (needed for WETH unwrap and router operations)
    receive() external payable {}
}
