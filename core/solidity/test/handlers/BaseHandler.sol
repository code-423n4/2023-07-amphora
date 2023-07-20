// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus} from 'solidity-utils/test/DSTestPlus.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockSUSD is ERC20 {
  constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

  function decimals() public pure override returns (uint8) {
    return 18;
  }
}

struct AddressSet {
  address[] addrs;
  mapping(address => bool) saved;
}

library LibAddressSet {
  function add(AddressSet storage _s, address _addr) internal {
    if (!_s.saved[_addr]) {
      _s.addrs.push(_addr);
      _s.saved[_addr] = true;
    }
  }

  function contains(AddressSet storage _s, address _addr) internal view returns (bool _contains) {
    return _s.saved[_addr];
  }

  function count(AddressSet storage _s) internal view returns (uint256 _count) {
    return _s.addrs.length;
  }

  function rand(AddressSet storage _s, uint256 _seed) internal view returns (address _random) {
    if (_s.addrs.length > 0) return _s.addrs[_seed % _s.addrs.length];
    else return address(0);
  }

  function forEach(AddressSet storage _s, function(address) external _func) internal {
    for (uint256 _i; _i < _s.addrs.length; ++_i) {
      _func(_s.addrs[_i]);
    }
  }

  function reduce(
    AddressSet storage _s,
    uint256 _acc,
    function(uint256,address) external returns (uint256) _func
  ) internal returns (uint256 _result) {
    for (uint256 _i; _i < _s.addrs.length; ++_i) {
      _acc = _func(_acc, _s.addrs[_i]);
    }
    return _acc;
  }
}

abstract contract BaseHandler is DSTestPlus {
  using LibAddressSet for AddressSet;

  AddressSet internal _actors;

  AddressSet internal _excludedActors;

  address internal _currentActor;

  mapping(bytes32 => uint256) public calls;

  uint256 public totalCalls;

  uint256 public actorsIndex;

  modifier countCall(bytes32 _key) {
    _;
    calls[_key]++;
    totalCalls++;
  }

  modifier createActor() {
    if (_excludedActors.contains(msg.sender)) return;
    _currentActor = msg.sender;
    _actors.add(msg.sender);
    _;
  }

  modifier useActor(uint256 _actorIndexSeed) {
    _currentActor = getRandomActor(_actorIndexSeed);
    _;
  }

  function createMultipleActors(uint256 _numberOfActors) public {
    for (uint256 _i; _i < _numberOfActors; _i++) {
      address _newActor = address(uint160(actorsIndex + 100));
      actorsIndex++;
      _actors.add(_newActor);
    }
  }

  function getRandomActor(uint256 _actorIndexSeed) public view returns (address _actor) {
    _actor = _actors.rand(_actorIndexSeed);
  }

  function actors() public view returns (address[] memory _addressActors) {
    return _actors.addrs;
  }

  function _excludeActor(address _actor) internal {
    _excludedActors.add(_actor);
  }

  /// @dev if max is less than min, dont revert and return 0
  function _boundWithCheck(uint256 _x, uint256 _min, uint256 _max) internal view returns (uint256 _res) {
    if (_min > _max) return 0;
    _res = bound(_x, _min, _max);
  }
}
