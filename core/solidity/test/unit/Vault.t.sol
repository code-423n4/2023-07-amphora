// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';

import {Vault} from '@contracts/core/Vault.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IBooster} from '@interfaces/utils/IBooster.sol';
import {IBaseRewardPool} from '@interfaces/utils/IBaseRewardPool.sol';
import {IVirtualBalanceRewardPool} from '@interfaces/utils/IVirtualBalanceRewardPool.sol';
import {IAMPHClaimer} from '@interfaces/core/IAMPHClaimer.sol';
import {IAmphoraProtocolToken} from '@interfaces/governance/IAmphoraProtocolToken.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';

import {DSTestPlus} from 'solidity-utils/test/DSTestPlus.sol';
import {TestConstants} from '@test/utils/TestConstants.sol';
import {ICVX} from '@interfaces/utils/ICVX.sol';

abstract contract Base is DSTestPlus, TestConstants {
  IERC20 internal _mockToken = IERC20(mockContract(newAddress(), 'mockToken'));
  IVaultController public mockVaultController = IVaultController(mockContract(newAddress(), 'mockVaultController'));
  IAMPHClaimer public mockAmphClaimer = IAMPHClaimer(mockContract(newAddress(), 'mockAmphClaimer'));
  IAmphoraProtocolToken public mockAmphToken = IAmphoraProtocolToken(mockContract(newAddress(), 'mockAmphToken'));
  IERC20 public cvx = IERC20(mockContract(newAddress(), 'cvx'));
  IERC20 public crv = IERC20(mockContract(newAddress(), 'crv'));

  uint256 public cvxTotalSupply = 1000 ether;
  uint256 public cvxMaxSupply = 2000 ether;
  uint256 public cvxTotalCliffs = 1000;
  uint256 public cvxReductionPerCliff = 10 ether;

  Vault public vault;
  address public vaultOwner = label(newAddress(), 'vaultOwner');

  function setUp() public virtual {
    vm.mockCall(address(_mockToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    // solhint-disable-next-line reentrancy
    vault = new Vault(1, vaultOwner, address(mockVaultController), cvx, crv);

    vm.mockCall(address(cvx), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(cvxTotalSupply));
    vm.mockCall(address(cvx), abi.encodeWithSelector(ICVX.maxSupply.selector), abi.encode(cvxMaxSupply));
    vm.mockCall(address(cvx), abi.encodeWithSelector(ICVX.totalCliffs.selector), abi.encode(cvxTotalCliffs));
    vm.mockCall(address(cvx), abi.encodeWithSelector(ICVX.reductionPerCliff.selector), abi.encode(cvxReductionPerCliff));
  }

  function depositCurveLpTokenMockCalls(
    uint256 _amount,
    address _token,
    uint256 _poolId,
    IVaultController.CollateralType _type
  ) public {
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.tokenId.selector, _token), abi.encode(1)
    );

    vm.mockCall(_token, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(_type)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, _token),
      abi.encode(_poolId)
    );

    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.BOOSTER.selector), abi.encode(BOOSTER)
    );
    vm.mockCall(_token, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(true));
    vm.prank(vaultOwner);
    vault.depositERC20(_token, _amount);
  }
}

contract UnitVaultGetters is Base {
  function testConstructor() public {
    assertEq(vault.minter(), vaultOwner);
    assertEq(vault.id(), 1);
    assertEq(address(vault.CONTROLLER()), address(mockVaultController));
  }

  function testTokenBalance(uint256 _amount) public {
    vm.assume(_amount > 0);
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(_mockToken)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.Single)
    );

    vm.prank(vaultOwner);
    vault.depositERC20(address(_mockToken), _amount);

    assertEq(vault.balances(address(_mockToken)), _amount);
  }

  function testCRV() public {
    assertEq(address(vault.CRV()), address(crv));
  }

  function testCVX() public {
    assertEq(address(vault.CVX()), address(cvx));
  }
}

