// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {BaseInvariant} from '@test/invariant/BaseInvariant.sol';
import {VaultController} from '@contracts/core/VaultController.sol';
import {VaultControllerOwnerHandler} from '@test/handlers/VaultControllerOwnerHandler.sol';
import {VaultControllerBorrowerHandler} from '@test/handlers/VaultControllerBorrowerHandler.sol';
import {MockSUSD} from '@test/handlers/USDAHandler.sol';

import {VaultDeployer} from '@contracts/core/VaultDeployer.sol';
import {USDA} from '@contracts/core/USDA.sol';
import {AmphoraProtocolToken} from '@contracts/governance/AmphoraProtocolToken.sol';
import {CurveMaster} from '@contracts/periphery/CurveMaster.sol';
import {ThreeLines0_100} from '@contracts/utils/ThreeLines0_100.sol';
import {AMPHClaimer} from '@contracts/core/AMPHClaimer.sol';
import {AnchoredViewRelay} from '@contracts/periphery/oracles/AnchoredViewRelay.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';
import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';
import {ThreeLines0_100} from '@contracts/utils/ThreeLines0_100.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IAMPHClaimer} from '@interfaces/core/IAMPHClaimer.sol';

import {TestConstants} from '@test/utils/TestConstants.sol';
import {console} from 'solidity-utils/test/DSTestPlus.sol';

