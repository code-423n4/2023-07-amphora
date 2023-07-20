// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {Deploy, DeployVars} from '@scripts/Deploy.s.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';

contract DeployMainnet is Deploy {
  address public deployer = vm.rememberKey(vm.envUint('DEPLOYER_MAINNNET_PRIVATE_KEY'));

  function run() external {
    vm.startBroadcast(deployer);
    UniswapV3OracleRelay _uniswapRelayEthUsdc = UniswapV3OracleRelay(_createEthUsdcTokenOracleRelay());
    ChainlinkOracleRelay _chainlinkEth = ChainlinkOracleRelay(_createEthUsdChainlinkOracleRelay());
    // Deploy weth oracle first, can be removed if the user defines a valid oracle address
    address _oracle = _createWethOracle(_uniswapRelayEthUsdc, _chainlinkEth);

    DeployVars memory _deployVars = DeployVars(
      deployer,
      IERC20(CVX_ADDRESS),
      IERC20(CRV_ADDRESS),
      IERC20(SUSD_ADDRESS),
      IERC20(WETH_ADDRESS),
      BOOSTER,
      _oracle,
      true
    );

    // Deploy protocol
    _deploy(_deployVars);
    vm.stopBroadcast();
  }
}