contract UnitVaultDepositERC20 is Base {
  event Deposit(address _token, uint256 _amount);

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(_mockToken)),
      abi.encode(1)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.modifyTotalDeposited.selector, address(_mockToken)),
      abi.encode(1)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.Single)
    );
  }

  function testRevertIfNotVaultOwner(address _token, uint256 _amount) public {
    vm.assume(_token != address(vm));
    vm.expectRevert(IVault.Vault_NotMinter.selector);
    vm.prank(newAddress());
    vault.depositERC20(_token, _amount);
  }

  function testRevertIfTokenNotRegistered(address _token, uint256 _amount) public {
    vm.assume(_token != address(vm));
    vm.expectRevert(IVault.Vault_TokenNotRegistered.selector);
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(_token)),
      abi.encode(0)
    );
    vm.prank(vaultOwner);
    vault.depositERC20(_token, _amount);
  }

  function testRevertIfAmountZero() public {
    vm.expectRevert(IVault.Vault_AmountZero.selector);
    vm.prank(vaultOwner);
    vault.depositERC20(address(_mockToken), 0);
  }

  function testRevertIfStakeOnConvexFails(uint256 _amount) public {
    vm.assume(_amount > 0);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_mockToken)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.BOOSTER.selector), abi.encode(BOOSTER)
    );
    vm.mockCall(address(_mockToken), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(false));
    vm.expectRevert(IVault.Vault_DepositAndStakeOnConvexFailed.selector);

    vm.prank(vaultOwner);
    vault.depositERC20(address(_mockToken), _amount);
  }

  function testRevertIfStakeOnConvexOnAlreadyStakedTokenFails(uint256 _amount) public {
    vm.assume(_amount > 0 && _amount < type(uint256).max / 2);

    depositCurveLpTokenMockCalls(_amount, address(_mockToken), 1, IVaultController.CollateralType.CurveLPStakedOnConvex);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_mockToken)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.BOOSTER.selector), abi.encode(BOOSTER)
    );
    vm.mockCall(address(_mockToken), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(false));
    vm.expectRevert(IVault.Vault_DepositAndStakeOnConvexFailed.selector);

    vm.prank(vaultOwner);
    vault.depositERC20(address(_mockToken), _amount);
  }

  function testExpectCallDepositOnConvex(uint256 _amount) public {
    vm.assume(_amount > 0);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_mockToken)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.BOOSTER.selector), abi.encode(BOOSTER)
    );
    vm.mockCall(address(_mockToken), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(true));

    vm.expectCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector, 1, _amount, true));
    vm.prank(vaultOwner);
    vault.depositERC20(address(_mockToken), _amount);
  }

  function testModifyTotalDepositedIsCalled(uint256 _amount) public {
    vm.assume(_amount > 0);

    vm.prank(vaultOwner);
    vm.expectCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.modifyTotalDeposited.selector, 1, _amount, address(_mockToken), true)
    );
    vault.depositERC20(address(_mockToken), _amount);
  }

  function testDepositERC20(uint256 _amount) public {
    vm.assume(_amount > 0);
    vm.expectEmit(false, false, false, true);
    emit Deposit(address(_mockToken), _amount);
    vm.prank(vaultOwner);
    vault.depositERC20(address(_mockToken), _amount);
    assertEq(vault.balances(address(_mockToken)), _amount);
  }

  function testDepositTokenAlreadyStaked(uint256 _amount) public {
    vm.assume(_amount > 0 && _amount < type(uint256).max / 2);

    depositCurveLpTokenMockCalls(_amount, address(_mockToken), 1, IVaultController.CollateralType.CurveLPStakedOnConvex);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_mockToken)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.BOOSTER.selector), abi.encode(BOOSTER)
    );
    vm.mockCall(address(_mockToken), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(true));

    vm.expectCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector, 1, _amount, true));
    vm.prank(vaultOwner);
    vault.depositERC20(address(_mockToken), _amount);

    assertEq(vault.balances(address(_mockToken)), _amount * 2);
  }
}

