// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';
import {VaultController} from '@contracts/core/VaultController.sol';
import {USDA} from '@contracts/core/USDA.sol';

import {Deploy, DeployVars} from '@scripts/Deploy.s.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {MintableToken} from '@scripts/fakes/MintableToken.sol';
import {FakeBooster} from '@scripts/fakes/FakeBooster.sol';
import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';
import {FakeCVX} from '@scripts/fakes/FakeBaseRewardPool.sol';

import {console} from 'forge-std/console.sol';

contract DeployGoerli is Deploy {
  address public deployer = vm.rememberKey(vm.envUint('DEPLOYER_GOERLI_PRIVATE_KEY'));

  function run() external {
    vm.startBroadcast(deployer);
    UniswapV3OracleRelay _uniswapRelayEthUsdc = UniswapV3OracleRelay(_createEthUsdcTokenOracleRelay());
    ChainlinkOracleRelay _chainlinkEth = ChainlinkOracleRelay(_createEthUsdChainlinkOracleRelay());
    // Deploy weth oracle first, can be removed if the user defines a valid oracle address
    address _oracle = _createWethOracle(_uniswapRelayEthUsdc, _chainlinkEth);

    DeployVars memory _deployVars = DeployVars(
      deployer,
      IERC20(CVX_ADDRESS),
      IERC20(CRV_ADDRESS),
      IERC20(SUSD_ADDRESS),
      IERC20(WETH_ADDRESS),
      BOOSTER,
      _oracle,
      true
    );

    _deploy(_deployVars);
    vm.stopBroadcast();
  }
}

contract DeployGoerliOpenDeployment is Deploy {
  address public deployer = vm.rememberKey(vm.envUint('DEPLOYER_GOERLI_PRIVATE_KEY'));
  address public constant wethGoerli = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
  address public constant linkGoerli = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
  address public constant ethUSD = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e;
  address public constant linkUSD = 0x48731cF7e84dc94C5f84577882c14Be11a5B7456;

  uint256 public susdCopySupply = 1_000_000 ether;
  uint256 public chainlinkStalePriceDelay = 100 days;

  function run() external {
    vm.startBroadcast(deployer);
    uint256 currentNonce = vm.getNonce(deployer);
    console.log('currentNonce: ', currentNonce);
    // Deploy CVX & CRV tokens
    MintableToken cvx = MintableToken(address(new FakeCVX()));
    MintableToken crv = new MintableToken('CRV',uint8(18));
    // Deploy Fake Booster
    FakeBooster fakeBooster = new FakeBooster();

    // Deploy a copy of sUSDA
    MintableToken susdCopy = new MintableToken('sUSD',uint8(18));
    susdCopy.mint(deployer, susdCopySupply);
    console.log('sUSD_COPY: ', address(susdCopy));

    // Chainlink ETH/USD
    ChainlinkOracleRelay _chainlinkEth =
      new ChainlinkOracleRelay(wethGoerli, ethUSD, 10_000_000_000, 1, chainlinkStalePriceDelay);
    console.log('CHAINLINK_ETH_FEED: ', address(_chainlinkEth));

    // Chainlink LINK/USD
    ChainlinkOracleRelay _chainlinkLink = new ChainlinkOracleRelay(linkGoerli, linkUSD, 10_000_000_000, 1, 100 days);
    console.log('CHAINLINK_LINK_FEED: ', address(_chainlinkLink));
    // Deploy and set up curve lp rewards
    uint256 _pid = _addFakeCurveLPRewards(cvx, crv, fakeBooster, linkGoerli);

    // Deploy protocol
    DeployVars memory _deployVars =
      DeployVars(deployer, cvx, crv, susdCopy, IERC20(wethGoerli), address(fakeBooster), address(_chainlinkEth), false);
    (,, VaultController _vaultController,,, USDA _usda) = _deploy(_deployVars);

    susdCopy.approve(address(_usda), 1_000_000 ether);
    _usda.donate(500_000 ether);

    // Register curveLP token
    _vaultController.registerErc20(
      address(linkGoerli), WETH_LTV, address(_chainlinkLink), LIQUIDATION_INCENTIVE, type(uint256).max, _pid
    );

    // Deploy fake wbtc
    MintableToken wbtc = new MintableToken('WBTC',uint8(8));
    wbtc.mint(deployer, 10_000e8);
    console.log('FAKE_WBTC_ADDRESS', address(wbtc));
    // Deploy chainlink oracle
    ChainlinkOracleRelay _chainlinkWbtc =
    new ChainlinkOracleRelay(address(wbtc), 0xA39434A63A52E749F02807ae27335515BA4b07F7, 10_000_000_000, 1, chainlinkStalePriceDelay);

    // Add fake WBTC
    _vaultController.registerErc20(address(wbtc), WETH_LTV, address(_chainlinkWbtc), LIQUIDATION_INCENTIVE, 1000e8, 0);

    vm.stopBroadcast();
  }
}
