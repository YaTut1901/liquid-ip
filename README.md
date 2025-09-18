# Liquid IP Protocol

<h4 align="center">
  <a href="#overview">Overview</a> |
  <a href="#architecture">Architecture</a> |
  <a href="#sponsor-integration">Sponsor Integration</a> |
  <a href="#getting-started">Getting Started</a>
</h4>

🔬 A decentralized protocol that transforms intellectual property licenses into liquid assets, solving the complex, expensive, and opaque patent licensing system through smart contracts and decentralized infrastructure.

⚙️ Built using Uniswap v4 Hooks, Fhenix FHE, EigenLayer AVS, Aave v3, and Foundry.

**The Problem**: According to WIPO, EPO, and USPTO databases, there are over 150,000 active refrigerator-related patents worldwide, with a typical fridge involving 150-300 patents. The current patent system is overly complex, expensive, and dominated by opaque lump-sum deals and defensive litigation.

**Our Solution**: A smarter system that leverages decentralized infrastructure and smart contracts to enable real-time, usage-based licensing that is fair, scalable, and cost-effective.

- 🔐 **"Vending Machine" License Distribution**: One-way purchase mechanism via Uniswap v4 hooks (no resale to avoid regulatory issues)
- 🛡️ **Decentralized Patent Verification**: EigenLayer AVS validates patent metadata authenticity
- 💰 **Automatic Yield Generation**: Rehypothecation of idle campaign funds to Aave v3
- 🌊 **Epoch-Based Liquidity Management**: Granular license allocation across time periods
- 🎯 **Dual Campaign Types**: Public campaigns for transparency, private campaigns with FHE encryption

## Overview

Liquid IP transforms patent licenses into tradeable ERC20 tokens, creating liquid markets for intellectual property. Patent holders can sell licenses at scale while maintaining ownership, and buyers can trade licenses freely in secondary markets.

### Key Features

- **"Vending Machine" License Distribution**: One-way purchase mechanism through Uniswap v4 hooks (users buy license tokens with USDC but cannot resell)
- **Epoch-Based Liquidity Management**: Granular license allocation across time periods with automatic position management
- **Yield Generation**: Automatic rehypothecation of idle campaign proceeds to Aave v3 during campaigns
- **Privacy-Preserving Campaigns**: Encrypted campaign parameters using Fhenix FHE for institutional users requiring confidentiality
- **Decentralized Patent Verification**: EigenLayer AVS validates patent metadata authenticity via TaskMailbox system

## Architecture

### Core Components

#### 1. License Tokens
- **LicenseERC20**: ERC20 tokens representing licenses for specific patents
- **PatentERC721**: NFT representing patent ownership
- Each patent can have multiple license campaigns with different terms

#### 2. Campaign Types

**Public Campaigns (`PublicLicenseHook`)**
- Transparent campaign parameters
- Open epoch schedules and liquidity ranges
- Suitable for public IP licensing

**Private Campaigns (`PrivateLicenseHook`)**
- Encrypted campaign parameters using **Fhenix FHE**
- Hidden liquidity ranges and allocation strategies
- Suitable for sensitive business IP

#### 3. Rehypothecation System
- **RehypothecationManager**: Routes idle campaign proceeds into Aave v3 to earn yield
- Per-pool, per-currency vaults keyed by Uniswap v4 `PoolId` and `Currency`
- Returns principal plus accrued yield to campaign owner after campaign ends
- Supports both ERC20 tokens and native ETH via Aave's Wrapped Token Gateway

#### 4. Patent Verification via EigenLayer AVS
- **PatentMetadataVerifier**: Coordinates off-chain verification via EigenLayer TaskMailbox
- At epoch start, verification tasks are dispatched to designated performer services
- Decentralized verification network with economic security from staked ETH
- Prevents circulation of invalid patent licenses through cryptographic proofs

## Sponsor Integration

### Fhenix Integration

Liquid IP leverages **Fhenix's Fully Homomorphic Encryption (FHE)** for private campaign functionality targeting institutional users who require confidentiality.

**Key Benefits:**
- **On-chain Privacy**: Campaign tick ranges and liquidity amounts remain encrypted using Fhenix's `InEuint32` and `InEuint128` types
- **Institutional Protection**: Prevents competitors from seeing sensitive licensing strategies and position ranges
- **Asynchronous Execution**: Swaps are deferred until FHE decryption completes to avoid revealing parameters prematurely
- **COFHE Integration**: Uses Fhenix's COFHE library for robust FHE operations

