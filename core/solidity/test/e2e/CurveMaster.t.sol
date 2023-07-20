// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase} from '@test/e2e/Common.sol';

contract E2ECurveMaster is CommonE2EBase {
  function setUp() public override {
    super.setUp();
  }

  function testSetCurve() public {
    vm.prank(address(governor));
    curveMaster.setCurve(address(0), address(threeLines));
  }

  function testThreeLinesViaCurveMaster() public {
    assertEq(curveMaster.getValueAt(address(0), 0), 2 ether);
    assertEq(curveMaster.getValueAt(address(0), 0.25 * 1 ether), 0.1 * 1 ether);
    assertEq(curveMaster.getValueAt(address(0), 0.5 * 1 ether), 0.005 * 1 ether);
    assertEq(curveMaster.getValueAt(address(0), 0.525 * 1 ether), 0.005 * 1 ether);
    assertEq(curveMaster.getValueAt(address(0), 0.55 * 1 ether), 0.005 * 1 ether);
    assertEq(curveMaster.getValueAt(address(0), 1 ether), 0.005 * 1 ether);
  }
}
