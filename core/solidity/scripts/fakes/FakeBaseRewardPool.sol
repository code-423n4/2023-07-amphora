// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IBaseRewardPool} from '@interfaces/utils/IBaseRewardPool.sol';
import {IBooster} from '@interfaces/utils/IBooster.sol';
import {IVirtualBalanceRewardPool} from '@interfaces/utils/IVirtualBalanceRewardPool.sol';

import {ERC20, IERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

import {FakeVirtualRewardsPool} from './FakeVirtualRewardsPool.sol';
import {MintableToken} from './MintableToken.sol';

struct Rewards {
  uint256 lastClaimTime;
  uint256 rewardsToPay;
}

contract FakeBaseRewardPool is IBaseRewardPool {
  FakeCVX public immutable CVX;
  address public booster;
  mapping(address => uint256) public balances;
  IERC20 public rewardToken;
  mapping(address => Rewards) public rewards;
  uint256 public rewardsPerSecondPerToken; //1e18 = 1 token
  IVirtualBalanceRewardPool[] public extraRewards;
  address public owner;
  IERC20 public lptoken;

  constructor(
    address _booster,
    IERC20 _rewardToken,
    uint256 _rewardsPerSecondPerToken,
    address _lptoken,
    FakeCVX _cvx
  ) {
    booster = _booster;
    rewardToken = _rewardToken;
    rewardsPerSecondPerToken = _rewardsPerSecondPerToken;
    owner = msg.sender;
    lptoken = IERC20(_lptoken);
    CVX = _cvx;
  }

  function withdraw(uint256, bool) external pure override returns (bool _success) {
    return true;
  }

  function queueNewRewards(uint256) external pure override returns (bool _success) {
    return true;
  }

  function stakeFor(address, uint256) external pure override returns (bool _staked) {
    return true;
  }

  function stake(uint256) external pure override returns (bool _staked) {
    return true;
  }

  function stakeForUser(uint256 _amount, address _user) external {
    require(msg.sender == booster, 'only booster');
    rewards[_user].rewardsToPay = rewards[_user].rewardsToPay + _newAccumulatedRewards(_user);
    rewards[_user].lastClaimTime = block.timestamp;
    balances[_user] += _amount;

    for (uint256 i = 0; i < extraRewards.length; i++) {
      FakeVirtualRewardsPool(address(extraRewards[i])).stake(_user, _amount);
    }
  }

  function earned(address _ad) external view override returns (uint256 _reward) {
    _reward = rewards[_ad].rewardsToPay + _newAccumulatedRewards(_ad);
  }

  function extraRewardsLength() external view override returns (uint256 _extraRewardsLength) {
    return extraRewards.length;
  }

  function withdrawAndUnwrap(uint256 _amount, bool) external override returns (bool _success) {
    rewards[msg.sender].rewardsToPay = rewards[msg.sender].rewardsToPay + _newAccumulatedRewards(msg.sender);
    rewards[msg.sender].lastClaimTime = block.timestamp;
    balances[msg.sender] -= _amount;

    for (uint256 i = 0; i < extraRewards.length; i++) {
      FakeVirtualRewardsPool(address(extraRewards[i])).unstake(msg.sender, _amount);
    }

    lptoken.transfer(msg.sender, _amount);
    return true;
  }

  function getReward(address _account, bool) external override returns (bool _success) {
    uint256 _earned = rewards[_account].rewardsToPay + _newAccumulatedRewards(_account);
    rewardToken.transfer(_account, _earned);

    rewards[_account].lastClaimTime = block.timestamp;
    rewards[_account].rewardsToPay = 0;

    CVX.transfer(_account, _calculateCVXReward(_earned));
    return true;
  }

  function addExtraReward(IVirtualBalanceRewardPool _extraReward) external {
    require(msg.sender == owner, 'only owner');
    extraRewards.push(_extraReward);
  }

  function _newAccumulatedRewards(address _user) internal view returns (uint256 _rewards) {
    uint256 _secondsSinceLastDeposit = (block.timestamp - rewards[_user].lastClaimTime);
    _rewards = ((rewardsPerSecondPerToken * _secondsSinceLastDeposit * balances[_user]) / 1 ether);
  }

  /// @notice Used to calculate the CVX reward for a given CRV amount
  /// @dev This is copied from the CVX mint function
  /// @param _crv The amount of CRV to calculate the CVX reward for
  /// @return _cvxAmount The amount of CVX to get
  function _calculateCVXReward(uint256 _crv) internal view returns (uint256 _cvxAmount) {
    uint256 _supply = CVX.totalSupply();
    uint256 _totalCliffs = CVX.totalCliffs();

    //use current supply to gauge cliff
    //this will cause a bit of overflow into the next cliff range
    //but should be within reasonable levels.
    //requires a max supply check though
    uint256 _cliff = _supply / CVX.reductionPerCliff();
    //mint if below total cliffs
    if (_cliff < _totalCliffs) {
      //for reduction% take inverse of current cliff
      uint256 _reduction = _totalCliffs - _cliff;
      //reduce
      _cvxAmount = (_crv * _reduction) / _totalCliffs;

      //supply cap check
      uint256 _amtTillMax = CVX.maxSupply() - _supply;
      if (_cvxAmount > _amtTillMax) _cvxAmount = _amtTillMax;
    }
  }
}

contract FakeCVX is MintableToken {
  constructor() MintableToken('CVX', uint8(18)) {
    _mint(msg.sender, 100_000 ether);
  }

  function totalCliffs() external pure returns (uint256) {
    return 10_000;
  }

  function reductionPerCliff() external pure returns (uint256) {
    return 100_000_000 ether;
  }

  function maxSupply() external pure returns (uint256) {
    return type(uint256).max;
  }
}
