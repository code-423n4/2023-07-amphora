// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, IVault, console} from '@test/e2e/Common.sol';
import {IUSDA} from '@interfaces/core/IUSDA.sol';

contract E2EUSDA is CommonE2EBase {
  uint256 public susdAmount = 500 ether;
  uint256 public maxwUSDASupply;

  function setUp() public override {
    super.setUp();
    maxwUSDASupply = wusda.MAX_wUSDA_SUPPLY();
  }

  function testAccountsForUSDARewards() public {
    // Andy deposits SUSD
    _depositSUSD(andy, andySUSDBalance);
    uint256 _andyUSDABalance = usdaToken.balanceOf(andy);

    // Bob Deposits SUSD
    _depositSUSD(bob, bobSUSDBalance);
    uint256 _bobUSDABalance = usdaToken.balanceOf(bob);

    // Check the total usda supply
    uint256 _totalUSDASupply = usdaToken.totalSupply();

    // Bob deposits usda to wusda
    vm.startPrank(bob);
    usdaToken.approve(address(wusda), _bobUSDABalance);
    wusda.deposit(_bobUSDABalance);
    uint256 _bobWUSDABalance = wusda.balanceOf(bob);
    vm.stopPrank();

    // Check that bob's wusda balance is correct
    assertEq(_bobWUSDABalance, (_bobUSDABalance * maxwUSDASupply) / _totalUSDASupply);

    // Andy deposits usda to wusda
    vm.startPrank(andy);
    usdaToken.approve(address(wusda), _andyUSDABalance);
    wusda.deposit(_andyUSDABalance);
    uint256 _andyWUSDABalance = wusda.balanceOf(andy);
    vm.stopPrank();

    // Check that andy's wusda balance is correct
    assertEq(_andyWUSDABalance, (_andyUSDABalance * maxwUSDASupply) / _totalUSDASupply);

    // Someone donates to the USDA pool
    uint256 _donationAmount = 1000 ether;
    vm.startPrank(dave);
    susd.approve(address(usdaToken), _donationAmount);
    usdaToken.donate(_donationAmount);
    vm.stopPrank();

    uint256 _newTotalUSDASupply = usdaToken.totalSupply();

    // Bob's wusda balance should remain the same
    assertEq(wusda.balanceOf(bob), _bobWUSDABalance);

    // Bob's underlying usda balance should increase
    assertEq(wusda.balanceOfUnderlying(bob), (_bobWUSDABalance * _newTotalUSDASupply) / maxwUSDASupply);

    // Andy's wusda balance should remain the same
    assertEq(wusda.balanceOf(andy), _andyWUSDABalance);

    // Andy's underlying usda balance should increase
    assertEq(wusda.balanceOfUnderlying(andy), (_andyWUSDABalance * _newTotalUSDASupply) / maxwUSDASupply);

    // Bob can now withdraw all usda and it will be the correct amount
    vm.startPrank(bob);
    wusda.approve(address(wusda), _bobWUSDABalance);
    wusda.burn(_bobWUSDABalance);
    vm.stopPrank();
    assertEq(usdaToken.balanceOf(bob), (_bobWUSDABalance * _newTotalUSDASupply) / maxwUSDASupply);

    // Andy can now withdraw all usda and it will be the correct amount
    vm.startPrank(andy);
    wusda.approve(address(wusda), _andyWUSDABalance);
    wusda.burn(_andyWUSDABalance);
    vm.stopPrank();
    assertEq(usdaToken.balanceOf(andy), (_andyWUSDABalance * _newTotalUSDASupply) / maxwUSDASupply);
  }
}
