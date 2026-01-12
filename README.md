# Circlepot Smart Contracts

A comprehensive DeFi savings platform built on Celo blockchain, enabling both community-based and individual savings solutions with reputation-based trust mechanisms and yield-bearing options.

## Overview

Circlepot digitizes traditional rotating savings and credit associations (ROSCAs) using blockchain technology. Unlike traditional ROSCAs, Circlepot puts idle funds to work through yield-bearing vaults. By combining Celo's L2 infrastructure, Mento Protocol's stablecoins (USDm and others), ERC-4626 Yield Vaults, and Thirdweb's Account Abstraction, Circlepot delivers a seamless Web2-like experience with decentralized finance benefits.

## Core Features

- **Yield-Bearing Savings**: Choose between "Standard" (no DeFi risk) and "Yield" (interest-earning) modes for both circles and personal goals.
- **Gasless Transactions**: EIP-7702 account abstraction powered by Thirdweb sponsors all user gas fees.
- **Reputation Scoring**: On-chain credit scoring adapted from standard FICO/VantageScore models.
- **90/10 Yield Sharing**: 90% of earned yield goes to the community/user, while 10% supports the platform.
- **Extensible Architecture**: Built with future-proof support for dynamic ERC20 tokens (primary currency: Mento USDm).

## Smart Contracts

### 🔄 CircleSavingsV1

A community-based savings platform for groups. Members contribute funds (primarily Mento USDm) regularly and rotate receiving the collective pot.

**Key Features:**

- **Dual-Mode Choice**: Creators choose between Standard and Yield-bearing circles.
- **Automatic Yield Deployment**: Collateral is instantly moved to ERC-4626 vaults in Yield mode.
- **Reputation-Based Ordering**: Payout order is assigned based on user reputation at start-time.
- **DEAD State & Liquidation**: Automated bulk liquidation if a circle fails to meet capacity or the start-vote fails.
- **Democratic Voting**: Members can vote to "Start early" or "Withdraw" during the pending phase.

---

### 💰 PersonalSavingsV1

An individual savings solution for personal financial goals with yield options and extensible asset support.

**Key Features:**

- **Goal-Mode Selection**: Choose Standard for safety or Yield to earn interest on your progress.
- **Primary Support for USDm**: Optimized for Mento USDm with architectural support for future assets.
- **Graduated Penalties**: Access funds early with progress-based fees (0% penalty at 100% completion).
- **Reputation Rewards**: Completing goals boosts your on-chain credit score.

---

### ⭐ ReputationV1

An on-chain credit scoring system that tracks financial behavior to build trust and reward responsibility.

**Key Features:**

- **Tiered Scoring**: Behavior-based reputation tiers (Bronze to Platinum).
- **Positive/Negative Impact**: Points for on-time contributions and goal completion; penalties for late payments.
- **Priority Access**: Higher reputation grants better payout positions and access to larger circles.

---

### 👤 UserProfileV1

Manages user identity and cross-platform profile data using unique usernames.

---

## Technical Stack

- **L2 Network**: Celo (Fast, stable, affordable)
- **Stablecoins**: Mento Protocol (USDm)
- **Yield Engine**: ERC-4626 Tokenized Vaults (Aave V3, Mento Reserve, etc.)
- **Account Abstraction**: Thirdweb (EIP-7702, In-App Wallets, Gas Sponsorship)
- **Smart Contracts**: Solidity (Foundry framework)

## Business Model & Sustainability

### Revenue Streams

- **Tiered Payout Fees**: 1% for payouts ≤ $1,000; fixed $10 for payouts > $1,000.
- **Yield Share**: 10% platform share of total interest earned in Yield circles/goals.
- **Late Fees**: 100% to platform for Standard circles; shared with community in Yield circles.
- **Operational Fees**: Small fees for visibility toggles ($0.50 USDm) and external withdrawals ($0.20 USDm).

## Security

- **Self-Custodial**: Users maintain full control of their keys via Thirdweb's secure architecture.
- **Collateral-Backed**: All circles require one-round of collateral to protect the group.
- **Audited Logic**: Designed with safety-first principles and comprehensive test suites.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

No License

---

**Built with ❤️ by the Circlepot Team**
