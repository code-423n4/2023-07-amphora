// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IOracleRelay, OracleRelay} from '@contracts/periphery/oracles/OracleRelay.sol';
import {StableCurveLpOracle} from '@contracts/periphery/oracles/StableCurveLpOracle.sol';

/// @notice Oracle Relay for curve lps safe for usage with pools that hold ETH
contract EthSafeStableCurveOracle is StableCurveLpOracle {
  uint256 public virtualPrice;

  constructor(
    address _crvPool,
    IOracleRelay[] memory _anchoredUnderlyingTokens
  ) StableCurveLpOracle(_crvPool, _anchoredUnderlyingTokens) {
    _updateVirtualPrice();
  }

  /// @notice returns the price with 18 decimals without any state changes
  /// @dev some oracles require a state change to get the exact current price.
  ///      This is updated when calling other state changing functions that query the price
  /// @return _price the current price
  function peekValue() public view override returns (uint256 _price) {
    _price = _get();
  }

  /// @notice returns the price with 18 decimals
  /// @return _currentValue the current price
  function currentValue() external override returns (uint256 _currentValue) {
    _updateVirtualPrice();
    _currentValue = _get();
  }

  /// @notice updates the virtual price for the pool
  /// @dev this function calls remove_liquidity with 0 as the amount to lock the curve pool
  ///      and prevent reentrancy attacks
  function _updateVirtualPrice() internal {
    uint256 _virtualPrice = CRV_POOL.get_virtual_price();

    // We remove 0 liquidity to check the curve pool lock and avoid any manipulation
    uint256[2] memory _amounts;
    CRV_POOL.remove_liquidity(0, _amounts);

    virtualPrice = _virtualPrice;
  }

  /// @notice returns the virtual price for the pool
  /// @return _value the virtual price
  function _getVirtualPrice() internal view override returns (uint256 _value) {
    _value = virtualPrice;
  }

  // We need this to be able to get the callback from curve after calling remove_liquidity
  // solhint-disable-next-line payable-fallback
  fallback() external {}
}
