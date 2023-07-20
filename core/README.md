# Amphora Protocol

## Deploy (Local)

To deploy the protocol locally and run the deployment script we need to have `foundry` installed.

1. Start anvil, which is our local Ethereum node.

```
anvil -f $MAINNET_RPC --fork-block-number 16784744 --chain-id 1337
```

2. After you run anvil, 10 accounts are gonna be auto-generated with their private keys. We can take one of the private keys and use it as the deployer wallet. So, add one of private keys to `.env` with key `DEPLOYER_ANVIL_LOCAL_PRIVATE_KEY`.

3. The we are ready to run the `Deploy` script.

```
yarn deploy:local
```

## Run Deposit and Borrow scripts

In order to run the `DepositAndBorrow` script we will need to have deployed the protocol locally. After that:

1. Copy the deployed addresses of `VaultController` and `USDA` contracts and replace them to their respective variables, `VAULT_CONTROLLER_ADDRESS` and `USDA_ADDRESS`, inside the `/solidity/test/utils/TestConstants.sol` file, under the `SCRIPTS` sections.

2. In order to run the scripts we will need some `WETH` to deposit to the Vault once we mint it. We will use foundry's `cast` to get some tokens to our address:

    - First we impersonate ourselves as a rich WETH address `cast rpc anvil_impersonateAccount 0xce0Adbb76A8Ce7224BeC6b586E18743aeB03250A`

    - Then we transfer some WETH to our address

        ```
        cast send $WETH_ADDRESS \
        --from 0xce0Adbb76A8Ce7224BeC6b586E18743aeB03250A \
        "transfer(address,uint)(bool)" \
        $DESTINATION_PUBLIC_ADDRESS \
        $AMOUNT
        ```

3. Now we should be able to run the scripts. First to mint a new Vault and deposit an amount of WETH we call `yarn scripts:deposit`.

4. Finally we will be able to run the borrow script. To borrow an amount of USDA tokens we call `yarn scripts:borrow`.

## Code Coverage (unit tests)

Running `forge coverage` on the project doesn't work straight away because of a "stack too deep" error in `GovernorCharlie` contract, for more information on the issue [check here](https://github.com/foundry-rs/foundry/issues/3357#issuecomment-1297192171). To bypass this problem for now we can do:

1. Comment the whole `Governor.t.sol` file in `test/unit`

2. In `foundry.toml` change the path of test to `test = './solidity/test/unit'`

3. Run `forge coverage -C solidity/contracts/core`

Following the steps above will create the summary of the code coverage. If you want to check the detailed report and see line-by-line the code covegare then we can do:

1. After following steps 1 & 2 from before we can then create the `lcov` report which will be saved in `lcov.info` file

    `forge coverage -C solidity/contracts/core --report lcov`

2. Use `genhtml` to create an html interface that will display the uncovered lines using the lcov report, the html files will be available in the newly created folder `report`

    `genhtml -o report lcov.info`

## Build and run docs

1. Generate and build docs, uses `forge doc`

`yarn docs:build`

2. Run docs locally

`yarn docs:run`

## Repository

```
~~ Structure ~~
├── solidity: All our contracts and interfaces are here
│   ├─── contracts/: All the contracts
│   │    ├─── core/: All core contracts
│   │    │   ├─── VaultController.sol : Can liquidate a vault, pay interest, changes protocol settings
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
│   │    │   └─── ThreeLines0_100.sol : The interest rate curve math for USDA **(NOT SURE ABOUT THIS)**
│   │    ├─── governance/: All contracts that are specific for the governance of the protocol
│   │    │   ├─── AmphoraProtocolToken.sol : Protocol governance token
│   │    │   └─── GovernorCharlie.sol : Governance contract of the protocol
│   ├─── interfaces/: The interfaces of all the contracts (SAME STRUCTURE WITH CONTRACTS)
│   ├─── tests/: All our tests for the contracts
│   │    ├─── e2e/: ...
│   │    └─── unit/: ...
└── README.md
```
