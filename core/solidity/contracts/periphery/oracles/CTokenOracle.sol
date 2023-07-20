// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IOracleRelay, OracleRelay} from '@contracts/periphery/oracles/OracleRelay.sol';
import {ICToken} from '@interfaces/periphery/ICToken.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

/// @notice Oracle Relay for Compound cTokens
contract CTokenOracle is OracleRelay, Ownable {
  /// @notice The cETH address
  address public constant cETH_ADDRESS = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
  /// @notice The cToken contract
  ICToken public cToken;
  /// @notice The oracle of the underlying asset
  IOracleRelay public anchoredViewUnderlying;
  /// @notice The divisor to convert the underlying to the cToken
  uint256 public div;

  constructor(address _cToken, IOracleRelay _anchoredViewUnderlying) OracleRelay(OracleType.Chainlink) {
    cToken = ICToken(_cToken);
    anchoredViewUnderlying = _anchoredViewUnderlying;

    // If underlying is ETH, decimals are 18, if not, get the decimals from the underlying
    uint256 _underlyingDecimals = cETH_ADDRESS == _cToken ? 18 : IERC20Metadata(cToken.underlying()).decimals();

    // Save the divisor to convert the underlying to the cToken
    div = 10 ** (18 + _underlyingDecimals - cToken.decimals());

    // If the underlying is different, revert
    address _underlying = cETH_ADDRESS == _cToken ? wETH_ADDRESS : cToken.underlying();
    if (_underlying != anchoredViewUnderlying.underlying()) revert OracleRelay_DifferentUnderlyings();

    // Set the underlying address
    _setUnderlying(_cToken);
  }

  /// @notice returns the price with 18 decimals without any state changes
  /// @dev some oracles require a state change to get the exact current price.
  ///      This is updated when calling other state changing functions that query the price
  /// @return _price the current price
  function peekValue() public view override returns (uint256 _price) {
    _price = _get();
  }

  /// @notice The current reported value of the oracle
  /// @return _value The current value
  function _get() internal view returns (uint256 _value) {
    uint256 _exchangeRate = cToken.exchangeRateStored();
    uint256 _currentValue = anchoredViewUnderlying.peekValue();

    _value = (_currentValue * _exchangeRate) / div;
  }

  /// @notice Change the underlying oracle
  /// @param _anchoredViewUnderlying The new underlying oracle
  function changeAnchoredView(address _anchoredViewUnderlying) external onlyOwner {
    anchoredViewUnderlying = IOracleRelay(_anchoredViewUnderlying);
  }
}
