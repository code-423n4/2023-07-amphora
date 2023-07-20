// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';

/// @notice Oracle that wraps a univ3 pool
/// @dev This oracle is for tokens that do not have a stable Uniswap V3 pair against sUSD
///      If QUOTE_TOKEN_IS_TOKEN0 == true, then the reciprocal is returned
///      quote_token refers to the token we are comparing to, so for an Aave price in ETH, Aave is the target and Eth is the quote
contract UniswapV3TokenOracleRelay is UniswapV3OracleRelay {
  /// @notice The oracle for eth/usdc
  UniswapV3OracleRelay public immutable ETH_ORACLE;

  /// @notice All values set at construction time
  /// @param _ethOracle The uniswap oracle for ethusdc
  /// @param _lookback How many seconds to twap for
  /// @param _poolAddress The address of uniswap feed
  /// @param _quoteTokenIsToken0 Boolean, true if eth is token 0, or false if eth is token 1
  constructor(
    UniswapV3OracleRelay _ethOracle,
    uint32 _lookback,
    address _poolAddress,
    bool _quoteTokenIsToken0
  ) UniswapV3OracleRelay(_lookback, _poolAddress, _quoteTokenIsToken0) {
    ETH_ORACLE = _ethOracle;
  }

  /// @notice The current reported value of the oracle
  /// @dev Implementation in _get
  /// @return _price The current value
  function peekValue() public view virtual override returns (uint256 _price) {
    uint256 _priceInEth = _getLastSeconds(LOOKBACK);

    //get price of eth to convert _priceInEth to USD terms
    uint256 _ethPrice = ETH_ORACLE.peekValue();

    _price = (_ethPrice * _priceInEth) / 1e18;
  }
}
