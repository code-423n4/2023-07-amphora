// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus, console} from 'solidity-utils/test/DSTestPlus.sol';
import {UniswapV3TokenOracleRelay} from '@contracts/periphery/oracles/UniswapV3TokenOracleRelay.sol';

import {
  IUniswapV3Pool,
  IUniswapV3PoolImmutables,
  IUniswapV3PoolDerivedState
} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

contract UniswapV3TokenOracleRelayForTest is UniswapV3TokenOracleRelay {
  bool public mock;

  constructor(
    UniswapV3OracleRelay _ethOracle,
    uint32 _lookback,
    address _poolAddress,
    bool _quoteTokenIsToken0
  ) UniswapV3TokenOracleRelay(_ethOracle, _lookback, _poolAddress, _quoteTokenIsToken0) {}

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
  UniswapV3TokenOracleRelayForTest public uniswapV3TokenOracleRelay;
  IUniswapV3Pool internal _mockPool = IUniswapV3Pool(mockContract(newAddress(), 'mockPool'));
  IOracleRelay internal _mockEthPriceFeed;

  uint32 public lookback = 60;
  bool public quoteTokenIsToken0 = true;

  int56[] public tickCumulatives;
  uint160[] public secondsPerLiquidityCumulativeX128s;

  IOracleRelay.OracleType public oracleType = IOracleRelay.OracleType(1); // 1 == Uniswap

  UniswapV3OracleRelay internal _uniswapRelayEthUsdc = UniswapV3OracleRelay(newAddress());

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
    uniswapV3TokenOracleRelay =
      new UniswapV3TokenOracleRelayForTest(_uniswapRelayEthUsdc, lookback, address(_mockPool), quoteTokenIsToken0);

    secondsPerLiquidityCumulativeX128s = new uint160[](2);
    tickCumulatives = new int56[](2);

    _mockEthPriceFeed = IOracleRelay(mockContract(address(_uniswapRelayEthUsdc), 'mockEthPriceFeed'));
  }
}

contract UnitTestUniswapV3OracleRelayConstructor is Base {
  function testConstructor() public {
    assertEq(uniswapV3TokenOracleRelay.LOOKBACK(), lookback);
    assertEq(address(uniswapV3TokenOracleRelay.POOL()), address(_mockPool));
    assertEq(uniswapV3TokenOracleRelay.QUOTE_TOKEN_IS_TOKEN0(), quoteTokenIsToken0);
    assertEq(uniswapV3TokenOracleRelay.BASE_TOKEN_DECIMALS(), uint8(18));
    assertEq(uniswapV3TokenOracleRelay.QUOTE_TOKEN_DECIMALS(), uint8(8));
    assertEq(uniswapV3TokenOracleRelay.BASE_TOKEN(), _token1);
    assertEq(uniswapV3TokenOracleRelay.QUOTE_TOKEN(), _token0);
    assertEq(address(uniswapV3TokenOracleRelay.ETH_ORACLE()), address(_uniswapRelayEthUsdc));
  }
}

contract UnitTestUniswapV3TokenOracleRelayUnderlyingIsSet is Base {
  function testUnderlyingIsSet() public {
    assertEq(quoteTokenIsToken0 ? _token1 : _token0, uniswapV3TokenOracleRelay.underlying());
  }
}

contract UnitTestUniswapV3TokenOracleRelayOracleType is Base {
  function testOracleType() public {
    assertEq(uint256(oracleType), uint256(uniswapV3TokenOracleRelay.oracleType()));
  }
}

contract UnitTestUniswapV3TokenOracleRelayCurrentValue is Base {
  function testUniswapV3OracleRelayCurrentValueMocked(
    uint8 _decimals1,
    uint8 _decimals0,
    bool _isQuoteToken0,
    uint256 _ethPrice
  ) public {
    vm.assume(_decimals0 > 0 && _decimals0 < 25);
    vm.assume(_decimals1 > 0 && _decimals1 < 25);
    vm.assume(_ethPrice > 0);
    vm.assume(_ethPrice < 1e5);

    vm.mockCall(
      address(_mockEthPriceFeed), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_ethPrice)
    );

    vm.mockCall(address(_token1), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals1));

    vm.mockCall(address(_token0), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals0));

    vm.mockCall(
      address(_mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.token0.selector), abi.encode(_token0)
    );

    vm.mockCall(
      address(_mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.token1.selector), abi.encode(_token1)
    );

    // Deploy contract
    uniswapV3TokenOracleRelay =
      new UniswapV3TokenOracleRelayForTest(_uniswapRelayEthUsdc, lookback, address(_mockPool), _isQuoteToken0);

    uniswapV3TokenOracleRelay.setMock(true);

    assertEq(uniswapV3TokenOracleRelay.currentValue(), 10 * _ethPrice);
  }
}
