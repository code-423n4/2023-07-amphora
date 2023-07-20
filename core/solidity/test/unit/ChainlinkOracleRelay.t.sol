// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus, console} from 'solidity-utils/test/DSTestPlus.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';

import {AggregatorV3Interface} from '@chainlink/interfaces/AggregatorV3Interface.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {ChainlinkStalePriceLib} from '@contracts/periphery/oracles/ChainlinkStalePriceLib.sol';

abstract contract Base is DSTestPlus {
  ChainlinkOracleRelay public chainlinkOracleRelay;
  AggregatorV3Interface internal _mockAggregator = AggregatorV3Interface(mockContract(newAddress(), 'mockAggregator'));
  address internal _mockWETH = mockContract(newAddress(), 'mockWETH');
  IOracleRelay internal _mockEthPriceFeed;

  uint256 public mul = 10_000_000_000;
  uint256 public div = 1;
  uint256 public stalePeriod = 1 hours;

  IOracleRelay.OracleType public oracleType = IOracleRelay.OracleType(0); // 0 == Chainlink

  function setUp() public virtual {
    // Deploy contract
    chainlinkOracleRelay = new ChainlinkOracleRelay(_mockWETH, address(_mockAggregator), mul, div, stalePeriod);
    vm.warp(block.timestamp + stalePeriod + 1);
  }
}

contract UnitTestChainlinkOracleRelayUnderlyingIsSet is Base {
  function testUnderlyingIsSet() public {
    assertEq(address(_mockWETH), chainlinkOracleRelay.underlying());
  }
}

contract UnitTestChainlinkOracleRelayOracleType is Base {
  function testOracleType() public {
    assertEq(uint256(oracleType), uint256(chainlinkOracleRelay.oracleType()));
  }
}

contract UnitTestChainlinkOracleRelayCurrentValue is Base {
  function testChainlinkOracleRelayRevertWithPriceLessThanZero(int256 _latestAnswer) public {
    vm.assume(_latestAnswer < 0);

    vm.mockCall(
      address(_mockAggregator),
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, _latestAnswer, 0, block.timestamp, 0)
    );

    vm.expectRevert(ChainlinkStalePriceLib.Chainlink_NegativePrice.selector);
    chainlinkOracleRelay.currentValue();
  }

  function testChainlinkOracleRelayWithPriceStale(int256 _latestAnswer) public {
    vm.assume(_latestAnswer > 0);
    vm.assume(uint256(_latestAnswer) < type(uint256).max / mul);

    vm.mockCall(
      address(_mockAggregator),
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, _latestAnswer, 0, block.timestamp - stalePeriod - 1, 0)
    );

    uint256 _response = chainlinkOracleRelay.currentValue();
    assertEq(_response, (uint256(_latestAnswer) * mul) / div);
  }

  function testChainlinkOracleRelay(int256 _latestAnswer) public {
    vm.assume(_latestAnswer > 0);

    vm.assume(uint256(_latestAnswer) < type(uint256).max / mul);
    vm.mockCall(
      address(_mockAggregator),
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, _latestAnswer, 0, block.timestamp, 0)
    );

    uint256 _response = chainlinkOracleRelay.currentValue();
    assertEq(_response, (uint256(_latestAnswer) * mul) / div);
  }
}

contract UnitChainlinkOracleRelaySetStaleDelay is Base {
  function testChainlinkOracleRelaySetStaleDelay(uint256 _stalePeriod) public {
    vm.assume(_stalePeriod > 0);
    chainlinkOracleRelay.setStalePriceDelay(_stalePeriod);
    assertEq(chainlinkOracleRelay.stalePriceDelay(), _stalePeriod);
  }

  function testChainlinkOracleRelaySetStaleDelayRevertWithZero() public {
    vm.expectRevert(ChainlinkOracleRelay.ChainlinkOracle_ZeroAmount.selector);
    chainlinkOracleRelay.setStalePriceDelay(0);
  }
}

contract UnitChainlinkOracleRelayIsStale is Base {
  function testIsStale() public {
    vm.mockCall(
      address(_mockAggregator),
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, 0, 0, block.timestamp - stalePeriod - 1, 0)
    );
    assertTrue(chainlinkOracleRelay.isStale());
  }

  function testIsNotStale() public {
    vm.mockCall(
      address(_mockAggregator),
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, 0, 0, block.timestamp - 1, 0)
    );
    assertFalse(chainlinkOracleRelay.isStale());
  }
}
