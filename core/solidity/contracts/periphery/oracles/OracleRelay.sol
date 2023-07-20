// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';

abstract contract OracleRelay is IOracleRelay {
  /// @notice The WETH address
  address public constant wETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  /// @notice The type of oracle
  OracleType public oracleType;
  /// @notice The underlying asset
  address public underlying;

  constructor(OracleType _oracleType) {
    oracleType = _oracleType;
  }

  /// @notice set the underlying address
  function _setUnderlying(address _underlying) internal {
    underlying = _underlying;
  }

  /// @dev Most oracles don't require a state change for pricing, for those who do, override this function
  function currentValue() external virtual returns (uint256 _currentValue) {
    _currentValue = peekValue();
  }

  /// @notice The current reported value of the oracle
  /// @dev Implementation in _get()
  /// @return _price The current value
  function peekValue() public view virtual override returns (uint256 _price);
}
