// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {
  CommonE2EBase,
  IVault,
  IVaultController,
  VaultController,
  IVaultDeployer,
  VaultDeployer,
  IERC20
} from '@test/e2e/Common.sol';
import {stdError} from 'forge-std/Test.sol';

contract E2EEdgeCases is CommonE2EBase {
  VaultController public newVaultController;
  VaultDeployer public newVaultDeployer;

  function setUp() public override {
    super.setUp();
  }

  function testWithdrawATokenThatYouDontHave() public {
    // create vault
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // try to withdraw token
    vm.expectRevert(stdError.arithmeticError);
    vm.prank(bob);
    bobVault.withdrawERC20(WBTC_ADDRESS, 1 ether);
  }

  function testWithdrawMoreTokensThanYouHave() public {
    // create vault
    gusVaultId = _mintVault(gus);
    gusVault = IVault(vaultController.vaultIdVaultAddress(gusVaultId));
    uint256 _deposit = 1000e8;

    // deposits tokens
    vm.startPrank(gus);
    wbtc.approve(address(gusVault), type(uint256).max);
    gusVault.depositERC20(WBTC_ADDRESS, _deposit);
    vm.stopPrank();

    // try to withdraw token
    vm.expectRevert(stdError.arithmeticError);
    vm.prank(gus);
    gusVault.withdrawERC20(WBTC_ADDRESS, _deposit + 1);
  }

  function testWithdrawTokensWhichWouldLiquidateYourVault() public {
    // create vault
    gusVaultId = _mintVault(gus);
    gusVault = IVault(vaultController.vaultIdVaultAddress(gusVaultId));

    uint256 _deposit = 1000e8;

    // deposits tokens
    vm.startPrank(gus);
    wbtc.approve(address(gusVault), type(uint256).max);
    gusVault.depositERC20(WBTC_ADDRESS, _deposit);
    vm.stopPrank();

    // borrow
    vm.startPrank(gus);
    vaultController.borrowUSDA(gusVaultId, vaultController.vaultBorrowingPower(gusVaultId));
    vm.stopPrank();

    // try to withdraw token
    vm.expectRevert(IVault.Vault_OverWithdrawal.selector);
    vm.prank(gus);
    gusVault.withdrawERC20(WBTC_ADDRESS, _deposit / 2);
  }

  function testDepositTokenThatIsNotWhitelisted() public {
    // create vault
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // deposits tokens
    vm.startPrank(bob);
    vm.expectRevert(IVault.Vault_TokenNotRegistered.selector);
    bobVault.depositERC20(newAddress(), 1);
    vm.stopPrank();
  }

  function testDepositATokenWhenItSurpassesTheCap() public {
    // create vault
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // deposits tokens
    vm.startPrank(bob);
    aave.approve(address(bobVault), type(uint256).max);
    vm.expectRevert(IVaultController.VaultController_CapReached.selector);
    bobVault.depositERC20(AAVE_ADDRESS, AAVE_CAP + 1);
    vm.stopPrank();
  }

  function testClaimRewardsWhenTheVaultControllerIsChangedInTheClaimer() public {
    // create vault in vaultController A
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // fill claimer with AMPH
    vm.prank(amphToken.owner());
    amphToken.mint(address(amphClaimer), 100 ether);

    // disable vaultController A and enable vaultController B
    vm.startPrank(frank);
    newVaultDeployer = new VaultDeployer(IERC20(CVX_ADDRESS), IERC20(CRV_ADDRESS));
    address[] memory _tokens = new address[](3);
    _tokens[0] = WETH_ADDRESS;
    _tokens[1] = UNI_ADDRESS;
    _tokens[2] = AAVE_ADDRESS;
    newVaultController =
      new VaultController(vaultController, _tokens, amphClaimer, newVaultDeployer, 0.01e18, BOOSTER, 0.005e18);

    vm.stopPrank();

    vm.prank(address(governor));
    usdaToken.removeVaultController(address(vaultController));

    vm.prank(amphClaimer.owner());
    amphClaimer.changeVaultController(address(newVaultController));

    // should receive 0 AMPH
    (uint256 _cvx, uint256 _crv, uint256 _amph) = amphClaimer.claimable(address(bobVault), bobVaultId, 1 ether, 1 ether);
    assertEq(_cvx, 0);
    assertEq(_crv, 0);
    assertEq(_amph, 0);
  }

  function testDepositAndRepayWhenUSDAIsPaused() public {
    // create vault
    gusVaultId = _mintVault(gus);
    gusVault = IVault(vaultController.vaultIdVaultAddress(gusVaultId));

    uint256 _deposit = 1000e8;

    // deposits tokens
    vm.startPrank(gus);
    wbtc.approve(address(gusVault), type(uint256).max);
    gusVault.depositERC20(WBTC_ADDRESS, _deposit);
    vm.stopPrank();

    // borrow
    vm.startPrank(gus);
    vaultController.borrowUSDA(gusVaultId, vaultController.vaultBorrowingPower(gusVaultId) / 4);
    vm.stopPrank();

    // pause USDA
    vm.prank(address(governor));
    usdaToken.pause();

    // more borrow with UDSA should fail
    vm.startPrank(gus);
    uint256 _toBorrow = vaultController.vaultBorrowingPower(gusVaultId) / 4;
    vm.expectRevert('Pausable: paused');
    vaultController.borrowUSDA(gusVaultId, uint192(_toBorrow));
    vm.stopPrank();

    // more borrow with sUSD should fail
    vm.startPrank(gus);
    uint256 _toBorrow2 = vaultController.vaultBorrowingPower(gusVaultId) / 4;
    vm.expectRevert('Pausable: paused');
    vaultController.borrowsUSDto(gusVaultId, uint192(_toBorrow2), gus);
    vm.stopPrank();

    // more deposit should pass
    vm.startPrank(gus);
    gusVault.depositERC20(WBTC_ADDRESS, _deposit);
    vm.stopPrank();

    // mint some USDA
    uint256 _toMint = gusVault.baseLiability() * 2;
    vm.startPrank(address(governor));
    usdaToken.mint(_toMint);
    usdaToken.transfer(gus, _toMint);
    vm.stopPrank();

    // repay debt should pass
    vm.startPrank(gus);
    vaultController.repayAllUSDA(gusVaultId);
    vm.stopPrank();
  }
}
