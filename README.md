# Amphora Protocol audit details
- Total Prize Pool: $65,500 USDC 
  - HM awards: $46,250 USDC 
  - Analysis awards: $2,500 USDC 
  - QA awards: $1,250 USDC 
  - Bot Race awards: $3,750 USDC 
  - Gas awards: $1,250 USDC 
  - Judge awards: $6,000 USDC 
  - Lookout awards: $4,000 USDC 
  - Scout awards: $500 USDC 
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-07-amphora/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts July 11, 2023 20:00 UTC
- Ends July 17, 2023 20:00 UTC 

## Automated Findings / Publicly Known Issues

Automated findings output for the audit can be found [here](add link to report) within 24 hours of audit opening.

*Note for C4 wardens: Anything included in the automated findings output is considered a publicly known issue and is ineligible for awards.*

[ ⭐️ SPONSORS ADD INFO HERE ]

# Overview

Amphora is a CDP borrow/lend protocol.

Users deposit sUSD(v3) to lend, and in turn recieve USDA a rebasing token that automatically rebases collecting yield.

To borrow from the sUSD pool, users open a "vault" and deposit collateral. Each vault is unique to a user keeping isolated positions and it can recieve both ERC-20 tokens and Curve LP tokens.

Curve LP tokens are deposited into their relative pools on Convex, so that users continue to earn CRV and CVX rewards while using the assets as collateral.

The protocol takes a small fee of the CRV and CVX rewards and in exchange rewars the user with $AMPH the protocols governance token.

https://docs.amphorafinance.com/

# Scope

├── solidity: All our contracts and interfaces are here
│   ├─── contracts/: All the contracts
│   │    ├─── core/: All core contracts
│   │    │   ├─── VaultController.sol : Master controller for all vaults and key logic. Can liquidate a vault, pay interest, changes protocol settings
│   │    │   ├─── VaultDeployer.sol : Will mint and deploy new Vaults
│   │    │   ├─── Vault.sol : User's vault, can deposit/withdraw collateral, claim protocol rewards, borrow sUSD
│   │    │   ├─── AMPHClaimer.sol : Contract for managing the liquidity mining program of amphora
│   │    │   ├─── USDA.sol : ERC20, given by the protocol 1:1 ratio when a lender deposits sUSD
│   │    │   └─── WUSDA.sol : Warped version of USDA to interact with other DeFi protocols
│   │    ├─── periphery/: All periphery contracts
│   │    │   │─── oracles
│   │    │   │   ├─── CurveLPOracle.sol : Responsible for getting the price of a curve LP token in USD
│   │    │   │   ├─── AnchoredViewRelay.sol : Oracle implementation that checks price against a relay for an acceptable buffer
│   │    │   │   ├─── CbEthEthOracle.sol : Oracle implementation for the cbeth-eth pool on curve
│   │    │   │   ├─── ChainlinkOracleRelay.sol : Oracle implementation for chainlink aggregators
│   │    │   │   ├─── ChainlinkStalePriceLib.sol : Library for checking price errors on chainlink
│   │    │   │   ├─── ChainlinkTokenOracleRelay.sol : Oracle implementation for chainlink pairs that don't have a USD oracle
│   │    │   │   ├─── CTokenOracle.sol : Oracle implementation for compound tokens
│   │    │   │   ├─── CurveRegistryUtils.sol : Helper to interact with the curve registry
│   │    │   │   ├─── EthSafeStableCurveOracle.sol : Safe curve lp oracle implementation for pairs that hold native ETH
│   │    │   │   ├─── OracleRelay.sol : Base implementation of amphora oracles
│   │    │   │   ├─── StableCurveLpOracle.sol : Oracle implementation for Curve lp stable pairs
│   │    │   │   ├─── TriCrypto2Oracle.sol : Oracle implementation for the tricrypto2 pool on curve
│   │    │   │   ├─── UniswapV3OracleRelay.sol : Oracle implementation for uniswap v3 pairs
│   │    │   │   ├─── UniswapV3TokenOracleRelay.sol : Oracle implementation for uniswap pairs that don't have a USDC oracle
│   │    │   │   ├─── WstEthOracle.sol : Oracle implementation for the wstETH token
│   │    │   │   └─── ETHOracle.sol : Responsible for getting the price of ETH in USD
│   │    │   └─── CurveMaster.sol : The CurveMaster manages the various interest rate curves, used in VaultManagerLogic
│   │    ├─── utils/: Util contracts that are being extended or used by other contracts
│   │    │   ├─── GovernanceStructs.sol : Structs needed to create proposals or governance related transactions
│   │    │   ├─── UFragments.sol : ERC20, extended by USDA, adjusts balances of all USDA holders
│   │    │   └─── ThreeLines0_100.sol : The interest rate curve math for USDA
│   │    ├─── governance/: All contracts that are specific for the governance of the protocol
│   │    │   ├─── AmphoraProtocolToken.sol : Protocol governance token
│   │    │   └─── GovernorCharlie.sol : Governance contract of the protocol
│   ├─── interfaces/: The interfaces of all the contracts (SAME STRUCTURE WITH CONTRACTS)

## Out of scope

-core/scripts/fakes/
-core/tests/
-core/scripts -- Primarily not within scope, but if you come across configuration issues during use, the team may be willing to provide additional $AMPH bounties for flagging it.

# Additional Context

Amphora's core is based on a fork of the "Interest Protocol" by Gfx Labs. They use a math model called 3 lines to manage interest rates. Robust documentation can be found here: https://interestprotocol.io/book/docs/concepts/Borrowing/CapitalEfficiency/ and here https://interestprotocol.io/book/docs/concepts/Borrowing/InterestRates/ 

The Interest Protocol rate parameters are as follows:

1st kink (s1): 25%
2nd kink (s2): 50%
1st kink rate (r1): 0.5%
2nd kink rate (r2): 10%
Max rate (r3): 200%

The aim of this curve model is to allow lending to work efficiently up to a fractional reserve when needed.

## Scoping Details 
```
- If you have a public code repo, please share it here: https://github.com/AmphoraProtocol/core 
- How many contracts are in scope?:   57
- Total SLoC for these contracts?:  2401
- How many external imports are there?: 15 
- How many separate interfaces and struct definitions are there for the contracts within scope?:  24
- Does most of your code generally use composition or inheritance?:  Composition
- How many external calls?:   8
- What is the overall line coverage percentage provided by your tests?: 90%
- Is this an upgrade of an existing system?: True; We took the Interest Protocol and made it so vaults can deposit Convex LP positions as collateral, which are automatically deposited into Convex, and share rewards back to the user and the protocol. We also upgraded the oracle system.
- Check all that apply (e.g. timelock, NFT, AMM, ERC20, rollups, etc.): ERC-20 Token
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?: False  
- Please describe required context:   n/a
- Does it use an oracle?:  Others; Uses both Chainlink, Curve and Uniswap V3 as Oracles, has interna
- Describe any novel or unique curve logic or mathematical models your code uses: Yes
- Is this either a fork of or an alternate implementation of another project?:   True
- Does it use a side-chain?: False
- Fresh or audited code: Protocol we forked was previously audit, this code has not been
- Describe any specific areas you would like addressed:
```

# Tests

Full test instructions and documentation can be found in /core/README.md 

We use Foundry/Forge for our local testing, and it is important to note `forge coverage` will result in a `stack too deep error` due to Governor Charlie contract. A detailed work around is provided in the /core/README.md