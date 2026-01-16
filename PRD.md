Circlepot Product Requirements Document (PRD)
Date: October 2026
Product: Yield-Bearing On-Chain Savings Circles Powered by Celo L2

1. Introduction
   Circlepot digitizes traditional rotating savings and credit associations (ROSCAs) using blockchain technology. Unlike traditional ROSCAs where idle money sits stagnant, Circlepot puts every dollar of collateral to work from the moment it is committed (for yield-enabled circles and goals). By combining Celo's infrastructure, Mento Protocol's USDm, and ERC-4626 Yield Vaults, Circlepot allows communities and individuals to save while choosing between secure standard savings or earning decentralized yield.
   Core Value Proposition: Community saving + Personal Goals + Celo L2 + Mento Stablecoin + Thirdweb AA + Immediate DeFi Yield = Circlepot.

2. Problem & Solution
   2.1. Problem Statements
   Traditional Savings Circles Face:

- Lack of transparency: Uncertainty around who has paid and who hasn't
- Trust issues: Risk of organizers or members absconding with funds
- Manual processes: Reliance on cash, spreadsheets, and in-person tracking
- No enforcement mechanisms: Inability to ensure timely payments
- Geographic limitations: Difficulty including members from abroad
- Blockchain friction: Gas fees and wallet complexity discourage adoption
  2.2. CirclePot Solution
  CirclePot solves these challenges by leveraging Celo L2 and Thirdweb's unique capabilities:
- Gasless transactions - Thirdweb's EIP-7702 sponsors all gas fees
- Web2 UX - No wallet management, no gas tokens needed
- Email/Social login - Sign up like any normal app via Thirdweb
- Self-custodial security - Users fully control their funds
- Fast finality - Instant confirmation of contributions and payouts
- USDm integration - Stable, widely-supported native stablecoin
- One-click onboarding - Start saving in 60 seconds
- Celo partner integration - Easy on/off ramps via trusted partners

3. Technical Foundation
   3.1. Infrastructure Stack

- Network: Celo L2 (EVM-compatible)
- Primary Currency: USDm (Mento Protocol stablecoin - Celo Dollar)
- Mento Stablecoins: Circlepot is built on Mento Protocol, the decentralized stablecoin platform powering Celo's family of stable digital currencies
- Smart Contracts: Solidity on Celo L2
- Yield Engine: ERC-4626 Tokenized Vaults (Aave V3 / Mento Reserve integration / other Stablecoins Yield platforms)
- Wallet Infrastructure: Thirdweb In-App Wallets with EIP-7702 (EOA smart wallet)
- Gas Sponsorship: Thirdweb paymaster infrastructure
- User Experience: Account Abstraction with sponsored gas fees
- Fiat Integration: Celo ecosystem partners (Fonbnk, Partna, Quidax, Yellow Card, Transfi, CashRamp)
  3.2. Key Mechanisms
- Self-custodial smart wallets
- Gasless transactions
- Collateralized commitments
- Reputation scoring (uses standard FICO and VantageScore models adapted for on-chain credit scoring)
- Personal savings goals (with Yield options)

4. Account Abstraction & Web2 Onboarding
   4.1. What is Account Abstraction?
   Account Abstraction transforms how users interact with blockchain by making smart contracts act as user accounts. With Circlepot + Thirdweb:

- Self-Custodial: You fully control your funds - no one else has access
- No Seed Phrases: Recovery through email/phone instead of 12-word phrases
- Gasless: Thirdweb sponsors all transaction fees via EIP-7702
- Simple Login: Use email, Google, or Twitter - just like any app
- Your Keys, Your Crypto: Despite the easy experience, you maintain full ownership
  4.2. Technical Foundation: Thirdweb In-App Wallets
  Circlepot leverages Thirdweb's infrastructure for:
- Smart wallet creation and management
- EIP-7702 gasless transactions
- Social login authentication
- Self-custodial wallet architecture
- Session key management
  4.3. Onboarding Flow
  4.3.1. Sign Up (60 seconds)

1. Click "Get Started"
2. Choose sign-up method:
   - Email + email confirmation
   - Continue with Google
