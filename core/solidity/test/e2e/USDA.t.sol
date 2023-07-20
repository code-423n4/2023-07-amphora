// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, IVault} from '@test/e2e/Common.sol';
import {IUSDA} from '@interfaces/core/IUSDA.sol';

contract E2EUSDA is CommonE2EBase {
  uint256 public susdAmount = 500 ether;

  event Deposit(address indexed _from, uint256 _value);
  event Withdraw(address indexed _from, uint256 _value);

  function setUp() public override {
    super.setUp();
  }

  function testDepositSUSD() public {
    _depositSUSD(andy, andySUSDBalance);
    assertEq(usdaToken.balanceOf(andy), andySUSDBalance);
  }

  function testRevertIfBurnByNonAdmin() public {
    vm.expectRevert();
    vm.prank(bob);
    usdaToken.burn(100);
  }

  function testDepositAndInterestWithStartingBalance() public {
    assertEq(susd.balanceOf(dave), daveSUSD);

    vm.prank(dave);
    susd.approve(address(usdaToken), susdAmount);

    uint256 _daveUSDABalance = usdaToken.balanceOf(dave);

    /// Test pause/unpause
    vm.prank(address(governor));
    usdaToken.pause();

    vm.expectRevert('Pausable: paused');
    vm.prank(dave);
    usdaToken.deposit(susdAmount);

    vm.prank(address(governor));
    usdaToken.unpause();

    /// Test deposit
    vm.expectEmit(false, false, false, true);
    emit Deposit(address(dave), susdAmount);

    vm.prank(dave);
    usdaToken.deposit(susdAmount);

    assertEq(susd.balanceOf(dave), daveSUSD - susdAmount);

    /// Someone borrows
    bobVaultId = _mintVault(bob);
    vm.startPrank(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));
    weth.approve(address(bobVault), bobWETH);
    IVault(address(bobVault)).depositERC20(address(weth), bobWETH);
    uint256 _toBorrow = vaultController.vaultBorrowingPower(bobVaultId);
    vaultController.borrowUSDA(bobVaultId, uint192(_toBorrow / 2));
    vm.stopPrank();

    // some interest has accrued, USDA balance should be slightly higher than existingUSDA balance + sUSD amount deposited
    vm.warp(block.timestamp + 1 days);
    vaultController.calculateInterest();
    assertGt(usdaToken.balanceOf(dave), _daveUSDABalance + susdAmount);
  }

  function testRevertIfDepositingMoreThanBalance() public {
    assertEq(0, susd.balanceOf(eric));

    vm.startPrank(eric);
    susd.approve(address(usdaToken), susdAmount);

    vm.expectRevert('Insufficient balance after any settlement owing');
    usdaToken.deposit(susdAmount);
    vm.stopPrank();
  }

  function testRevertIfDepositIsZero() public {
    vm.startPrank(dave);
    susd.approve(address(usdaToken), susdAmount);

    vm.expectRevert(IUSDA.USDA_ZeroAmount.selector);
    usdaToken.deposit(0);
    vm.stopPrank();
  }

  function testWithdrawSUSD() public {
    /// USDA balance before
    uint256 _usdaBalanceBefore = usdaToken.balanceOf(dave);

    /// Deposit
    _depositSUSD(dave, susdAmount);

    /// Someone borrows
    bobVaultId = _mintVault(bob);
    vm.startPrank(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));
    weth.approve(address(bobVault), bobWETH);
    IVault(address(bobVault)).depositERC20(address(weth), bobWETH);
    uint256 _toBorrow = vaultController.vaultBorrowingPower(bobVaultId);
    vaultController.borrowUSDA(bobVaultId, uint192(_toBorrow / 2));
    vm.stopPrank();

    /// Time travel
    vm.warp(block.timestamp + 1 days);

    /// Test pause/unpause
    vm.prank(address(governor));
    usdaToken.pause();

    vm.expectRevert('Pausable: paused');
    vm.prank(dave);
    usdaToken.withdraw(susdAmount);

    vm.prank(address(governor));
    usdaToken.unpause();

    /// SUSD balance before
    uint256 _susdBefore = susd.balanceOf(dave);
    assertEq(_susdBefore, daveSUSD - susdAmount);

    /// Withdraw
    vm.prank(dave);
    usdaToken.withdraw(susdAmount);
    assertEq(susd.balanceOf(dave), daveSUSD);

    /// Should end up with slightly more USDA than original due to interest
    assertGt(usdaToken.balanceOf(dave), _usdaBalanceBefore);
  }

  function testRevertIfWithdrawMoreThanBalance() public {
    /// Deposit
    _depositSUSD(andy, andySUSDBalance);

    uint256 _usdaBalanceBefore = usdaToken.balanceOf(eric);
    assertEq(0, _usdaBalanceBefore);

    vm.prank(andy);
    usdaToken.transfer(eric, 1 ether);

    assertEq(1 ether, usdaToken.balanceOf(eric));

    vm.expectRevert(IUSDA.USDA_InsufficientFunds.selector);
    vm.prank(eric);
    usdaToken.withdraw(5 ether);
  }

  function testWithdrawAllReserve() public {
    /// Deposit
    _depositSUSD(bob, bobSUSDBalance);

    uint256 _reserve = susd.balanceOf(address(usdaToken));
    assertEq(_reserve, usdaToken.balanceOf(bob));

    vm.prank(bob);
    usdaToken.transfer(dave, _reserve);

    uint256 _susdBalance = susd.balanceOf(dave);

    vm.expectEmit(false, false, false, true);
    emit Withdraw(address(dave), _reserve);

    /// Withdraw
    vm.prank(dave);
    usdaToken.withdrawAll();

    uint256 _susdBalanceAfter = susd.balanceOf(dave);
    uint256 _reserveAfter = susd.balanceOf(address(usdaToken));

    assertEq(_susdBalanceAfter, _susdBalance + _reserve);
    assertEq(0, _reserveAfter);

    vm.startPrank(dave);
    vm.expectRevert();
    usdaToken.withdraw(1);

    vm.expectRevert(IUSDA.USDA_EmptyReserve.selector);
    usdaToken.withdrawAll();
    vm.stopPrank();
  }

  function testDonateSUSD() public {
    uint256 _daveSUSDBalance = susd.balanceOf(dave);
    uint256 _reserve = susd.balanceOf(address(usdaToken));
    assertEq(0, _reserve);

    /// Donate
    vm.startPrank(dave);
    susd.approve(address(usdaToken), _daveSUSDBalance / 2);
    usdaToken.donate(_daveSUSDBalance / 2);
    vm.stopPrank();

    uint256 _reserveAfter = susd.balanceOf(address(usdaToken));
    assertGt(_reserveAfter, 0);
  }

  function testRevertIfDepositETH() public {
    vm.prank(dave);
    (bool _success,) = address(usdaToken).call{value: 1 ether}('');
    assertTrue(!_success);
  }

  function testTransferSUSDtoUSDA() public {
    uint256 _balance = susd.balanceOf(address(usdaToken));
    uint256 _reserveRatio = usdaToken.reserveRatio();
    uint256 _usdaSupply = usdaToken.totalSupply();

    vm.prank(dave);
    susd.transfer(address(usdaToken), 1 ether);

    uint256 _balanceAfter = susd.balanceOf(address(usdaToken));
    uint256 _reserveRatioAfter = usdaToken.reserveRatio();
    uint256 _usdaSupplyAfter = usdaToken.totalSupply();

    assertEq(_usdaSupply, _usdaSupplyAfter);
    assertGt(_balanceAfter, _balance);
    assertEq(_reserveRatioAfter, _reserveRatio);
  }

  function testRecoverDust() public {
    // Deposit half balance
    _depositSUSD(andy, andySUSDBalance / 2);
    assertEq(usdaToken.balanceOf(andy), andySUSDBalance / 2);

    // Transfer half balance
    vm.prank(andy);
    susd.transfer(address(usdaToken), andySUSDBalance / 2);
    // usda balance should remain same
    assertEq(usdaToken.balanceOf(andy), andySUSDBalance / 2);
    assertEq(susd.balanceOf(andy), 0);

    vm.prank(address(governor));
    usdaToken.recoverDust(andy);
    assertEq(susd.balanceOf(andy), andySUSDBalance / 2);
  }
}
