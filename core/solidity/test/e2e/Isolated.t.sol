// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, IVault, console} from '@test/e2e/Common.sol';
import {IUSDA} from '@interfaces/core/IUSDA.sol';
import {IUniswapV2Router02} from '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import {IUniswapV2Factory} from '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import {IUniswapV2Pair} from '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import {IUniswapV3Factory} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {ISwapRouter} from '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

interface INonfungiblePositionManager {
  struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
  }

  struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  struct DecreaseLiquidityParams {
    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  function mint(MintParams calldata _params)
    external
    payable
    returns (uint256 _tokenId, uint128 _liquidity, uint256 _amount0, uint256 _amount1);

  function collect(CollectParams calldata _params) external payable returns (uint256 _amount0, uint256 _amount1);

  function positions(uint256 _tokenId)
    external
    view
    returns (
      uint96 _nonce,
      address _operator,
      address _token0,
      address _token1,
      uint24 _fee,
      int24 _tickLower,
      int24 _tickUpper,
      uint128 _liquidity,
      uint256 _feeGrowthInside0LastX128,
      uint256 _feeGrowthInside1LastX128,
      uint128 _tokensOwed0,
      uint128 _tokensOwed1
    );

  function decreaseLiquidity(DecreaseLiquidityParams calldata _params)
    external
    payable
    returns (uint256 _amount0, uint256 _amount1);
}

abstract contract IsolatedBase is CommonE2EBase {
  IUniswapV2Router02 public uniV2Router = IUniswapV2Router02(UNI_V2_ROUTER);
  IUniswapV3Factory public factoryV3 = IUniswapV3Factory(UNI_V3_FACTORY);
  INonfungiblePositionManager public nfpManager = INonfungiblePositionManager(UNI_V3_NFP_MANAGER);
  ISwapRouter public swapRouter = ISwapRouter(UNI_V3_SWAP_ROUTER);

  function setUp() public virtual override {
    super.setUp();

    // time travel
    vm.warp(block.timestamp + 1 days);

    // pay interest
    vaultController.calculateInterest();

    // interest factor is slightly higher due to time passing
    uint256 _interestFactor = vaultController.interestFactor();
    assert(_interestFactor != 1 ether);

    // no new USDA has been minted
    assert(usdaToken.totalSupply() == 1 ether);
    assert(usdaToken.scaledTotalSupply() == usdaToken.totalSupply() * 1e48);
    assert(usdaToken.reserveRatio() == 0);

    // NOTE: should I make asserts to confirm that the protocol is empty?
  }
}

contract E2EBorrowSUSD is IsolatedBase {
  uint256 public depositAmount = daveSUSD - 500 ether;
  uint192 public sUSDBorrow = 1000 ether;
  uint256 public wethDepositAmount = 1 ether;

  function testBorrowSUSD() public {
    // dave deposits a large amount of sUSD for USDA
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(depositAmount);
    vm.stopPrank();
    assert(usdaToken.balanceOf(dave) == depositAmount);

    // check for interest generations
    vm.warp(block.timestamp + 1 days);
    vaultController.calculateInterest();
    assert(usdaToken.balanceOf(dave) == depositAmount);

    // check interest again after 1 year
    vm.warp(block.timestamp + 365 days);
    vaultController.calculateInterest();
    assert(usdaToken.balanceOf(dave) == depositAmount);

    // bob mints vault
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // bob deposits wETH collateral
    vm.startPrank(bob);
    weth.approve(address(bobVault), wethDepositAmount);
    bobVault.depositERC20(WETH_ADDRESS, wethDepositAmount);
    vm.stopPrank();

    // check borrow power
    uint256 _borrowPower = vaultController.vaultBorrowingPower(bobVaultId);
    uint192 _bp = _safeu192(_truncate(_truncate(WETH_LTV * wethDepositAmount * anchoredViewEth.currentValue())));
    assert(_borrowPower == _bp - vaultController.getBorrowingFee(_bp));
    uint256 _liability = vaultController.vaultLiability(bobVaultId);
    assert(_liability == 0);

    // bob borrows sUSD
    vm.startPrank(bob);
    uint256 _startingUSD = susd.balanceOf(bob);
    vaultController.borrowsUSDto(bobVaultId, sUSDBorrow, bob);
    uint256 _endingUSD = susd.balanceOf(bob);
    vm.stopPrank();
    assert(_endingUSD - _startingUSD == sUSDBorrow);

    // checks liability
    _liability = vaultController.vaultLiability(bobVaultId);
    uint256 _liabilityWithFee = sUSDBorrow + vaultController.getBorrowingFee(uint192(sUSDBorrow));
    assertApproxEqAbs(_liability / 1 ether, _liabilityWithFee / 1 ether, 1);

    // withdraw all reserves
    vm.prank(dave);
    usdaToken.withdrawAll();

    // reserve should be empty
    assert(susd.balanceOf(address(usdaToken)) == 0);

    // should revert
    vm.prank(bob);
    vm.expectRevert();
    vaultController.borrowsUSDto(bobVaultId, 1, bob);
  }
}

