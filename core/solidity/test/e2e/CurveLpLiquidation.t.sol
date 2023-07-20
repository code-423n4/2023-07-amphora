// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, IVault} from '@test/e2e/Common.sol';

contract CurveLpLiquidation is CommonE2EBase {
  uint256 public depositAmount;

  function setUp() public virtual override {
    super.setUp();

    depositAmount = usdtStableLP.balanceOf(bob);
  }

  function testCurveLpLiquidation() public {
    // bob mints vault
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // bob deposits LP
    vm.startPrank(bob);
    usdtStableLP.approve(address(bobVault), type(uint256).max);
    bobVault.depositERC20(address(usdtStableLP), depositAmount);
    vm.stopPrank();

    // start some liability
    vm.startPrank(bob);
    uint256 _maxBorrow = vaultController.vaultBorrowingPower(bobVaultId);
    vaultController.borrowUSDA(bobVaultId, uint192(_maxBorrow));
    vm.stopPrank();

    // try to withdraw (should fail)
    vm.expectRevert(IVault.Vault_OverWithdrawal.selector);
    vm.prank(bob);
    bobVault.withdrawERC20(address(usdtStableLP), depositAmount);

    // make the vault liquidatable
    vm.warp(block.timestamp + 7 days);
    vaultController.calculateInterest();

    // dave deposits sUSD
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(susd.balanceOf(dave));
    vm.stopPrank();

    // liquidate
    vm.startPrank(dave);
    uint256 _daveBalanceBefore = usdtStableLP.balanceOf(dave);
    uint256 _vaultTokenBalanceBefore = bobVault.balances(address(usdtStableLP));
    uint256 _tokensToLiquidate = vaultController.tokensToLiquidate(bobVaultId, address(usdtStableLP));
    vaultController.liquidateVault(bobVaultId, address(usdtStableLP), _tokensToLiquidate);
    uint256 _daveBalanceAfter = usdtStableLP.balanceOf(dave);
    uint256 _vaultTokenBalanceAfter = bobVault.balances(address(usdtStableLP));
    vm.stopPrank();
    assertGt(_vaultTokenBalanceBefore, _vaultTokenBalanceAfter);
    assertGt(_daveBalanceAfter, _daveBalanceBefore);

    // user should claim rewards succesfully
    vm.startPrank(bob);
    address[] memory _lps = new address[](1);
    _lps[0] = address(usdtStableLP);

    IVault.Reward[] memory _rewardsBefore = bobVault.claimableRewards(address(usdtStableLP));

    bobVault.claimRewards(_lps);
    vm.stopPrank();

    // check that rewards were claimed
    IVault.Reward[] memory _rewardsAfter = bobVault.claimableRewards(address(usdtStableLP));
    for (uint256 _i; _i < _rewardsAfter.length; _i++) {
      assertEq(_rewardsAfter[_i].amount, 0);
    }
    for (uint256 _i; _i < _rewardsAfter.length; _i++) {
      if (_rewardsBefore[_i].amount > 0) {
        // if rewards were positive, bob should have those tokens in the wallet
        assertGt(_rewardsBefore[_i].token.balanceOf(bob), 0);
      }
      assertEq(_rewardsAfter[_i].amount, 0);
    }
  }
}
