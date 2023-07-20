// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IAMPHClaimer} from '@interfaces/core/IAMPHClaimer.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IVault} from '@interfaces/core/IVault.sol';

import {AMPHClaimer} from '@contracts/core/AMPHClaimer.sol';

import {DSTestPlus, console} from 'solidity-utils/test/DSTestPlus.sol';

contract AMPHMath is AMPHClaimer {
  constructor() AMPHClaimer(address(0), IERC20(address(0)), IERC20(address(0)), IERC20(address(0)), 0, 0) {}

  function getRate() public pure returns (uint256 _rate) {
    return _getRate(0);
  }

  function totalToFraction(uint256 _total, uint256 _fraction) public pure returns (uint256 _amount) {
    return _totalToFraction(_total, _fraction);
  }
}

abstract contract Base is DSTestPlus {
  IERC20 internal _mockCVX = IERC20(mockContract(newAddress(), 'mockCVX'));
  IERC20 internal _mockCRV = IERC20(mockContract(newAddress(), 'mockCRV'));
  IERC20 internal _mockAMPH = IERC20(mockContract(newAddress(), 'mockAMPH'));
  IVaultController internal _mockVaultController = IVaultController(mockContract(newAddress(), 'mockVaultController'));

  address public deployer = newAddress();
  address public bobVault = newAddress();
  address public bob = newAddress();

  AMPHClaimer public amphClaimer;
  AMPHMath public amphMath;

  uint256 public cvxRewardFee = 0.02e18;
  uint256 public crvRewardFee = 0.01e18;

  function setUp() public virtual {
    // Deploy contract
    vm.prank(deployer);
    amphClaimer =
      new AMPHClaimer(address(_mockVaultController), _mockAMPH, _mockCVX, _mockCRV, cvxRewardFee, crvRewardFee);

    amphMath = new AMPHMath();

    vm.mockCall(
      address(_mockVaultController),
      abi.encodeWithSelector(IVaultController.vaultIdVaultAddress.selector),
      abi.encode(bobVault)
    );
    vm.mockCall(address(_mockCVX), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    vm.mockCall(address(_mockCRV), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    vm.mockCall(address(_mockAMPH), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
  }
}

contract UnitAMPHClaimerConstructor is Base {
  function testDeploy(
    address _vaultController,
    IERC20 _amph,
    IERC20 _cvx,
    IERC20 _crv,
    uint256 _cvxRewardFee,
    uint256 _crvRewardFee
  ) public {
    vm.prank(deployer);
    amphClaimer = new AMPHClaimer(_vaultController, _amph,  _cvx,  _crv, _cvxRewardFee, _crvRewardFee);

    assert(address(amphClaimer.vaultController()) == _vaultController);
    assert(address(amphClaimer.AMPH()) == address(_amph));
    assert(address(amphClaimer.CVX()) == address(_cvx));
    assert(address(amphClaimer.CRV()) == address(_crv));
    assert(amphClaimer.cvxRewardFee() == _cvxRewardFee);
    assert(amphClaimer.crvRewardFee() == _crvRewardFee);
    assert(amphClaimer.owner() == deployer);
    assert(amphClaimer.BASE_SUPPLY_PER_CLIFF() == 8_000_000 * 1e6);
    assert(amphClaimer.TOTAL_CLIFFS() == 1000);
  }
}

contract UnitAMPHClaimerClaimAMPH is Base {
  event ClaimedAmph(address indexed _vaultClaimer, uint256 _cvxAmount, uint256 _crvAmount, uint256 _amphAmount);

  function testClaimAMPHWithInvalidVault(address _caller) public {
    vm.assume(_caller != bobVault);
    vm.prank(_caller);
    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimedAmph) =
      amphClaimer.claimAmph(1, 100 ether, 100 ether, _caller);
    assert(_cvxAmountToSend == 0);
    assert(_crvAmountToSend == 0);
    assert(_claimedAmph == 0);
  }

  function testClaimAMPHEmitEvent(uint256 _cvxAmount, uint256 _crvAmount) public {
    vm.assume(_cvxAmount < 1_000_000_000 ether);
    vm.assume(_crvAmount < 1_000_000_000 ether);

    vm.mockCall(address(_mockAMPH), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(type(uint256).max));
    vm.mockCall(bobVault, abi.encodeWithSelector(IVault.minter.selector), abi.encode(bob));

    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimableAmph) =
      amphClaimer.claimable(address(bobVault), 1, _cvxAmount, _crvAmount);

    vm.expectEmit(true, true, true, true);
    emit ClaimedAmph(bobVault, _cvxAmountToSend, _crvAmountToSend, _claimableAmph);
    vm.prank(bobVault);
    amphClaimer.claimAmph(1, _cvxAmount, _crvAmount, bob);
  }

  function testClaimAMPH(uint256 _cvxAmount, uint256 _crvAmount) public {
    vm.assume(_cvxAmount < 1_000_000_000 ether);
    vm.assume(_crvAmount < 1_000_000_000 ether);

    vm.mockCall(address(_mockAMPH), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(type(uint256).max));
    vm.mockCall(bobVault, abi.encodeWithSelector(IVault.minter.selector), abi.encode(bob));

    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimableAmph) =
      amphClaimer.claimable(address(bobVault), 1, _cvxAmount, _crvAmount);

    uint256 _distributedAmphBefore = amphClaimer.distributedAmph();

    vm.expectCall(
      address(_mockCVX), abi.encodeWithSelector(IERC20.transferFrom.selector, bobVault, deployer, _cvxAmountToSend)
    );
    vm.expectCall(
      address(_mockCRV), abi.encodeWithSelector(IERC20.transferFrom.selector, bobVault, deployer, _crvAmountToSend)
    );
    vm.expectCall(address(_mockAMPH), abi.encodeWithSelector(IERC20.transfer.selector, bob, _claimableAmph));

    vm.prank(bobVault);
    amphClaimer.claimAmph(1, _cvxAmount, _crvAmount, bob);

    if (_crvAmountToSend > 0) assertGt(amphClaimer.distributedAmph(), _distributedAmphBefore);
  }
}

