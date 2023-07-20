// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {VaultController} from '@contracts/core/VaultController.sol';

import {Deploy, DeployVars} from '@scripts/Deploy.s.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {MintableToken} from '@scripts/fakes/MintableToken.sol';
import {FakeBooster} from '@scripts/fakes/FakeBooster.sol';
import {FakeWethOracle} from '@scripts/fakes/FakeWethOracle.sol';

import {console} from 'forge-std/console.sol';

contract DeploySepolia is Deploy {
  address public deployer = vm.rememberKey(vm.envUint('DEPLOYER_SEPOLIA_PRIVATE_KEY'));
  address public wethSepolia = 0xf531B8F309Be94191af87605CfBf600D71C2cFe0;

  uint256 public susdCopySupply = 1_000_000 ether;
  uint256 public fakeLpTokenSupply = 1_000_000 ether;

  uint256 public fakeOraclePrice = 500 * 1e18;

  function run() external {
    vm.startBroadcast(deployer);
    // Deploy CVX & CRV tokens
    MintableToken cvx = new MintableToken('CVX',uint8(18));
    MintableToken crv = new MintableToken('CRV',uint8(18));
    // Deploy Fake Booster
    FakeBooster fakeBooster = new FakeBooster();

    // Deploy a copy of sUSDA
    MintableToken susdCopy = new MintableToken('sUSD',uint8(18));
    susdCopy.mint(deployer, susdCopySupply);
    console.log('sUSD_COPY: ', address(susdCopy));

    // Deploy FakeWethOracle
    FakeWethOracle fakeWethOracle = new FakeWethOracle();
    console.log('FAKE_WETH_ORACLE: ', address(fakeWethOracle));

    // Deploy fake oracle
    address _lpTokenOracle = _createFakeOracle(fakeOraclePrice);
    // Deploy fake lp token
    address _lpToken = _createFakeLp(deployer, fakeLpTokenSupply);
    // Deploy and set up curve lp rewards
    uint256 _pid = _addFakeCurveLPRewards(cvx, crv, fakeBooster, _lpToken);

    // Save deployment vars
    DeployVars memory _deployVars = DeployVars(
      deployer, cvx, crv, susdCopy, IERC20(address(wethSepolia)), address(fakeBooster), address(fakeWethOracle), false
    );

    // Deploy protocol
    (,, VaultController _vaultController,,,) = _deploy(_deployVars);

    // Register curveLP token
    _vaultController.registerErc20(
      address(_lpToken), WETH_LTV, address(_lpTokenOracle), LIQUIDATION_INCENTIVE, type(uint256).max, _pid
    );
    vm.stopBroadcast();
  }
}
