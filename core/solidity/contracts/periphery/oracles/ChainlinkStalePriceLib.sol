// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import {AggregatorV2V3Interface} from '@chainlink/interfaces/AggregatorV2V3Interface.sol';

library ChainlinkStalePriceLib {
  // @notice Thrown when the price received is negative
  error Chainlink_NegativePrice();

  /// @notice Returns the current price from the aggregator
  function getCurrentPrice(AggregatorV2V3Interface _aggregator) internal view returns (uint256 _price) {
    (, int256 _answer,,,) = _aggregator.latestRoundData();
    if (_answer <= 0) revert Chainlink_NegativePrice();
    _price = uint256(_answer);
  }
}
