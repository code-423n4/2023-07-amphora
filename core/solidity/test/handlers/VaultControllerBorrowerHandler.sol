// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {VaultController} from '@contracts/core/VaultController.sol';
import {USDA} from '@contracts/core/USDA.sol';
import {BaseHandler} from '@test/handlers/BaseHandler.sol';
import {InvariantVaultController} from '@test/invariant/VaultController.t.sol';

import {IAnchoredViewRelay} from '@interfaces/periphery/IAnchoredViewRelay.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';

import {TestConstants} from '@test/utils/TestConstants.sol';
import {console} from 'solidity-utils/test/DSTestPlus.sol';

/// @notice VaultController handle for borrower actor
/// @dev    In this case the actors are able to call only mintVault/borrow/repay/liquidate
contract VaultControllerBorrowerHandler is BaseHandler, TestConstants {
  uint256 public constant EXP_SCALE = 1 ether;
  VaultController public vaultController;
  InvariantVaultController public invariantContract;
  USDA public usda;

  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_totalVaults;
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_borrowedSum;
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_repaidSum;
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_borrowFeeSum;

  uint256 public balance = 1000 ether;
  uint256 public totalActors = 5;

  IERC20 public susd;

  constructor(VaultController _vaultController, IERC20 _sUSD, USDA _usda, InvariantVaultController _invariantContract) {
    susd = _sUSD;
    vaultController = _vaultController;
    invariantContract = _invariantContract;
    usda = _usda;
    _excludeActor(address(0));

    /// We create 5 actors
    createMultipleActors(totalActors);
    /// Get all the actors addresses
    address[] memory _actors = actors();
    /// Make sure the actors were created correctly
    assertEq(_actors.length, totalActors);

    address _vault;
    /// Fund the actos and create their initial vaults
    for (uint256 _i; _i < totalActors; ++_i) {
      deal(address(susd), _actors[_i], balance);
      vm.startPrank(_actors[_i]);
      _vault = vaultController.mintVault();
      /// Exclude the newly created vault
      invariantContract.excludeContractFromHandler(_vault);
      susd.approve(_vault, type(uint256).max);
      IVault(_vault).depositERC20(address(susd), balance);
      vm.stopPrank();

      ++ghost_totalVaults;
    }
  }

  function callSummary() external view {
    console.log('Call summary VaultControllerBorrowersHandler:');
    console.log('-------------------');
    console.log('mintVault', calls['mintVault']);
    console.log('borrowUSDA', calls['borrowUSDA']);
    console.log('borrowUSDAto', calls['borrowUSDAto']);
    console.log('repayUSDA', calls['repayUSDA']);
    console.log('repayAllUSDA', calls['repayAllUSDA']);
    console.log('-------------------');
    console.log('totalCalls', totalCalls);
  }

  /// TODO: There is an issue when minting a vault contract it includes it in the contracts to run
  function mintVault(uint256 _actorSeed) public useActor(_actorSeed) countCall('mintVault') {
    vm.prank(_currentActor);
    address _vault = vaultController.mintVault();
    invariantContract.excludeContractFromHandler(_vault);
    ++ghost_totalVaults;
  }

  function borrowUSDA(
    uint256 _actorSeed,
    uint256 _vaultIdSeed,
    uint256 _amount
  ) public useActor(_actorSeed) countCall('borrowUSDA') {
    /// Get all the vault ids the wallet has
    uint96[] memory _ids = vaultController.vaultIDs(_currentActor);
    /// Get one random vault
    uint96 _id = _ids[_vaultIdSeed % _ids.length];

    /// Get the oracle
    address _oracle = address(vaultController.tokensOracle(address(susd)));

    /// Can't borrow
    vm.mockCall(_oracle, abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
    uint256 _borrowingPower = vaultController.vaultBorrowingPower(_id);
    uint256 _liability = vaultController.vaultLiability(_id);
    if (_borrowingPower <= _liability) return;
    _amount = bound(_amount, 1, _borrowingPower - _liability);

    /// Mock call the oracle price
    vm.mockCall(_oracle, abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(1 ether));
    /// Borrow
    vm.prank(_currentActor);
    vaultController.borrowUSDA(_id, uint192(_amount));

    uint256 _fee = vaultController.getBorrowingFee(uint192(_amount));
    ghost_borrowFeeSum += _fee;
    ghost_borrowedSum += _amount;
  }

  function borrowUSDAto(
    uint256 _actorSeed,
    uint256 _vaultIdSeed,
    uint256 _amount,
    address _target
  ) public useActor(_actorSeed) countCall('borrowUSDAto') {
    /// Get all the vault ids the wallet has
    uint96[] memory _ids = vaultController.vaultIDs(_currentActor);
    /// Get one random vault
    uint96 _id = _ids[_vaultIdSeed % _ids.length];

    /// Get the oracle
    address _oracle = address(vaultController.tokensOracle(address(susd)));

    /// Can't borrow
    vm.mockCall(_oracle, abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
    uint256 _borrowingPower = vaultController.vaultBorrowingPower(_id);
    uint256 _liability = vaultController.vaultLiability(_id);
    if (_borrowingPower <= _liability) return;
    _amount = bound(_amount, 1, _borrowingPower - _liability);

    /// Mock call the oracle price
    vm.mockCall(_oracle, abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(1 ether));

    /// Borrow
    vm.prank(_currentActor);
    vaultController.borrowUSDAto(_id, uint192(_amount), _target);

    uint256 _fee = vaultController.getBorrowingFee(uint192(_amount));
    ghost_borrowFeeSum += _fee;
    ghost_borrowedSum += _amount;
  }

  function repayUSDA(
    uint256 _actorSeed,
    uint256 _vaultIdSeed,
    uint256 _amount
  ) public useActor(_actorSeed) countCall('repayUSDA') {
    /// Get all the vault ids the wallet has
    uint96[] memory _ids = vaultController.vaultIDs(_currentActor);
    /// Get one random vault
    uint96 _id = _ids[_vaultIdSeed % _ids.length];

    uint256 _vaultLiability = vaultController.vaultLiability(_id);
    if (_vaultLiability == 0) return;
    /// If the user doesn't have enough usda to repay return
    if (usda.balanceOf(_currentActor) < _vaultLiability) return;
    _amount = bound(_amount, 1, _vaultLiability);

    /// Repay
    vm.prank(_currentActor);
    vaultController.repayUSDA(_id, uint192(_amount));

    ghost_repaidSum += _amount;
  }

  function repayAllUSDA(uint256 _actorSeed, uint256 _vaultIdSeed) public useActor(_actorSeed) countCall('repayAllUSDA') {
    /// Get all the vault ids the wallet has
    uint96[] memory _ids = vaultController.vaultIDs(_currentActor);
    /// Get one random vault
    uint96 _id = _ids[_vaultIdSeed % _ids.length];

    uint256 _vaultLiability = vaultController.vaultLiability(_id);
    if (_vaultLiability == 0) return;
    /// If the user doesn't have enough usda to repay return
    if (usda.balanceOf(_currentActor) < _vaultLiability) return;

    /// Repay
    vm.prank(_currentActor);
    vaultController.repayAllUSDA(_id);
    ghost_repaidSum += _vaultLiability;
  }

  /// TODO: Missing liquidate vault function
}
