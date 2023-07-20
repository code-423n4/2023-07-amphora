// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MintableToken is ERC20 {
  address immutable _deployer;
  uint8 internal immutable _DECIMALS;

  constructor(string memory _name, uint8 _decimals) ERC20(_name, _name) {
    _deployer = msg.sender;
    _DECIMALS = _decimals;
  }

  function mint(address to, uint256 amount) external {
    require(msg.sender == _deployer, 'Not deployer');
    _mint(to, amount);
  }

  function decimals() public view virtual override returns (uint8) {
    return _DECIMALS;
  }
}
