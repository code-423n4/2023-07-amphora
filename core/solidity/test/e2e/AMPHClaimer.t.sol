// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, IERC20, IVault} from '@test/e2e/Common.sol';
import {AMPHClaimer} from '@contracts/core/AMPHClaimer.sol';

contract AMPHMath is AMPHClaimer {
  constructor() AMPHClaimer(address(0), IERC20(address(0)), IERC20(address(0)), IERC20(address(0)), 0, 0) {}

  function totalToFraction(uint256 _total, uint256 _fraction) public pure returns (uint256 _amount) {
    return _totalToFraction(_total, _fraction);
  }
}

contract E2EAMPHClaimer is CommonE2EBase {
  IERC20 public cvx = IERC20(CVX_ADDRESS);
  IERC20 public crv = IERC20(CRV_ADDRESS);

  AMPHMath internal _amphMath;

  function _testClaimable(uint256 _cvxAmount, uint256 _crvAmount, uint256 _expected, address _receiver) internal {
    uint256 _amphBalanceBefore = amphToken.balanceOf(_receiver);
    vm.startPrank(address(bobVault));
    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimableAmph) =
      amphClaimer.claimAmph(1, _cvxAmount, _crvAmount, _receiver);
    vm.stopPrank();
    uint256 _amphBalanceAfter = amphToken.balanceOf(_receiver);

    assertEq(_crvAmountToSend, _amphMath.totalToFraction(_crvAmount, crvRewardFee), 'crvAmountToSend');

    if (_crvAmount != 0) {
      assertEq(_cvxAmountToSend, _amphMath.totalToFraction(_cvxAmount, cvxRewardFee), 'cvxAmountToSend');
    } else {
      assertEq(_cvxAmountToSend, 0, 'cvxAmountToSend');
    }
    assertEq(_claimableAmph, _expected, 'claimableAmph');
    assertEq(_amphBalanceAfter, _amphBalanceBefore + _expected, 'amphBalanceAfter');
  }

  function setUp() public override {
    super.setUp();

    _amphMath = new AMPHMath();

    // fill with AMPH tokens
    vm.prank(amphToken.owner());
    amphToken.mint(address(amphClaimer), 10_000_000_000 ether);

    // create a vault for bob
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // deal some tokens to bob
    deal(CVX_ADDRESS, address(bobVault), 1 ether);
    deal(CRV_ADDRESS, address(bobVault), 1 ether);

    vm.startPrank(address(bobVault));
    cvx.approve(address(amphClaimer), type(uint256).max);
    crv.approve(address(amphClaimer), type(uint256).max);
    vm.stopPrank();
  }

  function testAMPHClaimer() public {
    // change vault controller
    vm.startPrank(address(governor));
    amphClaimer.changeVaultController(address(2));
    assert(address(amphClaimer.vaultController()) == address(2));
    amphClaimer.changeVaultController(address(vaultController));
    vm.stopPrank();

    // try to claim sending 0 tokens
    (uint256 _cvx0, uint256 _crv0, uint256 _amph0) = amphClaimer.claimable(address(bobVault), bobVaultId, 0, 0);
    assert(_cvx0 == 0);
    assert(_crv0 == 0);
    assert(_amph0 == 0);
    amphClaimer.claimAmph(bobVaultId, 0, 0, bob);
    assert(amphToken.balanceOf(bob) == 0);
    assert(cvx.balanceOf(address(bobVault)) == 1 ether);
    assert(crv.balanceOf(address(bobVault)) == 1 ether);

    // try to claim sending more than 0 tokens
    vm.startPrank(address(bobVault));
    (uint256 _cvx1, uint256 _crv1, uint256 _amph1) =
      amphClaimer.claimable(address(bobVault), bobVaultId, 1 ether, 1 ether);
    assert(_cvx1 > 0);
    assert(_crv1 > 0);
    assert(_amph1 > 0);
    amphClaimer.claimAmph(bobVaultId, 1 ether, 1 ether, bob);
    assert(amphToken.balanceOf(bob) > 0);
    vm.stopPrank();

    // recover dust (empty the pool)
    uint256 _poolAmphBalance = amphToken.balanceOf(address(amphClaimer));
    vm.prank(address(governor));
    amphClaimer.recoverDust(address(amphToken), _poolAmphBalance);
    assert(amphToken.balanceOf(address(amphClaimer)) == 0);

    // try to claim when no tokens in the pool
    vm.startPrank(address(bobVault));
    uint256 _cvxBalanceBefore = cvx.balanceOf(address(bobVault));
    uint256 _crvBalanceBefore = crv.balanceOf(address(bobVault));
    (uint256 _cvx2, uint256 _crv2, uint256 _amph2) =
      amphClaimer.claimable(address(bobVault), bobVaultId, 1 ether, 1 ether);
    assert(_cvx2 == 0);
    assert(_crv2 == 0);
    assert(_amph2 == 0);
    (uint256 _cvxAmountToSend, uint256 _crvAmountToSend, uint256 _claimedAmph) =
      amphClaimer.claimAmph(bobVaultId, 1 ether, 1 ether, bob);
    uint256 _cvxBalanceAfter = cvx.balanceOf(address(bobVault));
    uint256 _crvBalanceAfter = crv.balanceOf(address(bobVault));
    assert(_cvxBalanceBefore == _cvxBalanceAfter);
    assert(_crvBalanceBefore == _crvBalanceAfter);
    assert(_cvxAmountToSend == 0);
    assert(_crvAmountToSend == 0);
    assert(_claimedAmph == 0);
    vm.stopPrank();
  }

  function testAMPHClaimerExactMatch() public {
    // deal more tokens to bob
    deal(CVX_ADDRESS, address(bobVault), 1_000_000_000 ether);
    deal(CRV_ADDRESS, address(bobVault), 1_000_000_000 ether);

    _testClaimable(100 ether, 100 ether, 4001 ether, bob);
    _testClaimable(100 ether, 1 ether, 40.009999 ether, bob);
    _testClaimable(100 ether, 0.1 ether, 4.000999 ether, bob);
    _testClaimable(100 ether, 0.01 ether, 0.400099 ether, bob);
    _testClaimable(100 ether, 0.001 ether, 0.040009 ether, bob);
    _testClaimable(0 ether, 1_000_000 ether, 40_009_599.73294 ether, bob);
    _testClaimable(0 ether, 100_000_000 ether, 597_178_205.494772 ether, bob);
    _testClaimable(100 ether, 1 ether, 3.132842 ether, bob);
    _testClaimable(0 ether, 0 ether, 0 ether, bob);
    _testClaimable(0 ether, 10_000 ether, 31_328.4228 ether, bob);
    /// TODO: add more tests
  }
}
