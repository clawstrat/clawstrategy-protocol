# ClawStrategy Protocol

A decentralized protocol for managing token launches via [Clanker](https://github.com/clanker-devco/v4-contracts), distributing trading fees to agents, and handling token burns with configurable mechanisms.

## Overview

ClawStrategy is a smart contract system that enables:

- **Token Launch Management**: Deploy tokens through Clanker protocol on Uniswap V4
- **Fee Distribution**: Automatically collect and distribute trading fees to agents based on configurable percentages
- **Token Burns**: Support for two burn mechanisms:
  - WETH-based burns (1 ETH per call with block cooldown)
  - Direct token burns (full accumulated amount)

## Architecture

### Core Components

- **ClawStrategy Contract**: Main contract managing token launches, fee distribution, and burns
- **Clanker Integration**: Interfaces with Clanker protocol for token deployment
- **Uniswap V4 Integration**: Uses PoolManager for WETH → token swaps
- **Fee Management**: Integrates with ClankerFeeLocker for fee collection

### Key Features

1. **Multi-Agent Support**: One agent can manage multiple tokens
2. **Configurable Fee Split**: Each token can have custom claim/burn percentages
3. **Automatic Fee Collection**: Collects fees from Uniswap V4 pools via Clanker
4. **Burn Mechanisms**:
   - WETH burn with 1-block cooldown to prevent price volatility
   - Direct token burn for accumulated fees

## Contract Structure

```
strategy-contract/
├── src/
│   ├── ClawStrategy.sol          # Main contract
│   └── interfaces/
│       ├── IClanker.sol          # Clanker protocol interface
│       ├── IClankerFeeLocker.sol # Fee locker interface
│       ├── IClankerLpLocker.sol  # LP locker interface
│       ├── IClankerToken.sol     # Clanker token interface
│       ├── IWETH.sol             # WETH interface
│       └── IOwnerAdmins.sol      # Owner/Admin interface
└── test/
    └── ClawStrategy.t.sol         # Test suite
```

## Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity ^0.8.28

### Setup

```bash
# Clone the repository
git clone https://github.com/clawstrat/clawstrategy-protocol.git
cd clawstrategy-protocol

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

## Usage

### Deploy ClawStrategy

```solidity
ClawStrategy strategy = new ClawStrategy(
    clankerAddress,      // Clanker contract address
    feeLockerAddress,   // ClankerFeeLocker address
    poolManagerAddress, // Uniswap V4 PoolManager address
    wethAddress,        // WETH contract address
    ownerAddress        // Contract owner
);
```

### Launch Token via Clanker

```solidity
IClanker.DeploymentConfig memory config = IClanker.DeploymentConfig({
    tokenConfig: tokenConfig,
    poolConfig: poolConfig,
    lockerConfig: lockerConfig,
    mevModuleConfig: mevModuleConfig,
    extensionConfigs: extensionConfigs
});

strategy.deployTokenViaClanker(
    config,
    agentAddress,
    claimPercent,  // e.g., 7000 = 70%
    burnPercent    // e.g., 3000 = 30%
);
```

### Collect and Distribute Fees

```solidity
// Trigger fee collection from pool and distribute according to config
strategy.collectAndDistributeFees(tokenAddress);
```

### Agent Claims Fees

```solidity
// Agent claims accumulated fees (WETH + token)
strategy.claimAgentFee(tokenAddress);
```

### Burn Tokens

```solidity
// Burn using WETH (1 ETH per call, requires cooldown)
strategy.burnWithWETH(tokenAddress);

// Burn accumulated token fees directly
strategy.burnWithToken(tokenAddress);
```

## Core Functions

### Token Launch

- `deployTokenViaClanker()`: Deploy token via Clanker and setup configuration
- Sets ClawStrategy as token admin for burn permissions
- Configures fee distribution percentages

### Fee Management

- `collectAndDistributeFees()`: Collects fees from pool and distributes by percentage
- `claimAgentFee()`: Allows agents to claim their accumulated fees

### Burn Mechanisms

- `burnWithWETH()`: Swaps 1 ETH worth of WETH → token and burns (1 block cooldown)
- `burnWithToken()`: Burns all accumulated token fees

## Security Features

- **Access Control**: Owner-only and agent-only functions
- **Reentrancy Protection**: All state-changing functions protected
- **Cooldown Mechanism**: WETH burns limited to 1 per block
- **Fee Validation**: Ensures claim + burn percentages equal 100%

## Development

### Build

```bash
forge build
```

### Test

```bash
forge test
forge test -vvv  # Verbose output
```

### Format

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) v5.5.0
- [Uniswap V4 Core](https://github.com/Uniswap/v4-core)
- [Uniswap V4 Periphery](https://github.com/Uniswap/v4-periphery)
- [Clanker Contracts](https://github.com/clanker-devco/v4-contracts)

## License

MIT

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Links

- [Clanker Protocol](https://github.com/clanker-devco/v4-contracts)
- [Uniswap V4](https://github.com/Uniswap/v4-core)
