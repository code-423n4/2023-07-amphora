// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {VaultDeployer} from '@contracts/core/VaultDeployer.sol';
import {IVaultDeployer} from '@interfaces/core/IVaultDeployer.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';

import {DSTestPlus} from 'solidity-utils/test/DSTestPlus.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

abstract contract Base is DSTestPlus {
  IVaultController public mockVaultController = IVaultController(mockContract('mockVaultController'));
  VaultDeployer public vaultDeployer;
  IERC20 public cvx = IERC20(mockContract(newAddress(), 'cvx'));
  IERC20 public crv = IERC20(mockContract(newAddress(), 'crv'));

  function setUp() public virtual {
    vm.prank(address(mockVaultController));
    vaultDeployer = new VaultDeployer(cvx, crv);
  }
}

contract UnitVaultDeployerDeployVault is Base {
  function testDeployVault(uint96 _id, address _owner) public {
    vm.assume(_id > 1);
    vm.prank(address(mockVaultController));
    IVault _vault = vaultDeployer.deployVault(_id, _owner);

    assertEq(address(_vault.CONTROLLER()), address(mockVaultController));
    assertEq(_vault.id(), _id);
    assertEq(_vault.minter(), _owner);
    assertEq(address(_vault.CRV()), address(crv));
    assertEq(address(_vault.CVX()), address(cvx));
  }
}
