// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {TestConstants} from '@test/utils/TestConstants.sol';

contract RegisterToken is Script, TestConstants {
  /// Use the correct private key based on the network you run the script
  /// This should be the same as that was used to deploy the contracts
  address public deployer = vm.rememberKey(vm.envUint('DEPLOYER_ANVIL_LOCAL_PRIVATE_KEY'));
  /// TODO: Change to corrrect address
  IVaultController public vaultController = IVaultController(VAULT_CONTROLLER_ADDRESS);
  /// The address of the token to register
  address public tokenAddress = 0x9fC689CCaDa600B6DF723D9E47D84d76664a1F23;
  /// The pool id of the token (if not crv lp token then set to 0)
  uint256 public poolId = 1;

  function run() external {
    vm.startBroadcast(deployer);
    /// Not available for borrowing since the oracle is not set for now
    /// To find the poolId of a specifil lp token check more details here: https://linear.app/defi-wonderland/issue/AMP-26#comment-fe3ec6f2
    vaultController.registerErc20(tokenAddress, 0, address(0), LIQUIDATION_INCENTIVE, type(uint256).max, poolId);
    console.log('Successfully registered token: ', tokenAddress);
    vm.stopBroadcast();
  }
}
