// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/// @title CurveAddressesProvider Interface
/// @notice Interface for interacting with CurveAddressesProvider
interface ICurveAddressesProvider {
  /// @notice Returns the CurveRegistry address
  function get_registry() external view returns (address _registry);
}

/// @title CurveRegistry Interface
/// @notice Interface for interacting with CurveRegistry
interface ICurveRegistry {
  /// @notice Returns the address of the LP given the pool address
  function get_lp_token(address _pool) external view returns (address _lpToken);
}
