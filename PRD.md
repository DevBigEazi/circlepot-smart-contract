Circlepot Product Requirements Document (PRD)
Date: March 2026
Product: Social Savings Circles & Personal Goals Powered by Avalanche

1. Introduction
   Circlepot digitizes traditional rotating savings and credit associations (ROSCAs) and personal savings goals using blockchain technology. By combining community-driven saving mechanisms with on-chain reputation scoring and decentralized yield options, Circlepot provides a transparent, trustless, and user-friendly experience. Currently implemented on the Avalanche network, it leverages Account Abstraction to offer a seamless Web2-like user experience.

   Core Value Proposition: Community saving + Personal Goals + Avalanche + Account Abstraction + DeFi Yield (Personal) = Circlepot.

2. Problem & Solution
   2.1. Problem Statements
   Traditional Savings Circles Face:

- Lack of transparency: Uncertainty around who has paid and who hasn't
- Trust issues: Risk of organizers or members absconding with funds
- Manual processes: Reliance on cash, spreadsheets, and in-person tracking
- No enforcement mechanisms: Inability to ensure timely payments
- Blockchain friction: Gas fees and wallet complexity discourage adoption

  2.2. CirclePot Solution
  CirclePot solves these challenges by leveraging Avalanche and ZeroDev's Account Abstraction:

- Gasless transactions - Sponsored via ZeroDev Paymaster for all user actions
- Web2 UX - No seed phrases, email/social login via Dynamic
- Self-custodial security - Users maintain control over their smart accounts
- Fast finality - Instant confirmation on Avalanche Fuji
- Stablecoin integration - Primary focus on USDT for price stability
- On-chain Reputation - Credit-like scoring based on payment behavior

3. Technical Foundation
   3.1. Infrastructure Stack

- Network: Avalanche Fuji (Testnet) -> Avalanche C-Chain (Mainnet)
- Primary Currency: USDT (Standardized for simplicity)
- Smart Contracts: Solidity (^0.8.27) with UUPS Upgradeable architecture
- Account Abstraction (AA): ZeroDev Kernel v3 (EntryPoint v0.7)
- Onboarding & Auth: Dynamic SDK (Social/Email Login)
- Yield Engine: ERC-4626 Tokenized Vaults (Isolated to Personal Goals)
- Middleware: The Graph (Subgraph) for relational data indexing
- Frontend: Next.js 16 (App Router), React 19, Tailwind CSS 4

  3.2. Key Mechanisms

- Multi-token support: Infrastructure built to support multiple ERC20s
- Reputation Registry: Central source of truth for user credit scores
- Collateralized commitments: 100% of one round + late fee buffer locked to join
- Voting system: Decisions to start or withdraw from pending circles

4. Account Abstraction & Onboarding
   4.1. Seamless UX with ZeroDev
   Circlepot uses ZeroDev Kernel v3 to transform smart contracts into user accounts:

- Self-Custodial: Users sign with social/email but own the account keys
- Gasless: All on-chain interactions (joining, contributing, withdrawing) are sponsored
- No Seed Phrases: Managed via Dynamic's embedded wallets
- Smart Account: Kernel v3 provides a robust, gas-efficient wallet foundation

  4.2. Onboarding Flow

1. Sign Up: Choose Gmail, Email, or Social login (Dynamic)
2. Wallet Creation: Smart account automatically provisioned via ZeroDev
3. Funding: Deposit USDT to the smart account address
4. Start Saving: Join a circle or create a personal goal instantly

5. Savings Features
   5.1. Community Circles (ROSCAs)

- Principal Protection: Funds are held securely in the contract to prioritize social coordination
- Custom Settings: Set contributionAmount, frequency (Daily/Weekly/Monthly), and maxMembers (5-20)
- Creator Incentives: Receives the first payout position; 0% payout fee
- Reputation-Based Order: Other payout positions are assigned based on Reputation Scores at the circle's start
- Visibility: Private by default; Public toggle incurs a $0.50 fee

  5.2. Personal Savings Goals

- Targeted Yield Choice: Users can choose between:
  - Standard Goals: No DeFi risk, local storage in contract
  - Yield Goals: Deposits to ERC-4626 vaults (e.g., Aave) to earn interest
- Multi-Token Support: Flexible selection of supported stablecoins
- Immediate Deployment: Funds are moved to vaults upon contribution to maximize APY
- Flexible Completion: Full withdrawal upon reaching target; partial withdrawals allowed with penalty

  5.3. Circle Lifecycle & Voting

- Ultimatum Window: 7 days for shorter cycles, 14 days for monthly
- Threshold: Requires 60% capacity to initiate voting
- Voting Result:
  - START: Circle activates; positions assigned; rounds begin
  - WITHDRAW: Circle becomes DEAD; collateral released in bulk to all members
- Tie-break: Intent to save is honored; ties result in the circle starting

6. Reputation & Credit Scoring
   6.1. Scoring Model
   Reputation is a numerical score reflecting user reliability.

- Increases: On-time contributions (+2), receiving payout (+5), completing goals (+10)
- Decreases: Late payments (-5), early goal withdrawals (-2 to -5), forfeiture (-10)
  6.2. Benefits
- Priority Payouts: Higher scores get earlier positions in community circles
- Platform Access: Unlocks premium features and future lending products

7. Business Model
   7.1. Revenue Streams

- Tiered Payout Fees:
  - Payouts ≤ $1,000: 1% fee
  - Payouts > $1,000: Fixed $10 fee
- Yield Sharing: 10% platform share of gross yield from Personal Goals
- Late Fees: 1% late fee buffer (forfeited if significantly late)
- Early Withdrawal Penalties: Progress-based fees (1.0% to 0.1%) for goal withdrawals
- Operational Fees: Visibility updates ($0.50), Dead creator fees

  7.2. Sustainability

- All platform fees and penalties fund the Infrastructure & Gas Sponsorship Pool
- ZeroDev paymaster costs are offset by platform activity fees

8. Conclusion
   Circlepot bridges the gap between traditional social saving and modern DeFi. By leveraging Avalanche for speed, ZeroDev for a gasless experience, and isolating yield risk to personal goals, the platform provides a secure, high-performance financial tool for communities worldwide.
