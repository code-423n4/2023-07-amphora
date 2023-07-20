// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IOracleRelay, OracleRelay} from '@contracts/periphery/oracles/OracleRelay.sol';
import {IStablePool} from '@interfaces/utils/ICurvePool.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {CurveRegistryUtils} from '@contracts/periphery/oracles/CurveRegistryUtils.sol';

/// @notice Oracle Relay for crv lps
contract StableCurveLpOracle is OracleRelay, CurveRegistryUtils {
  /// @notice Thrown when there are too few anchored oracles
  error StableCurveLpOracle_TooFewAnchoredOracles();

  /// @notice The pool of the crv lp token
  IStablePool public immutable CRV_POOL;
  /// @notice The anchor oracles of the underlying tokens
  IOracleRelay[] public anchoredUnderlyingTokens;

  constructor(address _crvPool, IOracleRelay[] memory _anchoredUnderlyingTokens) OracleRelay(OracleType.Chainlink) {
    if (_anchoredUnderlyingTokens.length < 2) revert StableCurveLpOracle_TooFewAnchoredOracles();
    CRV_POOL = IStablePool(_crvPool);
    for (uint256 _i; _i < _anchoredUnderlyingTokens.length;) {
      anchoredUnderlyingTokens.push(_anchoredUnderlyingTokens[_i]);

      unchecked {
        ++_i;
      }
    }

    _setUnderlying(_getLpAddress(_crvPool));
  }

  /// @notice The current reported value of the oracle
  /// @dev Implementation in _get()
  /// @return _price The current value
  function peekValue() public view virtual override returns (uint256 _price) {
    _price = _get();
  }

  /// @notice Calculates the lastest exchange rate
  function _get() internal view returns (uint256 _value) {
    // As the price should never be negative, the unchecked conversion is acceptable
    uint256 _minStable = anchoredUnderlyingTokens[0].peekValue();
    for (uint256 _i = 1; _i < anchoredUnderlyingTokens.length;) {
      _minStable = Math.min(_minStable, anchoredUnderlyingTokens[_i].peekValue());
      unchecked {
        ++_i;
      }
    }

    uint256 _lpPrice = _getVirtualPrice() * _minStable;

    _value = _lpPrice / 1e18;
  }

  /// @notice returns the updated virtual price for the pool
  function _getVirtualPrice() internal view virtual returns (uint256 _value) {
    _value = CRV_POOL.get_virtual_price();
  }
}
