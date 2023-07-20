// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IChainlinkOracleRelay {
  /// @notice Returns True if the oracle is stale
  function isStale() external view returns (bool _stale);
}
