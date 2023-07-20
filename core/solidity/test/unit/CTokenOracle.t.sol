// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {DSTestPlus} from 'solidity-utils/test/DSTestPlus.sol';
import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {ICToken} from '@interfaces/periphery/ICToken.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {CTokenOracle} from '@contracts/periphery/oracles/CTokenOracle.sol';
import {AnchoredViewRelay} from '@contracts/periphery/oracles/AnchoredViewRelay.sol';

abstract contract Base is DSTestPlus {
  CTokenOracle public cTokenOracle;

  ICToken internal _cToken;
  AnchoredViewRelay internal _underlyingAnchoredView;
  IERC20Metadata internal _underlying;

  address internal constant _wETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address internal constant _USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  function setUp() public virtual {
    _cToken = ICToken(mockContract(newAddress(), 'mockCToken'));
    _underlyingAnchoredView = AnchoredViewRelay(mockContract(newAddress(), 'mockUnderlyingAnchoredView'));
    _underlying = IERC20Metadata(mockContract(_USDC_ADDRESS, 'mockUnderlying'));

    vm.mockCall(address(_cToken), abi.encodeWithSelector(ICToken.underlying.selector), abi.encode(address(_underlying)));
    vm.mockCall(address(_cToken), abi.encodeWithSelector(ICToken.decimals.selector), abi.encode(uint8(8)));
    vm.mockCall(address(_underlying), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(6)));
    vm.mockCall(
      address(_underlyingAnchoredView),
      abi.encodeWithSelector(IOracleRelay.underlying.selector),
      abi.encode(_USDC_ADDRESS)
    );

    cTokenOracle = new CTokenOracle(address(_cToken), IOracleRelay(_underlyingAnchoredView));
  }
}

contract UnitCTokenOracleContructor is Base {
  function testCTokenOracleConstructorWhenUnderlyingIsUSDC() public view {
    assert(address(cTokenOracle.cToken()) == address(_cToken));
    assert(address(cTokenOracle.anchoredViewUnderlying()) == address(_underlyingAnchoredView));
    assert(cTokenOracle.div() == 10 ** (18 - 8 + 6));
    assert(cTokenOracle.underlying() == address(_cToken));
  }

  function testCTokenOracleConstructorWhenUnderlyingIsETH() public {
    _cToken = ICToken(mockContract(cTokenOracle.cETH_ADDRESS(), 'mockCToken'));
    vm.mockCall(address(_cToken), abi.encodeWithSelector(ICToken.decimals.selector), abi.encode(uint8(8)));
    vm.mockCall(
      address(_underlyingAnchoredView),
      abi.encodeWithSelector(IOracleRelay.underlying.selector),
      abi.encode(_wETH_ADDRESS)
    );

    cTokenOracle = new CTokenOracle(address(_cToken), IOracleRelay(_underlyingAnchoredView));

    assert(address(cTokenOracle.cToken()) == address(_cToken));
    assert(address(cTokenOracle.anchoredViewUnderlying()) == address(_underlyingAnchoredView));
    assert(cTokenOracle.div() == 10 ** (18 - 8 + 18));
    assert(cTokenOracle.underlying() == address(_cToken));
  }
}

contract UnitCTokenOracleCurrentValue is Base {
  function testCTokenOracleCurrentValue(uint256 _exchangeRateStored, uint256 _anchoredViewValue) public {
    vm.assume(_exchangeRateStored > 0);
    vm.assume(_anchoredViewValue > 0);
    vm.assume(_anchoredViewValue <= type(uint256).max / _exchangeRateStored);
    vm.assume(_anchoredViewValue * _exchangeRateStored > cTokenOracle.div());

    vm.mockCall(
      address(_cToken), abi.encodeWithSelector(ICToken.exchangeRateStored.selector), abi.encode(_exchangeRateStored)
    );
    vm.mockCall(
      address(_underlyingAnchoredView),
      abi.encodeWithSelector(IOracleRelay.peekValue.selector),
      abi.encode(_anchoredViewValue)
    );

    assertEq(cTokenOracle.currentValue(), _exchangeRateStored * _anchoredViewValue / cTokenOracle.div());
  }
}

contract UnitCTokenOracleChangeAnchoredView is Base {
  function testCTokenOracleChangeAnchoredViewRevertWhenCalledByNonOwner(address _caller) public {
    vm.assume(_caller != cTokenOracle.owner());

    vm.prank(_caller);
    vm.expectRevert('Ownable: caller is not the owner');
    cTokenOracle.changeAnchoredView(address(0));
  }

  function testCTokenOracleChangeAnchoredView(address _newAnchoredView) public {
    vm.assume(_newAnchoredView != address(_underlyingAnchoredView));

    vm.prank(cTokenOracle.owner());
    cTokenOracle.changeAnchoredView(_newAnchoredView);

    assertEq(address(cTokenOracle.anchoredViewUnderlying()), _newAnchoredView);
  }
}