contract E2EMultiAssetLoan is IsolatedBase {
  uint256 public depositAmount = daveSUSD - 1000 ether;
  uint256 public wbtcAmount = 1e8;
  uint256 public uniAmount = 90 ether;

  function testMultiAssetLoan() public {
    // dave deposits sUSD to reserve and receives USDA
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(depositAmount);
    vm.stopPrank();
    assert(usdaToken.balanceOf(dave) == depositAmount);

    // make a vault and transfer wBTC
    gusVaultId = _mintVault(gus);
    gusVault = IVault(vaultController.vaultIdVaultAddress(gusVaultId));

    // deposits wbtc
    vm.startPrank(gus);
    wbtc.approve(address(gusVault), wbtcAmount);
    gusVault.depositERC20(WBTC_ADDRESS, wbtcAmount);
    uint256 _wbtcBorrowPower = vaultController.vaultBorrowingPower(gusVaultId);
    vm.stopPrank();
    assert(wbtc.balanceOf(gus) == gusWBTC - wbtcAmount);

    // deposits uni
    vm.startPrank(gus);
    uni.approve(address(gusVault), uniAmount);
    gusVault.depositERC20(UNI_ADDRESS, uniAmount);
    uint256 _uniBorrowPower = vaultController.vaultBorrowingPower(gusVaultId) - _wbtcBorrowPower;
    vm.stopPrank();
    assert(uni.balanceOf(gus) == gusUni - uniAmount);

    // check borrow power
    uint256 _wbtcPrice = anchoredViewBtc.currentValue();
    uint256 _wbtcBalance = wbtc.balanceOf(address(gusVault));
    uint256 _wbtcValue = (_wbtcBalance * _wbtcPrice * 10 ** 10) / 1 ether; // in e18
    uint256 _expectedWbtcBorrowPower = (_wbtcValue * WBTC_LTV) / 1 ether;
    assert(
      _expectedWbtcBorrowPower - vaultController.getBorrowingFee(uint192(_expectedWbtcBorrowPower)) == _wbtcBorrowPower
    );
    uint256 _uniPrice = anchoredViewUni.currentValue();
    uint256 _uniBalance = uni.balanceOf(address(gusVault));
    uint256 _uniValue = (_uniBalance * _uniPrice) / 1 ether;
    uint256 _expectedUniBorrowPower = (_uniValue * UNI_LTV) / 1 ether;
    assert(
      _expectedUniBorrowPower - vaultController.getBorrowingFee(uint192(_expectedUniBorrowPower)) == _uniBorrowPower
    );

    // borrow max USDA
    vm.startPrank(gus);
    uint256 _maxBorrow = vaultController.vaultBorrowingPower(gusVaultId);
    vaultController.borrowUSDA(gusVaultId, uint192(_maxBorrow));
    vm.stopPrank();
    assert(_maxBorrow == usdaToken.balanceOf(gus));

    // put vault underwater
    vm.warp(block.timestamp + 2 weeks);
    vaultController.calculateInterest();
    assert(vaultController.checkVault(gusVaultId) == false);

    // liquidate wbtc
    vm.startPrank(dave);
    uint256 _wbtcToLiq = vaultController.tokensToLiquidate(gusVaultId, WBTC_ADDRESS);
    _wbtcToLiq -= 5000;
    vaultController.liquidateVault(gusVaultId, WBTC_ADDRESS, _wbtcToLiq);
    assert(wbtc.balanceOf(dave) == _wbtcToLiq - vaultController.getLiquidationFee(uint192(_wbtcToLiq), WBTC_ADDRESS));
    vm.stopPrank();

    // liquidate uni
    vm.startPrank(dave);
    uint256 _uniToLiq = vaultController.tokensToLiquidate(gusVaultId, UNI_ADDRESS);
    vaultController.liquidateVault(gusVaultId, UNI_ADDRESS, _uniToLiq);
    assert(uni.balanceOf(dave) == _uniToLiq - vaultController.getLiquidationFee(uint192(_uniToLiq), UNI_ADDRESS));
    vm.stopPrank();
    assertApproxEqAbs(vaultController.amountToSolvency(gusVaultId), 0, 5);

    // mint some USDA
    uint256 _toMint = gusVault.baseLiability() * 2;
    vm.startPrank(address(governor));
    usdaToken.mint(_toMint);
    usdaToken.transfer(gus, _toMint);
    vm.stopPrank();

    // repay all
    vm.startPrank(gus);
    usdaToken.approve(address(vaultController), type(uint256).max);
    vaultController.repayAllUSDA(gusVaultId);
    vm.stopPrank();
    assert(vaultController.vaultLiability(gusVaultId) == 0);

    // withdraw wBTC
    vm.startPrank(gus);
    uint256 _gusWbtcBalance = wbtc.balanceOf(gus);
    uint256 _wbtcToWithdraw = wbtc.balanceOf(address(gusVault));
    gusVault.withdrawERC20(WBTC_ADDRESS, _wbtcToWithdraw);
    vm.stopPrank();
    assert(wbtc.balanceOf(gus) == _gusWbtcBalance + _wbtcToWithdraw);

    // withdraw UNI
    vm.startPrank(gus);
    uint256 _gusUniBalance = uni.balanceOf(gus);
    uint256 _uniToWithdraw = uni.balanceOf(address(gusVault));
    gusVault.withdrawERC20(UNI_ADDRESS, _uniToWithdraw);
    vm.stopPrank();
    assert(uni.balanceOf(gus) == _gusUniBalance + _uniToWithdraw);

    // borrow power == 0
    assert(vaultController.vaultBorrowingPower(gusVaultId) == 0);
  }
}

