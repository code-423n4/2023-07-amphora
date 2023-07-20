// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, IVault, console, TestConstants} from '@test/e2e/Common.sol';
import {IUSDA} from '@interfaces/core/IUSDA.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {AggregatorV2V3Interface} from '@chainlink/interfaces/AggregatorV2V3Interface.sol';

interface ITriCryptoPool {
  function calc_token_amount(uint256[3] memory _amounts, bool _deposit) external view returns (uint256 _amount);
}

contract E2ETriCryptoOracle is CommonE2EBase {
  uint256 public constant POINT_ONE_PERCENT = 0.001e18;

  IERC20 public usdt = IERC20(USDT_ADDRESS);
  IERC20 public triCryptoLpToken = IERC20(TRI_CRYPTO_LP_TOKEN);
  ITriCryptoPool public triCryptoPool = ITriCryptoPool(TRI_CRYPTO_2_POOL_ADDRESS);

  // This test get's the price of 1 LP token in a way that is fully manipulatable by a sandwich attack
  // Do not use it in production
  function testTriCryptoReturnsTheCorrectPrice() public {
    // Get the current value of the Tri crypto oracle
    uint256 _currentValue = triCryptoOracle.currentValue();

    // Get the total supply of triCryptoLpToken
    uint256 _totalSupply = triCryptoLpToken.totalSupply();
    // Get the balance of wbtc in the pool and transform to 18 decimals
    uint256 _wbtcBalanceE18 = wbtc.balanceOf(address(triCryptoPool)) * 10 ** 10;
    // Get the balance of usdt in the pool and transform to 18 decimals
    uint256 _usdtBalanceE18 = usdt.balanceOf(address(triCryptoPool)) * 10 ** 12;
    // Get the balance of weth in the pool
    uint256 _wethBalance = weth.balanceOf(address(triCryptoPool));

    // Get the price of the tokens from chainlink
    uint256 _wbtcPrice = uint256(AggregatorV2V3Interface(CHAINLINK_BTC_FEED_ADDRESS).latestAnswer()) * 10 ** 10;
    uint256 _usdtPrice = uint256(AggregatorV2V3Interface(CHAINLINK_USDT_FEED_ADDRESS).latestAnswer()) * 10 ** 10;
    uint256 _wethPrice = uint256(AggregatorV2V3Interface(CHAINLINK_ETH_FEED_ADDRESS).latestAnswer()) * 10 ** 10;

    // Calculate the usd value of the whole pool
    uint256 _poolValue = ((_wbtcBalanceE18 * _wbtcPrice) + (_usdtBalanceE18 * _usdtPrice) + (_wethBalance * _wethPrice));
    // Calculate the value of 1 lp token
    uint256 _lpValue = _poolValue / _totalSupply;
    assertApproxEqRel(_currentValue, _lpValue, POINT_ONE_PERCENT);
  }
}
