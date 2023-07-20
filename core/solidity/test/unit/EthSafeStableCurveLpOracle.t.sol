// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus, console} from 'solidity-utils/test/DSTestPlus.sol';
import {EthSafeStableCurveOracle} from '@contracts/periphery/oracles/EthSafeStableCurveOracle.sol';

import {IStablePool, ICurvePool} from '@interfaces/utils/ICurvePool.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {ICurveAddressesProvider, ICurveRegistry} from '@interfaces/periphery/ICurveAddressesProvider.sol';

abstract contract Base is DSTestPlus {
  EthSafeStableCurveOracle public curveOracle;

  IStablePool internal _mockCurvePool;
  IOracleRelay[] internal _anchoredUnderlyingTokens;
  IOracleRelay internal _oracleRelayToken1;
  IOracleRelay internal _oracleRelayToken2;
  uint256 internal _initialVirtualPrice = 1 ether;
  ICurveAddressesProvider internal _curveAddressesProvider;
  ICurveRegistry internal _curveRegistry;
  address internal _lpToken;

  function setUp() public virtual {
    // mock curve pool & oracles
    _mockCurvePool = IStablePool(mockContract(address(newAddress()), 'mockCurvePool'));
    _oracleRelayToken1 = IOracleRelay(mockContract(address(newAddress()), 'anchorOracle1'));
    _oracleRelayToken2 = IOracleRelay(mockContract(address(newAddress()), 'anchorOracle2'));
    _curveAddressesProvider = ICurveAddressesProvider(
      mockContract(address(0x0000000022D53366457F9d5E68Ec105046FC4383), 'curveAddressesProvider')
    );
    _curveRegistry = ICurveRegistry(mockContract(address(newAddress()), 'curveRegistry'));

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

    _anchoredUnderlyingTokens = new IOracleRelay[](2);
    _anchoredUnderlyingTokens[0] = _oracleRelayToken1;
    _anchoredUnderlyingTokens[1] = _oracleRelayToken2;

    vm.mockCall(
      address(_oracleRelayToken1),
      abi.encodeWithSelector(IOracleRelay.peekValue.selector),
      abi.encode(_initialVirtualPrice)
    );

    vm.mockCall(
      address(_oracleRelayToken2),
      abi.encodeWithSelector(IOracleRelay.peekValue.selector),
      abi.encode(_initialVirtualPrice)
    );

    // Mock the curve pool virtual price function
    vm.mockCall(
      address(_mockCurvePool),
      abi.encodeWithSelector(ICurvePool.get_virtual_price.selector),
      abi.encode(_initialVirtualPrice)
    );
    // Mock the curve pool remove liquidity function
    uint256[2] memory _amounts;
    vm.mockCall(
      address(_mockCurvePool), abi.encodeWithSelector(IStablePool.remove_liquidity.selector), abi.encode(_amounts)
    );
    // Deploy contract
    curveOracle = new EthSafeStableCurveOracle(address(_mockCurvePool), _anchoredUnderlyingTokens);
  }

  function _getMin(uint256 _x, uint256 _z) internal pure returns (uint256 _min) {
    _min = _x >= _z ? _z : _x;
  }
}

contract UnitTestEthSafeStableCurveLpOracleConstructor is Base {
  function testConstructorParams() public {
    assertEq(address(curveOracle.CRV_POOL()), address(_mockCurvePool));
    assertEq(address(_anchoredUnderlyingTokens[0]), address(_oracleRelayToken1));
    assertEq(address(_anchoredUnderlyingTokens[1]), address(_oracleRelayToken2));
    assertEq(curveOracle.virtualPrice(), _initialVirtualPrice);
  }

  function testUnderlying() public {
    assertEq(curveOracle.underlying(), _lpToken);
  }
}

contract UnitTestEthSafeStableCurveLpOracleCurrentValue is Base {
  function testCurrentValueCallsVirtualPrice() public {
    vm.expectCall(address(_mockCurvePool), abi.encodeWithSelector(ICurvePool.get_virtual_price.selector));
    curveOracle.currentValue();
  }

  function testCurrentValueCallsRemoveLiquidity() public {
    uint256[2] memory _amounts;
    vm.expectCall(address(_mockCurvePool), abi.encodeWithSelector(IStablePool.remove_liquidity.selector, _amounts));
    curveOracle.currentValue();
  }

  function testPeekValueDoesNotUpdateVirtualPrice(
    uint256 _anchorToken1CurrentPrice,
    uint256 _anchorToken2CurrentPrice,
    uint256 _virtualPrice
  ) public {
    vm.assume(_anchorToken1CurrentPrice > 0);
    vm.assume(_anchorToken2CurrentPrice > 0);

    uint256 _minStable = uint256(_getMin(_anchorToken1CurrentPrice, _anchorToken2CurrentPrice));

    vm.assume(_initialVirtualPrice < type(uint256).max / _minStable);

    vm.mockCall(
      address(_oracleRelayToken1),
      abi.encodeWithSelector(IOracleRelay.peekValue.selector),
      abi.encode(_anchorToken1CurrentPrice)
    );

    vm.mockCall(
      address(_oracleRelayToken2),
      abi.encodeWithSelector(IOracleRelay.peekValue.selector),
      abi.encode(_anchorToken2CurrentPrice)
    );

    uint256 _beforeValue = curveOracle.peekValue();

    vm.mockCall(
      address(_mockCurvePool), abi.encodeWithSelector(ICurvePool.get_virtual_price.selector), abi.encode(_virtualPrice)
    );

    uint256 _afterValue = curveOracle.peekValue();
    assertEq(_beforeValue, _afterValue);
  }

  function testCurrentValue(
    uint256 _anchorToken1CurrentPrice,
    uint256 _anchorToken2CurrentPrice,
    uint256 _virtualPrice
  ) public {
    vm.assume(_anchorToken1CurrentPrice > 0);
    vm.assume(_anchorToken2CurrentPrice > 0);

    uint256 _minStable = uint256(_getMin(_anchorToken1CurrentPrice, _anchorToken2CurrentPrice));

    vm.assume(_virtualPrice < type(uint256).max / _minStable);

    uint256 _lpPrice = _virtualPrice * _minStable;

    vm.assume(_lpPrice > 1e18);

    vm.mockCall(
      address(_oracleRelayToken1),
      abi.encodeWithSelector(IOracleRelay.peekValue.selector),
      abi.encode(_anchorToken1CurrentPrice)
    );

    vm.mockCall(
      address(_oracleRelayToken2),
      abi.encodeWithSelector(IOracleRelay.peekValue.selector),
      abi.encode(_anchorToken2CurrentPrice)
    );

    vm.mockCall(
      address(_mockCurvePool), abi.encodeWithSelector(ICurvePool.get_virtual_price.selector), abi.encode(_virtualPrice)
    );

    uint256 _price = curveOracle.currentValue();
    assertEq(_price, _lpPrice / 1e18);
  }
}