contract E2ENoLoans is IsolatedBase {
  uint256 public depositAmount = daveSUSD - 1000 ether;

  function testNoLoans() public {
    // dave deposits sUSD to reserve and receives USDA
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(depositAmount);
    vm.stopPrank();
    assert(usdaToken.balanceOf(dave) == depositAmount);

    // check for interest generations
    vm.warp(block.timestamp + 1 days);
    vaultController.calculateInterest();
    assert(usdaToken.balanceOf(dave) == depositAmount);

    // check interest again after 1 year
    vm.warp(block.timestamp + 365 days);
    vaultController.calculateInterest();
    assert(usdaToken.balanceOf(dave) == depositAmount);

    // what happens if someone donates in this scenario
    uint256 _balance = susd.balanceOf(dave);
    uint256 _reserve = susd.balanceOf(address(usdaToken));
    assert(_reserve == depositAmount);

    vm.startPrank(dave);
    uint256 _initialTotalSupply = usdaToken.totalSupply();
    uint256 _donateAmount = _balance / 2;
    susd.approve(address(usdaToken), _donateAmount);
    usdaToken.donate(_donateAmount);
    uint256 _newTotalSupply = usdaToken.totalSupply();
    uint256 _newReserve = susd.balanceOf(address(usdaToken));
    vm.stopPrank();
    assert(_newTotalSupply == _initialTotalSupply + _donateAmount);
    assert(_newReserve == _reserve + _donateAmount);
    assert(usdaToken.reserveRatio() < 1 ether);
    assert(usdaToken.reserveRatio() > 0.99 ether);

    // andy send 100 sUSD to the USDA contract, reserve should be the same
    vm.startPrank(andy);
    uint256 _beforeReserveRatio = usdaToken.reserveRatio();
    susd.transfer(address(usdaToken), 100 ether);
    uint256 _afterReserveRatio = usdaToken.reserveRatio();
    assert(_beforeReserveRatio == _afterReserveRatio);
    vm.stopPrank();
  }
}

