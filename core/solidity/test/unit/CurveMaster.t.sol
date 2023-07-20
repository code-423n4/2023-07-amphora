// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus} from 'solidity-utils/test/DSTestPlus.sol';
import {CurveMaster} from '@contracts/periphery/CurveMaster.sol';

import {ICurveMaster} from '@interfaces/periphery/ICurveMaster.sol';
import {ICurveSlave} from '@interfaces/utils/ICurveSlave.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';

abstract contract Base is DSTestPlus {
  event VaultControllerSet(address _oldVaultControllerAddress, address _newVaultControllerAddress);
  event CurveSet(address _oldCurveAddress, address _token, address _newCurveAddress);
  event CurveForceSet(address _oldCurveAddress, address _token, address _newCurveAddress);

  CurveMaster public curveMaster;
  IVaultController internal _mockVaultController = IVaultController(mockContract(newAddress(), 'mockVaultController'));

  function setUp() public virtual {
    // Deploy contract
    curveMaster = new CurveMaster();
  }
}

contract UnitTestCurveMasterGetValueAt is Base {
  function testGetValueAtRevertWithTokenNotEnabled(address _token, int256 _xValue) public {
    vm.assume(_token != address(0));

    vm.expectRevert(ICurveMaster.CurveMaster_TokenNotEnabled.selector);
    curveMaster.getValueAt(_token, _xValue);
  }

  function testGetValueAtRevertWithZeroResult(address _token, address _curve, int256 _xValue) public {
    vm.assume(_token > address(10));
    vm.assume(_curve > address(10));
    vm.assume(_curve != address(curveMaster));
    vm.assume(_curve != address(this));
    vm.assume(_curve != address(vm));

    vm.prank(curveMaster.owner());
    curveMaster.forceSetCurve(_token, _curve);

    mockContract(_curve, 'mockCurveSlave');

    vm.mockCall(_curve, abi.encodeWithSelector(ICurveSlave.valueAt.selector), abi.encode(int256(0)));

    vm.expectRevert(ICurveMaster.CurveMaster_ZeroResult.selector);
    curveMaster.getValueAt(_token, _xValue);
  }

  function testGetValueAt(address _token, address _curve, int256 _xValue) public {
    vm.assume(_token > address(10));
    vm.assume(_curve > address(10));
    vm.assume(_curve != address(curveMaster));
    vm.assume(_curve != address(this));
    vm.assume(_curve != address(vm));
    vm.assume(_xValue != 0);

    vm.prank(curveMaster.owner());
    curveMaster.forceSetCurve(_token, _curve);

    mockContract(_curve, 'mockCurveSlave');

    vm.mockCall(_curve, abi.encodeWithSelector(ICurveSlave.valueAt.selector), abi.encode(int256(_xValue)));

    int256 _value = curveMaster.getValueAt(_token, _xValue);
    assertEq(_value, _xValue);
  }
}

contract UnitTestCurveMasterSetVaultController is Base {
  function testSetVaultControllerRevertOnlyOwner(address _notOwner) public {
    vm.assume(_notOwner != curveMaster.owner());
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(_notOwner);
    curveMaster.setVaultController(address(1));
  }

  function testSetVaultController(address _vaultController) public {
    vm.prank(curveMaster.owner());
    curveMaster.setVaultController(_vaultController);

    assertEq(_vaultController, curveMaster.vaultControllerAddress());
  }

  function testEmitEvent(address _vaultController) public {
    vm.expectEmit(false, false, false, true);
    emit VaultControllerSet(curveMaster.vaultControllerAddress(), _vaultController);

    vm.prank(curveMaster.owner());
    curveMaster.setVaultController(_vaultController);
  }
}

contract UnitTestCurveMasterSetCurve is Base {
  function testSetCurveRevertOnlyOwner(address _notOwner) public {
    vm.assume(_notOwner != curveMaster.owner());
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(_notOwner);
    curveMaster.setCurve(address(1), address(1));
  }

  function testSetCurveWithVaultControllerInZero(address _token, address _curve) public {
    vm.assume(_token != address(0));
    vm.assume(_curve != address(0));

    vm.prank(curveMaster.owner());
    curveMaster.setCurve(_token, _curve);

    assertEq(curveMaster.curves(_token), _curve);
  }

  function testSetCurveWithVaultControllerNotInZero(address _token, address _curve) public {
    vm.assume(_token != address(0));
    vm.assume(_curve != address(0));

    vm.prank(curveMaster.owner());
    curveMaster.setVaultController(address(_mockVaultController));

    vm.mockCall(
      address(_mockVaultController),
      abi.encodeWithSelector(IVaultController.calculateInterest.selector),
      abi.encode(true)
    );

    vm.prank(curveMaster.owner());
    vm.expectCall(address(_mockVaultController), abi.encodeWithSelector(IVaultController.calculateInterest.selector));
    curveMaster.setCurve(_token, _curve);

    assertEq(curveMaster.curves(_token), _curve);
  }

  function testEmitEvent(address _token, address _curve) public {
    vm.assume(_token != address(0));
    vm.assume(_curve != address(0));

    vm.prank(curveMaster.owner());
    curveMaster.setVaultController(address(_mockVaultController));

    vm.mockCall(
      address(_mockVaultController),
      abi.encodeWithSelector(IVaultController.calculateInterest.selector),
      abi.encode(true)
    );

    vm.expectEmit(false, false, false, true);
    emit CurveSet(curveMaster.curves(_token), _token, _curve);

    vm.prank(curveMaster.owner());
    curveMaster.setCurve(_token, _curve);
  }
}

contract UnitTestCurveMasterForceSetCurve is Base {
  function testForceSetCurveRevertOnlyOwner(address _notOwner) public {
    vm.assume(_notOwner != curveMaster.owner());
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(_notOwner);
    curveMaster.forceSetCurve(address(1), address(1));
  }

  function testForceSetCurveWithVaultControllerInZero(address _token, address _curve) public {
    vm.assume(_token != address(0));
    vm.assume(_curve != address(0));

    vm.prank(curveMaster.owner());
    curveMaster.forceSetCurve(_token, _curve);

    assertEq(curveMaster.curves(_token), _curve);
  }

  function testEmitEvent(address _token, address _curve) public {
    vm.assume(_token != address(0));
    vm.assume(_curve != address(0));

    vm.expectEmit(true, true, true, true);
    emit CurveForceSet(curveMaster.curves(_token), _token, _curve);

    vm.prank(curveMaster.owner());
    curveMaster.forceSetCurve(_token, _curve);
  }
}