contract UnitAMPHClaimerClaimable is Base {
  function _testClaimable(uint256 _cvxAmount, uint256 _crvAmount, uint256 _expected) internal {
    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimableAmph) =
      amphClaimer.claimable(address(bobVault), 1, _cvxAmount, _crvAmount);
    assertEq(_crvAmountToSend, amphMath.totalToFraction(_crvAmount, crvRewardFee), 'crvAmountToSend');

    if (_crvAmount != 0) {
      assertEq(_cvxAmountToSend, amphMath.totalToFraction(_cvxAmount, cvxRewardFee), 'cvxAmountToSend');
    } else {
      assertEq(_cvxAmountToSend, 0, 'cvxAmountToSend');
    }
    assertEq(_claimableAmph, _expected, 'claimableAmph');
  }

  function testClaimableWithAmountsInZero(uint256 _amphAmount) public {
    vm.assume(_amphAmount > 0);
    vm.mockCall(address(_mockAMPH), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(_amphAmount));

    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimableAmph) =
      amphClaimer.claimable(address(bobVault), 1, 0, 0);

    assert(_cvxAmountToSend == 0);
    assert(_crvAmountToSend == 0);
    assert(_claimableAmph == 0);
  }

  function testClaimableWithAMPHBalanceInZero(uint256 _cvxAmount, uint256 _crvAmount) public {
    vm.assume(_cvxAmount > 0);
    vm.assume(_crvAmount > 0);
    vm.assume(_cvxAmount < 1_000_000_000 ether);
    vm.assume(_crvAmount < 1_000_000_000 ether);
    vm.mockCall(address(_mockAMPH), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));

    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimableAmph) =
      amphClaimer.claimable(address(bobVault), 1, _cvxAmount, _crvAmount);

    assert(_cvxAmountToSend == 0);
    assert(_crvAmountToSend == 0);
    assert(_claimableAmph == 0);
  }

  function testClaimableWithMoreAMPHThanNeeded() public {
    vm.mockCall(address(_mockAMPH), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(type(uint256).max));

    // expected == 2% of 100 + 1% of 100
    _testClaimable(100 ether, 100 ether, 4001 ether);
    _testClaimable(1000 ether, 2000 ether, 80_020 ether);
    _testClaimable(2000 ether, 200 ether, 8002 ether);
    _testClaimable(3000 ether, 4500 ether, 180_045 ether);
    _testClaimable(0 ether, 0 ether, 0 ether);
    _testClaimable(3000 ether, 1_401_000 ether, 56_047_472.948844 ether);
    _testClaimable(0 ether, 1_399_700 ether, 56_001_033.197421 ether);
    _testClaimable(1_083_750 ether, 0 ether, 0 ether);
  }

  function testClaimableWithLessAMPHThanNeeded(uint256 _cvxAmount, uint256 _crvAmount) public {
    vm.assume(_crvAmount > 0);
    vm.assume(_cvxAmount > 0);
    vm.assume(_cvxAmount < 1_000_000_000 ether);
    vm.assume(_crvAmount < 1_000_000_000 ether);

    uint256 _minRate = amphMath.getRate();

    uint256 _crvToSend = amphMath.totalToFraction(_crvAmount, crvRewardFee);
    uint256 _amphToPay = (_crvToSend * _minRate) / 1 ether;
    vm.assume(_amphToPay > 0);
    vm.mockCall(address(_mockAMPH), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(_amphToPay - 1));

    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimableAmph) =
      amphClaimer.claimable(address(bobVault), 1, _cvxAmount, _crvAmount);

    assert(_cvxAmountToSend == 0);
    assert(_crvAmountToSend == 0);
    assert(_claimableAmph == 0);
  }

  function testCliffsAreConsumed() public {
    vm.mockCall(address(_mockAMPH), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(type(uint256).max));

    // Consume all cliffs (999)
    vm.prank(address(bobVault));
    amphClaimer.claimAmph(1, 0, 29_563_120_000 ether, address(this));
    assert((amphClaimer.distributedAmph() / amphClaimer.BASE_SUPPLY_PER_CLIFF()) == amphClaimer.TOTAL_CLIFFS() - 1);

    // It should return 0 AMPH, because it surpass the 1000 cliff
    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimableAmph) =
      amphClaimer.claimable(address(bobVault), 1, 1_000_000_000 ether, 1_000_000_000 ether);

    assert(_cvxAmountToSend == 0);
    assert(_crvAmountToSend == 0);
    assert(_claimableAmph == 0);
  }
}