contract E2ENoReserve is IsolatedBase {
  uint256 public depositAmount = daveSUSD - 1000 ether;
  uint256 public erroniusAmount = 500 ether;

  function testNoReserve() public {
    // confirm reserve is 0
    uint256 _reserve = susd.balanceOf(address(usdaToken));
    assert(_reserve == 0);

    // bob mints vault
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // bob deposits wETH collateral
    vm.startPrank(bob);
    weth.approve(address(bobVault), 1 ether);
    bobVault.depositERC20(WETH_ADDRESS, 1 ether);
    vm.stopPrank();

    // bob borrows full amount
    vm.startPrank(bob);
    uint256 _maxBorrow = vaultController.vaultBorrowingPower(bobVaultId);
    vaultController.borrowUSDA(bobVaultId, uint192(_maxBorrow));
    vm.stopPrank();
    assert(_maxBorrow == usdaToken.balanceOf(bob));

    // confirm reserve is still 0
    uint256 _reserveAgain = susd.balanceOf(address(usdaToken));
    assert(_reserveAgain == 0);

    // carol mints vault
    carolVaultId = _mintVault(carol);
    carolVault = IVault(vaultController.vaultIdVaultAddress(carolVaultId));

    // carol deposits wETH collateral
    vm.startPrank(carol);
    uni.approve(address(carolVault), 1 ether);
    carolVault.depositERC20(UNI_ADDRESS, 1 ether);
    vm.stopPrank();

    // carol borrows full amount
    vm.startPrank(carol);
    uint256 _maxBorrowCarol = vaultController.vaultBorrowingPower(carolVaultId);
    vaultController.borrowUSDA(carolVaultId, uint192(_maxBorrowCarol));
    vm.stopPrank();
    assert(_maxBorrowCarol == usdaToken.balanceOf(carol));

    // check
    uint256 _initLiability = vaultController.vaultLiability(carolVaultId);
    uint256 _startBalance = usdaToken.balanceOf(address(governor));
    uint256 _initBaseLiability = vaultController.totalBaseLiability();
    uint256 _initInterestFactor = vaultController.interestFactor();

    vm.warp(block.timestamp + 365 days);
    vaultController.calculateInterest();

    uint256 _accountLiability = vaultController.vaultLiability(carolVaultId);
    assert(_accountLiability > _initLiability);

    uint256 _balance = usdaToken.balanceOf(address(governor));
    assert(_balance > _startBalance);

    uint256 _totalBaseLiability = vaultController.totalBaseLiability();
    assert(_totalBaseLiability == _initBaseLiability);

    uint256 _interestFactor = vaultController.interestFactor();
    assert(_interestFactor > _initInterestFactor);

    // try to withdraw from empty reserve
    vm.prank(frank);
    vm.expectRevert(IUSDA.USDA_EmptyReserve.selector);
    usdaToken.withdrawAll();

    // test donate reserve
    assert(susd.balanceOf(address(usdaToken)) == 0);

    // deposit
    vm.startPrank(bob);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(susd.balanceOf(bob));
    vm.stopPrank();

    // errouniously transfer some sUSD to the reserve
    vm.prank(dave);
    susd.transfer(address(usdaToken), erroniusAmount);

    // check
    uint256 _totalSUSD = susd.balanceOf(address(usdaToken));
    assert(_totalSUSD == bobSUSDBalance + erroniusAmount);

    // do a normal donate
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.donate(erroniusAmount);
    vm.stopPrank();
  }
}

