// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, IERC20} from '@test/e2e/Common.sol';

import {VaultController} from '@contracts/core/VaultController.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {IAMPHClaimer} from '@interfaces/core/IAMPHClaimer.sol';
import {IVaultDeployer} from '@interfaces/core/IVaultDeployer.sol';
import {ChainlinkStalePriceLib} from '@contracts/periphery/oracles/ChainlinkStalePriceLib.sol';

contract E2EVaultController is CommonE2EBase {
  uint256 public borrowAmount = 500 ether;
  uint96 public bobsVaultId = 1;
  uint96 public carolsVaultId = 2;
  uint256 public gusWbtcDeposit = 1e8;

  event Liquidate(uint256 _vaultId, address _assetAddress, uint256 _usdaToRepurchase, uint256 _tokensToLiquidate);
  event BorrowUSDA(uint256 _vaultId, address _vaultAddress, uint256 _borrowAmount, uint256 _fee);

  function setUp() public override {
    super.setUp();

    // Bob mints vault
    _mintVault(bob);
    // Since we only have 1 vault the id: 1 is gonna be Bob's vault
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobsVaultId));

    vm.startPrank(bob);
    weth.approve(address(bobVault), bobWETH);
    bobVault.depositERC20(address(weth), bobWETH);
    vm.stopPrank();

    // Carol mints vault
    _mintVault(carol);
    // Since we only have 2 vaults the id: 2 is gonna be Carol's vault
    carolVault = IVault(vaultController.vaultIdVaultAddress(carolsVaultId));

    vm.startPrank(carol);
    uni.approve(address(carolVault), carolUni);
    carolVault.depositERC20(address(uni), carolUni);
    vm.stopPrank();

    _mintVault(dave);
    daveVault = IVault(vaultController.vaultIdVaultAddress(3));

    // Gus mints vault
    _mintVault(gus);
    gusVaultId = 4;
    // Since we only have 4 vaults the id: 4 is gonna be Gus' vault
    gusVault = IVault(vaultController.vaultIdVaultAddress(gusVaultId));
    vm.startPrank(gus);
    wbtc.approve(address(gusVault), gusWbtcDeposit);
    gusVault.depositERC20(address(wbtc), gusWbtcDeposit); // Deposit 1 wbtc
    vm.stopPrank();
  }

  /**
   * ----------------------- Internal Functions -----------------------
   */
  /**
   * @notice Takes interest factor and returns new interest factor - pulls block time from network and latestInterestTime from contract
   * @param _interestFactor Current interest factor read from contract
   * @return _newInterestFactor New interest factor based on time elapsed and reserve ratio
   */
  function _payInterestMath(uint192 _interestFactor) internal view returns (uint192 _newInterestFactor) {
    uint192 _latestInterestTime = vaultController.lastInterestTime();
    // vm.warp(block.timestamp + 1);

    uint256 _timeDiff = block.timestamp - _latestInterestTime;

    uint192 _reserveRatio = usdaToken.reserveRatio();
    int256 _curveValue = curveMaster.getValueAt(address(0), int192(_reserveRatio));

    uint192 _calculation = uint192(int192(int256(_timeDiff)) * int192(_curveValue)); //correct step 1
    _calculation = _calculation / (365 days + 6 hours); //correct step 2 - divide by OneYear
    _calculation = _calculation * _interestFactor;
    _calculation = _calculation / 1 ether;

    _newInterestFactor = _interestFactor + _calculation;
  }

  function _calculateAccountLiability(
    uint256 _borrowAmount,
    uint256 _currentInterestFactor,
    uint256 _initialInterestFactor
  ) internal pure returns (uint256 _liability) {
    uint256 _baseAmount = _borrowAmount / _initialInterestFactor;
    _liability = _baseAmount * _currentInterestFactor;
  }

  /**
   * @notice Proper procedure: read interest factor from contract -> elapse time -> call this to predict balance -> pay_interest() -> compare
   * @param _interestFactor CURRENT interest factor read from contract before any time has elapsed
   * @param _user Whose balance to calculate interest on
   * @return _balance Expected after pay_interest()
   */
  function _calculateBalance(uint192 _interestFactor, address _user) internal view returns (uint256 _balance) {
    uint192 _totalBaseLiability = vaultController.totalBaseLiability();
    uint192 _protocolFee = vaultController.protocolFee();

    uint192 _valueBefore = (_totalBaseLiability * _interestFactor) / 1 ether;
    uint192 _calculatedInterestFactor = _payInterestMath(_interestFactor);

    uint192 _valueAfter = (_totalBaseLiability * _calculatedInterestFactor) / 1 ether;
    uint192 _protocolAmount = ((_valueAfter - _valueBefore) * _protocolFee) / 1 ether;

    uint192 _donationAmount = _valueAfter - _valueBefore - _protocolAmount; // wrong
    uint256 _currentSupply = usdaToken.totalSupply();

    uint256 _newSupply = _currentSupply + _donationAmount;

    uint256 _totalGons = usdaToken._totalGons();

    uint256 _gpf = _totalGons / _newSupply;

    uint256 _gonBalance = usdaToken.scaledBalanceOf(_user);

    _balance = _gonBalance / _gpf;
  }

  // @notice Calculates the amount of USDA to repurchase
  // @param _collateralPrice Price of the collateral token
  // @param _tokensToLiquidate Amount of tokens to liquidate
  // @return _usdaToRepurchase Amount of USDA to repurchase
  function _calculateUSDAToRepurchase(
    uint256 _collateralPrice,
    uint256 _tokensToLiquidate
  ) internal pure returns (uint256 _usdaToRepurchase) {
    uint256 _badFillPrice = _collateralPrice * (1 ether - LIQUIDATION_INCENTIVE) / 1 ether;
    _usdaToRepurchase = (_badFillPrice * _tokensToLiquidate) / 1 ether;
  }

  /**
   * @notice Returns the number of tokens to liquidate
   * @param _vault The vault to target and liquidate
   * @param _asset The asset to target
   * @param _totalToLiquidate The expected number of tokens to liquidate
   * @param _calculatedLiability The expected liability
   * @return _finalTokensToLiquidate The final number of tokens to liquidate
   */
  function _calculatetokensToLiquidate(
    IVault _vault,
    address _asset,
    uint256 _totalToLiquidate,
    uint256 _calculatedLiability
  ) internal returns (uint256 _finalTokensToLiquidate) {
    uint256 _assetPrice = vaultController.tokensOracle(_asset).currentValue();
    uint256 _ltv = WETH_LTV;

    uint256 _denominator = (_assetPrice * 1 ether - LIQUIDATION_INCENTIVE - _ltv) / 1 ether;
    uint96 _vaultId = _vault.id();
    uint192 _borrowingPower = vaultController.vaultBorrowingPower(_vaultId);

    uint256 _maxTokens = ((_calculatedLiability - _borrowingPower) * 1 ether) / _denominator;

    if (_totalToLiquidate > _maxTokens) _finalTokensToLiquidate = _maxTokens;
    uint256 _vaultTokenBalance = _vault.balances(_asset);
    if (_finalTokensToLiquidate > _vaultTokenBalance) _finalTokensToLiquidate = _vaultTokenBalance;
  }

  /**
   * @notice Returns the total USDA to repurchase when liquidating
   * @param _asset The asset's address to target
   * @param _tokensToLiquidate The number of tokens to liquidate
   * @return _usdaToRepurchase The number of USDA tokens to repurchase
   */
  function _calculateUSDAToRepurchase(
    address _asset,
    uint256 _tokensToLiquidate
  ) internal returns (uint256 _usdaToRepurchase) {
    uint256 _assetPrice = vaultController.tokensOracle(_asset).currentValue();
    uint256 _badFillPrice = ((_assetPrice * 1 ether) - LIQUIDATION_INCENTIVE) / 1 ether;
    _usdaToRepurchase = (_badFillPrice * _tokensToLiquidate) / 1 ether;
  }

  /**
   * ----------------------- Public Function Tests -----------------------
   */

  function testMigrateFromOldVaultController() public {
    address[] memory _tokens = new address[](1);
    _tokens[0] = WETH_ADDRESS;
    vm.startPrank(frank);

    // Deploy the new vault controller
    vaultController2 =
    new VaultController(IVaultController(address(vaultController)), _tokens, IAMPHClaimer(address(amphClaimer)), IVaultDeployer(address(vaultDeployer)), 0.01e18, BOOSTER, 0.005e18);
    vm.stopPrank();

    assertEq(address(vaultController2.tokensOracle(WETH_ADDRESS)), address(anchoredViewEth));
    assertEq(vaultController2.tokensRegistered(), 1);
    assertEq(vaultController2.tokenId(WETH_ADDRESS), 1);
    assertEq(vaultController2.tokenLTV(WETH_ADDRESS), WETH_LTV);
    assertEq(vaultController2.tokenLiquidationIncentive(WETH_ADDRESS), LIQUIDATION_INCENTIVE);
    assertEq(vaultController2.tokenCap(WETH_ADDRESS), type(uint256).max);
  }

  function testMintVault() public {
    assertEq(bobVault.minter(), bob);
    assertEq(carolVault.minter(), carol);
  }

  function testVaultDeposits() public {
    assertEq(bobVault.balances(WETH_ADDRESS), bobWETH);

    assertEq(carolVault.balances(UNI_ADDRESS), carolUni);
  }

  function testCap() public {
    vm.startPrank(bob);
    aave.approve(address(bobVault), type(uint256).max);
    bobVault.depositERC20(address(aave), AAVE_CAP);
    vm.stopPrank();
  }

  function testRevertCapReached() public {
    vm.startPrank(bob);
    aave.approve(address(bobVault), type(uint256).max);

    uint256 _bobBalance = aave.balanceOf(bob);
    vm.expectRevert(IVaultController.VaultController_CapReached.selector);
    bobVault.depositERC20(address(aave), _bobBalance);
    vm.stopPrank();
  }

  function testRevertVaultDepositETH() public {
    vm.prank(dave);
    (bool _success,) = address(bobVault).call{value: 1 ether}('');
    assertTrue(!_success);
  }

  function testRevertBorrowIfVaultInsolvent() public {
    uint192 _foo = vaultController.vaultBorrowingPower(1);
    vm.expectRevert(IVaultController.VaultController_VaultInsolvent.selector);
    vm.prank(bob);
    vaultController.borrowUSDA(1, _foo * 2);
  }

  function testRegisterCurveLP() public {
    assertEq(address(vaultController.tokenCrvRewardsContract(USDT_LP_ADDRESS)), USDT_LP_REWARDS_ADDRESS);
  }

  function testBorrow() public {
    uint256 _usdaBalance = usdaToken.balanceOf(bob);
    assertEq(0, _usdaBalance);

    /// Get initial interest factFtestWithdrawUnderlyingr
    uint192 _interestFactor = vaultController.interestFactor();
    uint256 _expectedInterestFactor = _payInterestMath(_interestFactor);

    uint256 _liability = _calculateAccountLiability(borrowAmount, _interestFactor, _interestFactor);

    vm.expectEmit(false, false, false, true);
    emit BorrowUSDA(1, address(bobVault), borrowAmount, vaultController.getBorrowingFee(uint192(borrowAmount)));

    vm.prank(bob);
    vaultController.borrowUSDA(1, uint192(borrowAmount));

    uint256 _newInterestFactor = vaultController.interestFactor();
    assertEq(_newInterestFactor, _expectedInterestFactor);

    vaultController.calculateInterest();
    vm.prank(bob);
    uint256 _trueLiability = vaultController.vaultLiability(1);
    assertEq(_trueLiability, _liability + vaultController.getBorrowingFee(uint192(_liability)));

    uint256 _usdaBalanceAfter = usdaToken.balanceOf(bob);
    assertEq(_usdaBalanceAfter, borrowAmount);
  }

  function testLiabilityAfterAWeek() public {
    uint192 _initInterestFactor = vaultController.interestFactor();

    _borrow(bob, 1, borrowAmount);

    vm.warp(block.timestamp + 1 weeks);

    uint192 _interestFactor = vaultController.interestFactor();
    uint256 _expectedInterestFactor = _payInterestMath(_interestFactor);

    vm.prank(frank);
    vaultController.calculateInterest();
    vm.warp(block.timestamp + 1);

    _interestFactor = vaultController.interestFactor();
    uint256 _liability = _calculateAccountLiability(borrowAmount, _interestFactor, _initInterestFactor);

    _interestFactor = vaultController.interestFactor();
    assertEq(_interestFactor, _expectedInterestFactor);

    vm.prank(bob);
    uint192 _realLiability = vaultController.vaultLiability(1);
    assertGt(_realLiability, borrowAmount);
    assertEq(_realLiability, _liability + vaultController.getBorrowingFee(uint192(_liability)));
  }

  function testInterestGeneration() public {
    _depositSUSD(dave, daveSUSD);
    uint256 _balance = usdaToken.balanceOf(dave);

    _borrow(bob, 1, borrowAmount);

    /// pass 1 year
    vm.warp(block.timestamp + 365 days + 6 hours);

    uint192 _interestFactor = vaultController.interestFactor();

    uint256 _expectedBalance = _calculateBalance(_interestFactor, dave);

    uint256 _newBalance = usdaToken.balanceOf(dave);

    /// No yield before calculateInterest
    assertEq(_newBalance, _balance);

    /// Calculate and pay interest on the contract
    vm.prank(frank);
    vaultController.calculateInterest();
    advanceTime(60);

    _newBalance = usdaToken.balanceOf(dave);
    assertEq(_newBalance, _expectedBalance);
    assertGt(_newBalance, _balance);
  }

  function testPartialRepay() public {
    uint256 _borrowAmount = 10 ether;
    _borrow(bob, 1, _borrowAmount);

    vm.prank(bob);
    uint256 _liability = bobVault.baseLiability();
    uint256 _partialLiability = _liability / 2; // half

    vm.prank(address(governor));
    vaultController.pause();
    vm.warp(block.timestamp + 1);
    vm.expectRevert('Pausable: paused');
    vm.prank(bob);
    vaultController.repayUSDA(1, uint192(_liability / 2));
    vm.prank(address(governor));
    vaultController.unpause();
    vm.warp(block.timestamp + 1);

    //need to get liability again, 2 seconds have passed when checking pausable
    vm.prank(bob);
    _liability = bobVault.baseLiability();
    _partialLiability = _liability / 2;

    uint192 _interestFactor = vaultController.interestFactor();
    uint256 _expectedBalance = _calculateBalance(_interestFactor, bob);

    uint256 _expectedInterestFactor = _payInterestMath(_interestFactor);

    uint256 _baseAmount = (_partialLiability * 1 ether) / _expectedInterestFactor;
    uint256 _expectedBaseLiability = _liability - _baseAmount;

    vm.prank(bob);
    vaultController.repayUSDA(1, uint192(_partialLiability));
    vm.warp(block.timestamp + 1);

    _interestFactor = vaultController.interestFactor();
    assertEq(_interestFactor, _expectedInterestFactor);

    vm.prank(bob);
    uint256 _newLiability = bobVault.baseLiability();
    uint256 _usdaBalance = usdaToken.balanceOf(bob);

    assertEq(_expectedBaseLiability, _newLiability);
    assertEq(_usdaBalance, _expectedBalance - _partialLiability);
  }

  function testCompletelyRepayVault() public {
    uint256 _borrowAmount = 10 ether;
    _borrow(bob, 1, _borrowAmount);

    uint192 _interestFactor = vaultController.interestFactor();
    vm.prank(bob);
    uint256 _liability = bobVault.baseLiability();
    uint192 _expectedInterestFactor = _payInterestMath(_interestFactor);
    uint256 _expectedUSDALiability = (_expectedInterestFactor * _liability) / 1 ether;
    uint256 _expectedBalanceWithInterest = _calculateBalance(_expectedInterestFactor, bob);

    uint256 _neededUSDA = _expectedUSDALiability - _expectedBalanceWithInterest;
    _expectedBalanceWithInterest = _expectedBalanceWithInterest + _neededUSDA;

    vm.startPrank(bob);
    susd.approve(address(usdaToken), _neededUSDA + 1);
    usdaToken.deposit(_neededUSDA + 1);
    vaultController.repayAllUSDA(1);
    vm.stopPrank();
    vm.warp(block.timestamp + 1);

    vm.prank(bob);
    uint256 _newLiability = bobVault.baseLiability();
    assertEq(0, _newLiability);
  }

  function testLiquidateCompleteVault() public {
    uint192 _borrowInterestFactor = vaultController.interestFactor();
    uint192 _if = _payInterestMath(_borrowInterestFactor);
    uint192 _accountBorrowingPower = vaultController.vaultBorrowingPower(bobsVaultId);
    uint256 _vaultInitialWethBalance = bobVault.balances(WETH_ADDRESS);

    // Borrow the maximum amount
    vm.prank(bob);
    vaultController.borrowUSDA(bobsVaultId, _accountBorrowingPower);
    uint192 _initIF = vaultController.interestFactor();
    assertEq(_initIF, _if);

    // Let time pass so the vault becomes liquidatable because of interest
    uint256 _tenYears = 10 * (365 days + 6 hours);
    vm.warp(block.timestamp + _tenYears);
    uint192 _tenYearInterestFactor = _payInterestMath(_if);

    // Calculate interest to update the protocol, vault should now be liquidatable
    vaultController.calculateInterest();
    assertEq(vaultController.interestFactor(), _tenYearInterestFactor);

    // Vault shouldnt be liquidated if protocol is paused
    vm.prank(address(governor));
    vaultController.pause();
    vm.expectRevert('Pausable: paused');
    vm.prank(dave);
    vaultController.liquidateVault(bobsVaultId, WETH_ADDRESS, 1 ether);
    vm.prank(address(governor));
    vaultController.unpause();

    uint256 _expectedUSDAToRepurchase =
      _calculateUSDAToRepurchase(anchoredViewEth.currentValue(), _vaultInitialWethBalance);
    uint256 _liabilityBeforeLiquidation = vaultController.vaultLiability(bobsVaultId);

    // Liquidate vault
    uint256 _daveInitialWeth = IERC20(WETH_ADDRESS).balanceOf(dave);
    uint256 _daveUSDA = 1_000_000 ether;
    vm.startPrank(dave);
    susd.approve(address(usdaToken), _daveUSDA);
    usdaToken.deposit(_daveUSDA);
    uint256 _liquidated = vaultController.liquidateVault(bobsVaultId, WETH_ADDRESS, _vaultInitialWethBalance);
    vm.stopPrank();

    {
      // Check that everything was liquidate
      assertEq(_liquidated, _vaultInitialWethBalance);

      // Check that dave now has the weth of the vault
      uint256 _daveFinalWeth = IERC20(WETH_ADDRESS).balanceOf(dave);
      assertEq(
        _daveFinalWeth - _daveInitialWeth,
        _liquidated - vaultController.getLiquidationFee(uint192(_vaultInitialWethBalance), WETH_ADDRESS)
      );

      // Check that the vault's borrowing power is now zero
      uint192 _newAccountBorrowingPower = vaultController.vaultBorrowingPower(bobsVaultId);
      assertEq(_newAccountBorrowingPower, 0);

      // Check that the vault is now empty
      uint256 _vaultWethBalance = bobVault.balances(WETH_ADDRESS);
      uint256 _vaultWethBalanceOf = IERC20(WETH_ADDRESS).balanceOf(address(bobVault));
      assertEq(_vaultWethBalance, _vaultWethBalanceOf);
      assertEq(_vaultWethBalance, 0);

      // Check that the correct USDA amount was taken from dave
      uint256 _daveFinalUSDA = usdaToken.balanceOf(dave);
      assertEq(_daveUSDA - _expectedUSDAToRepurchase, _daveFinalUSDA);
    }

    {
      // Check that the vault's liability is correct
      uint256 _newAccountLiability = vaultController.vaultLiability(bobsVaultId);
      assertApproxEqAbs(_newAccountLiability, _liabilityBeforeLiquidation - _expectedUSDAToRepurchase, DELTA);
    }
  }

  function testOverLiquidationAndLiquidateInsolventVault() public {
    uint256 _carolVaultStartUniBalance = carolVault.balances(UNI_ADDRESS);

    uint192 _carolMaxBorrow = vaultController.vaultBorrowingPower(carolsVaultId);

    // Carol borrows max amount
    vm.prank(carol);
    vaultController.borrowUSDA(carolsVaultId, _carolMaxBorrow);
    assertEq(usdaToken.balanceOf(carol), _carolMaxBorrow);
    assertTrue(vaultController.checkVault(carolsVaultId));

    // Advance 1 week and add interest
    vm.warp(block.timestamp + 1 weeks);
    vaultController.calculateInterest();

    // Carol's vault is now not solvent
    assertTrue(!vaultController.checkVault(carolsVaultId));
    uint256 _liquidatableTokens = vaultController.tokensToLiquidate(carolsVaultId, UNI_ADDRESS);

    uint256 _expectedUSDAToRepurchase = _calculateUSDAToRepurchase(anchoredViewUni.currentValue(), _liquidatableTokens);
    uint256 _liabilityBeforeLiquidation = vaultController.vaultLiability(carolsVaultId);

    // Liquidate vault with a way higher maximum
    uint256 _daveStartUniBalance = IERC20(UNI_ADDRESS).balanceOf(dave);
    uint256 _daveUSDA = 1_000_000 ether;
    vm.startPrank(dave);
    susd.approve(address(usdaToken), _daveUSDA);
    usdaToken.deposit(_daveUSDA);
    uint256 _liquidated = vaultController.liquidateVault(carolsVaultId, UNI_ADDRESS, _liquidatableTokens * 10);
    vm.stopPrank();

    // Only the max liquidatable amount should be liquidated
    assertEq(_liquidated, _liquidatableTokens);

    // The correct amount of USDA was taken from dave
    assertEq(usdaToken.balanceOf(dave), _daveUSDA - _expectedUSDAToRepurchase);

    // The vault's liability is correct
    assertApproxEqAbs(
      vaultController.vaultLiability(carolsVaultId), _liabilityBeforeLiquidation - _expectedUSDAToRepurchase, DELTA
    );

    // Dave got the correct amount of uni tokens
    assertEq(
      _daveStartUniBalance
        + (_liquidated - vaultController.getLiquidationFee(uint192(_liquidatableTokens), UNI_ADDRESS)),
      IERC20(UNI_ADDRESS).balanceOf(dave)
    );

    // Carol's vault got some UNI tokens removed
    assertEq(_carolVaultStartUniBalance - _liquidated, carolVault.balances(UNI_ADDRESS));
    assertGt(carolVault.balances(UNI_ADDRESS), 0);
  }

  function testLiquidateVaultWhenCollateralLosesValue() public {
    uint192 _accountBorrowingPower = vaultController.vaultBorrowingPower(bobsVaultId);

    // Borrow the maximum amount
    vm.prank(bob);
    vaultController.borrowUSDA(bobsVaultId, _accountBorrowingPower);

    // Should revert since vault is solvent
    vm.expectRevert(IVaultController.VaultController_VaultSolvent.selector);
    uint256 _tokensToLiquidate = vaultController.tokensToLiquidate(bobsVaultId, WETH_ADDRESS);

    // moch the value of the token to make vault insolvent
    vm.mockCall(
      address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(0.5 ether)
    );
    vm.mockCall(
      address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(0.5 ether)
    );
    _tokensToLiquidate = vaultController.tokensToLiquidate(bobsVaultId, WETH_ADDRESS);
    assertEq(_tokensToLiquidate, bobWETH);
  }

  function testLiquidateVaultWhenPriceIsStale() public {
    uint192 _accountBorrowingPower = vaultController.vaultBorrowingPower(bobsVaultId);
    uint256 _vaultInitialWethBalance = bobVault.balances(WETH_ADDRESS);

    // Borrow the maximum amount
    vm.prank(bob);
    vaultController.borrowUSDA(bobsVaultId, _accountBorrowingPower);

    // Let time pass so the vault becomes liquidatable because of interest
    uint256 _tenYears = 10 * (365 days + 6 hours);
    vm.warp(block.timestamp + _tenYears);

    // Calculate interest to update the protocol, vault should now be liquidatable
    vaultController.calculateInterest();

    // Advance time so the price is stale
    vm.warp(block.timestamp + staleTime + 1);

    uint256 _liquidatableTokens = vaultController.tokensToLiquidate(bobsVaultId, WETH_ADDRESS);
    uint256 _daveUSDA = 1_000_000 ether;
    // Liquidate vault
    vm.startPrank(dave);
    susd.approve(address(usdaToken), _daveUSDA);
    usdaToken.deposit(_daveUSDA);
    uint256 _liquidated = vaultController.liquidateVault(bobsVaultId, WETH_ADDRESS, _vaultInitialWethBalance);
    vm.stopPrank();

    // Only the max liquidatable amount should be liquidated
    assertEq(_liquidated, _liquidatableTokens);
  }

  // Tests with less than 18 decimals
  function testLiquidateCompleteVaultLessThan18Decimals() public {
    uint192 _borrowInterestFactor = vaultController.interestFactor();
    uint192 _if = _payInterestMath(_borrowInterestFactor);
    uint192 _accountBorrowingPower = vaultController.vaultBorrowingPower(gusVaultId);
    uint256 _vaultInitialWbtcBalance = gusVault.balances(WBTC_ADDRESS);

    // Borrow the maximum amount
    vm.prank(gus);
    vaultController.borrowUSDA(gusVaultId, _accountBorrowingPower);
    uint192 _initIF = vaultController.interestFactor();
    assertEq(_initIF, _if);

    // Let time pass so the vault becomes liquidatable because of interest
    uint256 _tenYears = 10 * (365 days + 6 hours);
    vm.warp(block.timestamp + _tenYears);
    uint192 _tenYearInterestFactor = _payInterestMath(_if);

    // Calculate interest to update the protocol, vault should now be liquidatable
    vaultController.calculateInterest();
    assertEq(vaultController.interestFactor(), _tenYearInterestFactor);
    uint256 _expectedUSDAToRepurchase =
      _calculateUSDAToRepurchase(anchoredViewBtc.currentValue() * 10 ** 10, _vaultInitialWbtcBalance);
    uint256 _liabilityBeforeLiquidation = vaultController.vaultLiability(gusVaultId);

    // Liquidate vault
    uint256 _daveInitialWbtc = IERC20(WBTC_ADDRESS).balanceOf(dave);
    uint256 _daveUSDA = 1_000_000 ether;
    vm.startPrank(dave);
    susd.approve(address(usdaToken), _daveUSDA);
    usdaToken.deposit(_daveUSDA);
    uint256 _liquidated = vaultController.liquidateVault(gusVaultId, WBTC_ADDRESS, _vaultInitialWbtcBalance);
    vm.stopPrank();

    {
      // Check that everything was liquidate
      assertEq(_liquidated, _vaultInitialWbtcBalance);

      // Check that dave now has the wbtc of the vault
      uint256 _daveFinalWbtc = IERC20(WBTC_ADDRESS).balanceOf(dave);
      assertEq(
        _daveFinalWbtc - _daveInitialWbtc,
        _liquidated - vaultController.getLiquidationFee(uint192(_vaultInitialWbtcBalance), WBTC_ADDRESS)
      );

      // Check that the vault's borrowing power is now zero
      uint192 _newAccountBorrowingPower = vaultController.vaultBorrowingPower(gusVaultId);
      assertEq(_newAccountBorrowingPower, 0);

      // Check that the vault is now empty
      uint256 _vaultWbtcBalance = gusVault.balances(WBTC_ADDRESS);
      uint256 _vaultWbtcBalanceOf = IERC20(WBTC_ADDRESS).balanceOf(address(gusVault));
      assertEq(_vaultWbtcBalance, _vaultWbtcBalanceOf);
      assertEq(_vaultWbtcBalance, 0);

      // Check that the correct USDA amount was taken from dave
      uint256 _daveFinalUSDA = usdaToken.balanceOf(dave);
      assertEq(_daveUSDA - _expectedUSDAToRepurchase, _daveFinalUSDA);
    }

    {
      // Check that the vault's liability is correct
      uint256 _newAccountLiability = vaultController.vaultLiability(gusVaultId);
      assertApproxEqAbs(_newAccountLiability, _liabilityBeforeLiquidation - _expectedUSDAToRepurchase, DELTA);
    }
  }

  function testOverLiquidationAndLiquidateInsolventVaultLessThan18Decimals() public {
    uint256 _gusVaultStartWbtcBalance = gusVault.balances(WBTC_ADDRESS);

    uint192 _gusMaxBorrow = vaultController.vaultBorrowingPower(gusVaultId);

    // gus borrows max amount
    vm.prank(gus);
    vaultController.borrowUSDA(gusVaultId, _gusMaxBorrow);
    assertEq(usdaToken.balanceOf(gus), _gusMaxBorrow);
    assertTrue(vaultController.checkVault(gusVaultId));

    // Advance 1 week and add interest
    vm.warp(block.timestamp + 1 weeks);
    vaultController.calculateInterest();

    // gus's vault is now not solvent
    assertTrue(!vaultController.checkVault(gusVaultId));
    uint256 _liquidatableTokens = vaultController.tokensToLiquidate(gusVaultId, WBTC_ADDRESS);

    uint256 _expectedUSDAToRepurchase =
      _calculateUSDAToRepurchase(anchoredViewBtc.currentValue() * 10 ** 10, _liquidatableTokens);
    uint256 _liabilityBeforeLiquidation = vaultController.vaultLiability(gusVaultId);

    // Liquidate vault with a way higher maximum
    uint256 _daveStartWbtcBalance = IERC20(WBTC_ADDRESS).balanceOf(dave);
    uint256 _daveUSDA = 1_000_000 ether;
    vm.startPrank(dave);
    susd.approve(address(usdaToken), _daveUSDA);
    usdaToken.deposit(_daveUSDA);
    uint256 _liquidated = vaultController.liquidateVault(gusVaultId, WBTC_ADDRESS, _liquidatableTokens * 10);
    vm.stopPrank();

    // Only the max liquidatable amount should be liquidated
    assertEq(_liquidated, _liquidatableTokens);

    // The correct amount of USDA was taken from dave
    assertEq(usdaToken.balanceOf(dave), _daveUSDA - _expectedUSDAToRepurchase);

    // The vault's liability is correct
    assertApproxEqAbs(
      vaultController.vaultLiability(gusVaultId), _liabilityBeforeLiquidation - _expectedUSDAToRepurchase, DELTA
    );

    // Dave got the correct amount of wbtc tokens
    assertEq(
      _daveStartWbtcBalance
        + (_liquidated - vaultController.getLiquidationFee(uint192(_liquidatableTokens), WBTC_ADDRESS)),
      IERC20(WBTC_ADDRESS).balanceOf(dave)
    );

    // gus's vault got some WBTC tokens removed
    assertEq(_gusVaultStartWbtcBalance - _liquidated, gusVault.balances(WBTC_ADDRESS));
    assertGt(gusVault.balances(WBTC_ADDRESS), 0);
  }

  function testBorrowLessThan18Decimals() public {
    uint256 _usdaBalance = usdaToken.balanceOf(gus);
    assertEq(0, _usdaBalance);

    /// Get initial interest factFtestWithdrawUnderlyingr
    uint192 _interestFactor = vaultController.interestFactor();
    uint256 _expectedInterestFactor = _payInterestMath(_interestFactor);

    uint256 _liability = _calculateAccountLiability(borrowAmount, _interestFactor, _interestFactor);

    vm.expectEmit(false, false, false, true);
    emit BorrowUSDA(gusVaultId, address(gusVault), borrowAmount, vaultController.getBorrowingFee(uint192(borrowAmount)));

    vm.prank(gus);
    vaultController.borrowUSDA(gusVaultId, uint192(borrowAmount));

    uint256 _newInterestFactor = vaultController.interestFactor();
    assertEq(_newInterestFactor, _expectedInterestFactor);

    vaultController.calculateInterest();
    vm.prank(gus);
    uint256 _trueLiability = vaultController.vaultLiability(gusVaultId);
    assertEq(_trueLiability, _liability + vaultController.getBorrowingFee(uint192(_liability)));

    uint256 _usdaBalanceAfter = usdaToken.balanceOf(gus);
    assertEq(_usdaBalanceAfter, borrowAmount);
  }

  function testLiquidateVaultWhenCollateralLosesValueLessThan18Decimals() public {
    uint192 _accountBorrowingPower = vaultController.vaultBorrowingPower(gusVaultId);

    // Borrow the maximum amount
    vm.prank(gus);
    vaultController.borrowUSDA(gusVaultId, _accountBorrowingPower);

    // Should revert since vault is solvent
    vm.expectRevert(IVaultController.VaultController_VaultSolvent.selector);
    uint256 _tokensToLiquidate = vaultController.tokensToLiquidate(gusVaultId, WBTC_ADDRESS);

    // mock the value of the token to make vault insolvent
    vm.mockCall(
      address(anchoredViewBtc), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(0.5 ether)
    );
    vm.mockCall(
      address(anchoredViewBtc), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(0.5 ether)
    );
    _tokensToLiquidate = vaultController.tokensToLiquidate(gusVaultId, WBTC_ADDRESS);
    assertEq(_tokensToLiquidate, gusWbtcDeposit);
  }

  function testLiquidateVaultWhenPriceIsStaleLessThan18Decimals() public {
    uint192 _accountBorrowingPower = vaultController.vaultBorrowingPower(gusVaultId);
    uint256 _vaultInitialWbtcBalance = gusVault.balances(WBTC_ADDRESS);

    // Borrow the maximum amount
    vm.prank(gus);
    vaultController.borrowUSDA(gusVaultId, _accountBorrowingPower);

    // Let time pass so the vault becomes liquidatable because of interest
    uint256 _tenYears = 10 * (365 days + 6 hours);
    vm.warp(block.timestamp + _tenYears);

    // Calculate interest to update the protocol, vault should now be liquidatable
    vaultController.calculateInterest();

    // Advance time so the price is stale
    vm.warp(block.timestamp + staleTime + 1);

    uint256 _liquidatableTokens = vaultController.tokensToLiquidate(gusVaultId, WBTC_ADDRESS);
    uint256 _daveUSDA = 1_000_000 ether;
    // Liquidate vault
    vm.startPrank(dave);
    susd.approve(address(usdaToken), _daveUSDA);
    usdaToken.deposit(_daveUSDA);
    uint256 _liquidated = vaultController.liquidateVault(gusVaultId, WBTC_ADDRESS, _vaultInitialWbtcBalance);
    vm.stopPrank();

    // Only the max liquidatable amount should be liquidated
    assertEq(_liquidated, _liquidatableTokens);
  }
}
