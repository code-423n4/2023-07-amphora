// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {VaultController} from '@contracts/core/VaultController.sol';
import {USDA} from '@contracts/core/USDA.sol';
import {BaseHandler} from '@test/handlers/BaseHandler.sol';
import {InvariantVaultController} from '@test/invariant/VaultController.t.sol';

import {IAnchoredViewRelay} from '@interfaces/periphery/IAnchoredViewRelay.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';

import {TestConstants} from '@test/utils/TestConstants.sol';
import {console} from 'solidity-utils/test/DSTestPlus.sol';
import {IERC20Metadata, IERC20} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

/// @notice VaultController handle for owner actor
/// @dev    In this case the actor is able to call any function of the VaultController
contract VaultControllerOwnerHandler is BaseHandler, TestConstants {
  uint256 public constant EXP_SCALE = 1 ether;
  VaultController public vaultController;
  InvariantVaultController public invariantContract;
  USDA public usda;

  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_totalVaults;
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_totalCollateral;
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_borrowedSum;
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_repaidSum;
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_borrowFeeSum;

  address public owner;
  uint256 public ownerBalance = 1000 ether;

  IERC20 public susd;
  address[] public registeredTokens;
  mapping(address => address) public tokenOracle;

  uint160 public tokenId = 10;

  constructor(VaultController _vaultController, IERC20 _sUSD, USDA _usda, InvariantVaultController _invariantContract) {
    susd = _sUSD;
    vaultController = _vaultController;
    invariantContract = _invariantContract;
    owner = vaultController.owner();
    usda = _usda;
    _excludeActor(address(0));

    registeredTokens.push(address(susd));
    /// Fund owner with some usd for his vault
    deal(address(susd), owner, ownerBalance);

    vm.startPrank(owner);
    address _ownerVault = vaultController.mintVault();
    /// Exclude the newly created vault
    invariantContract.excludeContractFromHandler(_ownerVault);
    /// Deposit to the vault
    susd.approve(_ownerVault, type(uint256).max);
    IVault(_ownerVault).depositERC20(address(susd), ownerBalance);
    vm.stopPrank();

    ++ghost_totalVaults;
  }

  function callSummary() external view {
    console.log('Call summary VaultControllerOwnerHandler:');
    console.log('-------------------');
    console.log('mintVault', calls['mintVault']);
    console.log('registerErc20', calls['registerErc20']);
    console.log('updateRegisteredErc20', calls['updateRegisteredErc20']);
    console.log('borrowUSDA', calls['borrowUSDA']);
    console.log('borrowUSDAto', calls['borrowUSDAto']);
    console.log('repayUSDA', calls['repayUSDA']);
    console.log('repayAllUSDA', calls['repayAllUSDA']);
    console.log('-------------------');
    console.log('totalCalls', totalCalls);
  }

  /// TODO: There is an issue when minting a vault contract it includes it in the contracts to run
  function mintVault() public countCall('mintVault') {
    vm.prank(owner);
    address _vault = vaultController.mintVault();
    invariantContract.excludeContractFromHandler(_vault);
    ++ghost_totalVaults;
  }

  function registerErc20(
    uint256 _ltv,
    address _oracleAddress,
    uint256 _liquidationIncentive,
    uint256 _cap
  ) public countCall('registerErc20') {
    /// Bound liquidationIncentive from 1-99%
    /// ltv shouldn't be equal or higher than EXP_SCALE - liquidationIncentive
    address _tokenAddress = address(++tokenId);
    _liquidationIncentive = bound(_liquidationIncentive, 1, 99) * 0.01 ether;
    _ltv = bound(_ltv, 1, EXP_SCALE - _liquidationIncentive - 1);

    mockContract(_tokenAddress, 'token');
    vm.mockCall(_tokenAddress, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
    if (_oracleAddress == address(0)) return;

    /// For now we assume for single collateral
    uint256 _poolId = 0;

    /// Makes sure the same token isn't getting registered
    address[] memory _registeredTokens = vaultController.getEnabledTokens();
    for (uint256 _i; _i < _registeredTokens.length; ++_i) {
      if (_registeredTokens[_i] == _tokenAddress) return;
    }

    /// Save the oracle address
    tokenOracle[_tokenAddress] = _oracleAddress;

    vm.prank(owner);
    vaultController.registerErc20(_tokenAddress, _ltv, _oracleAddress, _liquidationIncentive, _cap, _poolId);
    registeredTokens.push(_tokenAddress);
    ++ghost_totalCollateral;
  }

  function updateRegisteredErc20(
    uint256 _tokenAddressSeed,
    uint256 _ltv,
    address _oracleAddress,
    uint256 _liquidationIncentive,
    uint256 _cap
  ) public countCall('updateRegisteredErc20') {
    /// Bound liquidationIncentive from 1-99%
    /// ltv shouldn't be equal or higher than EXP_SCALE - liquidationIncentive
    _liquidationIncentive = bound(_liquidationIncentive, 1, 99) * 0.01 ether;
    _ltv = bound(_ltv, 1, EXP_SCALE - _liquidationIncentive - 1);

    if (_oracleAddress == address(0)) return;

    /// Get random token address from the already registered tokens
    address _tokenAddress = registeredTokens[_tokenAddressSeed % registeredTokens.length];
    /// For now we assume for single collateral
    uint256 _poolId = 0;

    /// Update the oracle address
    tokenOracle[_tokenAddress] = _oracleAddress;

    vm.prank(owner);
    vaultController.updateRegisteredErc20(_tokenAddress, _ltv, _oracleAddress, _liquidationIncentive, _cap, _poolId);
  }

  function borrowUSDA(uint256 _vaultIdSeed, uint256 _amount) public countCall('borrowUSDA') {
    /// Get all the vault ids the wallet has
    uint96[] memory _ids = vaultController.vaultIDs(owner);
    /// Get one random vault
    uint96 _id = _ids[_vaultIdSeed % _ids.length];

    /// If oracle is address(0) then it means it hasn't been updated so just use the original one
    address _oracle = tokenOracle[address(susd)] == address(0)
      ? address(invariantContract.anchoredViewEth())
      : tokenOracle[address(susd)];

    /// Can't borrow
    vm.mockCall(_oracle, abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
    uint256 _borrowingPower = vaultController.vaultBorrowingPower(_id);
    uint256 _liability = vaultController.vaultLiability(_id);
    if (_borrowingPower <= _liability) return;
    _amount = bound(_amount, 1, _borrowingPower - _liability);

    /// Mock call the oracle price
    vm.mockCall(_oracle, abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(1 ether));
    /// Borrow
    vm.prank(owner);
    vaultController.borrowUSDA(_id, uint192(_amount));

    uint256 _fee = vaultController.getBorrowingFee(uint192(_amount));
    ghost_borrowFeeSum += _fee;
    ghost_borrowedSum += _amount;
  }

  function borrowUSDAto(uint256 _vaultIdSeed, uint256 _amount, address _target) public countCall('borrowUSDAto') {
    /// Get all the vault ids the wallet has
    uint96[] memory _ids = vaultController.vaultIDs(owner);
    /// Get one random vault
    uint96 _id = _ids[_vaultIdSeed % _ids.length];

    /// If oracle is address(0) then it means it hasn't been updated so just use the original one
    address _oracle = tokenOracle[address(susd)] == address(0)
      ? address(invariantContract.anchoredViewEth())
      : tokenOracle[address(susd)];

    /// Can't borrow
    vm.mockCall(_oracle, abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
    uint256 _borrowingPower = vaultController.vaultBorrowingPower(_id);
    uint256 _liability = vaultController.vaultLiability(_id);
    if (_borrowingPower <= _liability) return;
    _amount = bound(_amount, 1, _borrowingPower - _liability);

    /// Mock call the oracle price
    vm.mockCall(_oracle, abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(1 ether));

    /// Borrow
    vm.prank(owner);
    vaultController.borrowUSDAto(_id, uint192(_amount), _target);

    uint256 _fee = vaultController.getBorrowingFee(uint192(_amount));
    ghost_borrowFeeSum += _fee;
    ghost_borrowedSum += _amount;
  }

  function repayUSDA(uint256 _vaultIdSeed, uint256 _amount) public countCall('repayUSDA') {
    /// Get all the vault ids the wallet has
    uint96[] memory _ids = vaultController.vaultIDs(owner);
    /// Get one random vault
    uint96 _id = _ids[_vaultIdSeed % _ids.length];

    uint256 _vaultLiability = vaultController.vaultLiability(_id);
    if (_vaultLiability == 0) return;
    /// If the user doesn't have enough usda to repay return
    if (usda.balanceOf(owner) < _vaultLiability) return;
    _amount = bound(_amount, 1, _vaultLiability);

    /// Repay
    vm.prank(owner);
    vaultController.repayUSDA(_id, uint192(_amount));

    ghost_repaidSum += _amount;
  }

  function repayAllUSDA(uint256 _vaultIdSeed) public countCall('repayAllUSDA') {
    /// Get all the vault ids the wallet has
    uint96[] memory _ids = vaultController.vaultIDs(owner);
    /// Get one random vault
    uint96 _id = _ids[_vaultIdSeed % _ids.length];

    uint256 _vaultLiability = vaultController.vaultLiability(_id);
    if (_vaultLiability == 0) return;
    /// If the user doesn't have enough usda to repay return
    if (usda.balanceOf(owner) < _vaultLiability) return;

    /// Repay
    vm.prank(owner);
    vaultController.repayAllUSDA(_id);
    ghost_repaidSum += _vaultLiability;
  }

  /// TODO: Missing liquidate vault function
}