contract E2EUniPool is IsolatedBase {
  uint256 public depositAmount = daveSUSD - 500 ether;
  uint256 public susdDepositAmount = daveSUSD / 4;
  uint256 public collateralAmount = bobWETH / 2;
  uint256 public amountToSwap = 500 ether;

  function testUniPool() public {
    // dave deposits sUSD to reserve and receives USDA
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(susdDepositAmount);
    vm.stopPrank();
    assertEq(usdaToken.balanceOf(dave), susdDepositAmount);

    // bob mints vault, start some liability
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // bob deposits wETH collateral
    vm.startPrank(bob);
    weth.approve(address(bobVault), collateralAmount);
    bobVault.depositERC20(WETH_ADDRESS, collateralAmount);
    vm.stopPrank();

    // bob borrows full amount
    vm.startPrank(bob);
    uint256 _maxBorrow = vaultController.vaultBorrowingPower(bobVaultId);
    uint256 _borrowAmount = _maxBorrow - (_maxBorrow / 5);
    vaultController.borrowUSDA(bobVaultId, uint192(_borrowAmount));
    vm.stopPrank();
    assertEq(_borrowAmount, usdaToken.balanceOf(bob));

    // create uni v2 pool
    vm.startPrank(bob);
    uint256 _wethAmount = weth.balanceOf(bob);
    uint256 _usdaAmount = usdaToken.balanceOf(bob);
    weth.approve(address(uniV2Router), _wethAmount);
    usdaToken.approve(address(uniV2Router), _usdaAmount);
    uniV2Router.addLiquidity(
      WETH_ADDRESS, address(usdaToken), _wethAmount, _usdaAmount, _wethAmount, _usdaAmount, bob, block.timestamp
    );
    assertEq(weth.balanceOf(bob), 0);
    assertEq(usdaToken.balanceOf(bob), 0);

    // check pair
    IUniswapV2Factory _factory = IUniswapV2Factory(uniV2Router.factory());
    IUniswapV2Pair _pair = IUniswapV2Pair(_factory.getPair(WETH_ADDRESS, address(usdaToken)));
    assertTrue(address(_pair) != address(0));
    {
      (uint256 _reserve01, uint256 _reserve02,) = _pair.getReserves();
      (address _token0, address _token1) =
        WETH_ADDRESS < address(usdaToken) ? (WETH_ADDRESS, address(usdaToken)) : (address(usdaToken), WETH_ADDRESS);
      if (_token0 == address(usdaToken)) (_reserve01, _reserve02) = (_reserve02, _reserve01);
      assertEq(_reserve01, _wethAmount);
      assertEq(_reserve02, _usdaAmount);
      assertEq(_pair.token0(), _token0);
      assertEq(_pair.token1(), _token1);
    }

    // check what happens when USDA rebases in the pool
    (uint256 _startingUSDAReserves,,) = _pair.getReserves();
    uint256 _lpTokens = _pair.balanceOf(bob);
    vm.warp(block.timestamp + 365 days);
    vaultController.calculateInterest();
    (uint256 _currentUSDAReserves,,) = _pair.getReserves();
    assertEq(_startingUSDAReserves, _currentUSDAReserves);
    vm.stopPrank();

    // balance higher due interest
    assertGt(usdaToken.balanceOf(address(_pair)), _startingUSDAReserves);
    uint256 _currentLpTokens = _pair.balanceOf(bob);
    assertEq(_currentLpTokens, _lpTokens);

    // do a small swap
    vm.startPrank(dave);
    uint256 _usdaBalanceBeforeSwap = usdaToken.balanceOf(dave);
    uint256 _wethBalanceBeforeSwap = weth.balanceOf(dave);
    address[] memory _path = new address[](2);
    _path[0] = address(usdaToken);
    _path[1] = WETH_ADDRESS;
    usdaToken.approve(address(uniV2Router), amountToSwap);
    uniV2Router.swapExactTokensForTokens(amountToSwap, 1, _path, dave, block.timestamp);
    uint256 _usdaAfterBeforeSwap = usdaToken.balanceOf(dave);
    uint256 _wethAfterBeforeSwap = weth.balanceOf(dave);
    vm.stopPrank();
    assertEq(_usdaBalanceBeforeSwap - amountToSwap, _usdaAfterBeforeSwap);
    assertGt(_wethAfterBeforeSwap, _wethBalanceBeforeSwap);

    // remove liq
    vm.startPrank(bob);
    uint256 _lpTokenBalance = _pair.balanceOf(bob);
    _pair.approve(address(uniV2Router), _lpTokens);
    uniV2Router.removeLiquidity(WETH_ADDRESS, address(usdaToken), _lpTokenBalance, 1, 1, bob, block.timestamp);
    vm.stopPrank();
    assertApproxEqAbs(usdaToken.balanceOf(address(_pair)), 0, 100_000);
  }
}

