// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IBooster {
  function owner() external view returns (address _owner);
  function setVoteDelegate(address _voteDelegate) external;
  function vote(uint256 _voteId, address _votingAddress, bool _support) external returns (bool _success);
  function voteGaugeWeight(address[] calldata _gauge, uint256[] calldata _weight) external returns (bool _success);
  function poolInfo(uint256 _pid)
    external
    view
    returns (address _lptoken, address _token, address _gauge, address _crvRewards, address _stash, bool _shutdown);
  function earmarkRewards(uint256 _pid) external returns (bool _claimed);
  function earmarkFees() external returns (bool _claimed);
  function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool _success);
}
