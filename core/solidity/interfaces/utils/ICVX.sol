// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @title The interface for the CVX token
 */
interface ICVX is IERC20 {
  function totalCliffs() external view returns (uint256 _totalCliffs);
  function reductionPerCliff() external view returns (uint256 _reduction);
  function maxSupply() external view returns (uint256 _maxSupply);
}
