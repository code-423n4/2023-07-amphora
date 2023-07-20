// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, console} from '@test/e2e/Common.sol';
import {CTokenOracle} from '@contracts/periphery/oracles/CTokenOracle.sol';
import {ICToken} from '@interfaces/periphery/ICToken.sol';

contract E2ECTokenOracle is CommonE2EBase {
  CTokenOracle public cETHOracle;

  function testOracleReturnsTheCorrectPrice() public {
    cETHOracle = new CTokenOracle(cETH_ADDRESS, anchoredViewEth);

    assertGt(cETHOracle.currentValue(), 0);
    assertEq(
      cETHOracle.currentValue(), (anchoredViewEth.currentValue() * ICToken(cETH_ADDRESS).exchangeRateStored() / 1e28)
    );
    assertEq(cETHOracle.underlying(), cETH_ADDRESS);
  }
}
