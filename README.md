# Circlepot Smart Contracts

A comprehensive DeFi savings platform built on Celo blockchain, enabling both community-based and individual savings solutions with reputation-based trust mechanisms.

## Overview

Circlepot digitizes traditional rotating savings and credit associations (ROSCAs) using blockchain technology. Create or join savings circles where members contribute regularly, and each person receives the full pot when their turn arrives—all with complete transparency and zero gas fees. By combining the simplicity of community savings with Celo's infrastructure, Mento Protocol's stable digital currencies(cUSD first), Thirdweb's account abstraction, gasless transactions, and established partner ecosystem, CirclePot delivers a seamless Web2-like experience with Web3 benefits.

## Smart Contracts

### 🔄 CircleSavingsV1

A community-based savings platform that enables groups of people to create and participate in savings circles. Members contribute funds regularly and take turns receiving the collective pot.

**Key Features:**
- **Private or Public Circles** - Create invitation-only circles or open communities
- **Collateral-Backed Commitments** - Ensure participation through collateral requirements
- **Reputation-Based Position Assignment** - Earlier payout positions for trusted members
- **Automated Payment Handling** - Automatic processing of late payments and forfeitures
- **Democratic Voting System** - Start circles before they're full through member consensus
- **Flexible Schedules** - Support for daily, weekly, or monthly contribution cycles

**Use Cases:**
- Community savings groups
- Friend and family savings circles
- Goal-oriented group savings
- Trust-building financial communities

---

### 💰 PersonalSavingsV1

An individual savings solution that helps users save toward personal financial goals with built-in accountability mechanisms.

**Key Features:**
- **Goal-Based Savings** - Set customizable targets and deadlines
- **Flexible Contributions** - Contribute on your own schedule
- **Early Withdrawal Options** - Access funds early with a graduated penalty system
- **Reputation Rewards** - Earn reputation points for completing savings goals
- **Progress Tracking** - Monitor your savings journey with milestone celebrations
- **Automated Enforcement** - Smart contract ensures commitment to your goals

**Use Cases:**
- Emergency fund building
- Vacation savings
- Down payment accumulation
- Education fund
- Any personal financial goal

---

### ⭐ ReputationV1

A credit scoring system that tracks user financial behavior across the platform to build trust and reward responsible actions.

> **Note:** This contract uses standard FICO and VantageScore models adapted for on-chain credit scoring.

**Key Features:**
- **Score-Based Reputation System** - Multiple tiers based on financial behavior
- **Positive Behavior Rewards** - Earn points for completing savings goals and timely payments
- **Negative Action Penalties** - Score reduction for late payments or defaults
- **Preferential Treatment** - Higher reputation users get better positions in savings circles
- **Transparent History** - All financial activities recorded on-chain
- **Cross-Platform Impact** - Reputation affects all Circlepot products

**Reputation Benefits:**
- Priority positions in savings circles
- Reduced collateral requirements
- Access to larger circles
- Community trust indicator

---

### 👤 UserProfileV1

Manages user identity across the entire Circlepot platform.

**Key Features:**
- **Secure Profile Management** - Secure profile management
- **Cross-Platform Identity** - Single profile across all Circlepot products
---

## Architecture

```
┌─────────────────┐
│  UserProfileV1  │
└────────┬────────┘
         │
         ├──────────────────────┬──────────────────────┐
         │                      │                      │
┌────────▼─────────┐   ┌───────▼──────────┐   ┌──────▼──────────┐
│ CircleSavingsV1  │   │ PersonalSavingsV1│   │  ReputationV1   │
│   (Community)    │   │   (Individual)   │   │ (Credit Score)  │
└──────────────────┘   └──────────────────┘   └─────────────────┘
```

## Use Cases

### Community Savings Circle Example
A group of 10 friends wants to save $1,000 each month. They create a circle where:
- Each member contributes $100 monthly
- One member receives $1,000 each month (in rotating order)
- Members with higher reputation get earlier positions
- Late payments result in collateral forfeiture

### Personal Savings Goal Example
A user wants to save $5,000 for a vacation in 6 months:
- Sets a goal of $5,000 with a 6-month deadline
- Commits to $833 monthly contributions
- Earns reputation points upon completion
- Can withdraw early with a penalty if needed

## Security

- All contracts are designed with security best practices
- Comprehensive test coverage
- Regular security audits (planned)
- Bug bounty program (coming soon)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

No License

## Contact

- **Project Link:** [https://github.com/DevBigEazi/Circlepot-smart-contract](https://github.com/DevBigEazi/Circlepot-smart-contract)
- **Issues:** [https://github.com/DevBigEazi/Circlepot-smart-contract/issues](https://github.com/DevBigEazi/Circlepot-smart-contract/issues)

---

**Built with ❤️**