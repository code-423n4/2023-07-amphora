// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ICToken {
  /// @notice The exchange rate stored in the contract
  function exchangeRateStored() external view returns (uint256 _exchangeRate);

  /// @notice The amount of decimals of the cToken
  function decimals() external view returns (uint8 _decimals);

  /// @notice The underlying asset for the cToken
  function underlying() external view returns (address _underlying);
}