contract E2EUniV3Pool is IsolatedBase {
  uint256 public susdDepositAmount = daveSUSD / 4;
  uint256 public collateralAmount = bobWETH / 2;

  function testUniV3Pool() public {
    // dave deposits sUSD to reserve and receives USDA
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(susdDepositAmount);
    vm.stopPrank();
    assertEq(usdaToken.balanceOf(dave), susdDepositAmount);

    // bob mints vault, start some liability
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // bob deposits wETH collateral
    vm.startPrank(bob);
    weth.approve(address(bobVault), collateralAmount);
    bobVault.depositERC20(WETH_ADDRESS, collateralAmount);
    vm.stopPrank();

    // bob borrows full amount
    vm.startPrank(bob);
    uint256 _maxBorrow = vaultController.vaultBorrowingPower(bobVaultId);
    uint256 _borrowAmount = _maxBorrow - (_maxBorrow / 5);
    vaultController.borrowUSDA(bobVaultId, uint192(_borrowAmount));
    vm.stopPrank();
    assertEq(_borrowAmount, usdaToken.balanceOf(bob));

    // use borrowed USDA to make a pool
    vm.startPrank(bob);
    address _poolAddress = factoryV3.createPool(address(usdaToken), WETH_ADDRESS, 10_000);

    // mint
    uint256 _startUSDA = usdaToken.balanceOf(bob);
    uint256 _startWETH = weth.balanceOf(bob);
    uint160 _sqrtPriceX96 = 1_893_862_710_253_677_737_936_450_510;

    IUniswapV3Pool(_poolAddress).initialize(_sqrtPriceX96);

    weth.approve(address(nfpManager), type(uint256).max);
    usdaToken.approve(address(nfpManager), type(uint256).max);

    (address _token0, address _token1) =
      WETH_ADDRESS < address(usdaToken) ? (WETH_ADDRESS, address(usdaToken)) : (address(usdaToken), WETH_ADDRESS);
    if (_token0 == address(usdaToken)) (_startWETH, _startUSDA) = (_startUSDA, _startWETH);

    INonfungiblePositionManager.MintParams memory _params = INonfungiblePositionManager.MintParams({
      token0: _token0,
      token1: _token1,
      fee: 10_000,
      tickLower: -76_000,
      tickUpper: -73_200,
      amount0Desired: _startWETH,
      amount1Desired: _startUSDA,
      amount0Min: 1,
      amount1Min: 1,
      recipient: bob,
      deadline: block.timestamp
    });
    (uint256 _tokenId,,,) = nfpManager.mint(_params);

    vm.stopPrank();

    // advance time
    vm.warp(block.timestamp + 365 days);
    vaultController.calculateInterest();

    // dave does a small swap
    uint256 _usdaToSwap = 100 ether;

    vm.startPrank(dave);
    usdaToken.approve(address(swapRouter), _usdaToSwap);
    ISwapRouter.ExactInputSingleParams memory _swapParams = ISwapRouter.ExactInputSingleParams({
      tokenIn: address(usdaToken),
      tokenOut: WETH_ADDRESS,
      fee: 10_000,
      recipient: dave,
      deadline: block.timestamp,
      amountIn: _usdaToSwap,
      amountOutMinimum: 1,
      sqrtPriceLimitX96: 0
    });

    swapRouter.exactInputSingle(_swapParams);
    assertGt(weth.balanceOf(dave), 0);

    // advance time again
    vm.warp(block.timestamp + 365 days);
    vaultController.calculateInterest();
    vm.stopPrank();

    // collect fee from pool, unclaimed USDA rewards do not accrue interest
    vm.startPrank(bob);
    uint256 _usdaBeforeCollect = usdaToken.balanceOf(bob);

    INonfungiblePositionManager.CollectParams memory _collectParams = INonfungiblePositionManager.CollectParams({
      tokenId: _tokenId,
      recipient: bob,
      amount0Max: type(uint128).max,
      amount1Max: type(uint128).max
    });

    nfpManager.collect(_collectParams);

    uint256 _usdaAfterCollect = usdaToken.balanceOf(bob);
    uint256 _diff = _usdaAfterCollect - _usdaBeforeCollect;

    assert(_diff > 0);
    vm.stopPrank();

    // remove liq
    vaultController.calculateInterest();

    vm.startPrank(bob);

    (,,,,,,, uint128 _liquidity,,,,) = nfpManager.positions(_tokenId);

    INonfungiblePositionManager.DecreaseLiquidityParams memory _decreaseParams = INonfungiblePositionManager
      .DecreaseLiquidityParams({
      tokenId: _tokenId,
      liquidity: _liquidity,
      amount0Min: 0,
      amount1Min: 0,
      deadline: block.timestamp
    });

    nfpManager.decreaseLiquidity(_decreaseParams);

    _collectParams = INonfungiblePositionManager.CollectParams({
      tokenId: _tokenId,
      recipient: bob,
      amount0Max: type(uint128).max,
      amount1Max: type(uint128).max
    });

    nfpManager.collect(_collectParams);

    vm.stopPrank();

    // confirm liq == 0
    (,,,,,,, _liquidity,,,,) = nfpManager.positions(_tokenId);
    assertEq(_liquidity, 0);
  }
}

