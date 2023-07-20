// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/// @title AnchoredViewRelay Interface
interface IAnchoredViewRelay {
  /// @notice returns the price with 18 decimals
  /// @return _currentValue the current price
  function currentValue() external view returns (uint256 _currentValue);
}