contract UnitVaultWithdrawERC20 is Base {
  event Withdraw(address _token, uint256 _amount);

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(_mockToken)),
      abi.encode(1)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.Single)
    );

    vm.prank(vaultOwner);
    vault.depositERC20(address(_mockToken), 1 ether);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(_mockToken)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.checkVault.selector, 1), abi.encode(true)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.modifyTotalDeposited.selector, address(_mockToken)),
      abi.encode(1)
    );
  }

  function testRevertIfNotVaultOwner(address _token, uint256 _amount) public {
    vm.assume(_token != address(vm));
    vm.expectRevert(IVault.Vault_NotMinter.selector);
    vm.prank(newAddress());
    vault.withdrawERC20(_token, _amount);
  }

  function testRevertIfTokenNotRegistered(address _token, uint256 _amount) public {
    vm.assume(_token != address(vm));
    vm.expectRevert(IVault.Vault_TokenNotRegistered.selector);
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(_token)),
      abi.encode(0)
    );
    vm.prank(vaultOwner);
    vault.withdrawERC20(_token, _amount);
  }

  function testRevertIfOverWithdrawal(uint256 _amount) public {
    vm.assume(_amount <= 1 ether);

    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.checkVault.selector, 1), abi.encode(false)
    );
    vm.expectRevert(IVault.Vault_OverWithdrawal.selector);
    vm.prank(vaultOwner);
    vault.withdrawERC20(address(_mockToken), _amount);
  }

  function testRevertIfUnstakeOnConvexFails(uint256 _amount) public {
    vm.assume(_amount > 0);

    depositCurveLpTokenMockCalls(1 ether, address(_mockToken), 1, IVaultController.CollateralType.CurveLPStakedOnConvex);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCrvRewardsContract.selector),
      abi.encode(USDT_LP_REWARDS_ADDRESS)
    );
    vm.mockCall(
      USDT_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector), abi.encode(false)
    );
    vm.expectRevert(IVault.Vault_WithdrawAndUnstakeOnConvexFailed.selector);

    vm.prank(vaultOwner);
    vault.withdrawERC20(address(_mockToken), _amount);
  }

  function testExpectCallWithdrawOnConvex(uint256 _amount) public {
    vm.assume(_amount > 0);

    depositCurveLpTokenMockCalls(1 ether, address(_mockToken), 1, IVaultController.CollateralType.CurveLPStakedOnConvex);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCrvRewardsContract.selector),
      abi.encode(USDT_LP_REWARDS_ADDRESS)
    );
    vm.mockCall(
      USDT_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector), abi.encode(true)
    );

    vm.expectCall(
      USDT_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector, 1 ether, false)
    );
    vm.prank(vaultOwner);
    vault.withdrawERC20(address(_mockToken), 1 ether);
  }

  function testModifyTotalDepositedIsCalled() public {
    vm.expectCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.modifyTotalDeposited.selector, 1, 1 ether, address(_mockToken), false)
    );
    vm.prank(vaultOwner);
    vault.withdrawERC20(address(_mockToken), 1 ether);
  }

  function testWithdrawERC20() public {
    vm.expectEmit(false, false, false, true);
    emit Withdraw(address(_mockToken), 1 ether);
    assertEq(vault.balances(address(_mockToken)), 1 ether);
    vm.prank(vaultOwner);
    vault.withdrawERC20(address(_mockToken), 1 ether);
    assertEq(vault.balances(address(_mockToken)), 0);
  }

  function testWithdrawERC20CallsCheckVault() public {
    vm.expectCall(address(mockVaultController), abi.encodeWithSelector(IVaultController.checkVault.selector, 1));
    vm.prank(vaultOwner);
    vault.withdrawERC20(address(_mockToken), 1 ether);
  }
}