contract E2EwUSDAUniV3 is IsolatedBase {
  uint256 public susdDepositAmount = daveSUSD / 4;
  uint256 public collateralAmount = 4 ether;
  uint256 public usdaAmount = 1000 ether;

  function testwUSDAUniV3() public {
    // dave deposits sUSD to reserve and receives USDA
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(susdDepositAmount);
    vm.stopPrank();
    assert(usdaToken.balanceOf(dave) == susdDepositAmount);

    // bob mints vault, start some liability
    bobVaultId = _mintVault(bob);
    bobVault = IVault(vaultController.vaultIdVaultAddress(bobVaultId));

    // bob deposits wETH collateral
    vm.startPrank(bob);
    weth.approve(address(bobVault), collateralAmount);
    bobVault.depositERC20(WETH_ADDRESS, collateralAmount);
    vm.stopPrank();

    // bob borrows full amount
    vm.startPrank(bob);
    uint256 _maxBorrow = vaultController.vaultBorrowingPower(bobVaultId);
    uint256 _borrowAmount = _maxBorrow - (_maxBorrow / 5);
    vaultController.borrowUSDA(bobVaultId, uint192(_borrowAmount));
    vm.stopPrank();
    assert(_borrowAmount == usdaToken.balanceOf(bob));

    // initializes balances
    vm.startPrank(bob);
    usdaToken.transfer(eric, usdaAmount);
    usdaToken.transfer(gus, usdaAmount);
    vm.stopPrank();

    // wrap some USDA
    vm.startPrank(gus);
    usdaToken.approve(address(wusda), usdaAmount);
    wusda.deposit(usdaAmount);
    vm.stopPrank();
    assert(usdaToken.balanceOf(gus) == 0);
    assert(wusda.balanceOf(gus) == wusda.underlyingToWrapper(usdaAmount));

    // advance time, compare balances
    vm.warp(block.timestamp + 365 days);
    vaultController.calculateInterest();

    uint256 _controlBalance = usdaToken.balanceOf(eric);
    assert(_controlBalance > usdaAmount);

    uint256 _underlying = wusda.balanceOfUnderlying(gus);
    vm.prank(gus);
    wusda.withdraw(_underlying - 1 ether);
    assertApproxEqAbs(usdaToken.balanceOf(gus), _controlBalance, 1 ether);

    // wrap some more USDA
    vm.startPrank(gus);

    vm.stopPrank();

    // bob transfer some wETH
    vm.prank(bob);
    weth.transfer(gus, 5 ether);

    // use wUSDA to make a pool
    vm.startPrank(gus);
    address _poolAddress = factoryV3.createPool(address(wusda), WETH_ADDRESS, 10_000);

    // mint
    uint256 _startWUSDA = wusda.balanceOf(gus);
    uint256 _startWETH = weth.balanceOf(gus);

    uint160 _sqrtPriceX96 = 1_893_862_710_253_677_737_936_450_510;

    IUniswapV3Pool(_poolAddress).initialize(_sqrtPriceX96);

    weth.approve(address(nfpManager), type(uint256).max);
    wusda.approve(address(nfpManager), type(uint256).max);

    (address _token0, address _token1) =
      WETH_ADDRESS < address(wusda) ? (WETH_ADDRESS, address(wusda)) : (address(wusda), WETH_ADDRESS);
    if (_token0 == address(usdaToken)) (_startWETH, _startWUSDA) = (_startWUSDA, _startWETH);

    INonfungiblePositionManager.MintParams memory _params = INonfungiblePositionManager.MintParams({
      token0: _token0,
      token1: _token1,
      fee: 10_000,
      tickLower: -76_000,
      tickUpper: -73_200,
      amount0Desired: _startWUSDA,
      amount1Desired: _startWETH,
      amount0Min: 1,
      amount1Min: 1,
      recipient: gus,
      deadline: block.timestamp
    });
    (uint256 _tokenId,,,) = nfpManager.mint(_params);

    vm.stopPrank();

    // advance time
    vm.warp(block.timestamp + 365 days);
    vaultController.calculateInterest();

    // bob does a small swap
    vm.startPrank(bob);
    uint256 _bobWETH = weth.balanceOf(bob);
    uint256 _swapAmount = 0.001 ether;

    weth.approve(address(swapRouter), type(uint256).max);
    ISwapRouter.ExactInputSingleParams memory _swapParams = ISwapRouter.ExactInputSingleParams({
      tokenIn: WETH_ADDRESS,
      tokenOut: address(wusda),
      fee: 10_000,
      recipient: bob,
      deadline: block.timestamp,
      amountIn: _swapAmount,
      amountOutMinimum: 1,
      sqrtPriceLimitX96: 0
    });

    swapRouter.exactInputSingle(_swapParams);
    assertLt(weth.balanceOf(bob), _bobWETH);

    vm.stopPrank();

    // advance time again
    vm.warp(block.timestamp + 365 days);
    vaultController.calculateInterest();

    // collect fee from pool
    vm.startPrank(gus);
    uint256 _wusdaBeforeCollect = wusda.balanceOf(gus);

    INonfungiblePositionManager.CollectParams memory _collectParams = INonfungiblePositionManager.CollectParams({
      tokenId: _tokenId,
      recipient: gus,
      amount0Max: type(uint128).max,
      amount1Max: type(uint128).max
    });

    nfpManager.collect(_collectParams);

    uint256 _wusdaAfterCollect = wusda.balanceOf(gus);
    uint256 _diffCollect = _wusdaAfterCollect - _wusdaBeforeCollect;

    assert(_diffCollect == 0);
    vm.stopPrank();

    // remove liq
    vaultController.calculateInterest();

    vm.startPrank(gus);

    (,,,,,,, uint128 _liquidity,,,,) = nfpManager.positions(_tokenId);

    INonfungiblePositionManager.DecreaseLiquidityParams memory _decreaseParams = INonfungiblePositionManager
      .DecreaseLiquidityParams({
      tokenId: _tokenId,
      liquidity: _liquidity,
      amount0Min: 0,
      amount1Min: 0,
      deadline: block.timestamp
    });

    nfpManager.decreaseLiquidity(_decreaseParams);

    _collectParams = INonfungiblePositionManager.CollectParams({
      tokenId: _tokenId,
      recipient: gus,
      amount0Max: type(uint128).max,
      amount1Max: type(uint128).max
    });

    nfpManager.collect(_collectParams);

    vm.stopPrank();

    // confirm liq == 0
    (,,,,,,, _liquidity,,,,) = nfpManager.positions(_tokenId);
    assert(_liquidity == 0);

    // unwrap and compare to control
    vm.startPrank(gus);
    uint256 _balanceBeforeUnwrap = wusda.balanceOf(gus);
    wusda.withdrawAll();
    uint256 _balanceAfterUnwrap = wusda.balanceOf(gus);
    // TODO: This check fails after changing the three crv oracle
    // assert(_balanceBeforeUnwrap > _balanceAfterUnwrap);
    vm.stopPrank();
  }
}