3. Verify identity (email/SMS code)
4. Done! - Smart contract wallet created automatically by Thirdweb
   4.3.2. Deposit USDm
   First-time users see simple "Add Funds" screen with options:

- Deposit locally (via MoonPay/Transak integration, Fonbnk, Quidax, Yellow Card, etc.)
- Deposit internally from another Circlepot user
- Direct deposit from exchanges (simple instructions)
  4.4. Account Abstraction Benefits
- Zero Gas Fees for Users: Thirdweb sponsors all transaction costs via EIP-7702 paymaster
- Social Recovery: Lost access? Recover via email
- Batch Transactions: Multiple operations in single user action

5. Savings Features
   5.1. Create a Circle

- Custom Settings: Set contribution ($1–$5k), frequency (daily/weekly/monthly), and capacity (5–20 members)
- Dual-Mode Choice: Creators choose between:
  - Standard Circles: Funds held safely in contract; 100% late fees to platform.
  - Yield Circles: Funds to ERC-4626 vault; 10% yield to platform, 90% to community.
- Visibility: Private by default (free to create). Public toggle costs $0.50 USDm
- Immediate Yield Deployment (Yield Mode Only): Creator's collateral is instantly deposited into the DeFi vault to start earning interest during the "Pending" phase
- Creator Incentives: - Always receives the first payout - 0% platform fee on their payout
  5.2. Joining & Join-Order Logic
- Collateral Lock: Members lock 100% of one round's contribution plus a late buffer to join
- Instant Yield (Yield Mode Only): Member collateral is immediately moved to the vault upon joining
- Reputation-Based Assignment: Positions in the payout order are assigned based on the user's Reputation Score at the moment the circle starts
  5.3. Circle Lifecycle (Ultimatum & Voting System)
