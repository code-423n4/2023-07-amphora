// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus} from 'solidity-utils/test/DSTestPlus.sol';
import {AnchoredViewRelay} from '@contracts/periphery/oracles/AnchoredViewRelay.sol';

import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {IChainlinkOracleRelay} from '@interfaces/periphery/IChainlinkOracleRelay.sol';

abstract contract Base is DSTestPlus {
  AnchoredViewRelay public anchoredViewRelay;
  IOracleRelay internal _mockMainRelay = IOracleRelay(mockContract(newAddress(), 'mockMainRelay'));
  IOracleRelay internal _mockAnchorRelay = IOracleRelay(mockContract(newAddress(), 'mockAnchorRelay'));

  address internal _mockToken = mockContract(newAddress(), 'mockToken');

  uint256 public widthNumerator = 10;
  uint256 public widthDenominator = 100;

  uint256 public staleWidthNumerator = 5;
  uint256 public staleWidthDenominator = 100;

  IOracleRelay.OracleType public oracleType = IOracleRelay.OracleType(2); // 2 == Price

  function setUp() public virtual {
    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IOracleRelay.oracleType.selector), abi.encode(oracleType)
    );

    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IOracleRelay.underlying.selector), abi.encode(_mockToken)
    );
    vm.mockCall(
      address(_mockAnchorRelay), abi.encodeWithSelector(IOracleRelay.underlying.selector), abi.encode(_mockToken)
    );

    // Deploy contract
    anchoredViewRelay =
    new AnchoredViewRelay(address(_mockAnchorRelay), address(_mockMainRelay), widthNumerator, widthDenominator, staleWidthNumerator, staleWidthDenominator);
  }
}

contract UnitTestAnchoredViewRelayUnderlyingIsSet is Base {
  function testUnderlyingIsSet() public {
    assertEq(address(_mockToken), anchoredViewRelay.underlying());
  }
}

contract UnitTestAnchoredViewRelayRevertWhenDifferentUnderlying is Base {
  function testRevertWhenDifferentUnderlying() public {
    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IOracleRelay.underlying.selector), abi.encode(newAddress())
    );
    vm.mockCall(
      address(_mockAnchorRelay), abi.encodeWithSelector(IOracleRelay.underlying.selector), abi.encode(newAddress())
    );

    vm.expectRevert(IOracleRelay.OracleRelay_DifferentUnderlyings.selector);
    new AnchoredViewRelay(address(_mockAnchorRelay), address(_mockMainRelay), widthNumerator, widthDenominator, staleWidthNumerator, staleWidthDenominator);
  }
}

contract UnitTestAnchoredViewRelayOracleType is Base {
  function testOracleType() public {
    assertEq(uint256(oracleType), uint256(anchoredViewRelay.oracleType()));
  }
}

contract UnitTestAnchoredViewRelayCurrentValue is Base {
  function testCurrentValueRevertWithInvalidOracleValue() public {
    vm.mockCall(address(_mockMainRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(0));

    vm.expectRevert('invalid oracle value');
    anchoredViewRelay.currentValue();
  }

  function testCurrentValueRevertWithInvalidAnchorValue() public {
    vm.mockCall(address(_mockMainRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1));
    vm.mockCall(address(_mockAnchorRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(0));

    vm.expectRevert('invalid anchor value');
    anchoredViewRelay.currentValue();
  }

  function testCurrentValueRevertWithAnchorTooLow(uint256 _anchorPrice) public {
    vm.assume(_anchorPrice != 0);
    vm.assume(_anchorPrice < type(uint256).max / widthNumerator);
    vm.assume(widthNumerator * _anchorPrice >= widthDenominator);

    uint256 _mainPrice = 100 ether;
    uint256 _buffer = (widthNumerator * _anchorPrice) / widthDenominator;

    vm.assume(_anchorPrice + _buffer < _mainPrice);

    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_mainPrice)
    );
    vm.mockCall(
      address(_mockAnchorRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_anchorPrice)
    );
    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IChainlinkOracleRelay.isStale.selector), abi.encode(false)
    );

    vm.expectRevert('anchor too low');
    anchoredViewRelay.currentValue();
  }

  function testCurrentValueRevertWithAnchorTooHigh(uint256 _anchorPrice) public {
    vm.assume(_anchorPrice != 0);
    vm.assume(_anchorPrice < type(uint256).max / widthNumerator);
    vm.assume(widthNumerator * _anchorPrice >= widthDenominator);

    uint256 _mainPrice = 100 ether;
    uint256 _buffer = (widthNumerator * _anchorPrice) / widthDenominator;

    vm.assume(_anchorPrice - _buffer > _mainPrice);

    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_mainPrice)
    );
    vm.mockCall(
      address(_mockAnchorRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_anchorPrice)
    );
    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IChainlinkOracleRelay.isStale.selector), abi.encode(false)
    );

    vm.expectRevert('anchor too high');
    anchoredViewRelay.currentValue();
  }

  function testCurrentValueRevertWithAnchorTooLowAndStalePrice(uint256 _anchorPrice) public {
    vm.assume(_anchorPrice != 0);
    vm.assume(_anchorPrice < type(uint256).max / staleWidthNumerator);
    vm.assume(staleWidthNumerator * _anchorPrice >= staleWidthDenominator);

    uint256 _mainPrice = 100 ether;
    uint256 _buffer = (staleWidthNumerator * _anchorPrice) / staleWidthDenominator;

    vm.assume(_anchorPrice + _buffer < _mainPrice);

    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_mainPrice)
    );
    vm.mockCall(
      address(_mockAnchorRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_anchorPrice)
    );
    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IChainlinkOracleRelay.isStale.selector), abi.encode(true)
    );

    vm.expectRevert('anchor too low');
    anchoredViewRelay.currentValue();
  }

  function testCurrentValueRevertWithAnchorTooHighAndStalePrice(uint256 _anchorPrice) public {
    vm.assume(_anchorPrice != 0);
    vm.assume(_anchorPrice < type(uint256).max / staleWidthNumerator);
    vm.assume(staleWidthNumerator * _anchorPrice >= staleWidthDenominator);

    uint256 _mainPrice = 100 ether;
    uint256 _buffer = (staleWidthNumerator * _anchorPrice) / staleWidthDenominator;

    vm.assume(_anchorPrice - _buffer > _mainPrice);

    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_mainPrice)
    );
    vm.mockCall(
      address(_mockAnchorRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_anchorPrice)
    );
    vm.mockCall(
      address(_mockMainRelay), abi.encodeWithSelector(IChainlinkOracleRelay.isStale.selector), abi.encode(true)
    );

    vm.expectRevert('anchor too high');
    anchoredViewRelay.currentValue();
  }
}
