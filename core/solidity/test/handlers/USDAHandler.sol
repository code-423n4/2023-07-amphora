// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {USDA} from '@contracts/core/USDA.sol';
import {BaseHandler, MockSUSD} from '@test/handlers/BaseHandler.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {console} from 'solidity-utils/test/DSTestPlus.sol';

contract USDAHandler is BaseHandler {
  USDA public usda;
  IERC20 public susd;

  uint256 public sUSDTotalSupply = 45_000_000;

  address public vaultController;

  uint256 public initialFragmentsSupply;

  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_depositSum;
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_withdrawSum;

  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_mintedSum;
  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_burnedSum;

  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_donatedSum;

  // solhint-disable-next-line defi-wonderland/wonder-var-name-mixedcase
  uint256 public ghost_susdTransferredSum;

  address public owner;

  constructor(USDA _usda, IERC20 _sUSD) {
    usda = _usda;
    susd = _sUSD;

    // save initial supply
    initialFragmentsSupply = usda.totalSupply();

    owner = usda.owner();

    // exclude owner from set because it breaks the invariant when mint and withdraw (basic rug)
    _excludeActor(owner);
    _excludeActor(address(0));
    _excludeActor(address(usda));

    // set vault controller
    vaultController = newAddress();

    vm.startPrank(owner);
    usda.addVaultController(vaultController);
    usda.removeVaultControllerFromList(vaultController); // NOTE: doing this to prevent a revert when paying interest
    vm.stopPrank();
  }

  function callSummary() external view {
    console.log('Call summary:');
    console.log('-------------------');
    console.log('deposit', calls['deposit']);
    console.log('depositTo', calls['depositTo']);
    console.log('withdraw', calls['withdraw']);
    console.log('withdrawTo', calls['withdrawTo']);
    console.log('withdrawAll', calls['withdrawAll']);
    console.log('withdrawAllTo', calls['withdrawAllTo']);
    console.log('mint', calls['mint']);
    console.log('burn', calls['burn']);
    console.log('donate', calls['donate']);
    console.log('recoverDust', calls['recoverDust']);
    console.log('vaultControllerMint', calls['vaultControllerMint']);
    console.log('vaultControllerBurn', calls['vaultControllerBurn']);
    console.log('vaultControllerTransfer', calls['vaultControllerTransfer']);
    console.log('-------------------');
    console.log('totalCalls', totalCalls);
  }

  function deposit(uint256 _susdAmount) public createActor countCall('deposit') {
    _susdAmount = bound(_susdAmount, 1, sUSDTotalSupply);

    deal(address(susd), _currentActor, _susdAmount);
    vm.prank(_currentActor);
    susd.approve(address(usda), _susdAmount);
    vm.prank(_currentActor);
    usda.deposit(_susdAmount);

    ghost_depositSum += _susdAmount;
  }

  function depositTo(uint256 _receiverSeed, uint256 _susdAmount) public createActor countCall('depositTo') {
    _susdAmount = bound(_susdAmount, 1, sUSDTotalSupply);

    deal(address(susd), _currentActor, _susdAmount);
    vm.prank(_currentActor);
    susd.approve(address(usda), _susdAmount);
    vm.prank(_currentActor);
    usda.depositTo(_susdAmount, getRandomActor(_receiverSeed));

    ghost_depositSum += _susdAmount;
  }

  function withdraw(uint256 _actorSeed, uint256 _susdAmount) public useActor(_actorSeed) countCall('withdraw') {
    uint256 _min = usda.balanceOf(_currentActor) > susd.balanceOf(address(usda))
      ? susd.balanceOf(address(usda))
      : usda.balanceOf(_currentActor);
    _susdAmount = _boundWithCheck(_susdAmount, 1, _min);

    if (_susdAmount == 0) return;
    vm.prank(_currentActor);
    usda.withdraw(_susdAmount);

    ghost_withdrawSum += _susdAmount;
  }

  function withdrawTo(
    uint256 _actorSeed,
    uint256 _receiverSeed,
    uint256 _susdAmount
  ) public useActor(_actorSeed) countCall('withdrawTo') {
    uint256 _min = usda.balanceOf(_currentActor) > susd.balanceOf(address(usda))
      ? susd.balanceOf(address(usda))
      : usda.balanceOf(_currentActor);
    _susdAmount = _boundWithCheck(_susdAmount, 1, _min);

    if (_susdAmount == 0) return;
    vm.prank(_currentActor);
    usda.withdrawTo(_susdAmount, getRandomActor(_receiverSeed));

    ghost_withdrawSum += _susdAmount;
  }

  function withdrawAll(uint256 _actorSeed) public useActor(_actorSeed) countCall('withdrawAll') {
    uint256 _balance = usda.balanceOf(_currentActor);
    uint256 _reserve = susd.balanceOf(address(usda));

    if (_balance == 0 || _reserve == 0) return;
    uint256 _balanceBefore = susd.balanceOf(address(usda));
    vm.prank(_currentActor);
    usda.withdrawAll();
    uint256 _balanceAfter = susd.balanceOf(address(usda));

    ghost_withdrawSum += (_balanceBefore - _balanceAfter);
  }

  function withdrawAllTo(
    uint256 _actorSeed,
    uint256 _receiverSeed
  ) public useActor(_actorSeed) countCall('withdrawAllTo') {
    uint256 _balance = usda.balanceOf(_currentActor);
    uint256 _reserve = susd.balanceOf(address(usda));

    if (_balance == 0 || _reserve == 0) return;
    uint256 _balanceBefore = susd.balanceOf(address(usda));
    vm.prank(_currentActor);
    usda.withdrawAllTo(getRandomActor(_receiverSeed));
    uint256 _balanceAfter = susd.balanceOf(address(usda));

    ghost_withdrawSum += (_balanceBefore - _balanceAfter);
  }

  function mint(uint256 _amount) public countCall('mint') {
    if (_amount == 0 || _amount > sUSDTotalSupply) return;
    vm.prank(owner);
    usda.mint(_amount);

    ghost_mintedSum += _amount;
  }

  function burn(uint256 _amount) public countCall('burn') {
    _amount = _boundWithCheck(_amount, 1, usda.balanceOf(owner));

    if (_amount == 0) return;
    vm.prank(owner);
    usda.burn(_amount);

    ghost_burnedSum += _amount;
  }

  function donate(uint256 _susdAmount) public createActor countCall('donate') {
    _susdAmount = bound(_susdAmount, 1, sUSDTotalSupply);

    deal(address(susd), _currentActor, _susdAmount);
    vm.prank(_currentActor);
    susd.approve(address(usda), _susdAmount);
    vm.prank(_currentActor);
    usda.donate(_susdAmount);

    ghost_donatedSum += _susdAmount;
  }

  function recoverDust() public countCall('recoverDust') {
    vm.prank(owner);
    usda.recoverDust(owner);
  }

  function vaultControllerMint(uint256 _amount) public countCall('vaultControllerMint') {
    if (_amount > sUSDTotalSupply) return;

    vm.prank(vaultController);
    usda.vaultControllerMint(owner, _amount);

    ghost_mintedSum += _amount;
  }

  function vaultControllerBurn(uint256 _amount) public countCall('vaultControllerBurn') {
    _amount = _boundWithCheck(_amount, 1, usda.balanceOf(owner));

    if (_amount == 0) return;
    vm.prank(vaultController);
    usda.vaultControllerBurn(owner, _amount);

    ghost_burnedSum += _amount;
  }

  function vaultControllerTransfer(uint256 _amount) public countCall('vaultControllerTransfer') {
    _amount = bound(_amount, 0, susd.balanceOf(address(usda)));

    vm.prank(vaultController);
    usda.vaultControllerTransfer(owner, _amount);

    ghost_susdTransferredSum += _amount;
  }
}
