// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {console} from 'forge-std/console.sol';
import {DSTestPlus} from 'solidity-utils/test/DSTestPlus.sol';

import {VaultController} from '@contracts/core/VaultController.sol';
import {VaultDeployer} from '@contracts/core/VaultDeployer.sol';
import {USDA} from '@contracts/core/USDA.sol';
import {AmphoraProtocolToken} from '@contracts/governance/AmphoraProtocolToken.sol';
import {GovernorCharlie} from '@contracts/governance/GovernorCharlie.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';
import {AnchoredViewRelay} from '@contracts/periphery/oracles/AnchoredViewRelay.sol';
import {CurveMaster} from '@contracts/periphery/CurveMaster.sol';
import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';
import {UniswapV3TokenOracleRelay} from '@contracts/periphery/oracles/UniswapV3TokenOracleRelay.sol';
import {StableCurveLpOracle} from '@contracts/periphery/oracles/StableCurveLpOracle.sol';
import {TriCrypto2Oracle} from '@contracts/periphery/oracles/TriCrypto2Oracle.sol';
import {ThreeLines0_100} from '@contracts/utils/ThreeLines0_100.sol';
import {WUSDA} from '@contracts/core/WUSDA.sol';
import {IAMPHClaimer} from '@interfaces/core/IAMPHClaimer.sol';
import {AMPHClaimer} from '@contracts/core/AMPHClaimer.sol';

import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IVaultDeployer} from '@interfaces/core/IVaultDeployer.sol';
import {IWUSDA} from '@interfaces/core/IWUSDA.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';

import {TestConstants} from '@test/utils/TestConstants.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ExponentialNoError} from '@contracts/utils/ExponentialNoError.sol';
import {CreateOracles} from '@scripts/CreateOracles.sol';

