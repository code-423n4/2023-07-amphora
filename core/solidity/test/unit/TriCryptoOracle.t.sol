// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {WUSDA} from '@contracts/core/WUSDA.sol';
import {TriCrypto2Oracle} from '@contracts/periphery/oracles/TriCrypto2Oracle.sol';
import {ICurveAddressesProvider, ICurveRegistry} from '@interfaces/periphery/ICurveAddressesProvider.sol';
import {ICurvePool} from '@interfaces/utils/ICurvePool.sol';
import {DSTestPlus} from 'solidity-utils/test/DSTestPlus.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {AggregatorInterface} from '@chainlink/interfaces/AggregatorInterface.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {AggregatorV3Interface} from '@chainlink/interfaces/AggregatorV3Interface.sol';
import {ChainlinkStalePriceLib} from '@contracts/periphery/oracles/ChainlinkStalePriceLib.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';

abstract contract Base is DSTestPlus {
  uint256 public constant POINT_ONE_PERCENT = 0.001e18;

  ICurvePool public curvePool = ICurvePool(mockContract(newAddress(), 'curvePool'));
  IOracleRelay public wbtcFeed = IOracleRelay(mockContract(newAddress(), 'btcFeed'));
  IOracleRelay public ethFeed = IOracleRelay(mockContract(newAddress(), 'ethFeed'));
  IOracleRelay public usdtFeed = IOracleRelay(mockContract(newAddress(), 'usdtFeed'));

  address internal _lpToken = newAddress();
  ICurveAddressesProvider internal _curveAddressesProvider =
    ICurveAddressesProvider(mockContract(address(0x0000000022D53366457F9d5E68Ec105046FC4383), 'curveAddressesProvider'));
  ICurveRegistry internal _curveRegistry = ICurveRegistry(mockContract(address(newAddress()), 'curveRegistry'));

  TriCrypto2Oracle public triCryptoOracle;

  function setUp() public virtual {
    // Mock curve addresses provider
    vm.mockCall(
      address(_curveAddressesProvider),
      abi.encodeWithSelector(ICurveAddressesProvider.get_registry.selector),
      abi.encode(address(_curveRegistry))
    );
    // Mock curve registry
    vm.mockCall(
      address(_curveRegistry), abi.encodeWithSelector(ICurveRegistry.get_lp_token.selector), abi.encode(_lpToken)
    );

    triCryptoOracle = new TriCrypto2Oracle(address(curvePool), ethFeed, usdtFeed, wbtcFeed);
  }
}

contract UnitUnderlyingIsSet is Base {
  function testUnderlyingIsSet() public {
    assertEq(triCryptoOracle.underlying(), _lpToken);
  }
}

contract UnitRoot is Base {
  function testCubicRoot(uint80 _x) public {
    assertEq(FixedPointMathLib.cbrt(uint256(_x) * _x * _x), _x);
  }

  function testSqrt(uint128 _x) public {
    assertEq(FixedPointMathLib.sqrt(uint256(_x) * _x), _x);
  }

  // Calculated outside and chose a random number that is not round
  function testCubicRootHardcoded() public {
    assertApproxEqRel(FixedPointMathLib.cbrt(46_617_561_682_349_991_266_580_000), 359_901_207, POINT_ONE_PERCENT);
  }

  // Calculated outside and chose a random number that is not round
  function testSqrtHardcoded() public {
    assertApproxEqRel(FixedPointMathLib.sqrt(4_661_756_168_234_999_126_658), 68_277_082_538, POINT_ONE_PERCENT);
  }
}

contract UnitCurrentValue is Base {
  function testCurrentValue(uint32 _wbtcPrice, uint32 _ethPrice, uint32 _usdtPrice) public {
    vm.assume(_wbtcPrice > 0.1e8);
    vm.assume(_ethPrice > 0.1e8);
    vm.assume(_usdtPrice > 0.1e8);
    uint256 _vp = 1.1e18;

    // mockCall to get_virtual_price
    vm.mockCall(address(curvePool), abi.encodeWithSelector(ICurvePool.get_virtual_price.selector), abi.encode(_vp));

    // mockCall to feed latestAnswers
    vm.mockCall(address(ethFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_ethPrice));

    vm.mockCall(address(usdtFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_usdtPrice));

    vm.mockCall(address(wbtcFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_wbtcPrice));

    uint256 _basePrices = (uint256(_wbtcPrice) * _ethPrice * _usdtPrice);

    uint256 _maxPrice = (3 * _vp * FixedPointMathLib.cbrt(_basePrices)) / 1 ether;

    assertEq(triCryptoOracle.currentValue(), _maxPrice);
  }
}

contract UnitTriCryptoOracleExternalCalls is Base {
  uint256 internal _vp = 1 ether;
  uint256 internal _ethPrice = 2000 ether;
  uint256 internal _usdtPrice = 1 ether;
  uint256 internal _wbtcPrice = 20_000 ether;

  function setUp() public virtual override {
    super.setUp();

    // mockCall to get_virtual_price
    vm.mockCall(address(curvePool), abi.encodeWithSelector(ICurvePool.get_virtual_price.selector), abi.encode(_vp));

    // mockCall to feed latestAnswers
    vm.mockCall(address(ethFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_ethPrice));

    vm.mockCall(address(usdtFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_usdtPrice));

    vm.mockCall(address(wbtcFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_wbtcPrice));
  }

  function testCallsPeekValueOnEthFeed() public {
    vm.expectCall(address(ethFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector));
    triCryptoOracle.currentValue();
  }

  function testCallsPeekValueOnUsdtFeed() public {
    vm.expectCall(address(usdtFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector));
    triCryptoOracle.currentValue();
  }

  function testCallsPeekValueOnWbtcFeed() public {
    vm.expectCall(address(wbtcFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector));
    triCryptoOracle.currentValue();
  }
}
