// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IOracleRelay, OracleRelay} from '@contracts/periphery/oracles/OracleRelay.sol';

contract FakeWethOracle is OracleRelay {
  uint256 public price = 1850 * 1e18;
  address public _owner;

  constructor() OracleRelay(OracleType.Chainlink) {
    _owner = msg.sender;
  }

  function peekValue() public view virtual override returns (uint256 _price) {
    _price = _get();
  }

  /// @notice the current reported value of the oracle
  /// @return _value the current value
  /// @dev implementation in getLastSecond
  function _get() internal view returns (uint256 _value) {
    _value = price;
  }

  function setPrice(uint256 _price) external {
    require(msg.sender == _owner, 'Not owner');
    price = _price;
  }
}