- Minimum Threshold: Circles require 60% of max capacity to start
- Ultimatum Window: 7 days (Daily/Weekly) or 14 days (Monthly)
- Voting Mechanism (New):
  - Status Quo Protection: If a vote to start vs. withdraw results in a tie, the circle starts (honoring the participants' initial intent).
  - Early Execution: If 100% of eligible members vote, the result executes instantly, bypassing the 48-hour wait.
- Start Triggers: Creator can manually start when threshold is met, or it auto-starts at the deadline
- DEAD State (New): If the threshold isn't met or the 'Withdraw' vote wins, the circle becomes DEAD: - Automated Bulk Liquidation: The first member to trigger withdrawal releases principal to all members simultaneously in one transaction. - Yield Sweep: The platform captures 100% of any interest earned by the pending collateral while in the 'Pending' phase.
  5.4. Payout Mechanism
- Automated Distribution: Payouts occur automatically to the scheduled recipient on the final day of the round
- Vault Liquidity: If the contract's liquid balance is low, it automatically redeems shares from the ERC-4626 vault (for yield circles) to cover the payout
  5.5. Personal Savings Goals
- Custom Settings: Users set goal name, target amount ($10–$50,000), contribution frequency, and deadline.
- Dual-Mode Choice: Users choose between:
  - Standard Goals: Funds held safely in the contract (no DeFi risk).
  - Yield Goals: Funds automatically deposited to ERC-4626 vaults to earn interest.
- Multi-Token Support: Ability to choose between USDm and other supported stablecoins for the goal.
- Immediate Yield Deployment: Initial and recurring contributions are instantly moved to the vault (for Yield mode) to maximize interest earnings.
- Flexible Progression: Withdraw accumulated balance at any time (subject to progress-based penalties) or complete the goal to receive full principal plus yield.

6. Performance & Yield-Sharing Model
   6.1. Performance Points Ledger

- Awarding: Every on-time contribution (Circles) or successful goal milestone awards Performance Points/Reputation.
- Impact: Points determine the proportional share of the Community Reward Pool (for Circles).
- Late Handling: - Yield Circles: No points awarded for late payments; late fees are added to the Reward Pool for others. - Standard Circles: Late fees are routed directly to the platform fees.
  6.2. The 90/10 Yield Split
  Upon circle completion or goal withdrawal (for Yield variants), the accumulated yield (Interest + community-pooled Late Fees for Circles) is distributed:
- 90% (User/Community Share): Distributed to members/users based on participation or directly to the goal owner.
- 10% (Platform Share): Retained by the platform for infrastructure and sustainability.

7. Reputation & Credit Scoring
   7.1. On-Chain Credit Scoring Model
   Circlepot uses standard FICO and VantageScore models adapted for on-chain credit scoring, translating traditional credit metrics into blockchain-based reputation data.
   7.2. Reputation Benefits

- Priority Positioning: Better payout order assignments in new circles
- Access to Future loans: Unlock access to loans in the future
- Goal Incentives: Higher reputation score for completing personal goals.

8. Business Model & Sustainability
   8.1. Revenue Streams
   8.1.1. Tiered Payout Fees

- Payouts ≤ $1,000: 1% fee
- Payouts > $1,000: Fixed $10 fee
  8.1.2. Yield Capture (Idle Funds)
- 100% of yield from DEAD circles (interest earned while pending)
  8.1.3. Yield Sharing
- Yield Mode (Circles): 10% of total yield from completed ACTIVE circles
- Yield Mode (Personal Goals): 10% of total yield generated by personal savings goals
- Standard Mode: 100% of late fees
  8.1.4. Operational Fees
- Visibility Toggle: $0.50 USDm
- Dead Creator Fee: $1.00 (Private) or $0.50 (Public)
  8.1.5. Personal Savings Goal Penalties
  Early Withdrawal Penalty Structure:
  | Progress | Penalty Fee | User Impact |
  | :--- | :--- | :--- |
  | 0-24% | 1.0% | Low commitment, higher penalty |
  | 25-49% | 0.6% | Moderate progress |
  | 50-74% | 0.3% | Significant progress |
  | 75-99% | 0.1% | Near completion |
  | 100% | 0% | No penalty |

Penalty Allocation:

- 100% to platform sustainability fund
- Supports infrastructure and gas sponsorship costs
- Encourages goal completion while maintaining flexibility
  8.1.6. External Withdrawal Fee
- A flat $0.20 USDm fee is applied when users transfer funds out to external exchanges/wallets
  8.1.7. Partnership Revenue Opportunities
  Celo Ecosystem Integration:
- Potential referral fees from on/off-ramp partners: Fonbnk, Partna, Quidax, Yellow Card, Transfi, CashRamp
- Revenue share on successful conversions
  8.2. Cost Structure
  8.2.1. Operating Costs
- Gas Sponsorship (Thirdweb EIP-7702)
  - All user transactions sponsored via Thirdweb paymaster
  - Contributions, payouts, collateral locks - all gasless
  - Cost per transaction on Celo L2: ~$0.001-$0.01
  - Monthly estimate (100,000 transactions): $100-$1,000
- Other Costs: - Infrastructure & Hosting: $500-$2,000/month - Thirdweb Services: $200-$1,500/month - Smart Contract Security: $20,000-$70,000/year - Operations: Professional support and marketing
  8.3. Financial Projections
  8.3.1. Growth Scenario (Year 2)
- User Metrics: 100,000 MAU, 5,000 Active Circles
- Monthly Revenue: ~$56,000 - $57,000
- Monthly Costs: ~$14,000
- Net: +$42,000/month (Profitable)
  8.5. Sustainability Strategy
  8.5.1. Revenue Diversification
  Core platform fees, Dead circle fees, Goal penalties, Visibility updates, Partnership revenue.
  8.5.2. Cost Optimization
  Efficient gas abstraction, low L2 costs, automated systems.
  8.5.3. Growth Levers
  Viral coefficient, Reputation stickiness, Zero friction onboarding.

9. Conclusion
   Circlepot creates a "No-Loss" ecosystem where community trust is rewarded by DeFi performance. By offering a Choice-based Yield model for both community circles and personal goals, we eliminate friction and transform traditional savings into a resilient, high-engagement financial tool powered by Celo and Mento.
   Our mission: Helping millions of people around the world save and grow together through trusted digital savings circles and personal goals that work just like the ones they know — only easier and safer.
   Powered by:

- Celo L2 - Fast, stable, affordable
- Thirdweb - Seamless Web2 UX with Web3 security
- USDm - Mento's Celo Dollar stablecoin for stable savings and global reach
