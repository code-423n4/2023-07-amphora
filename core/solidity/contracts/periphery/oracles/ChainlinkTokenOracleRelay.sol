// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IOracleRelay, OracleRelay} from '@contracts/periphery/oracles/OracleRelay.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';

/// @notice This oracle is for tokens that don't have a USD pair but do have a wETH/ETH pair
/// @dev Oracle that wraps a chainlink oracle
///      The oracle returns (chainlinkPrice) * mul / div
contract ChainlinkTokenOracleRelay is OracleRelay {
  /// @notice The chainlink aggregator
  ChainlinkOracleRelay public immutable AGGREGATOR;

  /// @notice The chainlink aggregator for the base token
  ChainlinkOracleRelay public immutable BASE_AGGREGATOR;

  /// @notice All values set at construction time
  /// @param  _feedAddress The address of chainlink feed
  /// @param  _baseFeedAddress The address of chainlink feed for the base token
  constructor(
    ChainlinkOracleRelay _feedAddress,
    ChainlinkOracleRelay _baseFeedAddress
  ) OracleRelay(OracleType.Chainlink) {
    AGGREGATOR = ChainlinkOracleRelay(_feedAddress);
    BASE_AGGREGATOR = ChainlinkOracleRelay(_baseFeedAddress);

    _setUnderlying(_feedAddress.underlying());
  }

  /// @notice returns the price with 18 decimals without any state changes
  /// @dev some oracles require a state change to get the exact current price.
  ///      This is updated when calling other state changing functions that query the price
  /// @return _price the current price
  function peekValue() public view override returns (uint256 _price) {
    _price = _get();
  }

  /// @notice Returns true if the price is stale
  /// @return _stale True if the price is stale
  function isStale() external view returns (bool _stale) {
    _stale = AGGREGATOR.isStale() || BASE_AGGREGATOR.isStale();
  }

  /// @notice The current reported value of the oracle
  /// @dev Implementation in getLastSecond
  /// @return _value The current value
  function _get() internal view returns (uint256 _value) {
    uint256 _aggregatorPrice = AGGREGATOR.peekValue();
    uint256 _baseAggregatorPrice = BASE_AGGREGATOR.peekValue();

    _value = (_aggregatorPrice * _baseAggregatorPrice) / 1e18;
  }
}
