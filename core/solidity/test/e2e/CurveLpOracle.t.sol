// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {UniswapV3TokenOracleRelay} from '@contracts/periphery/oracles/UniswapV3TokenOracleRelay.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';
import {AnchoredViewRelay} from '@contracts/periphery/oracles/AnchoredViewRelay.sol';
import {StableCurveLpOracle} from '@contracts/periphery/oracles/StableCurveLpOracle.sol';
import {CreateOracles} from '@scripts/CreateOracles.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {IStablePool} from '@interfaces/utils/ICurvePool.sol';

import {CommonE2EBase, console} from '@test/e2e/Common.sol';
import {TestConstants} from '@test/utils/TestConstants.sol';

contract E2ECurveLpOracle is TestConstants, CommonE2EBase {
  uint256 public constant POINT_ONE_PERCENT = 0.001e18;
  uint256 public constant ONE_PERCENT = 0.01e18;
  uint256 public constant THREE_PERCENT = 0.03e18;

  StableCurveLpOracle public fraxCrvOracle;
  StableCurveLpOracle public frax3CrvOracle;
  StableCurveLpOracle public susdDaiUsdtUsdcOracle;
  StableCurveLpOracle public susdFraxCrvOracle;

  function setUp() public virtual override {
    super.setUp();
    /// Deploy FraxCrv oracle relay
    IOracleRelay _anchoredViewFrax = IOracleRelay(_createFraxOracle());
    /// Deploy susd oracle relay
    IOracleRelay _anchoredViewSusd = IOracleRelay(_createSusdOracle());

    fraxCrvOracle =
      StableCurveLpOracle(_createFraxCrvOracle(FRAX_USDC_CRV_POOL_ADDRESS, _anchoredViewFrax, anchoredViewUsdc));

    frax3CrvOracle =
      StableCurveLpOracle(_createFrax3CrvOracle(FRAX_3CRV_META_POOL_ADDRESS, _anchoredViewFrax, threeCrvOracle));

    susdDaiUsdtUsdcOracle = StableCurveLpOracle(
      _createSusdDaiUsdcUsdtOracle(
        SUSD_DAI_USDT_USDC_CRV_POOL_ADDRESS, _anchoredViewSusd, anchoredViewDai, anchoredViewUsdt, anchoredViewUsdc
      )
    );

    susdFraxCrvOracle =
      StableCurveLpOracle(_createSusdFraxCrvOracle(SUSD_FRAX_CRV_POOL_ADDRESS, _anchoredViewSusd, fraxCrvOracle));
  }

  function testFraxCrvOracleReturnsTheCorrectPrice() public {
    assertGt(fraxCrvOracle.currentValue(), 0);
    assertApproxEqRel(
      fraxCrvOracle.currentValue(),
      (fraxCrvOracle.anchoredUnderlyingTokens(0).currentValue() * fraxCrvOracle.CRV_POOL().get_virtual_price() / 1e18),
      POINT_ONE_PERCENT
    );

    assertApproxEqRel(
      fraxCrvOracle.currentValue(),
      (fraxCrvOracle.anchoredUnderlyingTokens(1).currentValue() * fraxCrvOracle.CRV_POOL().get_virtual_price() / 1e18),
      POINT_ONE_PERCENT
    );
  }

  function test3CrvOracleReturnsTheCorrectPrice() public {
    assertGt(threeCrvOracle.currentValue(), 0);
    assertApproxEqRel(
      threeCrvOracle.currentValue(),
      (threeCrvOracle.anchoredUnderlyingTokens(0).currentValue() * threeCrvOracle.CRV_POOL().get_virtual_price() / 1e18),
      POINT_ONE_PERCENT
    );

    assertApproxEqRel(
      threeCrvOracle.currentValue(),
      (threeCrvOracle.anchoredUnderlyingTokens(1).currentValue() * threeCrvOracle.CRV_POOL().get_virtual_price() / 1e18),
      POINT_ONE_PERCENT
    );

    assertApproxEqRel(
      threeCrvOracle.currentValue(),
      (threeCrvOracle.anchoredUnderlyingTokens(2).currentValue() * threeCrvOracle.CRV_POOL().get_virtual_price() / 1e18),
      POINT_ONE_PERCENT
    );
  }

  function testFrax3CrvOracleReturnsTheCorrectPrice() public {
    assertGt(frax3CrvOracle.currentValue(), 0);
    assertApproxEqRel(
      frax3CrvOracle.currentValue(),
      (frax3CrvOracle.anchoredUnderlyingTokens(0).currentValue() * frax3CrvOracle.CRV_POOL().get_virtual_price() / 1e18),
      POINT_ONE_PERCENT
    );

    assertApproxEqRel(
      frax3CrvOracle.currentValue(),
      (frax3CrvOracle.anchoredUnderlyingTokens(1).currentValue() * frax3CrvOracle.CRV_POOL().get_virtual_price() / 1e18),
      THREE_PERCENT
    );
  }

  function testSusdDaiUsdtUsdcOracleReturnsTheCorrectPrice() public {
    assertGt(susdDaiUsdtUsdcOracle.currentValue(), 0);
    assertApproxEqRel(
      susdDaiUsdtUsdcOracle.currentValue(),
      (
        susdDaiUsdtUsdcOracle.anchoredUnderlyingTokens(0).currentValue()
          * susdDaiUsdtUsdcOracle.CRV_POOL().get_virtual_price() / 1e18
      ),
      ONE_PERCENT
    );

    assertApproxEqRel(
      susdDaiUsdtUsdcOracle.currentValue(),
      (
        susdDaiUsdtUsdcOracle.anchoredUnderlyingTokens(1).currentValue()
          * susdDaiUsdtUsdcOracle.CRV_POOL().get_virtual_price() / 1e18
      ),
      POINT_ONE_PERCENT
    );

    assertApproxEqRel(
      susdDaiUsdtUsdcOracle.currentValue(),
      (
        susdDaiUsdtUsdcOracle.anchoredUnderlyingTokens(2).currentValue()
          * susdDaiUsdtUsdcOracle.CRV_POOL().get_virtual_price() / 1e18
      ),
      POINT_ONE_PERCENT
    );

    assertApproxEqRel(
      susdDaiUsdtUsdcOracle.currentValue(),
      (
        susdDaiUsdtUsdcOracle.anchoredUnderlyingTokens(3).currentValue()
          * susdDaiUsdtUsdcOracle.CRV_POOL().get_virtual_price() / 1e18
      ),
      POINT_ONE_PERCENT
    );
  }

  function testSusdFraxCrvOracleReturnsTheCorrectPrice() public {
    assertGt(susdFraxCrvOracle.currentValue(), 0);
    assertApproxEqRel(
      susdFraxCrvOracle.currentValue(),
      (
        susdFraxCrvOracle.anchoredUnderlyingTokens(0).currentValue() * susdFraxCrvOracle.CRV_POOL().get_virtual_price()
          / 1e18
      ),
      POINT_ONE_PERCENT
    );

    assertApproxEqRel(
      susdFraxCrvOracle.currentValue(),
      (
        susdFraxCrvOracle.anchoredUnderlyingTokens(1).currentValue() * susdFraxCrvOracle.CRV_POOL().get_virtual_price()
          / 1e18
      ),
      POINT_ONE_PERCENT
    );
  }
}
