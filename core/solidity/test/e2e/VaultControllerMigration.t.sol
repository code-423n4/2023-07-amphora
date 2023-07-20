// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, IERC20} from '@test/e2e/Common.sol';

import {VaultController} from '@contracts/core/VaultController.sol';
import {VaultDeployer} from '@contracts/core/VaultDeployer.sol';
import {IVaultDeployer} from '@interfaces/core/IVaultDeployer.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IRoles} from '@interfaces/utils/IRoles.sol';
import {IAMPHClaimer} from '@interfaces/core/IAMPHClaimer.sol';
import {IVaultDeployer} from '@interfaces/core/IVaultDeployer.sol';

contract E2EVaultControllerMigration is CommonE2EBase {
  VaultController public newVaultController;
  VaultDeployer public newVaultDeployer;

  function setUp() public override {
    super.setUp();

    // deposits sUSD
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(susd.balanceOf(dave));
    vm.stopPrank();
  }

  function testMigrateVaultController() public {
    newVaultDeployer = new VaultDeployer(IERC20(CVX_ADDRESS), IERC20(CRV_ADDRESS));

    // deploy new vault manager
    vm.startPrank(frank);
    address[] memory _tokens = new address[](3);
    _tokens[0] = WETH_ADDRESS;
    _tokens[1] = UNI_ADDRESS;
    _tokens[2] = AAVE_ADDRESS;
    newVaultController =
      new VaultController(vaultController, _tokens, amphClaimer, newVaultDeployer, 0.01e18, BOOSTER, 0.005e18);
    label(address(newVaultController), 'newVaultController');

    newVaultController.transferOwnership(address(governor));
    vm.stopPrank();

    // register USDA and curve master
    vm.startPrank(address(governor));
    newVaultController.registerUSDA(address(usdaToken));
    newVaultController.registerCurveMaster(address(curveMaster));
    vm.stopPrank();

    // should be able to mint and deposit, but borrow will revert
    vm.startPrank(bob);
    newVaultController.mintVault();
    bobVaultId = newVaultController.vaultsMinted();
    bobVault = IVault(newVaultController.vaultIdVaultAddress(uint96(bobVaultId)));

    weth.approve(address(bobVault), type(uint256).max);
    bobVault.depositERC20(WETH_ADDRESS, weth.balanceOf(bob));

    vm.expectRevert(
      abi.encodeWithSelector(
        IRoles.Roles_Unauthorized.selector, address(newVaultController), usdaToken.VAULT_CONTROLLER_ROLE()
      )
    );
    newVaultController.borrowUSDA(uint96(bobVaultId), 1);
    vm.stopPrank();

    // add the new vault manager as USDA minter
    vm.startPrank(address(governor));
    usdaToken.addVaultController(address(newVaultController));
    vm.stopPrank();

    // old vault manager should still work fine (users can borrow and get liquidated)
    carolVaultId = _mintVault(carol);
    carolVault = IVault(vaultController.vaultIdVaultAddress(uint96(carolVaultId)));

    vm.startPrank(carol);
    uni.approve(address(carolVault), type(uint256).max);
    carolVault.depositERC20(UNI_ADDRESS, uni.balanceOf(carol));
    vaultController.borrowUSDA(uint96(carolVaultId), vaultController.vaultBorrowingPower(uint96(carolVaultId)));

    vm.warp(block.timestamp + 2 weeks);
    vaultController.calculateInterest();

    assert(vaultController.checkVault(uint96(carolVaultId)) == false);
    vm.stopPrank();

    // users now should be able to borrowUSDA() / borrowsUSD() in the new vault controller
    vm.startPrank(bob);
    newVaultController.borrowUSDA(uint96(bobVaultId), newVaultController.vaultBorrowingPower(uint96(bobVaultId)));
    vm.stopPrank();

    // vaults in new vault controller can be liquidated and can repay
    vm.startPrank(bob);
    newVaultController.repayUSDA(uint96(bobVaultId), 1);
    vm.stopPrank();

    vm.warp(block.timestamp + 2 weeks);
    newVaultController.calculateInterest();

    vm.startPrank(dave);
    newVaultController.liquidateVault(
      uint96(bobVaultId), WETH_ADDRESS, newVaultController.tokensToLiquidate(uint96(bobVaultId), WETH_ADDRESS)
    );
    vm.stopPrank();

    // when a user deposits or withdraw from USDA contract, interest should accumulate in both controllers
    (, uint192 _oldControllerInterestBefore) = vaultController.interest();
    (, uint192 _newControllerInterestBefore) = newVaultController.interest();

    vm.warp(block.timestamp + 1 days);
    vm.prank(dave);
    usdaToken.withdraw(1 ether);

    (, uint192 _oldControllerInterestAfter) = vaultController.interest();
    (, uint192 _newControllerInterestAfter) = newVaultController.interest();

    assert(_oldControllerInterestBefore < _oldControllerInterestAfter);
    assert(_newControllerInterestBefore < _newControllerInterestAfter);

    // if we remove the old vault controller calling removeVaultControllerFromList(), everything should still work but not accumulate interest
    vm.startPrank(address(governor));
    usdaToken.removeVaultControllerFromList(address(vaultController));
    vm.stopPrank();

    vm.startPrank(carol);
    vaultController.repayUSDA(uint96(carolVaultId), uint192(usdaToken.balanceOf(carol) / 2));
    vm.stopPrank();

    (, _oldControllerInterestBefore) = vaultController.interest();
    (, _newControllerInterestBefore) = newVaultController.interest();

    vm.warp(block.timestamp + 1 days);
    vm.prank(dave);
    usdaToken.withdraw(1 ether);

    (, _oldControllerInterestAfter) = vaultController.interest();
    (, _newControllerInterestAfter) = newVaultController.interest();

    assert(_oldControllerInterestBefore == _oldControllerInterestAfter);
    assert(_newControllerInterestBefore < _newControllerInterestAfter);

    // if we call removeVaultController() on old vault controller users shouldn't be able to borrow() / repay()
    vm.startPrank(address(governor));
    usdaToken.removeVaultController(address(vaultController));
    vm.stopPrank();

    vm.startPrank(carol);
    uint192 _toRepay = uint192(usdaToken.balanceOf(carol));
    vm.expectRevert(
      abi.encodeWithSelector(
        IRoles.Roles_Unauthorized.selector, address(vaultController), usdaToken.VAULT_CONTROLLER_ROLE()
      )
    );
    vaultController.repayUSDA(uint96(carolVaultId), _toRepay);
    vm.stopPrank();
  }
}
