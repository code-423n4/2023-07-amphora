// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface ICurvePool {
  function get_virtual_price() external view returns (uint256 _price);
  function gamma() external view returns (uint256 _gamma);
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  function A() external view returns (uint256 _A);
  function calc_token_amount(uint256[] memory _amounts, bool _deposit) external view returns (uint256 _amount);
}

interface IStablePool is ICurvePool {
  function lp_token() external view returns (IERC20 _lpToken);
  function remove_liquidity(
    uint256 _amount,
    uint256[2] memory _minAmounts
  ) external returns (uint256[2] memory _amounts);
  function add_liquidity(
    uint256[2] memory _amounts,
    uint256 _minMintAmount
  ) external payable returns (uint256 _lpAmount);
}

interface IV2Pool is ICurvePool {
  function token() external view returns (IERC20 _lpToken);
  function claim_admin_fees() external;
  function add_liquidity(
    uint256[2] memory _amounts,
    uint256 _minMintAmount,
    bool _useEth
  ) external payable returns (uint256 _lpAmount);
  function remove_liquidity(uint256 _amount, uint256[2] memory _minAmounts, bool _useEth) external;
}