**Implementation:**
- `PrivateLicenseHook` stores encrypted position parameters using Fhenix FHE types
- Campaign configuration uses encrypted inputs that remain hidden until epoch activation
- Decryption is triggered asynchronously when epochs become active
- Swaps are stored as pending until decryption results become available for position creation

### EigenLayer Integration

Liquid IP uses **EigenLayer's AVS (Actively Validated Services)** for decentralized patent verification to prevent circulation of invalid patent licenses.

**Key Benefits:**
- **Decentralized Trust**: No single point of failure for patent validation through distributed operator network
- **Economic Security**: EigenLayer operators stake ETH to secure the verification network
- **TaskMailbox Coordination**: Leverages EigenLayer's proven task coordination and result submission system
- **Off-chain Processing**: Go-based performer services handle metadata retrieval and validation logic

**Implementation:**
- `PatentMetadataVerifier` implements EigenLayer's TaskMailbox system for patent verification workflows
- Patent validation is triggered automatically during swaps to ensure license authenticity
- Verification tasks are dispatched to operator sets with encoded patent metadata URIs
- Off-chain performer services validate patent metadata and submit results back on-chain
- Patent status is tracked with states: UNKNOWN, VALID, INVALID, or UNDER_ATTACK

## Technical Specifications

### Dependencies
- **Uniswap v4**: Core AMM infrastructure and hooks
- **Fhenix FHE**: Homomorphic encryption for private campaigns
- **EigenLayer**: Decentralized patent verification network
- **Aave v3**: Yield generation through lending markets
- **OpenZeppelin**: Standard contract libraries

### Smart Contracts

| Contract | Description |
|----------|-------------|
| `PublicLicenseHook` | Transparent IP license campaigns |
| `PrivateLicenseHook` | Encrypted IP license campaigns (Fhenix) |
| `RehypothecationManager` | Automatic yield generation via Aave |
| `PatentMetadataVerifier` | EigenLayer AVS integration |
| `LicenseERC20` | Tradeable license tokens |
| `PatentERC721` | Patent ownership NFTs |


## Getting Started

### Monorepo Structure

- `packages/foundry`: Solidity contracts, tests, and deployment scripts
- `packages/performer`: Go performer service for off-chain metadata verification

## How to Run

### 1. Prerequisites
Make sure you have the following tools installed:
- [Git](https://git-scm.com/downloads)
- [Foundry](https://getfoundry.sh/)
- [Node.js >= 20.18](https://nodejs.org/en/download/) and yarn/pnpm

### 2. Clone Repository
```bash
git clone <repository-url>
cd liquid-ip
```

### 3. Install Dependencies
```bash
forge install
yarn install
```

### 4. Run Tests
```bash
forge test
```

## What You Can Do

### Development Commands

```bash
# Build the contracts
forge build

# Run all tests
forge test

# Run tests with detailed output
forge test -vvv

# Run specific test file
forge test --match-contract PublicLicenseHook

# Run specific test function
forge test --match-test test_CampaignOwnerWithdrawal

# Check contract sizes
forge build --sizes

# Format code
forge fmt

# Generate gas report
forge test --gas-report

# Run with coverage
forge coverage
```

## Use Cases

### For Patent Holders
- **Monetize IP Portfolio**: Convert patent licenses into liquid tokens for immediate revenue
- **Maintain Ownership**: Retain full patent ownership while licensing usage rights
- **Automated Revenue**: Set-and-forget campaigns with automatic yield generation
- **Market Discovery**: Let the market determine fair licensing prices

### For License Buyers
- **Transparent Pricing**: Market-driven pricing through AMM mechanics
- **Instant Access**: Immediate license acquisition without lengthy negotiations
- **Portfolio Management**: Build diversified IP license portfolios

### For Liquidity Providers
- **Aave Integration**: Additional yield from rehypothecated campaign funds
- **Risk Management**: Diversified exposure across multiple IP campaigns

## Testing & Development

### Running Tests
```bash
# Install dependencies
yarn install

# Run all tests
yarn foundry:test

# Run specific test files
forge test --match-contract RehypothecationManager

# Run with coverage
yarn foundry:coverage
```

### Development Commands
```bash
# Start local blockchain
yarn chain

# Deploy contracts
yarn deploy

# Start frontend
yarn start
```
