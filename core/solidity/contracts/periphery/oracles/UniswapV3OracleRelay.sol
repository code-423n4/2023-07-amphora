// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

import {OracleRelay} from '@contracts/periphery/oracles/OracleRelay.sol';
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {OracleLibrary} from '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

/// @notice Oracle that wraps a univ3 pool
/// @dev The oracle returns (univ3) * mul / div
///      if QUOTE_TOKEN_IS_TOKEN0 == true, then the reciprocal is returned
contract UniswapV3OracleRelay is OracleRelay {
  /// @notice Thrown when the tick time diff fails
  error UniswapV3OracleRelay_TickTimeDiffTooLarge();

  /// @notice Returns True if the quote token is token0 in the pool
  bool public immutable QUOTE_TOKEN_IS_TOKEN0;

  /// @notice The pool
  IUniswapV3Pool public immutable POOL;

  /// @notice The lookback for the oracle
  uint32 public immutable LOOKBACK;

  /// @notice The base token decimals
  uint8 public immutable BASE_TOKEN_DECIMALS;

  /// @notice The quote token decimals
  uint8 public immutable QUOTE_TOKEN_DECIMALS;

  /// @notice The base token
  address public immutable BASE_TOKEN;

  /// @notice The quote token
  address public immutable QUOTE_TOKEN;

  /// @notice All values set at construction time
  /// @param _lookback How many seconds to twap for
  /// @param  _poolAddress The address of chainlink feed
  /// @param _quoteTokenIsToken0 The marker for which token to use as quote/base in calculation
  constructor(uint32 _lookback, address _poolAddress, bool _quoteTokenIsToken0) OracleRelay(OracleType.Uniswap) {
    LOOKBACK = _lookback;
    QUOTE_TOKEN_IS_TOKEN0 = _quoteTokenIsToken0;
    POOL = IUniswapV3Pool(_poolAddress);

    address _token0 = POOL.token0();
    address _token1 = POOL.token1();

    (BASE_TOKEN, QUOTE_TOKEN) = QUOTE_TOKEN_IS_TOKEN0 ? (_token1, _token0) : (_token0, _token1);
    BASE_TOKEN_DECIMALS = IERC20Metadata(BASE_TOKEN).decimals();
    QUOTE_TOKEN_DECIMALS = IERC20Metadata(QUOTE_TOKEN).decimals();

    _setUnderlying(BASE_TOKEN);
  }

  /// @notice returns the price with 18 decimals without any state changes
  /// @dev some oracles require a state change to get the exact current price.
  ///      This is updated when calling other state changing functions that query the price
  /// @return _price the current price
  function peekValue() public view virtual override returns (uint256 _price) {
    _price = _get();
  }

  /// @notice Returns the current reported value of the oracle
  /// @dev Implementation in _getLastSecond
  /// @return _value The current value
  function _get() internal view returns (uint256 _value) {
    _value = _getLastSeconds(LOOKBACK);
  }

  /// @notice Returns last second value of the oracle
  /// @param _seconds How many seconds to twap for
  /// @return _price The last second value of the oracle
  function _getLastSeconds(uint32 _seconds) internal view returns (uint256 _price) {
    uint256 _uniswapPrice = _getPriceFromUniswap(_seconds, uint128(10 ** BASE_TOKEN_DECIMALS));
    _price = _toBase18(_uniswapPrice, QUOTE_TOKEN_DECIMALS);
  }

  function _getPriceFromUniswap(uint32 _seconds, uint128 _amount) internal view virtual returns (uint256 _price) {
    (int24 _arithmeticMeanTick,) = OracleLibrary.consult(address(POOL), _seconds);
    _price = OracleLibrary.getQuoteAtTick(_arithmeticMeanTick, _amount, BASE_TOKEN, QUOTE_TOKEN);
  }

  function _toBase18(uint256 _amount, uint8 _decimals) internal pure returns (uint256 _e18Amount) {
    _e18Amount = (_decimals > 18) ? _amount / (10 ** (_decimals - 18)) : _amount * (10 ** (18 - _decimals));
  }
}