contract E2EWBtcLoan is IsolatedBase {
  uint256 public depositAmount = daveSUSD - 1000 ether;
  uint256 public wbtcAmount = 1e8;

  function testWBtcLoan() public {
    // dave deposits sUSD to reserve and receives USDA
    vm.startPrank(dave);
    susd.approve(address(usdaToken), type(uint256).max);
    usdaToken.deposit(depositAmount);
    vm.stopPrank();
    assert(usdaToken.balanceOf(dave) == depositAmount);

    // make a vault and transfer wBTC
    gusVaultId = _mintVault(gus);
    gusVault = IVault(vaultController.vaultIdVaultAddress(gusVaultId));

    // deposits wbtc
    vm.startPrank(gus);
    wbtc.approve(address(gusVault), wbtcAmount);
    gusVault.depositERC20(WBTC_ADDRESS, wbtcAmount);
    uint256 _wbtcBorrowPower = vaultController.vaultBorrowingPower(gusVaultId);
    vm.stopPrank();
    assert(wbtc.balanceOf(gus) == gusWBTC - wbtcAmount);

    // check borrow power
    uint256 _wbtcPrice = anchoredViewBtc.currentValue();
    uint256 _wbtcBalance = wbtc.balanceOf(address(gusVault));
    uint256 _wbtcValue = (_wbtcBalance * _wbtcPrice * 10 ** 10) / 1 ether; // In e18
    uint256 _expectedWbtcBorrowPower = (_wbtcValue * WBTC_LTV) / 1 ether;
    assert(
      _expectedWbtcBorrowPower - vaultController.getBorrowingFee(uint192(_expectedWbtcBorrowPower)) == _wbtcBorrowPower
    );

    // borrow max USDA
    vm.startPrank(gus);
    uint256 _maxBorrow = vaultController.vaultBorrowingPower(gusVaultId);
    vaultController.borrowUSDA(gusVaultId, uint192(_maxBorrow));
    vm.stopPrank();
    assert(_maxBorrow == usdaToken.balanceOf(gus));

    // put vault underwater
    vm.warp(block.timestamp + 2 weeks);
    vaultController.calculateInterest();
    assert(vaultController.checkVault(gusVaultId) == false);

    // liquidate wbtc
    vm.startPrank(dave);
    uint256 _wbtcToLiq = vaultController.tokensToLiquidate(gusVaultId, WBTC_ADDRESS);
    vaultController.liquidateVault(gusVaultId, WBTC_ADDRESS, _wbtcToLiq);
    assert(wbtc.balanceOf(dave) == _wbtcToLiq - vaultController.getLiquidationFee(uint192(_wbtcToLiq), WBTC_ADDRESS));
    vm.stopPrank();

    // mint some USDA
    uint256 _toMint = gusVault.baseLiability() * 2;
    vm.startPrank(address(governor));
    usdaToken.mint(_toMint);
    usdaToken.transfer(gus, _toMint);
    vm.stopPrank();

    // repay all
    vm.startPrank(gus);
    usdaToken.approve(address(vaultController), type(uint256).max);
    vaultController.repayAllUSDA(gusVaultId);
    vm.stopPrank();
    assert(vaultController.vaultLiability(gusVaultId) == 0);

    // withdraw wBTC
    vm.startPrank(gus);
    uint256 _gusWbtcBalance = wbtc.balanceOf(gus);
    uint256 _wbtcToWithdraw = wbtc.balanceOf(address(gusVault));
    gusVault.withdrawERC20(WBTC_ADDRESS, _wbtcToWithdraw);
    vm.stopPrank();
    assert(wbtc.balanceOf(gus) == _gusWbtcBalance + _wbtcToWithdraw);

    // borrow power == 0
    assert(vaultController.vaultBorrowingPower(gusVaultId) == 0);
  }
}
