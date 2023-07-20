// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IUSDA} from '@interfaces/core/IUSDA.sol';
import {TestConstants} from '@test/utils/TestConstants.sol';

contract MintVaultAndDeposit is Script, TestConstants {
  address public user = vm.rememberKey(vm.envUint('USER_PRIVATE_KEY'));
  uint256 public depositAmount = 1 ether;
  /// NOTE: Remember to set this address in the TestConstants.sol
  IVaultController public vaultController = IVaultController(VAULT_CONTROLLER_ADDRESS);
  /// @notice The user's vault
  IVault public vault;
  IERC20 public weth = IERC20(WETH_ADDRESS);

  function run() external {
    vm.startBroadcast(user);
    /// Mint a vault
    vault = IVault(vaultController.mintVault());
    console.log('VAULT: ', address(vault));

    weth.approve(address(vault), depositAmount);
    /// Deposit WETH
    vault.depositERC20(WETH_ADDRESS, depositAmount);
    console.log('WETH BALANCE IN VAULT AFTER DEPOSIT: ', vault.balances(WETH_ADDRESS));
    vm.stopBroadcast();
  }
}

contract Borrow is Script, TestConstants {
  /// NOTE: Remember to set this address in the TestConstants.sol
  IVaultController public vaultController = IVaultController(VAULT_CONTROLLER_ADDRESS);
  IUSDA public usda = IUSDA(USDA_ADDRESS);
  IERC20 public susd = IERC20(SUSD_ADDRESS);
  address public user = vm.rememberKey(vm.envUint('USER_PRIVATE_KEY'));
  uint192 public borrowAmount = 0.5 ether;
  uint96 public vaultId = 1;

  function run() external {
    vm.startBroadcast(user);
    /// Borrow USDA
    vaultController.borrowUSDA(vaultId, borrowAmount);
    console.log('USER USDA BALANCE: ', usda.balanceOf(user));
    vm.stopBroadcast();
  }
}