contract UnitVaultControllerTransfer is Base {
  uint256 internal _deposit = 5 ether;

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(_mockToken)),
      abi.encode(1)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.Single)
    );

    vm.prank(vaultOwner);
    vault.depositERC20(address(_mockToken), _deposit);
  }

  function testRevertsIfCalledByNonVault(uint256 _amount) public {
    vm.expectRevert(IVault.Vault_NotVaultController.selector);
    vault.controllerTransfer(address(_mockToken), address(this), _amount);
  }

  function testControllerTransfer(address _to) public {
    assertEq(vault.balances(address(_mockToken)), _deposit);
    vm.prank(address(mockVaultController));
    vault.controllerTransfer(address(_mockToken), _to, _deposit);
    assertEq(vault.balances(address(_mockToken)), 0);
  }
}

contract UnitVaultControllerWithdrawAndUnwrap is Base {
  function testRevertsIfCalledByNonVault(IBaseRewardPool _rewardPool, uint256 _amount) public {
    vm.expectRevert(IVault.Vault_NotVaultController.selector);
    vault.controllerWithdrawAndUnwrap(_rewardPool, _amount);
  }

  function testControllerWithdrawAndUnwrap(IBaseRewardPool _rewardPool, uint256 _amount) public {
    vm.assume(address(_rewardPool) != address(vm));

    vm.mockCall(
      address(_rewardPool), abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector), abi.encode(true)
    );

    vm.expectCall(
      address(_rewardPool), abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector, _amount, false)
    );

    vm.prank(address(mockVaultController));
    vault.controllerWithdrawAndUnwrap(_rewardPool, _amount);
  }

  function testRevertControllerWithdrawAndUnwrap(IBaseRewardPool _rewardPool, uint256 _amount) public {
    vm.assume(address(_rewardPool) != address(vm));

    vm.mockCall(
      address(_rewardPool), abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector), abi.encode(false)
    );

    vm.expectRevert(IVault.Vault_WithdrawAndUnstakeOnConvexFailed.selector);
    vm.prank(address(mockVaultController));
    vault.controllerWithdrawAndUnwrap(_rewardPool, _amount);
  }
}

contract UnitVaultModifyLiability is Base {
  function setUp() public virtual override {
    super.setUp();

    // increase liability first
    vm.prank(address(mockVaultController));
    vault.modifyLiability(true, 1 ether);
  }

  function testRevertsIfCalledByNonVault(bool _increase, uint256 _baseAmount) public {
    vm.expectRevert(IVault.Vault_NotVaultController.selector);
    vault.modifyLiability(_increase, _baseAmount);
  }

  function testRevertIfTooMuchRepay() public {
    vm.expectRevert(IVault.Vault_RepayTooMuch.selector);
    vm.prank(address(mockVaultController));
    vault.modifyLiability(false, 10 ether);
  }

  function testModifyLiabilitIncrease(uint56 _baseAmount) public {
    uint256 _liabilityBefore = vault.baseLiability();
    vm.prank(address(mockVaultController));
    vault.modifyLiability(true, _baseAmount);
    assertEq(vault.baseLiability(), _liabilityBefore + _baseAmount);
  }

  function testModifyLiabilitDecrease() public {
    vm.prank(address(mockVaultController));
    vault.modifyLiability(false, 1 ether);
    assertEq(vault.baseLiability(), 0);
  }
}

