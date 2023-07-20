// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IBaseRewardPool} from '@interfaces/utils/IBaseRewardPool.sol';
import {IBooster} from '@interfaces/utils/IBooster.sol';

import {FakeBaseRewardPool} from '@scripts/fakes/FakeBaseRewardPool.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

struct PoolInfo {
  address lptoken;
  address crvRewards;
}

contract FakeBooster is IBooster {
  using SafeERC20Upgradeable for IERC20;

  address public owner;
  mapping(uint256 => PoolInfo) public poolInfos;
  uint256 public pools;

  constructor() {
    owner = msg.sender;
  }

  function setVoteDelegate(address _voteDelegate) external override {}

  function vote(uint256, address, bool) external pure override returns (bool _success) {
    return true;
  }

  function voteGaugeWeight(address[] calldata, uint256[] calldata) external pure override returns (bool _success) {
    return true;
  }

  function earmarkRewards(uint256) external pure override returns (bool _claimed) {
    return true;
  }

  function earmarkFees() external pure override returns (bool _claimed) {
    return true;
  }

  function addPoolInfo(address _lptoken, address _crvRewards) external returns (uint256 _pid) {
    require(msg.sender == owner, 'only owner');
    ++pools;
    poolInfos[pools] = PoolInfo(_lptoken, _crvRewards);
    return pools;
  }

  function poolInfo(uint256 _pid)
    external
    view
    override
    returns (address _lptoken, address _token, address _gauge, address _crvRewards, address _stash, bool _shutdown)
  {
    PoolInfo memory _poolInfo = poolInfos[_pid];
    return (_poolInfo.lptoken, address(0), address(0), _poolInfo.crvRewards, address(0), false);
  }

  function deposit(uint256 _pid, uint256 _amount, bool _stake) external override returns (bool _success) {
    if (!_stake) revert('only stake');
    PoolInfo memory _poolInfo = poolInfos[_pid];
    IBaseRewardPool(_poolInfo.crvRewards).stake(_amount);

    //send to proxy to stake
    address _lptoken = _poolInfo.lptoken;
    address _crvRewards = _poolInfo.crvRewards;
    IERC20(_lptoken).transferFrom(msg.sender, _crvRewards, _amount);

    // Call crvRewards.stake with the amount staked
    FakeBaseRewardPool(_crvRewards).stakeForUser(_amount, msg.sender);

    return true;
  }
}
