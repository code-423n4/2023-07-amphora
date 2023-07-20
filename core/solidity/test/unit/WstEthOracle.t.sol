// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus, console} from 'solidity-utils/test/DSTestPlus.sol';
import {EthSafeStableCurveOracle} from '@contracts/periphery/oracles/EthSafeStableCurveOracle.sol';

import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {WstEthOracle} from '@contracts/periphery/oracles/WstEthOracle.sol';
import {IWStETH} from '@interfaces/utils/IWStETH.sol';

abstract contract Base is DSTestPlus {
  IOracleRelay public stEthOracleRelay = IOracleRelay(mockContract(newAddress(), 'stEthOracleRelay'));
  IWStETH public wstEth;
  WstEthOracle public wstEthOracle;

  function setUp() public virtual {
    wstEthOracle = new WstEthOracle(stEthOracleRelay);
    wstEth = IWStETH(mockContract(address(wstEthOracle.WSTETH()), 'wstEth'));
  }
}

contract UnitTestWstEthOraclePeekValue is Base {
  function testCallsStEthPerTokenOnWsteth() public {
    vm.mockCall(address(wstEth), abi.encodeWithSelector(wstEth.stEthPerToken.selector), abi.encode(1 ether));
    vm.mockCall(address(stEthOracleRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
    vm.expectCall(address(wstEth), abi.encodeWithSelector(wstEth.stEthPerToken.selector));
    wstEthOracle.peekValue();
  }

  function testCallsPeekValueOnStEthOracle() public {
    vm.mockCall(address(wstEth), abi.encodeWithSelector(wstEth.stEthPerToken.selector), abi.encode(1 ether));
    vm.mockCall(address(stEthOracleRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
    vm.expectCall(address(stEthOracleRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector));
    wstEthOracle.peekValue();
  }

  function testPeekValue(uint256 _stEthValue, uint256 _stEthPerWstEth) public {
    vm.assume(_stEthPerWstEth > 0);
    vm.assume(_stEthValue < type(uint256).max / _stEthPerWstEth);
    vm.mockCall(address(wstEth), abi.encodeWithSelector(wstEth.stEthPerToken.selector), abi.encode(_stEthPerWstEth));
    vm.mockCall(
      address(stEthOracleRelay), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_stEthValue)
    );
    assertEq(wstEthOracle.peekValue(), (_stEthValue * _stEthPerWstEth) / 1e18);
  }
}
