// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IVirtualBalanceRewardPool} from '@interfaces/utils/IVirtualBalanceRewardPool.sol';

interface IBaseRewardPool {
  function stake(uint256 _amount) external returns (bool _staked);
  function stakeFor(address _for, uint256 _amount) external returns (bool _staked);
  function withdraw(uint256 _amount, bool _claim) external returns (bool _success);
  function withdrawAndUnwrap(uint256 _amount, bool _claim) external returns (bool _success);
  function getReward(address _account, bool _claimExtras) external returns (bool _success);
  function rewardToken() external view returns (IERC20 _rewardToken);
  function earned(address _ad) external view returns (uint256 _reward);
  function extraRewardsLength() external view returns (uint256 _extraRewardsLength);
  function extraRewards(uint256 _position) external view returns (IVirtualBalanceRewardPool _virtualReward);
  function queueNewRewards(uint256 _rewards) external returns (bool _success);
}
