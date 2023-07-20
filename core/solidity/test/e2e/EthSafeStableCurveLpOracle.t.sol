// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {UniswapV3TokenOracleRelay} from '@contracts/periphery/oracles/UniswapV3TokenOracleRelay.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';
import {AnchoredViewRelay} from '@contracts/periphery/oracles/AnchoredViewRelay.sol';
import {
  EthSafeStableCurveOracle, StableCurveLpOracle
} from '@contracts/periphery/oracles/EthSafeStableCurveOracle.sol';
import {CreateOracles} from '@scripts/CreateOracles.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {CommonE2EBase, console, IERC20} from '@test/e2e/Common.sol';
import {TestConstants} from '@test/utils/TestConstants.sol';
import {IStablePool} from '@interfaces/utils/ICurvePool.sol';

contract E2ECurveLpOracle is TestConstants, CommonE2EBase {
  uint256 public constant POINT_ONE_PERCENT = 0.001e18;

  EthSafeStableCurveOracle public steCrvOracle;

  function setUp() public virtual override {
    super.setUp();
    /// Deploy StETH oracle relay
    IOracleRelay _anchoredViewStETH = IOracleRelay(_createStEthOracle(uniswapRelayEthUsdc));

    steCrvOracle = EthSafeStableCurveOracle(
      _createSteCrvOracle(STE_CRV_POOL_ADDRESS, _anchoredViewStETH, IOracleRelay(anchoredViewEth))
    );
  }

  function testStethethCrvOracleReturnsTheCorrectPrice() public {
    assertGt(steCrvOracle.currentValue(), 0);
    assertEq(
      steCrvOracle.currentValue(),
      (steCrvOracle.anchoredUnderlyingTokens(0).currentValue() * steCrvOracle.CRV_POOL().get_virtual_price() / 1e18)
    );

    assertApproxEqRel(
      steCrvOracle.currentValue(),
      (steCrvOracle.anchoredUnderlyingTokens(1).currentValue() * steCrvOracle.CRV_POOL().get_virtual_price() / 1e18),
      POINT_ONE_PERCENT
    );
  }
}

contract E2EEthSafeCurveLpOracleManipulations is E2ECurveLpOracle {
  address public wrappedStEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
  IERC20 public stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
  EthCurveLPExploiter public exploiter;

  function setUp() public virtual override {
    super.setUp();
    // We impersonate the wstETH contract to get some stETH
    vm.prank(wrappedStEth);
    stETH.transfer(address(this), 100_001e18); // 100k stETH for us

    // deploy the exploiter contract
    // solhint-disable-next-line reentrancy
    exploiter = new EthCurveLPExploiter(IStablePool(STE_CRV_POOL_ADDRESS), stETH, steCrvOracle);

    // We apporve a lot of stETH
    stETH.approve(address(exploiter), type(uint256).max);
  }

  function testEthSafeCurveLpOracleIsSafeFromManipulation() public {
    vm.expectRevert();
    exploiter.exec{value: 100_000 ether}(100_000 ether);
  }

  function testNotSafeOracleIsRektByManipulation() public {
    IOracleRelay _anchoredViewStETH = IOracleRelay(_createStEthOracle(uniswapRelayEthUsdc));

    IOracleRelay[] memory _anchoredUnderlyingTokens = new IOracleRelay[](2);
    _anchoredUnderlyingTokens[0] = _anchoredViewStETH;
    _anchoredUnderlyingTokens[1] = IOracleRelay(anchoredViewEth);

    // This is an UNSAFE oracle for stETH/ETH. DO NOT USE.
    StableCurveLpOracle _unsafeStETHOracle = new StableCurveLpOracle(STE_CRV_POOL_ADDRESS, _anchoredUnderlyingTokens);

    // deploy the exploiter contract with the unsafe oracle
    EthCurveLPExploiter _exploiter =
    new EthCurveLPExploiter(IStablePool(STE_CRV_POOL_ADDRESS), stETH, EthSafeStableCurveOracle(address(_unsafeStETHOracle)));

    // We apporve max stETH
    stETH.approve(address(_exploiter), type(uint256).max);

    _exploiter.exec{value: 100_000 ether}(100_000 ether);

    assertEq(_exploiter.wasManipulated(), true);
  }
}

contract EthCurveLPExploiter {
  IStablePool public pool;
  IERC20 public stETH;
  EthSafeStableCurveOracle public oracle;
  bool public wasManipulated;
  uint256 internal _virtualPriceBeforeManipulation;

  constructor(IStablePool _pool, IERC20 _stETH, EthSafeStableCurveOracle _oracle) {
    pool = _pool;
    stETH = _stETH;
    oracle = _oracle;
  }

  // pool is assumed to be an ETH pool with just one other token (e.g. stETH pool)
  function exec(uint256 _amountToken) public payable {
    _virtualPriceBeforeManipulation = pool.get_virtual_price();
    // prepare token
    stETH.transferFrom(msg.sender, address(this), _amountToken);
    stETH.approve(address(pool), type(uint256).max); // add liquidity
    uint256[2] memory _amounts = [msg.value, _amountToken];
    uint256 _lps = pool.add_liquidity{value: msg.value}(_amounts, 0);

    pool.lp_token().approve(address(pool), type(uint256).max);

    uint256[2] memory _amounts0;
    pool.remove_liquidity(_lps, _amounts0); // virtual price increased
  }

  receive() external payable {
    // price of LP is pumped right now
    // malicious actions, use the remaining balance of lps if needed ...
    // in here, we need to borrow or withdraw
    oracle.currentValue();
    // Check if the virtual price is now higher
    if (pool.get_virtual_price() > _virtualPriceBeforeManipulation) wasManipulated = true;
  }
}
