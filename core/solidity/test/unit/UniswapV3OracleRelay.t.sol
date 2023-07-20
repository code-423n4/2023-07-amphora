// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus, console} from 'solidity-utils/test/DSTestPlus.sol';
import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';

import {
  IUniswapV3Pool,
  IUniswapV3PoolImmutables,
  IUniswapV3PoolDerivedState
} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

contract UniswapV3OracleRelayForTest is UniswapV3OracleRelay {
  bool public mock;

  constructor(
    uint32 _lookback,
    address _poolAddress,
    bool _quoteTokenIsToken0
  ) UniswapV3OracleRelay(_lookback, _poolAddress, _quoteTokenIsToken0) {}

  function setMock(bool _mock) public {
    mock = _mock;
  }

  function toBase18(uint256 _amount, uint8 _decimals) public pure returns (uint256 _base18) {
    _base18 = _toBase18(_amount, _decimals);
  }

  function _getPriceFromUniswap(uint32 _seconds, uint128 _amount) internal view override returns (uint256 _price) {
    if (mock) _price = (_amount * 10) * (10 ** QUOTE_TOKEN_DECIMALS) / (10 ** BASE_TOKEN_DECIMALS);
    else super._getPriceFromUniswap(_seconds, _amount);
  }
}

abstract contract Base is DSTestPlus {
  UniswapV3OracleRelayForTest public uniswapV3OracleRelay;
  IUniswapV3Pool internal _mockPool = IUniswapV3Pool(mockContract(newAddress(), 'mockPool'));

  uint32 public lookback = 3600;
  bool public quoteTokenIsToken0 = true;

  int56[] public tickCumulatives;
  uint160[] public secondsPerLiquidityCumulativeX128s;

  IOracleRelay.OracleType public oracleType = IOracleRelay.OracleType(1); // 1 == Uniswap

  address internal _token0 = mockContract(newAddress(), 'token0');
  address internal _token1 = mockContract(newAddress(), 'token1');

  function setUp() public virtual {
    vm.mockCall(
      address(_mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.token0.selector), abi.encode(_token0)
    );

    vm.mockCall(
      address(_mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.token1.selector), abi.encode(_token1)
    );

    vm.mockCall(address(_token1), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));

    vm.mockCall(address(_token0), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(8)));

    // Deploy contract
    uniswapV3OracleRelay = new UniswapV3OracleRelayForTest(lookback, address(_mockPool), quoteTokenIsToken0);

    secondsPerLiquidityCumulativeX128s = new uint160[](2);
    tickCumulatives = new int56[](2);
  }
}

contract UnitTestUniswapV3OracleRelayConstructor is Base {
  function testConstructor() public {
    assertEq(uniswapV3OracleRelay.LOOKBACK(), lookback);
    assertEq(address(uniswapV3OracleRelay.POOL()), address(_mockPool));
    assertEq(uniswapV3OracleRelay.QUOTE_TOKEN_IS_TOKEN0(), quoteTokenIsToken0);
    assertEq(uniswapV3OracleRelay.BASE_TOKEN_DECIMALS(), uint8(18));
    assertEq(uniswapV3OracleRelay.QUOTE_TOKEN_DECIMALS(), uint8(8));
    assertEq(uniswapV3OracleRelay.BASE_TOKEN(), _token1);
    assertEq(uniswapV3OracleRelay.QUOTE_TOKEN(), _token0);
  }
}

contract UnitTestUniswapV3OracleRelayUnderlyingIsSet is Base {
  function testUnderlyingIsSet() public {
    assertEq(quoteTokenIsToken0 ? _token1 : _token0, uniswapV3OracleRelay.underlying());
  }
}

contract UnitTestUniswapV3OracleRelayOracleType is Base {
  function testOracleType() public {
    assertEq(uint256(oracleType), uint256(uniswapV3OracleRelay.oracleType()));
  }
}

contract UnitTestUniswapV3OracleRelayCurrentValue is Base {
  function testUniswapV3OracleRelayCurrentValueMocked(uint8 _decimals1, uint8 _decimals0, bool _isQuoteToken0) public {
    vm.assume(_decimals0 > 0 && _decimals0 < 25);
    vm.assume(_decimals1 > 0 && _decimals1 < 25);

    vm.mockCall(address(_token1), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals1));

    vm.mockCall(address(_token0), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals0));

    vm.mockCall(
      address(_mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.token0.selector), abi.encode(_token0)
    );

    vm.mockCall(
      address(_mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.token1.selector), abi.encode(_token1)
    );

    // Deploy contract
    uniswapV3OracleRelay = new UniswapV3OracleRelayForTest(lookback, address(_mockPool), _isQuoteToken0);

    uniswapV3OracleRelay.setMock(true);

    assertEq(uniswapV3OracleRelay.currentValue(), 10 * 10 ** 18);
  }
}

contract UnitTestUniswapV3OracleRelayToBase18 is Base {
  function testToBase18() public {
    assertEq(uniswapV3OracleRelay.toBase18(1e18, 18), 1e18);
    assertEq(uniswapV3OracleRelay.toBase18(1.5e8, 8), 1.5e18);
    assertEq(uniswapV3OracleRelay.toBase18(2e30, 30), 2e18);
    assertEq(uniswapV3OracleRelay.toBase18(2, 0), 2e18);
  }
}