contract UnitAMPHClaimerGovernanceFunctions is Base {
  event ChangedVaultController(address indexed _newVaultController);
  event ChangedCvxRate(uint256 _newCvxRate);
  event ChangedCrvRate(uint256 _newCrvRate);
  event RecoveredDust(address indexed _token, address _receiver, uint256 _amount);
  event ChangedCvxRewardFee(uint256 _newCvxReward);
  event ChangedCrvRewardFee(uint256 _newCrvReward);

  function testChangeVaultController(address _vaultController) public {
    vm.assume(_vaultController != address(amphClaimer.vaultController()));

    vm.expectEmit(true, true, true, true);
    emit ChangedVaultController(_vaultController);

    vm.prank(deployer);
    amphClaimer.changeVaultController(_vaultController);

    assert(address(amphClaimer.vaultController()) == _vaultController);
  }

  function testChangeVaultControllerRevertOnlyOwner(address _caller) public {
    vm.assume(_caller != deployer);

    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(_caller);
    amphClaimer.changeVaultController(address(0));
  }

  function testRecoverDust(address _token, uint256 _amount) public {
    vm.assume(_token != address(vm));
    vm.assume(_token != deployer);
    vm.assume(_token != address(amphClaimer));

    vm.mockCall(_token, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

    vm.expectEmit(true, true, true, true);
    emit RecoveredDust(_token, deployer, _amount);

    vm.prank(deployer);
    vm.expectCall(_token, abi.encodeWithSelector(IERC20.transfer.selector, deployer, _amount));
    amphClaimer.recoverDust(_token, _amount);
  }

  function testRecoverDustRevertOnlyOwner(address _caller) public {
    vm.assume(_caller != deployer);

    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(_caller);
    amphClaimer.recoverDust(address(0), 0);
  }

  function testChangeCvxRewardFee(uint256 _newFee) public {
    vm.assume(_newFee != amphClaimer.cvxRewardFee());

    vm.expectEmit(true, true, true, true);
    emit ChangedCvxRewardFee(_newFee);

    vm.prank(deployer);
    amphClaimer.changeCvxRewardFee(_newFee);

    assert(amphClaimer.cvxRewardFee() == _newFee);
  }

  function testChangeCvxRewardFeeRevertOnlyOwner(address _caller) public {
    vm.assume(_caller != deployer);

    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(_caller);
    amphClaimer.changeCvxRewardFee(0);
  }

  function testChangeCrvRewardFee(uint256 _newFee) public {
    vm.assume(_newFee != amphClaimer.crvRewardFee());

    vm.expectEmit(true, true, true, true);
    emit ChangedCrvRewardFee(_newFee);

    vm.prank(deployer);
    amphClaimer.changeCrvRewardFee(_newFee);

    assert(amphClaimer.crvRewardFee() == _newFee);
  }

  function testChangeCrvRewardFeeRevertOnlyOwner(address _caller) public {
    vm.assume(_caller != deployer);

    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(_caller);
    amphClaimer.changeCrvRewardFee(0);
  }
}

contract UnitAMPHClaimerConvertFunctions is Base {
  function testTotalToFraction() public {
    assertEq(amphMath.totalToFraction(100 ether, 1e18), 100 ether);
    assertEq(amphMath.totalToFraction(100 ether, 0.5e18), 50 ether);
    assertEq(amphMath.totalToFraction(100 ether, 0.25e18), 25 ether);
    assertEq(amphMath.totalToFraction(100 ether, 0.2e18), 20 ether);
    assertEq(amphMath.totalToFraction(1 ether, 1e18), 1 ether);
    assertEq(amphMath.totalToFraction(100 ether, 0.01e18), 1 ether);
  }
}