contract InvariantVaultController is BaseInvariant, TestConstants {
  VaultController public vaultController;
  VaultControllerOwnerHandler public vaultControllerOwnerHandler;
  VaultControllerBorrowerHandler public vaultControllerBorrowerHandler;

  AMPHClaimer public amphoraClaimer;
  VaultDeployer public vaultDeployer;
  CurveMaster public curveMaster;
  USDA public usdaToken;
  AmphoraProtocolToken public amphoraToken;
  ThreeLines0_100 public threeLines;

  ChainlinkOracleRelay public chainlinkEth;
  AnchoredViewRelay public anchoredViewEth;

  IERC20 public susd;

  uint256 public initialAMPH = 100_000_000 ether;

  uint256 public cvxRewardFee = 0.02e18;
  uint256 public crvRewardFee = 0.01e18;
  uint256 public staleTime = 20 * 365 days; // TODO: Change this to something better?

  uint192 public initialBorrowingFee = 0.01e18;
  uint192 public liquidationFee = 0.005e18;

  function setUp() public {
    /**
     * --------------- Deploy Protocol ---------------
     */
    address[] memory _tokens = new address[](0);

    // Deploy VaultDeployer
    vaultDeployer = new VaultDeployer(IERC20(CVX_ADDRESS), IERC20(CRV_ADDRESS));
    // Deploy AMPH token
    amphoraToken = new AmphoraProtocolToken(address(this), initialAMPH);
    // Deploy VaultController
    vaultController =
    new VaultController(IVaultController(address(0)), _tokens, IAMPHClaimer(address(0)), vaultDeployer, initialBorrowingFee, BOOSTER, liquidationFee);
    // Deploy amphora claimer
    amphoraClaimer =
    new AMPHClaimer(address(vaultController), IERC20(address(amphoraToken)), IERC20(CVX_ADDRESS), IERC20(CRV_ADDRESS), cvxRewardFee, crvRewardFee);

    // Deploy CurveMaster
    curveMaster = new CurveMaster();
    // Deploy curve
    threeLines = new ThreeLines0_100(2 ether, 0.1 ether, 0.005 ether, 0.25 ether, 0.5 ether);
    // Deploy usda
    susd = new MockSUSD('sUSD', 'sUSD');
    usdaToken = new USDA(susd);

    // Deploy chainlinkEth oracle relay
    chainlinkEth = new ChainlinkOracleRelay(WETH_ADDRESS, CHAINLINK_ETH_FEED_ADDRESS, 10_000_000_000, 1, staleTime);
    // Deploy anchoredViewEth relay
    anchoredViewEth = new AnchoredViewRelay(address(chainlinkEth), address(chainlinkEth), 20, 100, 10, 100);

    // Register an acceptable erc20 to vault controller
    // TODO: Create a mock WETH and change address
    vaultController.registerErc20(
      address(susd), WETH_LTV, address(anchoredViewEth), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );

    // Change AMPH claimer
    vaultController.changeClaimerContract(amphoraClaimer);
    // Add curve master to vault controller
    vaultController.registerCurveMaster(address(curveMaster));
    // Add usda token to vault controller
    vaultController.registerUSDA(address(usdaToken));
    // Set curve for curve master
    curveMaster.setCurve(address(0), address(threeLines));
    // Add vault controller to usda
    usdaToken.addVaultController(address(vaultController));

    /**
     * --------------- Set up Handlers ---------------
     */
    excludeContract(address(amphoraToken));
    excludeContract(address(vaultController));
    excludeContract(address(amphoraClaimer));
    excludeContract(address(vaultDeployer));
    excludeContract(address(curveMaster));
    excludeContract(address(threeLines));
    excludeContract(address(susd));
    excludeContract(address(usdaToken));
    excludeContract(address(chainlinkEth));
    excludeContract(address(anchoredViewEth));

    vaultControllerOwnerHandler = new VaultControllerOwnerHandler(vaultController, susd, usdaToken, this);

    bytes4[] memory _ownerSelectors = new bytes4[](6);
    // _ownerSelectors[0] = VaultControllerOwnerHandler.mintVault.selector;
    _ownerSelectors[0] = VaultControllerOwnerHandler.registerErc20.selector;
    _ownerSelectors[1] = vaultControllerOwnerHandler.updateRegisteredErc20.selector;
    _ownerSelectors[2] = vaultControllerOwnerHandler.borrowUSDA.selector;
    _ownerSelectors[3] = vaultControllerOwnerHandler.borrowUSDAto.selector;
    _ownerSelectors[4] = vaultControllerOwnerHandler.repayUSDA.selector;
    _ownerSelectors[5] = vaultControllerOwnerHandler.repayAllUSDA.selector;

    targetSelector(FuzzSelector({addr: address(vaultControllerOwnerHandler), selectors: _ownerSelectors}));
    targetContract(address(vaultControllerOwnerHandler));

    vaultControllerBorrowerHandler = new VaultControllerBorrowerHandler(vaultController, susd, usdaToken, this);

    bytes4[] memory _borrowerSelectors = new bytes4[](4);
    // _borrowerSelectors[0] = vaultControllerBorrowerHandler.mintVault.selector;
    _borrowerSelectors[0] = vaultControllerBorrowerHandler.borrowUSDA.selector;
    _borrowerSelectors[1] = vaultControllerBorrowerHandler.borrowUSDAto.selector;
    _borrowerSelectors[2] = vaultControllerBorrowerHandler.repayUSDA.selector;
    _borrowerSelectors[3] = vaultControllerBorrowerHandler.repayAllUSDA.selector;

    targetSelector(FuzzSelector({addr: address(vaultControllerBorrowerHandler), selectors: _borrowerSelectors}));
    targetContract(address(vaultControllerBorrowerHandler));
  }

  /// @dev The sum of all vaults minted should be equal to vaultsMinted
  // function invariant_SumOfMintedVaultsShouldBeEqualToVaultsMinted() public {
  //   assertEq(vaultControllerOwnerHandler.ghost_totalVaults(), vaultController.vaultsMinted());
  // }

  /// @dev The sum of all collaterals registered should be equal to tokens Registered
  function invariant_SumOfCollateralsShouldBeEqualToTokensRegistered() public {
    assertEq(vaultControllerOwnerHandler.ghost_totalCollateral() + 1, vaultController.tokensRegistered());
  }

  /// @dev The total borrowed amount + total borrowed fee should be equal to the total liability
  function invariant_SumOfTotalBorrowedAndBorrowedFeeShouldBeEqualToTotalLiability() public {
    uint256 _totalBorrowed =
      vaultControllerOwnerHandler.ghost_borrowedSum() + vaultControllerBorrowerHandler.ghost_borrowedSum();
    uint256 _totalBorrowedFee =
      vaultControllerOwnerHandler.ghost_borrowFeeSum() + vaultControllerBorrowerHandler.ghost_borrowFeeSum();
    uint256 _totalRepaid =
      vaultControllerOwnerHandler.ghost_repaidSum() + vaultControllerBorrowerHandler.ghost_repaidSum();
    assertEq(_totalBorrowed + _totalBorrowedFee - _totalRepaid, vaultController.totalBaseLiability());
  }

  /// @dev The total liability should be less than total deposited
  /// @dev In this case we mock the price of both tokens to 1 ether so we only check for the amount and not their total value
  function invariant_TotalLiabilityShouldBeLessThanTotalDeposited() public {
    uint256 _totalBalances = vaultControllerOwnerHandler.ownerBalance()
      + vaultControllerBorrowerHandler.balance() * vaultControllerBorrowerHandler.totalActors();
    assertLt(vaultController.totalBaseLiability(), _totalBalances);
  }

  /// @dev Ensure that all getters do not revert at any time after init
  /// TODO: Doesn't include all getters
  function invariant_GettersDoNotRevert() public view {
    vaultController.tokensRegistered();
    vaultController.vaultsMinted();
    vaultController.lastInterestTime();
    vaultController.totalBaseLiability();
    vaultController.interestFactor();
    vaultController.protocolFee();
    vaultController.MAX_INIT_BORROWING_FEE();
    vaultController.initialBorrowingFee();
    vaultController.liquidationFee();
    vaultController.BOOSTER();
    vaultController.claimerContract();
    vaultController.VAULT_DEPLOYER();
    vaultController.getEnabledTokens();
  }

  function invariant_callSummary() public view {
    vaultControllerOwnerHandler.callSummary();
    vaultControllerBorrowerHandler.callSummary();
  }

  function excludeContractFromHandler(address _contract) public {
    excludeContract(_contract);
  }
}
