// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

import {VaultController} from '@contracts/core/VaultController.sol';
import {VaultDeployer} from '@contracts/core/VaultDeployer.sol';
import {USDA} from '@contracts/core/USDA.sol';
import {GovernorCharlie} from '@contracts/governance/GovernorCharlie.sol';
import {AmphoraProtocolToken} from '@contracts/governance/AmphoraProtocolToken.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';
import {AnchoredViewRelay} from '@contracts/periphery/oracles/AnchoredViewRelay.sol';
import {CurveMaster} from '@contracts/periphery/CurveMaster.sol';
import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';
import {ThreeLines0_100} from '@contracts/utils/ThreeLines0_100.sol';
import {AMPHClaimer} from '@contracts/core/AMPHClaimer.sol';
import {IAMPHClaimer} from '@interfaces/core/IAMPHClaimer.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IVaultDeployer} from '@interfaces/core/IVaultDeployer.sol';
import {TestConstants} from '@test/utils/TestConstants.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {CreateOracles} from '@scripts/CreateOracles.sol';

import {FakeBaseRewardPool} from '@scripts/fakes/FakeBaseRewardPool.sol';
import {FakeBooster} from '@scripts/fakes/FakeBooster.sol';
import {FakeVirtualRewardsPool} from '@scripts/fakes/FakeVirtualRewardsPool.sol';
import {FakeWethOracle} from '@scripts/fakes/FakeWethOracle.sol';
import {MintableToken} from '@scripts/fakes/MintableToken.sol';
import {FakeCVX} from '@scripts/fakes/FakeBaseRewardPool.sol';

