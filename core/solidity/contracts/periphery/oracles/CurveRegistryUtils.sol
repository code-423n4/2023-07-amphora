// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {ICurveRegistry, ICurveAddressesProvider} from '@interfaces/periphery/ICurveAddressesProvider.sol';

abstract contract CurveRegistryUtils {
  /// @notice The inmutable curve registry
  ICurveAddressesProvider public constant CURVE_ADDRESSES_PROVIDER =
    ICurveAddressesProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);

  /// @notice Returns the lp address of the curve pool
  function _getLpAddress(address _crvPool) internal view returns (address _lpAddress) {
    address _registry = CURVE_ADDRESSES_PROVIDER.get_registry();
    _lpAddress = ICurveRegistry(_registry).get_lp_token(_crvPool);
  }
}
