// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IOracleRelay, OracleRelay} from '@contracts/periphery/oracles/OracleRelay.sol';
import {IV2Pool} from '@interfaces/utils/ICurvePool.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {CurveRegistryUtils} from '@contracts/periphery/oracles/CurveRegistryUtils.sol';

/// @notice Oracle Relay for the cbETH/ETH pool
contract CbEthEthOracle is OracleRelay, CurveRegistryUtils {
  /// @notice The Curve pool
  IV2Pool public immutable CB_ETH_POOL;

  /// @notice The oracle relay for the cbETH/ETH price
  IOracleRelay public immutable CB_ETH_ORACLE_RELAY;

  /// @notice The oracle relay for the ETH/USD price
  IOracleRelay public immutable ETH_ORACLE_RELAY;

  /// @notice The stored virtual price for the pool
  uint256 public virtualPrice;

  constructor(
    address _cbETHPool,
    IOracleRelay _cbEthOracleRelay,
    IOracleRelay _ethOracleRelay
  ) OracleRelay(OracleType.Chainlink) {
    CB_ETH_POOL = IV2Pool(_cbETHPool);

    CB_ETH_ORACLE_RELAY = _cbEthOracleRelay;
    ETH_ORACLE_RELAY = _ethOracleRelay;

    _setUnderlying(_getLpAddress(_cbETHPool));
  }

  /// @notice The current reported value of the oracle
  /// @dev Implementation in _get
  /// @return _value The current value
  function peekValue() public view override returns (uint256 _value) {
    _value = _get();
  }

  /// @notice returns the price with 18 decimals
  /// @return _currentValue the current price
  function currentValue() external override returns (uint256 _currentValue) {
    _updateVirtualPrice();
    _currentValue = _get();
  }

  /// @notice Calculated the price of 1 LP token
  /// @dev This function comes from the implementation in vyper
  /// @return _maxPrice The current value
  function _get() internal view returns (uint256 _maxPrice) {
    uint256 _vp = virtualPrice;

    // Get the prices from chainlink and add 10 decimals
    uint256 _cbEthPrice = CB_ETH_ORACLE_RELAY.peekValue();
    uint256 _ethPrice = ETH_ORACLE_RELAY.peekValue();

    uint256 _basePrices = (_cbEthPrice * _ethPrice);

    _maxPrice = (2 * _vp * FixedPointMathLib.sqrt(_basePrices)) / 1 ether;
    // removed discount since the % is so small that it doesn't make a difference
  }

  /// @notice updates the virtual price for the pool
  /// @dev this function calls claim_admin_fees to lock the curve pool
  ///      and prevent reentrancy attacks
  function _updateVirtualPrice() internal {
    uint256 _virtualPrice = CB_ETH_POOL.get_virtual_price();

    // We remove claim admin fees on the curve pool locked to avoid any manipulation
    CB_ETH_POOL.claim_admin_fees();

    virtualPrice = _virtualPrice;
  }
}