// solhint-disable-next-line max-states-count
contract CommonE2EBase is DSTestPlus, TestConstants, ExponentialNoError, CreateOracles {
  uint256 public constant FORK_BLOCK = 17_300_000;
  /// 16442788;///;
  uint256 public constant DELTA = 100;

  // AMPH token
  AmphoraProtocolToken public amphToken;
  AMPHClaimer public amphClaimer;
  // USDA token
  USDA public usdaToken;
  // WUSDA token
  WUSDA public wusda;
  // VaultControllers
  VaultController public vaultController;
  VaultController public vaultController2;
  // VaultDeployer
  VaultDeployer public vaultDeployer;
  // Curve Master and ThreeLines0_100 curve
  CurveMaster public curveMaster;
  ThreeLines0_100 public threeLines;
  // uniswapv3 oracles
  UniswapV3OracleRelay public uniswapRelayEthUsdc;
  UniswapV3OracleRelay public uniswapRelayUniUsdc;
  UniswapV3TokenOracleRelay public uniswapRelayDydxWeth;
  UniswapV3TokenOracleRelay public uniswapRelayAaveWeth;
  UniswapV3OracleRelay public uniswapRelayWbtcUsdc;
  // Chainlink oracles
  ChainlinkOracleRelay public chainLinkUni;
  ChainlinkOracleRelay public chainlinkEth;
  ChainlinkOracleRelay public chainlinkAave;
  ChainlinkOracleRelay public chainlinkBtc;
  ChainlinkOracleRelay public chainlinkDydx;
  // AnchoredView relayers
  AnchoredViewRelay public anchoredViewEth;
  AnchoredViewRelay public anchoredViewUni;
  AnchoredViewRelay public anchoredViewAave;
  AnchoredViewRelay public anchoredViewDydx;
  AnchoredViewRelay public anchoredViewStEth;
  AnchoredViewRelay public anchoredViewSnx;
  IOracleRelay public anchoredViewBtc;
  IOracleRelay public anchoredViewDai;
  IOracleRelay public anchoredViewUsdc;
  IOracleRelay public anchoredViewUsdt;
  // Curve oracles
  StableCurveLpOracle public threeCrvOracle;
  TriCrypto2Oracle public triCryptoOracle;
  // Governance
  GovernorCharlie public governor;

  IERC20 public susd = IERC20(label(SUSD_ADDRESS, 'SUSD'));
  IERC20 public weth = IERC20(label(WETH_ADDRESS, 'WETH'));
  IERC20 public wbtc = IERC20(label(WBTC_ADDRESS, 'WBTC'));
  IERC20 public uni = IERC20(label(UNI_ADDRESS, 'UNI'));
  IERC20 public aave = IERC20(label(AAVE_ADDRESS, 'AAVE'));
  IERC20 public dydx = IERC20(label(DYDX_ADDRESS, 'DYDX'));
  IERC20 public usdtStableLP = IERC20(label(USDT_LP_ADDRESS, 'USDT_LP'));
  IERC20 public threeCrvLP = IERC20(label(THREE_CRV_LP_ADDRESS, 'THREE_CRV_LP'));
  /// gearLP is a curveLP token that provides extra rewards compared to usdtLP
  IERC20 public gearLP = IERC20(label(GEAR_LP_ADDRESS, 'GEAR_LP'));
  // frank is the Frank and master of USDA, and symbolizes the power of governance
  address public frank = label(newAddress(), 'frank');
  // andy is a susd holder. He wishes to deposit his sUSD to hold USDA
  address public andy = label(newAddress(), 'andy');
  // bob is an eth holder. He wishes to deposit his eth and borrow USDA
  address public bob = label(newAddress(), 'bob');
  // carol is a uni holder. She wishes to deposit uni and borrow USDA, and still be able to vote
  address public carol = label(newAddress(), 'carol');
  // dave is a liquidator. he enjoys liquidating, so he's going to try to liquidate Bob
  address public dave = label(newAddress(), 'dave');
  // eric only holds ETH and generally does not use AP unless a clean slate is needed
  address public eric = label(newAddress(), 'eric');
  // gus is a wBTC holder. He wishes to deposit wBTC and borrow USDA
  address public gus = label(newAddress(), 'gus');
  // hector is also here
  address public hector = label(newAddress(), 'hector');

  IVault public bobVault;
  uint96 public bobVaultId;

  IVault public carolVault;
  uint96 public carolVaultId;

  IVault public daveVault;
  uint96 public daveVaultId;

  IVault public gusVault;
  uint96 public gusVaultId;

  uint256 public andySUSDBalance = 100 ether;
  uint256 public bobSUSDBalance = 1000 ether;
  uint256 public bobCurveLPBalance = 10 ether;
  uint256 public bobWETH = 10 ether;
  uint256 public carolUni = 100 ether;
  uint256 public gusWBTC = 1_000_000_000 ether;
  uint256 public daveSUSD = 10_000_000_000 ether;
  uint256 public bobAAVE = 1000 ether;
  uint256 public carolDYDX = 100 ether;
  uint256 public gusUni = 100 ether;

  uint256 public initialAMPH = 100_000_000 ether;

  uint256 public cvxRewardFee = 0.02e18;
  uint256 public crvRewardFee = 0.01e18;

  uint256 public staleTime = 20 * 365 days; // 20 years stale time so we can advance time in tests

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl('mainnet'), FORK_BLOCK);

    address[] memory _tokens = new address[](0);

    // Transfer some susd, weth and uni to users
    _dealSUSD(andy, andySUSDBalance);
    _dealSUSD(dave, daveSUSD);
    _dealSUSD(bob, bobSUSDBalance);
    deal(address(weth), bob, bobWETH);
    deal(address(uni), carol, carolUni);
    deal(address(aave), bob, bobAAVE);
    deal(address(dydx), carol, carolDYDX);
    deal(address(wbtc), gus, gusWBTC);
    deal(address(uni), gus, gusUni);
    deal(address(usdtStableLP), bob, bobCurveLPBalance);
    deal(address(gearLP), bob, bobCurveLPBalance);
    deal(address(threeCrvLP), bob, 1000 ether);
    deal(dave, 1000 ether);

    vm.startPrank(frank);

    // Deploy AMPH token
    amphToken = new AmphoraProtocolToken(frank, initialAMPH);

    // Deploy VaultDeployer
    vaultDeployer = new VaultDeployer(IERC20(CVX_ADDRESS), IERC20(CRV_ADDRESS));
    label(address(vaultDeployer), 'VaultDeployer');

    // Deploy VaultController
    vaultController =
    new VaultController(IVaultController(address(0)), _tokens, IAMPHClaimer(address(0)), vaultDeployer, 0.01e18, BOOSTER, 0.005e18);
    label(address(vaultController), 'VaultController');

    // Deploy claimer
    amphClaimer =
    new AMPHClaimer(address(vaultController), IERC20(address(amphToken)), IERC20(CVX_ADDRESS), IERC20(CRV_ADDRESS), cvxRewardFee, crvRewardFee);

    // Change AMPH claimer
    vaultController.changeClaimerContract(amphClaimer);

    // Deploy and initialize USDA
    usdaToken = new USDA(IERC20(SUSD_ADDRESS));
    label(address(usdaToken), 'USDA');

    // Deploy curve
    threeLines = new ThreeLines0_100(2 ether, 0.1 ether, 0.005 ether, 0.25 ether, 0.5 ether);
    label(address(threeLines), 'ThreeLines0_100');

    // Deploy CurveMaster
    curveMaster = new CurveMaster();
    label(address(curveMaster), 'CurveMaster');

    // Add curveMaster to VaultController
    vaultController.registerCurveMaster(address(curveMaster));

    // Set VaultController address for usdatoken
    usdaToken.addVaultController(address(vaultController));

    // Deploy uniswapRelayEthUsdc oracle relay
    uniswapRelayEthUsdc = UniswapV3OracleRelay(_createEthUsdcTokenOracleRelay());
    // Deploy uniswapRelayUniUsdc oracle relay
    uniswapRelayUniUsdc = new UniswapV3OracleRelay(14400, USDC_UNI_POOL_ADDRESS, false);
    // Deploys uniswapRelayDydxWeth oracle relay
    uniswapRelayDydxWeth = new UniswapV3TokenOracleRelay(uniswapRelayEthUsdc, 14400, DYDX_WETH_POOL_ADDRESS, false);
    // Deploy uniswapRelayAaveWeth oracle relay
    uniswapRelayAaveWeth = new UniswapV3TokenOracleRelay(uniswapRelayEthUsdc, 14400, AAVE_WETH_POOL_ADDRESS, false);
    // Deploy uniswapRelayUniUsdc oracle relay
    uniswapRelayWbtcUsdc = new UniswapV3OracleRelay(7200, USDC_WBTC_POOL_ADDRESS, false);
    // Deploy chainLinkUni oracle relay
    chainLinkUni = new ChainlinkOracleRelay(UNI_ADDRESS, CHAINLINK_UNI_FEED_ADDRESS, 10_000_000_000, 1, staleTime);
    // Deploy chainlinkEth oracle relay
    chainlinkEth = new ChainlinkOracleRelay(WETH_ADDRESS, CHAINLINK_ETH_FEED_ADDRESS, 10_000_000_000, 1, staleTime);
    // Deploy chainlinkAave oracle relay
    chainlinkAave = new ChainlinkOracleRelay(AAVE_ADDRESS, CHAINLINK_AAVE_FEED_ADDRESS, 10_000_000_000, 1, staleTime);
    // Deploy chainlinkAave oracle relay
    chainlinkDydx = new ChainlinkOracleRelay(DYDX_ADDRESS, CHAINLINK_DYDX_FEED_ADDRESS, 10_000_000_000, 1, staleTime);
    // Deploy chainlinkWbtc oracle relay
    chainlinkBtc =
      new ChainlinkOracleRelay(WBTC_ADDRESS, CHAINLINK_BTC_FEED_ADDRESS, 100_000_000_000_000_000_000, 1, staleTime);
    // Deploy anchoredViewEth relay
    anchoredViewEth = new AnchoredViewRelay(address(uniswapRelayEthUsdc), address(chainlinkEth), 20, 100, 10, 100);
    // Deploy anchoredViewUni relay
    anchoredViewUni = new AnchoredViewRelay(address(uniswapRelayUniUsdc), address(chainLinkUni), 40, 100, 10, 100);
    // Deploy anchoredViewAave relay
    anchoredViewAave = new AnchoredViewRelay(address(uniswapRelayAaveWeth), address(chainlinkAave), 25, 100, 10, 100);
    // Deploy anchoredViewDydx relay
    anchoredViewDydx = new AnchoredViewRelay(address(uniswapRelayDydxWeth), address(chainlinkDydx), 20, 100, 10, 100);
    // Deploy anchoredViewsTEth relay
    anchoredViewStEth = AnchoredViewRelay(_createStEthOracle(uniswapRelayEthUsdc));
    anchoredViewSnx = AnchoredViewRelay(_createSnxOracle(uniswapRelayEthUsdc));

    /// Deploy usdc oracle relay
    anchoredViewUsdc = IOracleRelay(_createUsdcOracle());
    /// Deploy dai oracle relay
    anchoredViewDai = IOracleRelay(_createDaiOracle());
    /// Deploy usdt oracle relay
    anchoredViewUsdt = IOracleRelay(_createUsdtOracle());
    // Deploy wbtc oracle relay
    anchoredViewBtc = IOracleRelay(_createWbtcOracle(uniswapRelayEthUsdc));

    // Deploy the ThreeCrvOracle
    threeCrvOracle = StableCurveLpOracle(
      _create3CrvOracle(THREE_CRV_POOL_ADDRESS, anchoredViewDai, anchoredViewUsdt, anchoredViewUsdc)
    );
    // Deploy the triCryptoOracle
    triCryptoOracle = TriCrypto2Oracle(_createTriCrypto2Oracle(anchoredViewEth, anchoredViewUsdt, anchoredViewBtc));

    // Register WETH as acceptable erc20 to vault controller
    vaultController.registerErc20(
      WETH_ADDRESS, WETH_LTV, address(anchoredViewEth), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );
    // Register UNI as acceptable erc20 to vault controller
    vaultController.registerErc20(
      UNI_ADDRESS, UNI_LTV, address(anchoredViewUni), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );
    // Register AAVE as acceptable erc20 to vault controller
    vaultController.registerErc20(AAVE_ADDRESS, AAVE_LTV, address(anchoredViewAave), LIQUIDATION_INCENTIVE, AAVE_CAP, 0);
    // Register wbtc as acceptable erc20 to vault controller
    vaultController.registerErc20(
      WBTC_ADDRESS, WBTC_LTV, address(anchoredViewBtc), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );

    vaultController.registerErc20(
      USDT_LP_ADDRESS, OTHER_LTV, address(threeCrvOracle), LIQUIDATION_INCENTIVE, type(uint256).max, 1
    );
    vaultController.registerErc20(
      GEAR_LP_ADDRESS, OTHER_LTV, address(anchoredViewUni), LIQUIDATION_INCENTIVE, type(uint256).max, 136
    );

    // Register the triCrypto2 pool as collateral
    vaultController.registerErc20(
      TRI_CRYPTO_LP_TOKEN, OTHER_LTV, address(triCryptoOracle), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );

    // Register USDA as acceptable erc20 to vault controller
    vaultController.registerUSDA(address(usdaToken));

    // Set new curve
    curveMaster.setCurve(address(0), address(threeLines));

    // Set pauser
    usdaToken.setPauser(address(frank));

    // Deploy governance
    governor = new GovernorCharlie(address(amphToken));

    usdaToken.setPauser(address(governor));

    usdaToken.transferOwnership(address(governor));
    vaultController.transferOwnership(address(governor));
    curveMaster.transferOwnership(address(governor));
    amphClaimer.transferOwnership(address(governor));

    // Deploy wUSDA
    wusda = new WUSDA(address(usdaToken), 'Wrapped USDA', 'wUSDA');

    // TODO: add checks for everything being set
    vm.stopPrank();
  }

  function _dealSUSD(address _receiver, uint256 _amount) internal {
    // sUSD is a proxy so doesn't work with `deal`
    // here executes deal in the `TokenState` contract from sUSD
    deal(SUSD_TOKEN_STATE, _receiver, _amount);
  }

  function _mintVault(address _minter) internal returns (uint96 _id) {
    vm.prank(_minter);
    vaultController.mintVault();
    _id = uint96(vaultController.vaultsMinted());
  }

  function _borrow(address _account, uint96 _vaultId, uint256 _borrowAmount) internal {
    vm.prank(_account);
    vaultController.borrowUSDA(_vaultId, uint192(_borrowAmount));
  }

  function _depositSUSD(address _account, uint256 _amountToDeposit) internal {
    vm.startPrank(_account);
    susd.approve(address(usdaToken), _amountToDeposit);
    usdaToken.deposit(_amountToDeposit);
    vm.stopPrank();
  }
}
