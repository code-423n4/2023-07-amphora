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

|Contract|SLOC|
|[VaultController.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/core/VaultController.sol)|535|
|[GovernorCharlie.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/governance/GovernorCharlie.sol)|419|
|[Vault.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/core/Vault.sol)|211|
|[USDA.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/core/USDA.sol)|162|
|[UFragments.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/utils/UFragments.sol)|151|
|[AMPHClaimer.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/core/AMPHClaimer.sol)|134|
|[WUSDA.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/core/WUSDA.sol)|99|
|[AnchoredViewRelay.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/AnchoredViewRelay.sol)|48|
|[ThreeLines0_100.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/utils/ThreeLines0_100.sol)|46|
|[UniswapV3OracleRelay.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/UniswapV3OracleRelay.sol)|43|
|[CbEthEthOracle.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/CbEthEthOracle.sol)|41|
|[ChainlinkOracleRelay.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/ChainlinkOracleRelay.sol)|40|
|[StableCurveLpOracle.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/StableCurveLpOracle.sol)|38|
|[TriCrypto2Oracle.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/TriCrypto2Oracle.sol)|35|
|[GovernanceStructs.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/utils/GovernanceStructs.sol)|35|
|[CurveMaster.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/CurveMaster.sol)|31|
|[CTokenOracle.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/CTokenOracle.sol)|31|
|[EthSafeStableCurveOracle.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/EthSafeStableCurveOracle.sol)|29|
|[ChainlinkTokenOracleRelay.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/ChainlinkTokenOracleRelay.sol)|26|
|[WstEthOracle.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/WstEthOracle.sol)|19|
|[UniswapV3TokenOracleRelay.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/UniswapV3TokenOracleRelay.sol)|18|
|[AmphoraProtocolToken.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/governance/AmphoraProtocolToken.sol)|17|
|[OracleRelay.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/OracleRelay.sol)|17|
|[VaultDeployer.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/core/VaultDeployer.sol)|16|
|[ChainlinkStalePriceLib.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/ChainlinkStalePriceLib.sol)|10|
|[CurveRegistryUtils.sol](https://github.com/code-423n4/2023-07-amphora/blob/main/core/solidity/contracts/periphery/oracles/CurveRegistryUtils.sol)|10|
|SUM:|2261|

## Out of scope

```
-/core/.husky
-/core/docs/
-core/scripts/fakes/
-core/tests/
-core/scripts -- Primarily not within scope, but if you come across configuration issues during use, the team may be willing to provide additional $AMPH bounties for flagging it.
```

# Additional Context

Amphora's core is based on a fork of the "Interest Protocol" by Gfx Labs. They use a math model called 3 lines to manage interest rates. Robust documentation can be found here: https://interestprotocol.io/book/docs/concepts/Borrowing/CapitalEfficiency/ and here https://interestprotocol.io/book/docs/concepts/Borrowing/InterestRates/ 

The Interest Protocol rate parameters are as follows:

```
1st kink (s1): 25%
2nd kink (s2): 50%
1st kink rate (r1): 0.5%
2nd kink rate (r2): 10%
Max rate (r3): 200%
```

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