contract UnitVaultClaimRewards is Base {
  IERC20 public mockVirtualRewardsToken = IERC20(newAddress());
  IERC20 public otherMockToken = IERC20(newAddress());
  IVirtualBalanceRewardPool public mockVirtualRewardsPool = IVirtualBalanceRewardPool(newAddress());

  IVaultController.CollateralInfo public collateralInfo;

  function setUp() public virtual override {
    super.setUp();

    collateralInfo = IVaultController.CollateralInfo({
      tokenId: 1,
      ltv: 0,
      cap: 0,
      totalDeposited: 0,
      liquidationIncentive: 0,
      oracle: IOracleRelay(address(0)),
      collateralType: IVaultController.CollateralType.CurveLPStakedOnConvex,
      crvRewardsContract: IBaseRewardPool(GEAR_LP_REWARDS_ADDRESS),
      poolId: 15,
      decimals: 18
    });

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralInfo.selector),
      abi.encode(collateralInfo)
    );

    vm.mockCall(GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.getReward.selector), abi.encode(true));

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS,
      abi.encodeWithSelector(IBaseRewardPool.earned.selector, address(vault)),
      abi.encode(1 ether)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.claimerContract.selector),
      abi.encode(mockAmphClaimer)
    );

    vm.mockCall(address(mockAmphClaimer), abi.encodeWithSelector(IAMPHClaimer.AMPH.selector), abi.encode(mockAmphToken));

    vm.mockCall(address(crv), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    vm.mockCall(address(crv), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(address(cvx), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCall(
      address(mockAmphClaimer), abi.encodeWithSelector(IAMPHClaimer.claimAmph.selector), abi.encode(0, 1 ether, 0)
    );

    vm.mockCall(address(cvx), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
  }

  function testRevertIfNotVaultOwner(address _token) public {
    vm.assume(_token != address(vm));
    address[] memory _tokens = new address[](1);
    _tokens[0] = _token;
    vm.expectRevert(IVault.Vault_NotMinter.selector);
    vm.prank(newAddress());
    vault.claimRewards(_tokens);
  }

  function testRevertIfTokenNotRegistered(address _token) public {
    vm.assume(_token != address(vm));
    address[] memory _tokens = new address[](1);
    _tokens[0] = _token;
    collateralInfo.tokenId = 0;
    vm.expectRevert(IVault.Vault_TokenNotRegistered.selector);
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralInfo.selector),
      abi.encode(collateralInfo)
    );
    vm.prank(vaultOwner);
    vault.claimRewards(_tokens);
  }

  function testRevertIfProvidedTokenIsNotCurveLP() public {
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(_mockToken);
    collateralInfo.collateralType = IVaultController.CollateralType.Single;
    vm.expectRevert(IVault.Vault_TokenNotCurveLP.selector);
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralInfo.selector),
      abi.encode(collateralInfo)
    );
    vm.prank(vaultOwner);
    vault.claimRewards(_tokens);
  }

  function testExpectTransferCRV() public {
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(_mockToken);
    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.extraRewardsLength.selector), abi.encode(0)
    );

    vm.mockCall(
      address(mockAmphClaimer),
      abi.encodeWithSelector(IAMPHClaimer.claimable.selector, address(vault), 1, 1 ether * 90 / 100, 1 ether),
      abi.encode(0, 0.5 ether, 1 ether)
    );

    vm.expectCall(address(crv), abi.encodeWithSelector(IERC20.transfer.selector, vaultOwner, 0.5 ether));

    vm.prank(vaultOwner);
    vault.claimRewards(_tokens);
  }

  function testClaimExtraRewards() public {
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(_mockToken);
    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.extraRewardsLength.selector), abi.encode(1)
    );

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS,
      abi.encodeWithSelector(IBaseRewardPool.extraRewards.selector, 0),
      abi.encode(mockVirtualRewardsPool)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.rewardToken.selector),
      abi.encode(mockVirtualRewardsToken)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.earned.selector, address(vault)),
      abi.encode(1 ether)
    );

    vm.mockCall(
      address(mockAmphClaimer),
      abi.encodeWithSelector(IAMPHClaimer.claimable.selector, address(vault), 1, 1 ether * 90 / 100, 1 ether),
      abi.encode(0, 0.5 ether, 1 ether)
    );

    vm.mockCall(address(mockVirtualRewardsToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

    vm.expectCall(
      address(mockVirtualRewardsToken), abi.encodeWithSelector(IERC20.transfer.selector, vaultOwner, 1 ether)
    );
    vm.expectCall(address(crv), abi.encodeWithSelector(IERC20.transfer.selector, vaultOwner, 0.5 ether));
    vm.prank(vaultOwner);
    vault.claimRewards(_tokens);
  }

  function testClaimMultipleTokens() public {
    address[] memory _tokens = new address[](2);
    _tokens[0] = address(_mockToken);
    _tokens[1] = address(otherMockToken);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(otherMockToken)),
      abi.encode(2)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector, address(otherMockToken)),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCrvRewardsContract.selector, address(otherMockToken)),
      abi.encode(GEAR_LP_REWARDS_ADDRESS)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.earned.selector, address(vault)),
      abi.encode(1 ether)
    );

    vm.mockCall(GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.getReward.selector), abi.encode(true));

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.extraRewardsLength.selector), abi.encode(0)
    );

    vm.mockCall(
      address(mockAmphClaimer),
      abi.encodeWithSelector(IAMPHClaimer.claimable.selector, address(vault), 1, 2 ether * 90 / 100, 2 ether),
      abi.encode(0, 0.5 ether, 1 ether)
    );

    vm.mockCall(address(mockAmphClaimer), abi.encodeWithSelector(IAMPHClaimer.AMPH.selector), abi.encode(mockAmphToken));

    vm.mockCall(address(crv), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCall(
      address(mockAmphClaimer), abi.encodeWithSelector(IAMPHClaimer.claimAmph.selector), abi.encode(0, 2 ether, 0)
    );

    vm.mockCall(address(crv), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

    vm.expectCall(
      address(mockAmphClaimer),
      abi.encodeWithSelector(IAMPHClaimer.claimAmph.selector, 1, 2 ether * 90 / 100, 2 ether, vaultOwner)
    );

    vm.expectCall(address(crv), abi.encodeWithSelector(IERC20.transfer.selector, vaultOwner, 1.5 ether));
    vm.prank(vaultOwner);
    vault.claimRewards(_tokens);
  }

  function testClaimWhenNoAMPHToClaim() public {
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(_mockToken);
    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.extraRewardsLength.selector), abi.encode(1)
    );

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS,
      abi.encodeWithSelector(IBaseRewardPool.extraRewards.selector, 0),
      abi.encode(mockVirtualRewardsPool)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.rewardToken.selector),
      abi.encode(mockVirtualRewardsToken)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.earned.selector, address(vault)),
      abi.encode(1 ether)
    );

    vm.mockCall(
      address(mockAmphClaimer),
      abi.encodeWithSelector(IAMPHClaimer.claimable.selector, address(vault), 1, 1 ether * 90 / 100, 1 ether),
      abi.encode(0, 0.5 ether, 0)
    );

    vm.mockCall(address(mockVirtualRewardsToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

    vm.expectCall(
      address(mockVirtualRewardsToken), abi.encodeWithSelector(IERC20.transfer.selector, vaultOwner, 1 ether)
    );
    // user gets the full amount
    vm.expectCall(address(crv), abi.encodeWithSelector(IERC20.transfer.selector, vaultOwner, 1 ether));
    vm.prank(vaultOwner);
    vault.claimRewards(_tokens);
  }

  function testClaimWhenTheRewardsAreZero() public {
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(_mockToken);

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.earned.selector, address(vault)), abi.encode(0)
    );

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.extraRewardsLength.selector), abi.encode(1)
    );

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS,
      abi.encodeWithSelector(IBaseRewardPool.extraRewards.selector, 0),
      abi.encode(mockVirtualRewardsPool)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.rewardToken.selector),
      abi.encode(mockVirtualRewardsToken)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.earned.selector, address(vault)),
      abi.encode(0)
    );

    vm.prank(vaultOwner);
    vault.claimRewards(_tokens);
  }
}

