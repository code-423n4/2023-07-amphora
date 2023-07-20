// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IBaseRewardPool} from '@interfaces/utils/IBaseRewardPool.sol';
import {IBooster} from '@interfaces/utils/IBooster.sol';
import {IVirtualBalanceRewardPool} from '@interfaces/utils/IVirtualBalanceRewardPool.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

struct Rewards {
  uint256 lastClaimTime;
  uint256 rewardsToPay;
}

contract FakeVirtualRewardsPool is IVirtualBalanceRewardPool {
  IBaseRewardPool public baseRewardPool;
  IERC20 public rewardToken;
  mapping(address => uint256) public balances;
  mapping(address => Rewards) public rewards;
  uint256 public rewardsPerSecondPerToken; //1e18 = 1 token

  constructor(IBaseRewardPool _baseRewardPool, IERC20 _rewardToken, uint256 _rewardsPerSecondPerToken) {
    baseRewardPool = _baseRewardPool;
    rewardToken = _rewardToken;
    rewardsPerSecondPerToken = _rewardsPerSecondPerToken;
  }

  function earned(address _ad) external view override returns (uint256 _reward) {
    _reward = rewards[_ad].rewardsToPay + _newAccumulatedRewards(_ad);
  }

  function getReward() external override {
    uint256 _earned = rewards[msg.sender].rewardsToPay + _newAccumulatedRewards(msg.sender);
    rewardToken.transfer(msg.sender, _earned);
    rewards[msg.sender].lastClaimTime = block.timestamp;
    rewards[msg.sender].rewardsToPay = 0;
  }

  function queueNewRewards(uint256 _rewards) external override {}

  function stake(address _user, uint256 _amount) external {
    if (msg.sender != address(baseRewardPool)) revert('Only base reward pool');
    rewards[_user].rewardsToPay = rewards[_user].rewardsToPay + _newAccumulatedRewards(_user);
    rewards[_user].lastClaimTime = block.timestamp;
    balances[_user] += _amount;
  }

  function unstake(address _user, uint256 _amount) external {
    if (msg.sender != address(baseRewardPool)) revert('Only base reward pool');
    rewards[_user].rewardsToPay = rewards[_user].rewardsToPay + _newAccumulatedRewards(_user);
    rewards[_user].lastClaimTime = block.timestamp;
    balances[_user] -= _amount;
  }

  function _newAccumulatedRewards(address _user) internal view returns (uint256 _rewards) {
    uint256 _secondsSinceLastDeposit = (block.timestamp - rewards[_user].lastClaimTime);
    _rewards = ((rewardsPerSecondPerToken * _secondsSinceLastDeposit * balances[_user]) / 1 ether);
  }
}
