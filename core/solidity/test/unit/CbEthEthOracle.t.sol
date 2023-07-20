// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CbEthEthOracle} from '@contracts/periphery/oracles/CbEthEthOracle.sol';
import {ICurveAddressesProvider, ICurveRegistry} from '@interfaces/periphery/ICurveAddressesProvider.sol';
import {ICurvePool, IV2Pool} from '@interfaces/utils/ICurvePool.sol';
import {DSTestPlus} from 'solidity-utils/test/DSTestPlus.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';

abstract contract Base is DSTestPlus {
  uint256 public constant POINT_ONE_PERCENT = 0.001e18;

  ICurvePool public curvePool = ICurvePool(mockContract(newAddress(), 'curvePool'));
  IOracleRelay public cbEthFeed = IOracleRelay(mockContract(newAddress(), 'cbEthFeed'));
  IOracleRelay public ethFeed = IOracleRelay(mockContract(newAddress(), 'ethFeed'));

  address internal _lpToken = newAddress();
  ICurveAddressesProvider internal _curveAddressesProvider =
    ICurveAddressesProvider(mockContract(address(0x0000000022D53366457F9d5E68Ec105046FC4383), 'curveAddressesProvider'));
  ICurveRegistry internal _curveRegistry = ICurveRegistry(mockContract(address(newAddress()), 'curveRegistry'));

  CbEthEthOracle public cbEthEthOracle;

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

    cbEthEthOracle = new CbEthEthOracle(address(curvePool), cbEthFeed, ethFeed);
  }
}

contract UnitUnderlyingIsSet is Base {
  function testUnderlyingIsSet() public {
    assertEq(cbEthEthOracle.underlying(), _lpToken);
  }
}

contract UnitValue is Base {
  function testPeekValue(uint32 _cbEthPrice, uint32 _ethPrice) public {
    vm.assume(_cbEthPrice > 0.1e8);
    vm.assume(_ethPrice > 0.1e8);
    uint256 _vp = 1.1e18;

    // trigger and save virtual price
    vm.mockCall(address(curvePool), abi.encodeWithSelector(ICurvePool.get_virtual_price.selector), abi.encode(_vp));
    vm.mockCall(address(curvePool), abi.encodeWithSelector(IV2Pool.claim_admin_fees.selector), abi.encode(0));
    // mockCall to feed latestAnswers
    vm.mockCall(address(ethFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_ethPrice));
    vm.mockCall(address(cbEthFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_cbEthPrice));
    cbEthEthOracle.currentValue();

    uint256 _basePrices = (uint256(_cbEthPrice) * _ethPrice);

    uint256 _maxPrice = (2 * _vp * FixedPointMathLib.sqrt(_basePrices)) / 1 ether;

    assertEq(cbEthEthOracle.peekValue(), _maxPrice);
  }

  function testCurrentValue(uint32 _cbEthPrice, uint32 _ethPrice) public {
    vm.assume(_cbEthPrice > 0.1e8);
    vm.assume(_ethPrice > 0.1e8);
    uint256 _vp = 1.1e18;

    vm.mockCall(address(curvePool), abi.encodeWithSelector(ICurvePool.get_virtual_price.selector), abi.encode(_vp));
    vm.mockCall(address(curvePool), abi.encodeWithSelector(IV2Pool.claim_admin_fees.selector), abi.encode(0));

    // mockCall to feed latestAnswers
    vm.mockCall(address(ethFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_ethPrice));
    vm.mockCall(address(cbEthFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_cbEthPrice));

    uint256 _basePrices = (uint256(_cbEthPrice) * _ethPrice);

    uint256 _maxPrice = (2 * _vp * FixedPointMathLib.sqrt(_basePrices)) / 1 ether;

    vm.expectCall(address(curvePool), abi.encodeWithSelector(IV2Pool.claim_admin_fees.selector));
    assertEq(cbEthEthOracle.currentValue(), _maxPrice);
  }
}

contract UnitCbEthEthOracleExternalCalls is Base {
  uint256 internal _vp = 1 ether;
  uint256 internal _ethPrice = 2000 ether;
  uint256 internal _cbEthPrice = 2010 ether;

  function setUp() public virtual override {
    super.setUp();

    // mockCall to get_virtual_price
    vm.mockCall(address(curvePool), abi.encodeWithSelector(ICurvePool.get_virtual_price.selector), abi.encode(_vp));

    // mockCall to feed latestAnswers
    vm.mockCall(address(ethFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_ethPrice));

    vm.mockCall(address(cbEthFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_cbEthPrice));
  }

  function testCallsPeekValueOnEthFeed() public {
    vm.expectCall(address(ethFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector));
    cbEthEthOracle.currentValue();
  }

  function testCallsPeekValueOnCbEthFeed() public {
    vm.expectCall(address(cbEthFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector));
    cbEthEthOracle.currentValue();
  }
}
