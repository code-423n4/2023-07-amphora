// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, console, IOracleRelay} from '@test/e2e/Common.sol';
import {AggregatorInterface} from '@chainlink/interfaces/AggregatorInterface.sol';
import {WstEthOracle} from '@contracts/periphery/oracles/WstEthOracle.sol';

contract E2ESimpleOracles is CommonE2EBase {
  IOracleRelay public sUSDOracle;
  WstEthOracle public wstEthOracle;
  IOracleRelay public snxOracle;
  IOracleRelay public cbETHOracle;

  function setUp() public override {
    super.setUp();
    sUSDOracle = IOracleRelay(_createSusdOracle());
    wstEthOracle = WstEthOracle(_createWstEthOracle(IOracleRelay(address(anchoredViewStEth))));
    snxOracle = IOracleRelay(_createSnxOracle(uniswapRelayEthUsdc));
    cbETHOracle = IOracleRelay(_createCbEthOracle(uniswapRelayEthUsdc, chainlinkEth));
  }

  function testSusdOracle() public {
    AggregatorInterface _chainlink = AggregatorInterface(CHAINLINK_SUSD_FEED_ADDRESS);
    uint256 _chainlinkPrice = uint256(_chainlink.latestAnswer()) * 10 ** 10;
    assertEq(sUSDOracle.peekValue(), _chainlinkPrice);
  }

  function testWstEthOracle() public {
    AggregatorInterface _chainlink = AggregatorInterface(CHAINLINK_STETH_USD_FEED_ADDRESS);
    uint256 _chainlinkPrice = uint256(_chainlink.latestAnswer()) * 10 ** 10;
    uint256 _wstEthChainlinkPrice = wstEthOracle.WSTETH().stEthPerToken() * _chainlinkPrice / 1e18;
    assertEq(wstEthOracle.peekValue(), _wstEthChainlinkPrice);
  }

  function testSnxOracle() public {
    AggregatorInterface _chainlink = AggregatorInterface(CHAINLINK_SNX_FEED_ADDRESS);
    uint256 _chainlinkPrice = uint256(_chainlink.latestAnswer()) * 10 ** 10;
    assertEq(snxOracle.peekValue(), _chainlinkPrice);
  }

  function testCbEthOracle() public {
    AggregatorInterface _chainlinkCbEthEth = AggregatorInterface(CHAINLINK_CBETH_ETH_FEED_ADDRESS);
    uint256 _chainlinkCbEthPrice = uint256(_chainlinkCbEthEth.latestAnswer());
    AggregatorInterface _chainlinkEth = AggregatorInterface(CHAINLINK_ETH_FEED_ADDRESS);
    uint256 _chainlinEthPrice = uint256(_chainlinkEth.latestAnswer()) * 10 ** 10;
    assertEq(cbETHOracle.peekValue(), (_chainlinkCbEthPrice * _chainlinEthPrice) / 1e18);
  }
}