contract UnitVaultClaimableRewards is Base {
  IERC20 public mockVirtualRewardsToken = IERC20(newAddress());
  IVirtualBalanceRewardPool public mockVirtualRewardsPool = IVirtualBalanceRewardPool(newAddress());

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(_mockToken)),
      abi.encode(1)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCrvRewardsContract.selector, address(_mockToken)),
      abi.encode(GEAR_LP_REWARDS_ADDRESS)
    );

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS,
      abi.encodeWithSelector(IBaseRewardPool.earned.selector, address(vault)),
      abi.encode(1 ether)
    );

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.claimerContract.selector),
      abi.encode(mockAmphClaimer)
    );
  }

  function testRevertIfTokenNotRegistered(address _token) public {
    vm.assume(_token != address(vm));
    vm.expectRevert(IVault.Vault_TokenNotRegistered.selector);
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenId.selector, address(_token)),
      abi.encode(0)
    );
    vault.claimableRewards(_token);
  }

  function testRevertIfProvidedTokenIsNotCurveLP() public {
    vm.expectRevert(IVault.Vault_TokenNotCurveLP.selector);
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.Single)
    );
    vault.claimableRewards(address(_mockToken));
  }

  function testClaimableRewards() public {
    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.extraRewardsLength.selector), abi.encode(1)
    );

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS,
      abi.encodeWithSelector(IBaseRewardPool.extraRewards.selector, 0),
      abi.encode(mockVirtualRewardsPool)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.rewardToken.selector),
      abi.encode(mockVirtualRewardsToken)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.earned.selector, address(vault)),
      abi.encode(1 ether)
    );

    uint256 _claimedCVX = 1 ether * 90 / 100;
    vm.mockCall(
      address(mockAmphClaimer),
      abi.encodeWithSelector(IAMPHClaimer.claimable.selector, address(vault), 1, _claimedCVX, 1 ether),
      abi.encode(0, 0.5 ether, 3 ether)
    );

    vm.mockCall(address(mockAmphClaimer), abi.encodeWithSelector(IAMPHClaimer.AMPH.selector), abi.encode(mockAmphToken));

    IVault.Reward[] memory _rewards = vault.claimableRewards(address(_mockToken));
    assertEq(address(_rewards[0].token), address(crv));
    assertEq(_rewards[0].amount, 0.5 ether);

    assertEq(address(_rewards[1].token), address(cvx));
    assertEq(_rewards[1].amount, _claimedCVX);

    assertEq(address(_rewards[2].token), address(mockVirtualRewardsToken));
    assertEq(_rewards[2].amount, 1 ether);

    assertEq(address(_rewards[3].token), address(mockAmphToken));
    assertEq(_rewards[3].amount, 3 ether);
  }

  function testClaimableWhenAmphClaimerIsZeroAddress() public {
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.claimerContract.selector),
      abi.encode(address(0))
    );

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS, abi.encodeWithSelector(IBaseRewardPool.extraRewardsLength.selector), abi.encode(1)
    );

    vm.mockCall(
      GEAR_LP_REWARDS_ADDRESS,
      abi.encodeWithSelector(IBaseRewardPool.extraRewards.selector, 0),
      abi.encode(mockVirtualRewardsPool)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.rewardToken.selector),
      abi.encode(mockVirtualRewardsToken)
    );

    vm.mockCall(
      address(mockVirtualRewardsPool),
      abi.encodeWithSelector(IVirtualBalanceRewardPool.earned.selector, address(vault)),
      abi.encode(1 ether)
    );

    IVault.Reward[] memory _rewards = vault.claimableRewards(address(_mockToken));

    assertEq(_rewards.length, 4);

    assertEq(address(_rewards[0].token), address(crv));
    assertEq(_rewards[0].amount, 1 ether);

    assertEq(address(_rewards[1].token), address(cvx));
    assertEq(_rewards[1].amount, 1 ether * 90 / 100);

    assertEq(address(_rewards[2].token), address(mockVirtualRewardsToken));
    assertEq(_rewards[2].amount, 1 ether);

    assertEq(address(_rewards[3].token), address(0));
    assertEq(_rewards[3].amount, 0);
  }
}

