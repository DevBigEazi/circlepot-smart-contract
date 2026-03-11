# Circlepot Smart Contracts

A comprehensive social savings platform built on **Avalanche**, enabling both community-based (ROSCAs) and individual savings solutions with reputation-based trust mechanisms and decentralized yield options.

## Overview

Circlepot digitizes traditional rotating savings and credit associations (ROSCAs) and personal savings goals using blockchain technology. By combining community-driven saving mechanisms with on-chain reputation scoring and gasless transactions, Circlepot provides a transparent, trustless, and user-friendly experience for savers worldwide.

## Core Features

- **Gasless User Experience**: Powered by **ZeroDev Kernel v3** and Sponsored Paymasters, users interact with the blockchain without needing to manage gas fees or native AVAX.
- **Yield-Bearing Goals**: Choose between "Standard" (no DeFi risk) and "Yield" (interest-earning via ERC-4626) modes for personal savings goals.
- **Reputation Registry**: An on-chain credit scoring system that tracks user reliability (on-time payments, goal completions) to incentivize positive behavior.
- **Democratic Governance**: Members in community circles can vote on circle lifecycle events (e.g., deciding to start or withdraw from a pending circle).
- **Scalable Stablecoin Support**: Built to support multiple ERC20 tokens, with a primary focus on **USDT (Avalanche)** for price stability.

## Smart Contracts

### 🔄 CircleSavings.sol

Manages community-based savings circles (ROSCAs). Members contribute funds regularly and rotate receiving the collective pot.

**Key Features:**

- **Principal Protection**: Focuses on social coordination and principal security; funds are held safely in the contract during the rotation.
- **Collateral-Backed**: Members lock 100% of one round's contribution plus a late fee buffer to join, ensuring the schedule is honored.
- **Reputation-Based Ordering**: Payout order is assigned based on user reputation scores at the moment the circle starts.
- **Voting System**: Decisions to start early or withdraw from pending circles are democratically decided by participants.
- **Automated Payouts**: The contract manages the automated distribution of the pot to the scheduled recipient each round.

---

### 💰 PersonalSavings.sol

An individual savings solution for personal financial goals with optional yield generation.

**Key Features:**

- **Goal-Mode Selection**: Choose Standard for safety or Yield to earn interest on your savings through **ERC-4626 Tokenized Vaults**.
- **Yield Sharing**: The platform captures a 10% share of generated yield, while 90% goes directly to the user.
- **Graduated Penalties**: Flexible access to funds with progress-based early withdrawal fees (0% penalty at 100% completion).
- **Referral Integration**: Incentivizes growth and onboarding of new savers.

---

### ⭐ Reputation.sol

A unified registry for tracking and rewarding financial reliability across the entire Circlepot ecosystem.

**Key Features:**

- **Dynamic Scoring**: Behavior-based points for on-time contributions, payout reception, and goal completions.
- **Negative Impact**: Penalties for late payments or early goal withdrawals to protect the community.
- **Score Categorization**: Translates raw points into recognizable trust tiers.

---

## Visual Workflow

```mermaid
flowchart TD
    subgraph A [1. ONBOARDING & FUNDING]
        direction TB
        A1[Start] --> A2[Sign Up<br>Social/Email via Dynamic]
        A2 --> A3[ZeroDev Creates<br>Smart Account Wallet]
        A3 --> A4[Add Funds USDT]

        subgraph A4_Sub [Funding Methods]
            A4_1[🏦 Avalanche On-Ramp]
            A4_2[🔄 Crypto Exchange]
        end

        A4 --> A4_Sub
        A4_Sub --> A5{Funds Added?}
        A5 -- Yes --> A6[Smart Account Ready]
        A5 -- No --> A4
    end

    A6 --> B{User Choice}

    subgraph C [2. SAVINGS CIRCLES JOURNEY]
        B -- Create/Join Circle --> C1{Action}

        C1 -- Create --> C2[Setup Circle Config]
        C2 --> C3[Lock Collateral<br>Gasless via ZeroDev]
        C3 --> C4[Get Position #1<br>Invite Members]

        C1 -- Join --> C6[Join Circle &<br>Lock Collateral]

        C4 --> C7{Threshold Met?}
        C6 --> C7

        C7 -- No & Ultimatum Reached --> C5_DEAD[DEAD State<br>Bulk Principal Release]
        C7 -- Yes --> C5_VOTE{Voting Phase}

        C5_VOTE -- Withdraw Wins --> C5_DEAD
        C5_VOTE -- Start Wins --> C8[Assign Positions<br>via Reputation]
        C8 --> C5[Circle Starts]
    end

    subgraph D [3. CONTRIBUTION CYCLE]
        C5 --> D1[Monthly/Weekly Contrib]
        D1 --> D2[Sponsored Gas<br>ZeroDev Paymaster]
        D2 --> D3{On-Time?}
        D3 -- Yes --> D4[Earn Reputation Points]
        D3 -- Late --> D5[Deduct Late Fee<br>Reputation Hit]
        D6{Round Complete?}
        D4 --> D6
        D5 --> D6
        D6 -- No --> D1
    end

    subgraph E [4. CIRCLE PAYOUT]
        D6 -- Yes --> E1[Payment Turn?]
        E1 -- Yes --> E2[Automated Payout]
        E2 --> E3[💰 USDT to Smart Account]
        E3 --> E4[Reputation Boost]
        E1 -- No --> D1
    end

    subgraph F [PERSONAL SAVINGS GOAL JOURNEY]
        B -- Create Personal Goal --> F1[Setup Goal Config]
        F1 --> F1_Choice{Choose Mode}
        F1_Choice -- Standard --> F2[Safety Mode]
        F1_Choice -- Yield --> F3[Earn Interest via<br>ERC-4626 Vaults]
        F2 --> F4[Contributions]
        F3 --> F4
        F4 --> F5{Goal Complete?}
        F5 -- No --> F6[Early Withdrawal<br>Progress-based Penalty]
        F5 -- Yes --> F7[Full Withdrawal + Yield]
        F6 --> F8[Reputation Hit]
        F7 --> F9[Reputation Boost]
    end

    classDef primaryJourney fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef goalJourney fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef infrastructure fill:#fff8e1,stroke:#ff6f00,stroke-width:1px

    class C,D,E primaryJourney
    class F goalJourney
```

## Security & Architecture

- **Self-Custodial**: Users maintain full control of their accounts via Dynamic + ZeroDev secure architecture.
- **Collateral-Backed**: Community circles require 100% of one round + late fee buffer to ensure participant commitment.
- **Isolated Yield Risk**: DeFi yield exposure is strictly isolated to Personal Goals, protecting the core community saving experience.
- **UUPS Upgradeable**: All core contracts use the Universal Upgradeable Proxy Standard for secure logic updates.

## Technical Stack

- **Network**: Avalanche Fuji / C-Chain
- **AA Provider**: ZeroDev (Kernel v3)
- **Auth**: Dynamic
- **Contracts**: Solidity 0.8.27
- **Indexing**: The Graph (Subgraph)
- **Stablecoin**: USDT

---

**Built with ❤️ by the Circlepot Team**
