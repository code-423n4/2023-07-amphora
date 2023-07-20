// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, console, IERC20} from '@test/e2e/Common.sol';
import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

contract E2EUniswapV3OracleRelay is CommonE2EBase {
  function testE2EPeekValueUSDCWETH() public {
    uint256 _price = uniswapRelayEthUsdc.peekValue();
    assertEq(_price, 1_811_349_739_000_000_000_000); // Price searched in block 17_300_000
  }

  function testE2EPeekValueWBTCUSDC() public {
    uint256 _price = uniswapRelayWbtcUsdc.peekValue();
    assertEq(_price, 26_902_929_140_000_000_000_000); // Price searched in block 17_300_000
  }

  function testE2EPeekValueDydxWETH() public {
    uint256 _price = uniswapRelayDydxWeth.peekValue();
    assertEq(_price, 2_152_573_947_694_835_464); // Price searched in block 17_300_000
  }

  function testE2EPeekValueSnx() public {
    uint256 _price = anchoredViewSnx.peekValue();
    assertEq(_price, 2_381_000_000_000_000_000); // Price searched in block 17_300_000
  }
}
