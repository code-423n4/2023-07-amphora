# Overview

## What is Amphora Protocol?

Amphora is a lending market that supports various types of collateral, such as single-type collateral like ETH a liquidity provider tokens from Curve, including TriCrypto2. When users deposit Curve LP tokens into the platform, they are also staked in Convex. Allowing users to keep earning rewards while borrowing.

Amphora has its own stablecoin, USDA, which can be exchanged at a 1:1 ratio with sUSD (Synthetix USD). The stablecoin is designed to be overcollateralized and yield-bearing, enabling holders to receive a portion of the protocol's revenue just by holding the token.

## Main components of Amphora

  - The **VaultController** is the protocol's brain, enabling users to create vaults and borrow USDA. It also oversees liquidations by calculating current LTV and allowing liquidators to liquidate vaults. Governance can register new collaterals through the VaultController and tweak parameters for existing collaterals.
  &nbsp;
  - **USDA** is Amphora's stablecoin. All loans are denominated in it, and it can be exchanged 1:1 with sUSD (Synthetix USD), depending on reserve amounts. USDA is a rebasing token that adjusts user balances based on interest payments, letting anyone participate and earn a share of the protocol's profits just by holding it.
  &nbsp;
  - **Vaults** store users' collateral and can hold multiple types of collateral, allowing anyone to deposit different collaterals at the same time and get loans. When depositing Curve LPs, Vaults automatically stake them into Convex and start earning yield right away. Vault owners can claim this yield whenever they want.
    &nbsp;
  - **AMPH** is the protocol's governance token. Holding this token allows you to vote and propose changes to the protocol, such as adding new collaterals or adjusting LTV.
  &nbsp;
  - The **AMPHClaimer** takes care of the protocol's Liquidity Mining program. It exchanges a small percentage of a user's CVX/CRV rewards for AMPH, which is the governance token of the protocol. This swapping process happens automatically when the user claims their convex rewards from their staked collateral.
  &nbsp;
  - **WUSDA** lets users deposit USDA in protocols that don't support rebasing tokens. Anyone can deposit their USDA and get WUSDA in return, which increases in value instead of increasing user balances. Users can then withdraw their USDA + acumulated interest from the contract at any time.
  &nbsp;