contract UnitVaultStakeCrvLPCollateral is Base {
  event Staked(address _token, uint256 _amount);

  function testRevertIfPoolIdZero(address _token) public {
    vm.assume(_token != address(vm));
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(0)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.expectRevert(IVault.Vault_TokenCanNotBeStaked.selector);

    vm.prank(vaultOwner);
    vault.stakeCrvLPCollateral(_token);
  }

  function testRevertIfBalanceZero(address _token) public {
    vm.assume(_token != address(vm));
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.expectRevert(IVault.Vault_TokenZeroBalance.selector);

    vm.prank(vaultOwner);
    vault.stakeCrvLPCollateral(_token);
  }

  function testRevertIfStakeFails(address _token) public {
    vm.assume(_token != address(vm));
    /// deposit
    depositCurveLpTokenMockCalls(1 ether, _token, 0, IVaultController.CollateralType.Single);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.BOOSTER.selector), abi.encode(BOOSTER)
    );
    vm.mockCall(_token, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(false));
    vm.expectRevert(IVault.Vault_DepositAndStakeOnConvexFailed.selector);

    vm.prank(vaultOwner);
    vault.stakeCrvLPCollateral(_token);
  }

  function testRevertIfTokenIsStaked(address _token) public {
    vm.assume(_token != address(vm));
    depositCurveLpTokenMockCalls(1 ether, _token, 0, IVaultController.CollateralType.Single);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.BOOSTER.selector), abi.encode(BOOSTER)
    );
    vm.mockCall(_token, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(true));

    vm.prank(vaultOwner);
    vault.stakeCrvLPCollateral(_token);

    vm.expectRevert(IVault.Vault_TokenAlreadyStaked.selector);
    vm.prank(vaultOwner);
    vault.stakeCrvLPCollateral(_token);
  }

  function testStakeCurveLP(address _token) public {
    vm.assume(_token != address(vm));
    /// deposit
    depositCurveLpTokenMockCalls(1 ether, _token, 0, IVaultController.CollateralType.Single);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.BOOSTER.selector), abi.encode(BOOSTER)
    );
    vm.mockCall(_token, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(true));
    vm.expectCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector, 1, 1 ether, true));

    vm.expectEmit(true, true, true, true);
    emit Staked(_token, 1 ether);

    vm.prank(vaultOwner);
    vault.stakeCrvLPCollateral(_token);
  }
}

