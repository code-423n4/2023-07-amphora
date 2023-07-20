// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus, console} from 'solidity-utils/test/DSTestPlus.sol';
import {ChainlinkTokenOracleRelay} from '@contracts/periphery/oracles/ChainlinkTokenOracleRelay.sol';

import {AggregatorInterface} from '@chainlink/interfaces/AggregatorInterface.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';

abstract contract Base is DSTestPlus {
  ChainlinkTokenOracleRelay public chainlinkTokenOracleRelay;

  address internal _mockWETH = mockContract(newAddress(), 'mockWETH');

  ChainlinkOracleRelay internal _mockAggregator = ChainlinkOracleRelay(mockContract(newAddress(), 'mockAggregator'));
  ChainlinkOracleRelay internal _mockBaseAggregator =
    ChainlinkOracleRelay(mockContract(newAddress(), 'mockBaseAggregator'));

  IOracleRelay.OracleType public oracleType = IOracleRelay.OracleType(0); // 0 == Chainlink

  function setUp() public virtual {
    vm.mockCall(
      address(_mockAggregator), abi.encodeWithSelector(IOracleRelay.underlying.selector), abi.encode(address(_mockWETH))
    );
    // Deploy contract
    chainlinkTokenOracleRelay = new ChainlinkTokenOracleRelay(_mockAggregator, _mockBaseAggregator);
  }
}

contract UnitTestChainlinkTokenOracleRelayUnderlyingIsSet is Base {
  function testUnderlyingIsSet() public {
    assertEq(address(_mockWETH), chainlinkTokenOracleRelay.underlying());
  }
}

contract UnitTestChainlinkTokenOracleRelayOracleType is Base {
  function testOracleType() public {
    assertEq(uint256(oracleType), uint256(chainlinkTokenOracleRelay.oracleType()));
  }
}

contract UnitTestChainlinkTokenOracleRelayCurrentValue is Base {
  function testChainlinkTokenOracleRelay(uint256 _latestAnswer, uint256 _baseLatestAnswer) public {
    vm.assume(_latestAnswer > 0);
    vm.assume(_baseLatestAnswer > 0);
    vm.assume(uint256(_latestAnswer) < type(uint256).max / _baseLatestAnswer);

    vm.mockCall(
      address(_mockAggregator),
      abi.encodeWithSelector(ChainlinkOracleRelay.peekValue.selector),
      abi.encode(_latestAnswer)
    );

    vm.mockCall(
      address(_mockBaseAggregator),
      abi.encodeWithSelector(ChainlinkOracleRelay.peekValue.selector),
      abi.encode(_baseLatestAnswer)
    );

    uint256 _response = chainlinkTokenOracleRelay.currentValue();
    assertEq(_response, (_latestAnswer * _baseLatestAnswer) / 1e18);
  }
}

contract UnitTestChainlinkTokenOracleRelayIsStale is Base {
  function testChainlinkTokenOracleRelayIsNotStaleIfNonAreStale() public {
    vm.mockCall(
      address(_mockAggregator), abi.encodeWithSelector(ChainlinkOracleRelay.isStale.selector), abi.encode(false)
    );

    vm.mockCall(
      address(_mockBaseAggregator), abi.encodeWithSelector(ChainlinkOracleRelay.isStale.selector), abi.encode(false)
    );

    bool _response = chainlinkTokenOracleRelay.isStale();
    assertFalse(_response);
  }

  function testChainlinkTokenOracleRelayIsStaleIfFeedIsStale() public {
    vm.mockCall(
      address(_mockAggregator), abi.encodeWithSelector(ChainlinkOracleRelay.isStale.selector), abi.encode(true)
    );

    vm.mockCall(
      address(_mockBaseAggregator), abi.encodeWithSelector(ChainlinkOracleRelay.isStale.selector), abi.encode(false)
    );

    bool _response = chainlinkTokenOracleRelay.isStale();
    assertTrue(_response);
  }

  function testChainlinkTokenOracleRelayIsStaleIfBaseIsStale() public {
    vm.mockCall(
      address(_mockAggregator), abi.encodeWithSelector(ChainlinkOracleRelay.isStale.selector), abi.encode(false)
    );

    vm.mockCall(
      address(_mockBaseAggregator), abi.encodeWithSelector(ChainlinkOracleRelay.isStale.selector), abi.encode(true)
    );

    bool _response = chainlinkTokenOracleRelay.isStale();
    assertTrue(_response);
  }

  function testChainlinkTokenOracleRelayIsStaleIfBothAreStale() public {
    vm.mockCall(
      address(_mockAggregator), abi.encodeWithSelector(ChainlinkOracleRelay.isStale.selector), abi.encode(true)
    );

    vm.mockCall(
      address(_mockBaseAggregator), abi.encodeWithSelector(ChainlinkOracleRelay.isStale.selector), abi.encode(true)
    );

    bool _response = chainlinkTokenOracleRelay.isStale();
    assertTrue(_response);
  }
}
