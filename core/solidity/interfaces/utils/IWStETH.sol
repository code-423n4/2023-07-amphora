// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @title The wstETH interface
 */
interface IWStETH is IERC20 {
  /**
   * @notice Get amount of stETH for one wstETH
   * @return _stEth Amount of stETH for 1 wstETH
   */
  function stEthPerToken() external view returns (uint256 _stEth);
}