contract UnitVaultCanStake is Base {
  function testCanStakeReturnFalseWithZeroBalance(address _token) public {
    vm.assume(_token != address(vm));
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(1)
    );

    vm.prank(vaultOwner);
    assertFalse(vault.canStake(_token));
  }

  function testCanStakeReturnFalseWithZeroPoolId(address _token) public {
    vm.assume(_token != address(vm));
    depositCurveLpTokenMockCalls(1 ether, _token, 0, IVaultController.CollateralType.Single);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(0)
    );

    vm.prank(vaultOwner);
    assertFalse(vault.canStake(_token));
  }

  function testCanStakeReturnFalseWhenTokenAlreadyStaked(address _token) public {
    vm.assume(_token != address(vm));
    depositCurveLpTokenMockCalls(1 ether, _token, 0, IVaultController.CollateralType.Single);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(1)
    );
    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenCollateralType.selector),
      abi.encode(IVaultController.CollateralType.CurveLPStakedOnConvex)
    );
    vm.mockCall(
      address(mockVaultController), abi.encodeWithSelector(IVaultController.BOOSTER.selector), abi.encode(BOOSTER)
    );
    vm.mockCall(_token, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(BOOSTER, abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(true));

    vm.prank(vaultOwner);
    vault.stakeCrvLPCollateral(_token);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(1)
    );

    vm.prank(vaultOwner);
    assertFalse(vault.canStake(_token));
  }

  function testCanStakeReturnTrue(address _token) public {
    vm.assume(_token != address(vm));
    depositCurveLpTokenMockCalls(1 ether, _token, 0, IVaultController.CollateralType.Single);

    vm.mockCall(
      address(mockVaultController),
      abi.encodeWithSelector(IVaultController.tokenPoolId.selector, address(_token)),
      abi.encode(1)
    );

    vm.prank(vaultOwner);
    assertTrue(vault.canStake(_token));
  }
}