import {ERC20, IERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

struct DeployVars {
  address deployer;
  IERC20 cvxAddress;
  IERC20 crvAddress;
  IERC20 sUSDAddress;
  IERC20 wethAddress;
  address booster;
  address wethOracle;
  bool giveOwnershipToGov;
}

abstract contract Deploy is Script, TestConstants, CreateOracles {
  uint256 public constant initialAmphSupply = 100_000_000 ether;

  uint256 public constant cvxRewardFee = 0.02 ether;
  uint256 public constant crvRewardFee = 0.01 ether;

  function _deploy(DeployVars memory _deployVars)
    internal
    returns (
      AmphoraProtocolToken _amphToken,
      GovernorCharlie _governor,
      VaultController _vaultController,
      VaultDeployer _vaultDeployer,
      AMPHClaimer _amphClaimer,
      USDA _usda
    )
  {
    address[] memory _tokens;
    // Current nonce saved
    uint256 currentNonce = vm.getNonce(_deployVars.deployer);

    // Deploy governance and amph token
    _amphToken = new AmphoraProtocolToken(_deployVars.deployer, initialAmphSupply); // Nonce + 0
    console.log('AMPHORA_TOKEN: ', address(_amphToken));
    _governor = new GovernorCharlie(address(_amphToken)); // Nonce + 1
    console.log('GOVERNOR: ', address(_governor));

    // Deploy VaultController & VaultDeployer
    _vaultDeployer = new VaultDeployer(_deployVars.cvxAddress, _deployVars.crvAddress); // Nonce + 2
    console.log('VAULT_DEPLOYER: ', address(_vaultDeployer));

    // Pre-compute AMPClaimer address since we need it for the vault controller
    address _amphClaimerAddress = computeCreateAddress(_deployVars.deployer, currentNonce + 4);
    _vaultController =
    new VaultController(IVaultController(address(0)), _tokens, IAMPHClaimer(_amphClaimerAddress), _vaultDeployer, 0.01e18, _deployVars.booster, 0.005e18); // Nonce + 3
    console.log('VAULT_CONTROLLER: ', address(_vaultController));

    // Deploy claimer
    _amphClaimer =
    new AMPHClaimer(address(_vaultController), IERC20(address(_amphToken)), _deployVars.cvxAddress, _deployVars.crvAddress, cvxRewardFee, crvRewardFee); // Nonce + 4
    console.log('AMPH_CLAIMER: ', address(_amphClaimer));
    _amphToken.mint(address(_amphClaimer), 1_000_000 ether); // Mint amph to start LM program

    // Make sure the calculated address is correct
    assert(_amphClaimerAddress == address(_amphClaimer));

    // Deploy USDA
    _usda = new USDA(_deployVars.sUSDAddress);
    console.log('USDA: ', address(_usda));

    // Deploy curve
    ThreeLines0_100 _threeLines = new ThreeLines0_100(2 ether, 0.1 ether, 0.005 ether, 0.25 ether, 0.5 ether);
    console.log('THREE_LINES_0_100: ', address(_threeLines));

    // Deploy CurveMaster
    CurveMaster _curveMaster = new CurveMaster();
    console.log('CURVE_MASTER: ', address(_curveMaster));
    // Set curve
    _curveMaster.setCurve(address(0), address(_threeLines));
    // Add _curveMaster to VaultController
    _vaultController.registerCurveMaster(address(_curveMaster));

    // Set VaultController address for _usda
    _usda.addVaultController(address(_vaultController));
    // Register WETH as acceptable erc20 to vault controller
    _vaultController.registerErc20(
      address(_deployVars.wethAddress), WETH_LTV, _deployVars.wethOracle, LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );
    // Register USDA
    _vaultController.registerUSDA(address(_usda));
    // Set pauser
    _usda.setPauser(_deployVars.deployer);

    if (_deployVars.giveOwnershipToGov) {
      _changeOwnership(
        _deployVars.deployer, address(_governor), _amphToken, _vaultController, _amphClaimer, _usda, _curveMaster
      );
    }
  }

  function _addFakeCurveLPRewards(
    MintableToken _cvx,
    MintableToken _crv,
    FakeBooster _fakeBooster,
    address _lpToken
  ) internal returns (uint256 _pid) {
    uint256 _oneEther = 1 ether;
    uint256 _rewardsPerSecond = _oneEther / 3600; // 1 token per hour
    console.log('FAKE_BOOSTER: ', address(_fakeBooster));
    console.log('CRV: ', address(_crv));

    FakeBaseRewardPool fakeBaseRewardPool1 =
      new FakeBaseRewardPool(address(_fakeBooster), _crv, _rewardsPerSecond, address(_lpToken), FakeCVX(address(_cvx)));

    _crv.mint(address(fakeBaseRewardPool1), 1_000_000_000 ether);
    _cvx.mint(address(fakeBaseRewardPool1), 1_000_000_000 ether);

    _pid = _fakeBooster.addPoolInfo(address(_lpToken), address(fakeBaseRewardPool1));

    for (uint256 i = 0; i < 2; i++) {
      // Add extra rewards
      MintableToken _fakeRewardsToken =
        new MintableToken(string.concat('RewardToken', Strings.toString(i+1)), uint8(18));
      console.log(string.concat('REWARD_TOKEN', Strings.toString(i + 1)), ': ', address(_fakeRewardsToken));
      FakeVirtualRewardsPool fakeExtraVirtualRewardsPool =
        new FakeVirtualRewardsPool(fakeBaseRewardPool1, _fakeRewardsToken, _rewardsPerSecond * (i + 2));

      _fakeRewardsToken.mint(address(fakeExtraVirtualRewardsPool), 1_000_000_000 ether);

      fakeBaseRewardPool1.addExtraReward(fakeExtraVirtualRewardsPool);
    }
  }

  function _changeOwnership(
    address _usdaPauser,
    address _governor,
    AmphoraProtocolToken _amphToken,
    VaultController _vaultController,
    AMPHClaimer _amphClaimer,
    USDA _usda,
    CurveMaster _curveMaster
  ) internal {
    //AMPH
    _amphToken.transferOwnership(_governor);
    //vault controller
    _vaultController.transferOwnership(_governor);
    //amph claimer
    _amphClaimer.transferOwnership(_governor);
    //usda
    //TODO: Pauser powers should remain in a wallet controller by team for fast reaction but ownership is for gov
    _usda.setPauser(_usdaPauser);
    _usda.transferOwnership(_governor);
    //curveMaster
    _curveMaster.transferOwnership(_governor);
    // TODO: chainlinkEth transfer ownership, gets into stack too deep errors
    // if (address(_chainlinkEth) != address(0)) _chainlinkEth.transferOwnership(_governor);
  }

  /**
   *  @notice Creates a fake oracle
   *  @param _price The price to set for the oracle
   *  @return _oracle Address of the fake oracle
   */
  function _createFakeOracle(uint256 _price) internal returns (address _oracle) {
    // Deploy for convex rewards
    FakeWethOracle fakeRewardsOracle1 = new FakeWethOracle();
    fakeRewardsOracle1.setPrice(_price);
    console.log('FAKE_ORACLE_1: ', address(fakeRewardsOracle1));
    _oracle = address(fakeRewardsOracle1);
  }

  /**
   *  @notice Creates a fake lp token
   *  @param _minter The address that's gonna receive the tokens
   *  @param _amount The amount of tokens to mint
   *  @return _lpToken The address of the lp token
   */
  function _createFakeLp(address _minter, uint256 _amount) internal returns (address _lpToken) {
    MintableToken fakeLp1 = new MintableToken('LPToken',uint8(18));
    fakeLp1.mint(_minter, _amount);
    console.log('FAKE_LP', address(fakeLp1));
    _lpToken = address(fakeLp1);
  }
}
