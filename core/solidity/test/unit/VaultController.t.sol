// solhint-disable max-states-count
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {VaultController} from '@contracts/core/VaultController.sol';
import {VaultDeployer} from '@contracts/core/VaultDeployer.sol';
import {Vault} from '@contracts/core/Vault.sol';
import {UniswapV3OracleRelay} from '@contracts/periphery/oracles/UniswapV3OracleRelay.sol';
import {ChainlinkOracleRelay} from '@contracts/periphery/oracles/ChainlinkOracleRelay.sol';
import {CurveMaster} from '@contracts/periphery/CurveMaster.sol';
import {AnchoredViewRelay} from '@contracts/periphery/oracles/AnchoredViewRelay.sol';
import {USDA} from '@contracts/core/USDA.sol';
import {StableCurveLpOracle} from '@contracts/periphery/oracles/StableCurveLpOracle.sol';
import {ThreeLines0_100} from '@contracts/utils/ThreeLines0_100.sol';
import {ExponentialNoError} from '@contracts/utils/ExponentialNoError.sol';

import {IOracleRelay} from '@interfaces/periphery/IOracleRelay.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IUSDA} from '@interfaces/core/IUSDA.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IBooster} from '@interfaces/utils/IBooster.sol';
import {IBaseRewardPool} from '@interfaces/utils/IBaseRewardPool.sol';
import {IAMPHClaimer} from '@interfaces/core/IAMPHClaimer.sol';
import {IVaultDeployer} from '@interfaces/core/IVaultDeployer.sol';

import {DSTestPlus, console} from 'solidity-utils/test/DSTestPlus.sol';
import {TestConstants} from '@test/utils/TestConstants.sol';
import {IERC20Metadata, IERC20} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {CreateOracles} from '@scripts/CreateOracles.sol';

contract VaultControllerForTest is VaultController {
  constructor(
    IVaultController _oldVaultController,
    address[] memory _tokenAddresses,
    IAMPHClaimer _claimerContract,
    IVaultDeployer _vaultDeployer,
    uint192 _initialBorrowingFee,
    address _booster,
    uint192 _liquidationFee
  )
    VaultController(
      _oldVaultController,
      _tokenAddresses,
      _claimerContract,
      _vaultDeployer,
      _initialBorrowingFee,
      _booster,
      _liquidationFee
    )
  {}

  function migrateCollateralsFrom(IVaultController _oldVaultController, address[] memory _tokenAddresses) public {
    _migrateCollateralsFrom(_oldVaultController, _tokenAddresses);
  }

  function getVault(uint96 _id) public view returns (IVault _vault) {
    _vault = _getVault(_id);
  }
}

abstract contract Base is DSTestPlus, TestConstants, CreateOracles {
  address public governance = label(newAddress(), 'governance');
  address public alice = label(newAddress(), 'alice');
  address public vaultOwner = label(newAddress(), 'vaultOwner');
  address public vaultOwner2 = label(newAddress(), 'vaultOwner2');
  address public vaultOwnerWbtc = label(newAddress(), 'vaultOwnerWbtc');
  address public booster = mockContract(newAddress(), 'booster');
  IERC20 public cvx = IERC20(mockContract(newAddress(), 'cvx'));
  IERC20 public crv = IERC20(mockContract(newAddress(), 'crv'));

  AnchoredViewRelay public anchoredViewEth = AnchoredViewRelay(mockContract(newAddress(), 'anchoredViewEth'));
  AnchoredViewRelay public anchoredViewUni = AnchoredViewRelay(mockContract(newAddress(), 'anchoredViewUni'));

  IERC20 public mockToken = IERC20(mockContract(newAddress(), 'mockToken'));
  IERC20 public usdtLp = IERC20(mockContract(newAddress(), 'usdtLpAddress'));

  IAMPHClaimer public mockAmphClaimer = IAMPHClaimer(mockContract(newAddress(), 'mockAmphClaimer'));
  VaultController public vaultController;
  VaultControllerForTest public mockVaultController;
  VaultDeployer public vaultDeployer;
  USDA public usdaToken;
  CurveMaster public curveMaster;
  ThreeLines0_100 public threeLines;

  StableCurveLpOracle public threeCrvOracle;

  uint256 public cap = 100 ether;
  address internal _mockedWeth = mockContract(WETH_ADDRESS, 'mockedWeth');
  address internal _mockedWbtc = mockContract(WBTC_ADDRESS, 'mockedWbtc');
  address internal _mockedWbtcOracle = mockContract(newAddress(), 'wbtcOracle');

  uint256 public wbtcPrice = 30_000 ether;

  function setUp() public virtual {
    address[] memory _tokens = new address[](1);
    vm.startPrank(governance);

    vaultDeployer = new VaultDeployer(cvx, crv);
    vaultController =
    new VaultController(IVaultController(address(0)), _tokens, mockAmphClaimer, vaultDeployer, 0.01e18, booster, 0.005e18);

    curveMaster = new CurveMaster();
    threeLines = new ThreeLines0_100(2 ether, 0.1 ether, 0.005 ether, 0.25 ether, 0.5 ether);

    vaultController.registerCurveMaster(address(curveMaster));
    curveMaster.setCurve(address(0), address(threeLines));

    usdaToken = new USDA(mockToken);

    vaultController.registerUSDA(address(usdaToken));

    usdaToken.setPauser(governance);
    usdaToken.addVaultController(address(vaultController));

    // Deploy the ThreeCrvOracle
    threeCrvOracle = StableCurveLpOracle(mockContract(newAddress(), 'threeCrvOracle'));

    vm.mockCall(address(_mockedWeth), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
    vm.mockCall(address(_mockedWbtc), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(8)));

    vm.mockCall(
      address(_mockedWbtcOracle), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(wbtcPrice)
    );
    vm.mockCall(
      address(_mockedWbtcOracle), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(wbtcPrice)
    );
    vm.stopPrank();
  }
}

abstract contract VaultBase is Base {
  event BorrowUSDA(uint256 _vaultId, address _vaultAddress, uint256 _borrowAmount, uint256 _fee);

  IVault internal _vault;
  IVault internal _vault2;
  IVault internal _vaultWbtc;
  uint256 internal _vaultDeposit = 10 ether;
  uint256 internal _wbtcDeposit = 10e8;
  uint96 internal _vaultId = 1;
  uint96 internal _vaultId2 = 2;
  uint96 internal _vaultIdWbtc = 3;
  uint192 internal _borrowAmount = 5 ether;

  IBaseRewardPool internal _crvRewards = IBaseRewardPool(mockContract(newAddress(), 'crvRewards'));

  function setUp() public virtual override {
    super.setUp();

    vm.prank(governance);
    vaultController.registerErc20(
      _mockedWeth, WETH_LTV, address(anchoredViewEth), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );

    vm.prank(governance);
    vaultController.registerErc20(
      address(_mockedWbtc), OTHER_LTV, address(_mockedWbtcOracle), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );

    vm.prank(vaultOwner);
    _vault = IVault(vaultController.mintVault());

    vm.prank(vaultOwner2);
    _vault2 = IVault(vaultController.mintVault());

    vm.prank(vaultOwnerWbtc);
    _vaultWbtc = IVault(vaultController.mintVault());

    vm.mockCall(
      WETH_ADDRESS,
      abi.encode(IERC20.transferFrom.selector, vaultOwner, address(_vault), _vaultDeposit),
      abi.encode(true)
    );

    vm.mockCall(
      WETH_ADDRESS,
      abi.encode(IERC20.transferFrom.selector, vaultOwner2, address(_vault2), _vaultDeposit * 2),
      abi.encode(true)
    );

    vm.mockCall(
      WBTC_ADDRESS,
      abi.encode(IERC20.transferFrom.selector, vaultOwnerWbtc, address(_vaultWbtc), _wbtcDeposit),
      abi.encode(true)
    );

    vm.prank(vaultOwner);
    _vault.depositERC20(WETH_ADDRESS, _vaultDeposit);

    vm.prank(vaultOwner2);
    _vault2.depositERC20(WETH_ADDRESS, _vaultDeposit * 2);

    vm.prank(vaultOwnerWbtc);
    _vaultWbtc.depositERC20(WBTC_ADDRESS, _wbtcDeposit);

    vm.mockCall(
      address(vaultController.BOOSTER()),
      abi.encodeWithSelector(IBooster.poolInfo.selector),
      abi.encode(address(usdtLp), address(0), address(0), _crvRewards, address(0), false)
    );

    vm.mockCall(address(usdtLp), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));

    vm.prank(governance);
    vaultController.registerErc20(
      address(usdtLp), OTHER_LTV, address(threeCrvOracle), LIQUIDATION_INCENTIVE, type(uint256).max, 1
    );

    vm.mockCall(
      address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(1 ether)
    );
    vm.mockCall(address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
  }

  function testOwnerVaultIds() public {
    uint96[] memory _vaultIDs = vaultController.vaultIDs(vaultOwner);
    assertEq(_vaultIDs.length, 1);
    assertEq(_vaultIDs[0], _vaultId);
  }
}

contract UnitVaultControllerConstructor is Base {
  function testDeployedCorrectly() public {
    address[] memory _tokens = new address[](1);

    mockVaultController =
    new VaultControllerForTest(IVaultController(address(0)), _tokens, mockAmphClaimer, vaultDeployer, 0.01e18, booster, 0.005e18);

    assertEq(mockVaultController.owner(), address(this));
    assertEq(mockVaultController.lastInterestTime(), block.timestamp);
    assertEq(mockVaultController.interestFactor(), 1 ether);
    assertEq(mockVaultController.protocolFee(), 100_000_000_000_000);
    assertEq(mockVaultController.vaultsMinted(), 0);
    assertEq(mockVaultController.tokensRegistered(), 0);
    assertEq(mockVaultController.totalBaseLiability(), 0);
    assertEq(mockVaultController.initialBorrowingFee(), 10_000_000_000_000_000);
    assertEq(mockVaultController.liquidationFee(), 5_000_000_000_000_000);
    assertEq(address(mockVaultController.claimerContract()), address(mockAmphClaimer));
  }

  function testMigrateFromPreviousVaultController() public {
    address[] memory _tokens = new address[](1);
    _tokens[0] = WETH_ADDRESS;
    vm.startPrank(governance);
    // Add erc20 collateral in first vault controller
    vaultController.registerErc20(
      WETH_ADDRESS, WETH_LTV, address(anchoredViewEth), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );

    // Deploy the new vault controller
    mockVaultController =
    new VaultControllerForTest(IVaultController(address(vaultController)), _tokens, mockAmphClaimer, vaultDeployer, 0.01e18, booster, 0.005e18);
    vm.stopPrank();

    assertEq(address(mockVaultController.tokensOracle(WETH_ADDRESS)), address(anchoredViewEth));
    assertEq(mockVaultController.tokensRegistered(), 1);
    assertEq(mockVaultController.tokenId(WETH_ADDRESS), 1);
    assertEq(mockVaultController.tokenLTV(WETH_ADDRESS), WETH_LTV);
    assertEq(mockVaultController.tokenLiquidationIncentive(WETH_ADDRESS), LIQUIDATION_INCENTIVE);
    assertEq(mockVaultController.tokenCap(WETH_ADDRESS), type(uint256).max);
    assertEq(mockVaultController.tokenCollateralInfo(WETH_ADDRESS).decimals, 18);
  }
}

contract UnitVaultControllerPause is Base {
  function testPauseVaultController() public {
    vm.prank(governance);
    vaultController.pause();

    vm.expectRevert('Pausable: paused');
    vaultController.mintVault();
  }

  function testUnPauseVaultController() public {
    vm.prank(governance);
    vaultController.pause();

    vm.expectRevert('Pausable: paused');
    vaultController.mintVault();

    vm.prank(governance);
    vaultController.unpause();

    vaultController.mintVault();
    assertEq(vaultController.vaultsMinted(), 1);
  }
}

contract UnitVaultControllerMigrateCollateralsFrom is Base {
  function testRevertIfWrongCollateral() public {
    address[] memory _empty = new address[](0);
    vm.startPrank(governance);
    // Deploy the new vault controller
    mockVaultController =
    new VaultControllerForTest(IVaultController(address(0)), _empty, mockAmphClaimer, vaultDeployer, 0.01e18, booster, 0.005e18);
    vm.expectRevert(IVaultController.VaultController_WrongCollateralAddress.selector);
    address[] memory _tokens = new address[](1);
    _tokens[0] = WETH_ADDRESS;
    mockVaultController.migrateCollateralsFrom(IVaultController(address(vaultController)), _tokens);
    vm.stopPrank();
  }

  function testMigrateCollaterallsFrom() public {
    address[] memory _tokens = new address[](1);
    _tokens[0] = WETH_ADDRESS;
    vm.startPrank(governance);
    // Add erc20 collateral in first vault controller
    vaultController.registerErc20(
      WETH_ADDRESS, WETH_LTV, address(anchoredViewEth), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );
    // Deploy the new vault controller
    address[] memory _empty = new address[](0);
    mockVaultController =
    new VaultControllerForTest(IVaultController(address(0)), _empty, mockAmphClaimer, vaultDeployer, 0.01e18, booster, 0.005e18);
    mockVaultController.migrateCollateralsFrom(IVaultController(address(vaultController)), _tokens);
    vm.stopPrank();

    assertEq(address(mockVaultController.tokensOracle(WETH_ADDRESS)), address(anchoredViewEth));
    assertEq(mockVaultController.tokensRegistered(), 1);
    assertEq(mockVaultController.tokenId(WETH_ADDRESS), 1);
    assertEq(mockVaultController.tokenLTV(WETH_ADDRESS), WETH_LTV);
    assertEq(mockVaultController.tokenLiquidationIncentive(WETH_ADDRESS), LIQUIDATION_INCENTIVE);
    assertEq(mockVaultController.tokenCap(WETH_ADDRESS), type(uint256).max);
    assertEq(mockVaultController.tokenCollateralInfo(WETH_ADDRESS).decimals, 18);
  }
}

contract UnitVaultControllerMintVault is Base {
  function testRevertIfPaused() public {
    vm.startPrank(governance);
    vaultController.pause();
    vm.stopPrank();

    vm.expectRevert('Pausable: paused');
    vaultController.mintVault();
  }

  function testMintVault() public {
    address _vault = vaultController.mintVault();
    assertEq(vaultController.vaultsMinted(), 1);
    assertEq(vaultController.vaultIdVaultAddress(1), _vault);
  }
}

contract UnitVaultControllerRegisterUSDA is Base {
  event RegisterUSDA(address _usdaContractAddress);

  function testRevertIfRegisterFromNonOwner(address _usda) public {
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(alice);
    vaultController.registerUSDA(_usda);
  }

  function testRegisterUSDA(address _usda) public {
    vm.prank(governance);
    vaultController.registerUSDA(_usda);
    assertEq(address(vaultController.usda()), _usda);
  }

  function testEmitEvent(address _usda) public {
    vm.expectEmit(false, false, false, true);
    emit RegisterUSDA(_usda);

    vm.prank(governance);
    vaultController.registerUSDA(_usda);
  }
}

contract UnitVaultControllerChangeProtocolFee is Base {
  event NewProtocolFee(uint192 _newFee);

  function testRevertIfChangeFromNonOwner(uint192 _newFee) public {
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(alice);
    vaultController.changeProtocolFee(_newFee);
  }

  function testRevertIfFeeIsTooHigh(uint192 _newFee) public {
    vm.assume(_newFee > 1 ether);
    vm.expectRevert(IVaultController.VaultController_FeeTooLarge.selector);
    vm.prank(governance);
    vaultController.changeProtocolFee(_newFee);
  }

  function testChangeProtocolFee(uint192 _protocolFee) public {
    vm.assume(_protocolFee < 1 ether);
    vm.expectEmit(false, false, false, true);
    emit NewProtocolFee(_protocolFee);

    vm.prank(governance);
    vaultController.changeProtocolFee(_protocolFee);
    assertEq(vaultController.protocolFee(), _protocolFee);
  }
}

contract UnitVaultControllerChangeInitialBorrowingFee is Base {
  event ChangedInitialBorrowingFee(uint192 _oldBorrowingFee, uint192 _newBorrowingFee);

  function testRevertIfChangeFromNonOwner(uint192 _newFee) public {
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(alice);
    vaultController.changeInitialBorrowingFee(_newFee);
  }

  function testRevertIfFeeIsTooHigh(uint192 _newFee) public {
    vm.assume(_newFee > vaultController.MAX_INIT_BORROWING_FEE());
    vm.expectRevert(IVaultController.VaultController_FeeTooLarge.selector);
    vm.prank(governance);
    vaultController.changeInitialBorrowingFee(_newFee);
  }

  function testChangeInitialBorrowingFee(uint192 _fee) public {
    vm.assume(_fee < vaultController.MAX_INIT_BORROWING_FEE());
    vm.expectEmit(false, false, false, true);
    emit ChangedInitialBorrowingFee(vaultController.initialBorrowingFee(), _fee);

    vm.prank(governance);
    vaultController.changeInitialBorrowingFee(_fee);
    assertEq(vaultController.initialBorrowingFee(), _fee);
  }
}

contract UnitVaultControllerChangeLiquidationFee is Base {
  event ChangedLiquidationFee(uint192 _oldLiquidationFee, uint192 _newLiquidationFee);

  function testRevertIfChangeFromNonOwner(uint192 _newFee) public {
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(alice);
    vaultController.changeLiquidationFee(_newFee);
  }

  function testRevertIfFeeIsTooHigh(uint192 _newFee) public {
    vm.assume(_newFee > 1 ether);
    vm.expectRevert(IVaultController.VaultController_FeeTooLarge.selector);
    vm.prank(governance);
    vaultController.changeLiquidationFee(_newFee);
  }

  function testChangeLiquidationFee(uint192 _fee) public {
    vm.assume(_fee < 1 ether);

    vm.expectEmit(false, false, false, true);
    emit ChangedLiquidationFee(vaultController.liquidationFee(), _fee);

    vm.prank(governance);
    vaultController.changeLiquidationFee(_fee);
    assertEq(vaultController.liquidationFee(), _fee);
  }
}

contract UnitVaultControllerGetBorrowingFee is Base {
  function testGetBorrowingFee(uint192 _baseAmount) public {
    vm.assume(_baseAmount < type(uint192).max / vaultController.initialBorrowingFee());
    vm.assume(_baseAmount < type(uint192).max / (vaultController.initialBorrowingFee() + 1e18));
    vm.assume(_baseAmount * vaultController.initialBorrowingFee() >= 1e18);

    assertEq(vaultController.getBorrowingFee(_baseAmount), (_baseAmount * vaultController.initialBorrowingFee()) / 1e18);
  }
}

contract UnitVaultControllerGetLiquidationFee is Base {
  function testGetLiquidationFee(uint192 _amount) public {
    vm.assume(_amount < type(uint192).max / vaultController.liquidationFee());
    vm.assume(_amount < type(uint192).max / (vaultController.liquidationFee() + 1e18));
    vm.assume(_amount * vaultController.liquidationFee() >= 1e18);

    uint256 _liquidatorExpectedProfit = (_amount * vaultController.tokenLiquidationIncentive(WETH_ADDRESS)) / 1e18;

    assertEq(
      vaultController.getLiquidationFee(_amount, WETH_ADDRESS),
      (_liquidatorExpectedProfit * vaultController.liquidationFee()) / 1e18
    );
  }
}

contract UnitVaultControllerRegisterCurveMaster is Base {
  event RegisterCurveMaster(address _curveMasterAddress);

  CurveMaster public otherCurveMaster;

  function setUp() public virtual override {
    super.setUp();
    vm.prank(governance);
    otherCurveMaster = new CurveMaster();
  }

  function testRevertIfRegisterFromNonOwner() public {
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(alice);
    vaultController.registerCurveMaster(address(otherCurveMaster));
  }

  function testRegisterCurveMaster() public {
    vm.expectEmit(false, false, false, true);
    emit RegisterCurveMaster(address(otherCurveMaster));
    vm.prank(governance);
    vaultController.registerCurveMaster(address(otherCurveMaster));
    assertEq(address(vaultController.curveMaster()), address(otherCurveMaster));
  }
}

contract UnitVaultControllerRegisterERC20 is Base {
  event RegisteredErc20(
    address _tokenAddress, uint256 _ltv, address _oracleAddress, uint256 _liquidationIncentive, uint256 _cap
  );

  function testRevertIfRegisterFromNonOwner(
    IERC20 _token,
    address _oracle,
    uint256 _ltv,
    uint256 _liquidationIncentive,
    uint256 _cap,
    uint8 _decimals
  ) public {
    vm.assume(address(_token) > address(10));
    vm.assume(_decimals <= 18);
    mockContract(address(_token), 'token');
    vm.mockCall(address(_token), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals));
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(alice);
    vaultController.registerErc20(address(_token), _ltv, _oracle, _liquidationIncentive, _cap, 0);
  }

  function testRevertIfTokenAlreadyRegistered(address _oracle, uint64 _ltv, uint256 _cap) public {
    vm.assume(_ltv < 0.95 ether);
    // Register WETH as acceptable erc20 collateral to vault controller and set oracle
    vm.prank(governance);
    vaultController.registerErc20(WETH_ADDRESS, _ltv, _oracle, LIQUIDATION_INCENTIVE, _cap, 0);
    vm.expectRevert(IVaultController.VaultController_TokenAlreadyRegistered.selector);
    // Try to register the same again
    vm.prank(governance);
    vaultController.registerErc20(WETH_ADDRESS, _ltv, _oracle, LIQUIDATION_INCENTIVE, _cap, 0);
  }

  function testRevertIfIncompatibleLTV(
    IERC20 _token,
    address _oracle,
    uint64 _liquidationIncentive,
    uint256 _cap
  ) public {
    vm.assume(_liquidationIncentive < 1 ether && _liquidationIncentive > 0.2 ether);
    vm.assume(address(_token) > address(10));
    mockContract(address(_token), 'token');

    vm.mockCall(address(_token), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
    vm.expectRevert(IVaultController.VaultController_LTVIncompatible.selector);
    vm.prank(governance);
    vaultController.registerErc20(address(_token), WETH_LTV, _oracle, _liquidationIncentive, _cap, 0);
  }

  function testRevertIfTokenAddressDoesNotMatchLPTokenAddress(
    IERC20 _token,
    address _oracle,
    uint64 _ltv,
    uint256 _cap
  ) public {
    vm.assume(_ltv < 0.95 ether);
    vm.assume(address(_token) > address(10));
    vm.mockCall(
      address(booster),
      abi.encodeWithSelector(IBooster.poolInfo.selector, 136),
      abi.encode(address(0), address(0), address(0), address(0), address(0), false)
    );
    mockContract(address(_token), 'token');

    vm.mockCall(address(_token), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
    vm.expectRevert(IVaultController.VaultController_TokenAddressDoesNotMatchLpAddress.selector);
    vm.prank(governance);
    vaultController.registerErc20(address(_token), WETH_LTV, _oracle, LIQUIDATION_INCENTIVE, _cap, 136);
  }

  function testRegisterCurveLPToken(address _oracle, uint64 _ltv, uint256 _cap, uint8 _decimals) public {
    vm.assume(_ltv < 0.95 ether);
    vm.assume(_decimals <= 18);
    address _token = newAddress();
    mockContract(address(_token), 'token');
    vm.mockCall(address(_token), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals));

    address _mockCrvRewards = newAddress();
    vm.mockCall(
      address(booster),
      abi.encodeWithSelector(IBooster.poolInfo.selector, 15),
      abi.encode(address(_token), address(0), address(0), _mockCrvRewards, address(0), false)
    );
    vm.prank(governance);
    vaultController.registerErc20(address(_token), _ltv, _oracle, LIQUIDATION_INCENTIVE, _cap, 15);
    assertEq(address(vaultController.tokensOracle(address(_token))), _oracle);
    assertEq(vaultController.tokensRegistered(), 1);
    assertEq(vaultController.tokenId(address(_token)), 1);
    assertEq(vaultController.tokenLTV(address(_token)), _ltv);
    assertEq(vaultController.tokenLiquidationIncentive(address(_token)), LIQUIDATION_INCENTIVE);
    assertEq(vaultController.tokenCap(address(_token)), _cap);
    assertEq(vaultController.tokenCollateralInfo(address(_token)).decimals, _decimals);
    assertTrue(
      vaultController.tokenCollateralType(address(_token)) == IVaultController.CollateralType.CurveLPStakedOnConvex
    );
    assertEq(address(vaultController.tokenCrvRewardsContract(address(_token))), _mockCrvRewards);
    assertEq(vaultController.tokenPoolId(address(_token)), 15);
  }

  function testRegisterERC20(IERC20 _token, address _oracle, uint8 _decimals) public {
    vm.assume(address(_token) > address(10));
    vm.assume(_decimals <= 18);
    vm.expectEmit(false, false, false, true);
    emit RegisteredErc20(address(_token), WETH_LTV, _oracle, LIQUIDATION_INCENTIVE, type(uint256).max);
    mockContract(address(_token), 'token');
    vm.mockCall(address(_token), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals));

    vm.prank(governance);
    vaultController.registerErc20(address(_token), WETH_LTV, _oracle, LIQUIDATION_INCENTIVE, type(uint256).max, 0);
    assertEq(address(vaultController.tokensOracle(address(_token))), _oracle);
    assertEq(vaultController.tokensRegistered(), 1);
    assertEq(vaultController.tokenId(address(_token)), 1);
    assertEq(vaultController.tokenLTV(address(_token)), WETH_LTV);
    assertEq(vaultController.tokenLiquidationIncentive(address(_token)), LIQUIDATION_INCENTIVE);
    assertEq(vaultController.tokenCap(address(_token)), type(uint256).max);
    assertEq(vaultController.tokenCollateralInfo(address(_token)).decimals, _decimals);
  }

  function testRevertIfRegisterERC20WithMoreThan18Decimals(IERC20 _token, address _oracle, uint8 _decimals) public {
    vm.assume(address(_token) > address(10));
    vm.assume(_decimals > 18);
    mockContract(address(_token), 'token');
    vm.mockCall(address(_token), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals));
    vm.expectRevert(IVaultController.VaultController_TooManyDecimals.selector);
    vm.prank(governance);
    vaultController.registerErc20(address(_token), WETH_LTV, _oracle, LIQUIDATION_INCENTIVE, type(uint256).max, 0);
  }

  function testRevertIfRegisterCurveLpWithMoreThan18Decimals(
    address _oracle,
    uint64 _ltv,
    uint256 _cap,
    uint8 _decimals
  ) public {
    vm.assume(_ltv < 0.95 ether);
    vm.assume(_decimals > 18);
    address _token = newAddress();
    mockContract(address(_token), 'token');
    vm.mockCall(address(_token), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals));

    address _mockCrvRewards = newAddress();
    vm.mockCall(
      address(booster),
      abi.encodeWithSelector(IBooster.poolInfo.selector, 15),
      abi.encode(address(_token), address(0), address(0), _mockCrvRewards, address(0), false)
    );
    vm.expectRevert(IVaultController.VaultController_TooManyDecimals.selector);

    vm.prank(governance);
    vaultController.registerErc20(address(_token), _ltv, _oracle, LIQUIDATION_INCENTIVE, _cap, 15);
  }
}

contract UnitVaultControllerUpdateRegisteredERC20 is Base {
  event UpdateRegisteredErc20(
    address _tokenAddress,
    uint256 _ltv,
    address _oracleAddress,
    uint256 _liquidationIncentive,
    uint256 _cap,
    uint256 _poolId
  );

  function setUp() public virtual override {
    super.setUp();
    vm.prank(governance);
    vaultController.registerErc20(
      WETH_ADDRESS, WETH_LTV, address(anchoredViewEth), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );
  }

  function testRevertIfUpdateFromNonOwner(
    IERC20 _token,
    address _oracle,
    uint64 _ltv,
    uint256 _liquidationIncentive,
    uint256 _poolId
  ) public {
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(alice);
    vaultController.updateRegisteredErc20(
      address(_token), _ltv, _oracle, _liquidationIncentive, type(uint256).max, _poolId
    );
  }

  function testRevertIfTokenNotRegistered(IERC20 _token, address _oracle, uint64 _ltv, uint256 _poolId) public {
    vm.assume(_ltv < 0.95 ether && address(_token) != WETH_ADDRESS);
    vm.expectRevert(IVaultController.VaultController_TokenNotRegistered.selector);
    // Try to update a non registered token
    vm.prank(governance);
    vaultController.updateRegisteredErc20(
      address(_token), _ltv, _oracle, LIQUIDATION_INCENTIVE, type(uint256).max, _poolId
    );
  }

  function testRevertIfIncompatibleLTV(address _oracle, uint64 _liquidationIncentive, uint256 _poolId) public {
    vm.assume(_liquidationIncentive < 1 ether && _liquidationIncentive > 0.2 ether);
    vm.expectRevert(IVaultController.VaultController_LTVIncompatible.selector);
    vm.prank(governance);
    vaultController.updateRegisteredErc20(
      WETH_ADDRESS, WETH_LTV, _oracle, _liquidationIncentive, type(uint256).max, _poolId
    );
  }

  function testRevertIfUpdatingPoolIdAndLpTokenDoesNotMatch(
    address _oracle,
    uint256 _ltv,
    uint256 _cap,
    uint256 _poolId
  ) public {
    vm.assume(_ltv < 0.95 ether);
    vm.assume(_poolId != 0);

    address _mockCrvRewards = newAddress();

    vm.mockCall(
      address(vaultController.BOOSTER()),
      abi.encodeWithSelector(IBooster.poolInfo.selector),
      abi.encode(newAddress(), address(0), address(0), _mockCrvRewards, address(0), false)
    );

    vm.expectRevert(IVaultController.VaultController_TokenAddressDoesNotMatchLpAddress.selector);
    vm.prank(governance);
    vaultController.updateRegisteredErc20(WETH_ADDRESS, _ltv, _oracle, LIQUIDATION_INCENTIVE, _cap, _poolId);
  }

  function testUpdateRegisteredERC20(address _oracle, uint256 _ltv, uint256 _cap) public {
    vm.assume(_ltv < 0.95 ether);
    vm.expectEmit(false, false, false, true);
    emit UpdateRegisteredErc20(WETH_ADDRESS, _ltv, _oracle, LIQUIDATION_INCENTIVE, _cap, 0);

    vm.prank(governance);
    vaultController.updateRegisteredErc20(WETH_ADDRESS, _ltv, _oracle, LIQUIDATION_INCENTIVE, _cap, 0);
    assertEq(address(vaultController.tokensOracle(WETH_ADDRESS)), _oracle);
    assertEq(vaultController.tokenLTV(WETH_ADDRESS), _ltv);
    assertEq(vaultController.tokenLiquidationIncentive(WETH_ADDRESS), LIQUIDATION_INCENTIVE);
    assertEq(vaultController.tokenCap(WETH_ADDRESS), _cap);
  }

  function testUpdateRegisteredSingleToCurveLPStakedOnConvex(
    address _oracle,
    uint256 _ltv,
    uint256 _cap,
    uint256 _poolId
  ) public {
    vm.assume(_ltv < 0.95 ether);
    vm.assume(_poolId != 0);

    address _mockCrvRewards = newAddress();

    vm.mockCall(
      address(vaultController.BOOSTER()),
      abi.encodeWithSelector(IBooster.poolInfo.selector),
      abi.encode(WETH_ADDRESS, address(0), address(0), _mockCrvRewards, address(0), false)
    );

    vm.prank(governance);
    vaultController.updateRegisteredErc20(WETH_ADDRESS, _ltv, _oracle, LIQUIDATION_INCENTIVE, _cap, _poolId);

    assertEq(address(vaultController.tokensOracle(WETH_ADDRESS)), _oracle);
    assertEq(vaultController.tokenLTV(WETH_ADDRESS), _ltv);
    assertEq(vaultController.tokenLiquidationIncentive(WETH_ADDRESS), LIQUIDATION_INCENTIVE);
    assertEq(vaultController.tokenCap(WETH_ADDRESS), _cap);
    assertEq(vaultController.tokenPoolId(WETH_ADDRESS), _poolId);
    assertEq(address(vaultController.tokenCrvRewardsContract(WETH_ADDRESS)), _mockCrvRewards);
    assert(vaultController.tokenCollateralType(WETH_ADDRESS) == IVaultController.CollateralType.CurveLPStakedOnConvex);
  }
}

contract UnitVaultControllerChangeClaimerContract is Base {
  event ChangedClaimerContract(IAMPHClaimer _oldClaimerContract, IAMPHClaimer _newClaimerContract);

  function testRevertIfChangeFromNonOwner(IAMPHClaimer _claimerContract) public {
    vm.expectRevert('Ownable: caller is not the owner');
    vm.prank(alice);
    vaultController.changeClaimerContract(_claimerContract);
  }

  function testChangeClaimerContract(IAMPHClaimer _claimerContract) public {
    vm.expectEmit(false, false, false, true);
    emit ChangedClaimerContract(vaultController.claimerContract(), _claimerContract);

    vm.prank(governance);
    vaultController.changeClaimerContract(_claimerContract);
    assertEq(address(vaultController.claimerContract()), address(_claimerContract));
  }
}

contract UnitVaultControllerLiquidateVault is VaultBase, ExponentialNoError {
  event Liquidate(
    uint256 _vaultId,
    address _assetAddress,
    uint256 _usdaToRepurchase,
    uint256 _tokensToLiquidate,
    uint256 _liquidationFee
  );

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    usdaToken.deposit(100 ether);
  }

  function testRevertIfPaused(uint96 _id, address _assetAddress, uint256 _tokensToLiquidate) public {
    vm.startPrank(governance);
    vaultController.pause();
    vm.stopPrank();

    vm.expectRevert('Pausable: paused');
    vaultController.liquidateVault(_id, _assetAddress, _tokensToLiquidate);
  }

  function testRevertIfLiquidateZeroAmount(uint96 _id, address _assetAddress) public {
    vm.expectRevert(IVaultController.VaultController_LiquidateZeroTokens.selector);
    vaultController.liquidateVault(_id, _assetAddress, 0);
  }

  function testRevertIfLiquidateTokenNotRegistered(
    uint96 _id,
    address _assetAddress,
    uint256 _tokensToLiquidate
  ) public {
    vm.assume(
      _assetAddress != WETH_ADDRESS && _assetAddress != address(usdtLp) && _assetAddress != WBTC_ADDRESS
        && _tokensToLiquidate != 0
    );
    vm.expectRevert(IVaultController.VaultController_TokenNotRegistered.selector);
    vaultController.liquidateVault(_id, _assetAddress, _tokensToLiquidate);
  }

  function testRevertIfVaultDoesNotExist(uint96 _id, uint256 _tokensToLiquidate) public {
    vm.assume(_tokensToLiquidate != 0 && _id > 100);
    vm.expectRevert(IVaultController.VaultController_VaultDoesNotExist.selector);
    vaultController.liquidateVault(_id, WETH_ADDRESS, _tokensToLiquidate);
  }

  function testRevertIfVaultIsSolvent(uint256 _tokensToLiquidate) public {
    vm.assume(_tokensToLiquidate != 0);
    vm.expectRevert(IVaultController.VaultController_VaultSolvent.selector);
    vaultController.liquidateVault(_vaultId, WETH_ADDRESS, _tokensToLiquidate);
  }

  function testRevertIfWbtcVaultIsSolvent(uint256 _tokensToLiquidate) public {
    vm.assume(_tokensToLiquidate != 0);
    uint192 _borrowingPower = vaultController.vaultBorrowingPower(_vaultIdWbtc);
    vm.prank(vaultOwnerWbtc);
    vaultController.borrowUSDA(_vaultIdWbtc, _borrowingPower);
    vm.expectRevert(IVaultController.VaultController_VaultSolvent.selector);
    vaultController.liquidateVault(_vaultIdWbtc, WBTC_ADDRESS, _tokensToLiquidate);
  }

  function testLiquidateWbtc() public {
    uint192 _borrowingPower = vaultController.vaultBorrowingPower(_vaultIdWbtc);
    vm.prank(vaultOwnerWbtc);
    vaultController.borrowUSDA(_vaultIdWbtc, _borrowingPower);
    uint256 _oldPrice = wbtcPrice;
    uint256 _newPrice = (_oldPrice * OTHER_LTV) / 100 ether;
    // We lower the price
    vm.mockCall(
      address(_mockedWbtcOracle), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(_newPrice)
    );
    vm.mockCall(
      address(_mockedWbtcOracle), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_newPrice)
    );
    // Need to pay USDA to cover for _wbtcDeposit
    vm.prank(address(vaultController));
    usdaToken.vaultControllerMint(address(this), _borrowingPower);
    uint256 _liqFee = vaultController.getLiquidationFee(uint192(_wbtcDeposit), address(_mockedWbtc));
    vm.expectCall(
      address(_mockedWbtc), abi.encodeWithSelector(IERC20.transfer.selector, address(this), _wbtcDeposit - _liqFee)
    );
    vaultController.liquidateVault(_vaultIdWbtc, WBTC_ADDRESS, _wbtcDeposit);
  }

  function testLiquidatePartialWbtc() public {
    vm.prank(vaultOwnerWbtc);
    _vaultWbtc.depositERC20(WETH_ADDRESS, _vaultDeposit);

    uint192 _borrowingPower = vaultController.vaultBorrowingPower(_vaultIdWbtc);
    vm.prank(vaultOwnerWbtc);
    vaultController.borrowUSDA(_vaultIdWbtc, _borrowingPower);
    uint256 _doubleTruncate = 1 ether * 1 ether;
    uint256 _valueInWeth = (_vaultDeposit * anchoredViewEth.currentValue() * WETH_LTV) / _doubleTruncate;
    uint256 _wbtcNewPrice = (wbtcPrice * 90) / 100;

    // We lower the price
    vm.mockCall(
      address(_mockedWbtcOracle), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(_wbtcNewPrice)
    );
    vm.mockCall(
      address(_mockedWbtcOracle), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(_wbtcNewPrice)
    );

    // uint256 _wbtcToLiquidate = 0;
    // We calculate the wbtcToLiquidate to let the vault be solvent
    uint256 _newMaxBorrow = _valueInWeth + (_wbtcDeposit * _wbtcNewPrice * 10 ** 10 * OTHER_LTV) / _doubleTruncate;
    uint256 _wbtcToLiquidate =
      (_borrowingPower - _newMaxBorrow) * _doubleTruncate * 1e8 / (_wbtcDeposit * _wbtcNewPrice * 10 ** 10 * OTHER_LTV);

    // Need to pay USDA to cover for _wbtcDeposit
    vm.prank(address(vaultController));
    usdaToken.vaultControllerMint(address(this), 100_000 ether);
    uint256 _liqFee = vaultController.getLiquidationFee(uint192(_wbtcToLiquidate), address(_mockedWbtc));
    vm.expectCall(
      address(_mockedWbtc), abi.encodeWithSelector(IERC20.transfer.selector, address(this), _wbtcToLiquidate - _liqFee)
    );
    uint256 _usdaToPay =
      (_wbtcToLiquidate * _wbtcNewPrice * 10 ** 10 * (1e18 - LIQUIDATION_INCENTIVE)) / _doubleTruncate;
    vm.expectCall(
      address(usdaToken), abi.encodeWithSelector(IUSDA.vaultControllerBurn.selector, address(this), _usdaToPay)
    );
    vaultController.liquidateVault(_vaultIdWbtc, WBTC_ADDRESS, _wbtcToLiquidate);
  }

  function testLiquidateWithCurveLpAsCollateral() public {
    vm.mockCall(address(usdtLp), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCall(address(vaultController.BOOSTER()), abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(true));

    vm.prank(vaultOwner);
    _vault.depositERC20(address(usdtLp), _vaultDeposit);

    vm.mockCall(
      address(_crvRewards), abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector), abi.encode(true)
    );

    vm.mockCall(
      address(threeCrvOracle), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(1 ether)
    );
    vm.mockCall(address(threeCrvOracle), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));

    // borrow a few usda
    vm.startPrank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, vaultController.vaultBorrowingPower(_vaultId));
    vm.stopPrank();

    // make vault insolvent
    vm.warp(block.timestamp + 2 weeks);
    vaultController.calculateInterest();

    uint256 _tokensToLiquidate = vaultController.tokensToLiquidate(_vaultId, address(usdtLp));
    uint256 _badFillPrice = _truncate(threeCrvOracle.currentValue() * (1e18 - LIQUIDATION_INCENTIVE));

    (, uint192 _factor) = vaultController.interest();
    uint256 _liability = (_truncate(_badFillPrice * _tokensToLiquidate) * 1e18) / _factor;

    address _owner = vaultController.owner();
    uint256 _liqFee = vaultController.getLiquidationFee(uint192(_tokensToLiquidate), address(usdtLp));

    vm.expectCall(address(_vault), abi.encodeWithSelector(IVault.modifyLiability.selector, false, _liability));
    vm.expectCall(
      address(_crvRewards),
      abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector, _tokensToLiquidate, false)
    );
    vm.expectCall(
      address(_vault),
      abi.encodeWithSelector(
        IVault.controllerTransfer.selector, address(usdtLp), address(this), _tokensToLiquidate - _liqFee
      )
    );
    vm.expectCall(
      address(_vault), abi.encodeWithSelector(IVault.controllerTransfer.selector, address(usdtLp), _owner, _liqFee)
    );

    vaultController.liquidateVault(_vaultId, address(usdtLp), 10 ether);
  }

  function testLiquidateWhenLiquidationFeeIsZero() public {
    vm.mockCall(address(usdtLp), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCall(address(vaultController.BOOSTER()), abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(true));

    vm.prank(vaultOwner);
    _vault.depositERC20(address(usdtLp), _vaultDeposit);

    vm.mockCall(
      address(_crvRewards), abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector), abi.encode(true)
    );

    vm.mockCall(
      address(threeCrvOracle), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(1 ether)
    );
    vm.mockCall(address(threeCrvOracle), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));

    // set liquidation fee in zero
    vm.prank(vaultController.owner());
    vaultController.changeLiquidationFee(0);

    // borrow a few usda
    vm.startPrank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, vaultController.vaultBorrowingPower(_vaultId));
    vm.stopPrank();

    // make vault insolvent
    vm.warp(block.timestamp + 2 weeks);
    vaultController.calculateInterest();

    uint256 _tokensToLiquidate = vaultController.tokensToLiquidate(_vaultId, address(usdtLp));
    uint256 _badFillPrice = _truncate(threeCrvOracle.currentValue() * (1e18 - LIQUIDATION_INCENTIVE));

    (, uint192 _factor) = vaultController.interest();
    uint256 _liability = (_truncate(_badFillPrice * _tokensToLiquidate) * 1e18) / _factor;

    address _owner = vaultController.owner();

    vm.expectCall(address(_vault), abi.encodeWithSelector(IVault.modifyLiability.selector, false, _liability));
    vm.expectCall(
      address(_crvRewards),
      abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector, _tokensToLiquidate, false)
    );
    vm.expectCall(
      address(_vault),
      abi.encodeWithSelector(IVault.controllerTransfer.selector, address(usdtLp), address(this), _tokensToLiquidate)
    );
    vm.expectCall(
      address(_vault), abi.encodeWithSelector(IVault.controllerTransfer.selector, address(usdtLp), _owner, 0)
    );

    vaultController.liquidateVault(_vaultId, address(usdtLp), 10 ether);
  }

  function testCallExternalCalls() public {
    // borrow a few usda
    vm.startPrank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, vaultController.vaultBorrowingPower(_vaultId));
    vm.stopPrank();
    // make vault insolvent
    vm.warp(block.timestamp + 2 weeks);
    vaultController.calculateInterest();

    uint256 _tokensToLiquidate = vaultController.tokensToLiquidate(_vaultId, WETH_ADDRESS);
    uint256 _badFillPrice = _truncate(anchoredViewEth.currentValue() * (1e18 - LIQUIDATION_INCENTIVE));

    (, uint192 _factor) = vaultController.interest();
    uint256 _liability = (_truncate(_badFillPrice * _tokensToLiquidate) * 1e18) / _factor;

    uint256 _liqFee = vaultController.getLiquidationFee(uint192(_tokensToLiquidate), WETH_ADDRESS);

    vm.expectCall(address(_vault), abi.encodeWithSelector(IVault.modifyLiability.selector, false, _liability));
    vm.expectCall(
      address(usdaToken),
      abi.encodeWithSelector(
        IUSDA.vaultControllerBurn.selector, address(this), _truncate(_badFillPrice * _tokensToLiquidate)
      )
    );
    vm.expectCall(address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.currentValue.selector));
    vm.expectCall(
      address(_vault),
      abi.encodeWithSelector(
        IVault.controllerTransfer.selector, WETH_ADDRESS, address(this), _tokensToLiquidate - _liqFee
      )
    );
    vaultController.liquidateVault(_vaultId, WETH_ADDRESS, 10 ether);
  }

  function testEmitEvent() public {
    // borrow a few usda
    vm.startPrank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, vaultController.vaultBorrowingPower(_vaultId));
    vm.stopPrank();
    // make vault insolvent
    vm.warp(block.timestamp + 2 weeks);
    vaultController.calculateInterest();

    uint256 _tokensToLiquidate = vaultController.tokensToLiquidate(_vaultId, WETH_ADDRESS);
    uint256 _badFillPrice = _truncate(anchoredViewEth.currentValue() * (1e18 - LIQUIDATION_INCENTIVE));

    vm.expectEmit(true, true, true, true);
    uint256 _liquidationFee = vaultController.getLiquidationFee(uint192(_tokensToLiquidate), WETH_ADDRESS);
    emit Liquidate(
      _vaultId,
      WETH_ADDRESS,
      _truncate(_badFillPrice * _tokensToLiquidate),
      _tokensToLiquidate - _liquidationFee,
      _liquidationFee
    );
    vaultController.liquidateVault(_vaultId, WETH_ADDRESS, 10 ether);
  }
}

contract UnitVaultControllerSimulateLiquidateVault is VaultBase, ExponentialNoError {
  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    usdaToken.deposit(100 ether);
  }

  function testRevertIfLiquidateZeroAmount(uint96 _id, address _assetAddress) public {
    vm.expectRevert(IVaultController.VaultController_LiquidateZeroTokens.selector);
    vaultController.simulateLiquidateVault(_id, _assetAddress, 0);
  }

  function testRevertIfLiquidateTokenNotRegistered(
    uint96 _id,
    address _assetAddress,
    uint256 _tokensToLiquidate
  ) public {
    vm.assume(
      _assetAddress != WETH_ADDRESS && _assetAddress != address(usdtLp) && _assetAddress != WBTC_ADDRESS
        && _tokensToLiquidate != 0
    );
    vm.expectRevert(IVaultController.VaultController_TokenNotRegistered.selector);
    vaultController.simulateLiquidateVault(_id, _assetAddress, _tokensToLiquidate);
  }

  function testRevertIfVaultDoesNotExist(uint96 _id, uint256 _tokensToLiquidate) public {
    vm.assume(_tokensToLiquidate != 0 && _id > 100);
    vm.expectRevert(IVaultController.VaultController_VaultDoesNotExist.selector);
    vaultController.simulateLiquidateVault(_id, WETH_ADDRESS, _tokensToLiquidate);
  }

  function testRevertIfVaultIsSolvent(uint256 _tokensToLiquidate) public {
    vm.assume(_tokensToLiquidate != 0);
    vm.expectRevert(IVaultController.VaultController_VaultSolvent.selector);
    vaultController.simulateLiquidateVault(_vaultId, WETH_ADDRESS, _tokensToLiquidate);
  }

  function testSimulateLiquidateVault() public {
    vm.mockCall(address(usdtLp), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCall(address(vaultController.BOOSTER()), abi.encodeWithSelector(IBooster.deposit.selector), abi.encode(true));

    vm.prank(vaultOwner);
    _vault.depositERC20(address(usdtLp), _vaultDeposit);

    vm.mockCall(
      address(_crvRewards), abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector), abi.encode(true)
    );

    vm.mockCall(address(threeCrvOracle), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
    vm.mockCall(
      address(threeCrvOracle), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(1 ether)
    );

    // borrow a few usda
    vm.startPrank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, vaultController.vaultBorrowingPower(_vaultId));
    vm.stopPrank();

    // make vault insolvent
    vm.warp(block.timestamp + 2 weeks);
    vaultController.calculateInterest();

    // simulate
    (uint256 _collateralReceivedInSimulation, uint256 _usdaPaidSimulation) =
      vaultController.simulateLiquidateVault(_vaultId, address(usdtLp), 10 ether);

    // liquidate
    vm.expectCall(
      address(usdaToken), abi.encodeWithSelector(IUSDA.vaultControllerBurn.selector, address(this), _usdaPaidSimulation)
    );
    uint256 _collateralLiquidated = vaultController.liquidateVault(_vaultId, address(usdtLp), 10 ether);

    // compare
    assertEq(
      _collateralReceivedInSimulation
        + vaultController.getLiquidationFee(uint192(_collateralLiquidated), address(usdtLp)),
      _collateralLiquidated
    );
  }
}

contract UnitVaultControllerCheckVault is VaultBase {
  function setUp() public virtual override {
    super.setUp();
  }

  function testRevertIfVaultNotFound(uint96 _id) public {
    vm.assume(_id > 100);
    vm.expectRevert(IVaultController.VaultController_VaultDoesNotExist.selector);
    vaultController.checkVault(_id);
  }

  function testCheckVaultSolvent() public {
    assertTrue(vaultController.checkVault(_vaultId));
  }

  function testCheckVaultCallsCurrentValue() public {
    vm.expectCall(address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.currentValue.selector));
    vaultController.checkVault(_vaultId);
  }

  function testCheckVaultInsolvent() public {
    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, _borrowAmount);

    vm.mockCall(
      address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.currentValue.selector), abi.encode(1 ether / 4)
    );
    assertFalse(vaultController.checkVault(_vaultId));
  }
}

contract UnitVaultControllerBorrow is VaultBase {
  function setUp() public virtual override {
    super.setUp();
  }

  function testRevertIfPaused(uint96 _id, uint192 _amount) public {
    vm.prank(governance);
    vaultController.pause();

    vm.expectRevert('Pausable: paused');
    vaultController.borrowUSDA(_id, _amount);
  }

  function testRevertIfNotMinter(uint192 _amount) public {
    vm.expectRevert(IVaultController.VaultController_OnlyMinter.selector);
    vm.prank(alice);
    vaultController.borrowUSDA(_vaultId, _amount);
  }

  function testRevertIfVaultInsolvent() public {
    vm.expectRevert(IVaultController.VaultController_VaultInsolvent.selector);
    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, uint192(_vaultDeposit * 1000));
  }

  function testBorrowUSDA() public {
    uint256 _usdaBalanceBefore = usdaToken.balanceOf(vaultOwner);
    vm.expectEmit(true, true, true, true);
    emit BorrowUSDA(_vaultId, address(_vault), _borrowAmount, vaultController.getBorrowingFee(uint192(_borrowAmount)));

    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, _borrowAmount);
    assertEq(usdaToken.balanceOf(vaultOwner), _usdaBalanceBefore + _borrowAmount);
  }

  function testBorrowUSDATo() public {
    uint256 _usdaBalanceBefore = usdaToken.balanceOf(vaultOwner);
    vm.expectEmit(true, true, true, true);
    emit BorrowUSDA(_vaultId, address(_vault), _borrowAmount, vaultController.getBorrowingFee(uint192(_borrowAmount)));

    vm.prank(vaultOwner);
    vaultController.borrowUSDAto(_vaultId, _borrowAmount, vaultOwner);
    assertEq(usdaToken.balanceOf(vaultOwner), _usdaBalanceBefore + _borrowAmount);
  }

  function testBorrowUSDATreasuryReceivesFee() public {
    uint256 _usdaBalanceBefore = usdaToken.balanceOf(vaultController.owner());

    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, _borrowAmount);
    assertEq(
      usdaToken.balanceOf(vaultController.owner()),
      _usdaBalanceBefore + vaultController.getBorrowingFee(uint192(_borrowAmount))
    );
  }

  function testBorrowUSDAWithFeeInZero() public {
    uint256 _usdaBalanceTreasuryBefore = usdaToken.balanceOf(vaultController.owner());
    uint256 _usdaBalanceBefore = usdaToken.balanceOf(vaultOwner);

    // set fee to 0
    vm.prank(vaultController.owner());
    vaultController.changeInitialBorrowingFee(0);

    vm.expectEmit(true, true, true, true);
    emit BorrowUSDA(_vaultId, address(_vault), _borrowAmount, 0);

    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, _borrowAmount);

    assertEq(usdaToken.balanceOf(vaultOwner), _usdaBalanceBefore + _borrowAmount);
    assertEq(usdaToken.balanceOf(vaultController.owner()), _usdaBalanceTreasuryBefore);
  }

  function testBorrowUSDACallsCurrentValue() public {
    vm.expectCall(address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.currentValue.selector));
    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, _borrowAmount);
  }
}

contract UnitVaultControllerBorrowSUSDto is VaultBase {
  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    usdaToken.deposit(10 ether);
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
  }

  function testRevertIfPaused(uint96 _id, uint192 _amount, address _receiver) public {
    vm.prank(governance);
    vaultController.pause();

    vm.expectRevert('Pausable: paused');
    vaultController.borrowsUSDto(_id, _amount, _receiver);
  }

  function testRevertIfNotMinter(uint192 _amount, address _receiver) public {
    vm.expectRevert(IVaultController.VaultController_OnlyMinter.selector);
    vm.prank(alice);
    vaultController.borrowsUSDto(_vaultId, _amount, _receiver);
  }

  function testRevertIfVaultInsolvent(address _receiver) public {
    vm.expectRevert(IVaultController.VaultController_VaultInsolvent.selector);
    vm.prank(vaultOwner);
    vaultController.borrowsUSDto(_vaultId, uint192(_vaultDeposit * 1000), _receiver);
  }

  function testCallModifyLiability(address _receiver) public {
    vm.expectCall(
      address(_vault),
      abi.encodeWithSelector(
        IVault.modifyLiability.selector, true, _borrowAmount + vaultController.getBorrowingFee(uint192(_borrowAmount))
      )
    );
    vm.prank(vaultOwner);
    vaultController.borrowsUSDto(_vaultId, _borrowAmount, _receiver);
  }

  function testCallVaultControllerTransfer(address _receiver) public {
    vm.expectCall(
      address(usdaToken), abi.encodeWithSelector(IUSDA.vaultControllerTransfer.selector, _receiver, _borrowAmount)
    );
    vm.prank(vaultOwner);
    vaultController.borrowsUSDto(_vaultId, _borrowAmount, _receiver);
  }

  function testEmitEvent(address _receiver) public {
    vm.expectEmit(true, true, true, true);
    emit BorrowUSDA(_vaultId, address(_vault), _borrowAmount, vaultController.getBorrowingFee(uint192(_borrowAmount)));

    vm.prank(vaultOwner);
    vaultController.borrowsUSDto(_vaultId, _borrowAmount, _receiver);
  }
}

contract UnitVaultControllerModifyTotalDeposited is VaultBase {
  function testRevertIfNotValidVault(address _caller) public {
    vm.assume(_caller != alice);
    vm.assume(_caller != address(_vault));
    vm.prank(_caller);

    vm.expectRevert(IVaultController.VaultController_NotValidVault.selector);
    vaultController.modifyTotalDeposited(_vaultId, 0, WETH_ADDRESS, true);
  }

  function testRevertNotValidToken() public {
    address _token = newAddress();

    vm.prank(vaultController.vaultIdVaultAddress(_vaultId));
    vm.expectRevert(IVaultController.VaultController_TokenNotRegistered.selector);
    vaultController.modifyTotalDeposited(_vaultId, 0, _token, true);
  }

  function testValidVault() public {
    vm.prank(vaultController.vaultIdVaultAddress(_vaultId));
    vaultController.modifyTotalDeposited(_vaultId, 0, WETH_ADDRESS, true);
  }

  function testIncrease(uint56 _toIncrease) public {
    vm.startPrank(vaultController.vaultIdVaultAddress(_vaultId));
    uint256 _totalDepositedBefore = vaultController.tokenTotalDeposited(WETH_ADDRESS);
    vaultController.modifyTotalDeposited(_vaultId, _toIncrease, WETH_ADDRESS, true);
    uint256 _totalDepositedAfter = vaultController.tokenTotalDeposited(WETH_ADDRESS);
    assert(_totalDepositedBefore + _toIncrease == _totalDepositedAfter);
    vm.stopPrank();
  }

  function testDecrease(uint56 _toDecrease) public {
    vm.startPrank(vaultController.vaultIdVaultAddress(_vaultId));
    vaultController.modifyTotalDeposited(_vaultId, _toDecrease, WETH_ADDRESS, true);

    uint256 _totalDepositedBefore = vaultController.tokenTotalDeposited(WETH_ADDRESS);
    vaultController.modifyTotalDeposited(_vaultId, _toDecrease, WETH_ADDRESS, false);
    uint256 _totalDepositedAfter = vaultController.tokenTotalDeposited(WETH_ADDRESS);
    assert(_totalDepositedBefore - _toDecrease == _totalDepositedAfter);
    vm.stopPrank();
  }
}

contract UnitVaultControllerCapReached is Base {
  function setUp() public virtual override {
    super.setUp();

    // register token
    vm.prank(governance);
    vaultController.registerErc20(WETH_ADDRESS, WETH_LTV, address(anchoredViewEth), LIQUIDATION_INCENTIVE, cap, 0);

    // mint vault
    vm.prank(alice);
    vaultController.mintVault();

    vm.mockCall(WETH_ADDRESS, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
  }

  function testCap(uint256 _amount) public {
    vm.assume(cap >= _amount);
    vm.assume(_amount > 0);

    address _vaultAddress = vaultController.vaultIdVaultAddress(1);
    vm.prank(alice);
    IVault(_vaultAddress).depositERC20(WETH_ADDRESS, _amount);
  }

  function testRevertCapReached(uint256 _amount) public {
    vm.assume(cap < _amount);
    vm.assume(_amount > 0);

    address _vaultAddress = vaultController.vaultIdVaultAddress(1);
    vm.prank(alice);
    vm.expectRevert(IVaultController.VaultController_CapReached.selector);
    IVault(_vaultAddress).depositERC20(WETH_ADDRESS, _amount);
  }
}

contract UnitVaultControllerRepayUSDA is VaultBase {
  event RepayUSDA(uint256 _vaultId, address _vaultAddress, uint256 _repayAmount);

  function setUp() public virtual override {
    super.setUp();
    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, _borrowAmount);
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    usdaToken.deposit(5 ether);
  }

  function testRevertIfPaused(uint96 _id, uint192 _amount) public {
    vm.prank(governance);
    vaultController.pause();

    vm.expectRevert('Pausable: paused');
    vaultController.repayUSDA(_id, _amount);
  }

  // function testRevertIfRepayTooMuch() public {
  //   vm.expectRevert(IVaultController.VaultController_RepayTooMuch.selector);
  //   vaultController.repayUSDA(_vaultId, _borrowAmount * 10);
  // }

  function testCallModifyLiability(uint56 _amount) public {
    vm.assume(_amount > 0 && _amount <= _borrowAmount);
    vm.expectCall(address(_vault), abi.encodeWithSelector(IVault.modifyLiability.selector, false, _amount));
    vaultController.repayUSDA(_vaultId, _amount);
  }

  function testCallVaultControllerBurn(uint56 _amount) public {
    vm.assume(_amount > 0 && _amount <= _borrowAmount);
    vm.expectCall(
      address(usdaToken), abi.encodeWithSelector(IUSDA.vaultControllerBurn.selector, address(this), _amount)
    );
    vaultController.repayUSDA(_vaultId, _amount);
  }

  function testRepayUSDA(uint56 _amount) public {
    vm.assume(_amount > 0 && _amount <= _borrowAmount);
    vm.expectEmit(true, true, true, true);
    emit RepayUSDA(_vaultId, address(_vault), _amount);
    vaultController.repayUSDA(_vaultId, _amount);
  }
}

contract UnitVaultControllerRepayAllUSDA is VaultBase {
  function setUp() public virtual override {
    super.setUp();
    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, _borrowAmount);

    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    usdaToken.deposit(5 ether);

    vm.mockCall(address(_vault), abi.encodeWithSelector(IVault.baseLiability.selector), abi.encode(_borrowAmount));
  }

  function testRevertIfPaused(uint96 _id) public {
    vm.prank(governance);
    vaultController.pause();

    vm.expectRevert('Pausable: paused');
    vaultController.repayAllUSDA(_id);
  }

  function testCallModifyLiability() public {
    vm.expectCall(address(_vault), abi.encodeWithSelector(IVault.modifyLiability.selector, false, _borrowAmount));
    vaultController.repayAllUSDA(_vaultId);
  }

  function testCallVaultControllerBurn() public {
    vm.expectCall(
      address(usdaToken), abi.encodeWithSelector(IUSDA.vaultControllerBurn.selector, address(this), _borrowAmount)
    );
    vaultController.repayAllUSDA(_vaultId);
  }
}

contract UnitVaultControllerTokensToLiquidate is VaultBase {
  function setUp() public virtual override {
    super.setUp();
    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, _borrowAmount);
  }

  function testRevertIfVaultIsSolvent() public {
    vm.expectRevert(IVaultController.VaultController_VaultSolvent.selector);
    vaultController.tokensToLiquidate(_vaultId, WETH_ADDRESS);
  }

  function testTokensToLiquidate() public {
    vm.mockCall(
      address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether / 4)
    );
    assertEq(vaultController.tokensToLiquidate(_vaultId, WETH_ADDRESS), _vaultDeposit);
  }
}

contract UnitVaultControllerGetVault is VaultBase {
  IVault internal _mockVault;
  VaultDeployer internal _mockVaultDeployer;

  function setUp() public virtual override {
    super.setUp();
    _mockVaultDeployer = new VaultDeployer(cvx, crv);
    address[] memory _tokens = new address[](1);

    mockVaultController =
    new VaultControllerForTest(IVaultController(address(0)), _tokens, mockAmphClaimer, _mockVaultDeployer, 0.01e18, booster, 0.005e18);
  }

  function testRevertIfVaultDoesNotExist(uint96 _id) public {
    vm.assume(_id > 100);
    vm.expectRevert(IVaultController.VaultController_VaultDoesNotExist.selector);
    mockVaultController.getVault(_id);
  }

  function testGetVault() public {
    vm.startPrank(vaultOwner);
    _mockVault = IVault(mockVaultController.mintVault());
    assertEq(address(mockVaultController.getVault(1)), address(_mockVault));
  }
}

contract UnitVaultControllerAmountToSolvency is VaultBase, ExponentialNoError {
  function testRevertIfVaultIsSolvent() public {
    vm.expectRevert(IVaultController.VaultController_VaultSolvent.selector);
    vaultController.amountToSolvency(_vaultId);
  }

  function testAmountToSolvency() public {
    uint192 _rawPrice = _safeu192(anchoredViewEth.currentValue());
    uint192 _borrowPowerWithoutDiscount = _safeu192(_truncate(_truncate(_rawPrice * _vaultDeposit * WETH_LTV)));

    vm.mockCall(
      address(_vault), abi.encodeWithSelector(IVault.baseLiability.selector), abi.encode(_vaultDeposit + 1 ether)
    );

    assertEq(vaultController.amountToSolvency(_vaultId), 11 ether - _borrowPowerWithoutDiscount);
  }
}

contract UnitVaultControllerVaultLiability is VaultBase {
  function testRevertIfVaultDoesNotExist(uint96 _id) public {
    vm.assume(_id > 100);
    vm.expectRevert(IVaultController.VaultController_VaultDoesNotExist.selector);
    vaultController.vaultLiability(_id);
  }

  function testVaultLiability(uint56 _amount) public {
    vm.mockCall(address(_vault), abi.encodeWithSelector(IVault.baseLiability.selector), abi.encode(_amount));
    assertEq(vaultController.vaultLiability(_vaultId), _amount);
  }
}

contract UnitVaultControllerVaultBorrowingPower is VaultBase {
  function testVaultBorrowingPower() public {
    uint256 _borrowingPowerWithoutDiscount = _vaultDeposit * WETH_LTV / 1 ether;
    assertEq(
      vaultController.vaultBorrowingPower(_vaultId),
      _borrowingPowerWithoutDiscount - vaultController.getBorrowingFee(uint192(_borrowingPowerWithoutDiscount))
    );
  }

  function testVaultBorrowingPowerWbtc() public {
    uint256 _borrowingPowerWithoutDiscount = (_wbtcDeposit * wbtcPrice * 10 ** 10 * OTHER_LTV) / (1 ether * 1 ether);
    assertEq(
      vaultController.vaultBorrowingPower(_vaultIdWbtc),
      _borrowingPowerWithoutDiscount - vaultController.getBorrowingFee(uint192(_borrowingPowerWithoutDiscount))
    );
  }

  function testVaultBorrowingPowerWhenOracleReturnsZero() public {
    vm.mockCall(address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(0));
    assertEq(vaultController.vaultBorrowingPower(_vaultId), 0);
  }

  function testVaultBorrowingPowerWhenLTVIsZero() public {
    mockContract(address(UNI_ADDRESS), 'UNI');
    vm.mockCall(address(UNI_ADDRESS), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
    vm.prank(governance);
    vaultController.registerErc20(UNI_ADDRESS, 0, address(anchoredViewUni), LIQUIDATION_INCENTIVE, type(uint256).max, 0);

    vm.startPrank(vaultOwner);
    vm.mockCall(
      UNI_ADDRESS,
      abi.encode(IERC20.transferFrom.selector, vaultOwner, address(_vault), _vaultDeposit),
      abi.encode(true)
    );
    _vault.depositERC20(UNI_ADDRESS, _vaultDeposit);
    vm.stopPrank();

    vm.mockCall(address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
    vm.mockCall(address(anchoredViewUni), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));

    // we calculate only for weth since uni borrowing power should be 0
    uint256 _borrowingPower = (_vaultDeposit * WETH_LTV) / 1 ether;
    assertEq(
      vaultController.vaultBorrowingPower(_vaultId),
      _borrowingPower - vaultController.getBorrowingFee(uint192(_borrowingPower))
    );
  }

  function testVaultBorrowingPowerMultipleCollateral() public {
    vm.prank(governance);
    mockContract(address(UNI_ADDRESS), 'UNI');
    vm.mockCall(address(UNI_ADDRESS), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
    vaultController.registerErc20(
      UNI_ADDRESS, UNI_LTV, address(anchoredViewUni), LIQUIDATION_INCENTIVE, type(uint256).max, 0
    );

    vm.startPrank(vaultOwner);
    vm.mockCall(
      UNI_ADDRESS,
      abi.encode(IERC20.transferFrom.selector, vaultOwner, address(_vault), _vaultDeposit),
      abi.encode(true)
    );
    _vault.depositERC20(UNI_ADDRESS, _vaultDeposit);

    vm.mockCall(
      WBTC_ADDRESS,
      abi.encode(IERC20.transferFrom.selector, vaultOwner, address(_vault), _wbtcDeposit),
      abi.encode(true)
    );
    _vault.depositERC20(WBTC_ADDRESS, _wbtcDeposit);
    vm.stopPrank();

    vm.mockCall(address(anchoredViewEth), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));
    vm.mockCall(address(anchoredViewUni), abi.encodeWithSelector(IOracleRelay.peekValue.selector), abi.encode(1 ether));

    uint256 _borrowingPowerWethUni = (_vaultDeposit * WETH_LTV + _vaultDeposit * UNI_LTV) / 1 ether;
    uint256 _borrowingPowerWbtc = (_wbtcDeposit * wbtcPrice * 10 ** 10 * OTHER_LTV) / (1 ether * 1 ether);

    assertEq(
      vaultController.vaultBorrowingPower(_vaultId),
      _borrowingPowerWethUni + _borrowingPowerWbtc
        - vaultController.getBorrowingFee(uint192(_borrowingPowerWethUni + _borrowingPowerWbtc))
    );
  }
}

contract UnitVaultControllerCalculateInterest is VaultBase, ExponentialNoError {
  event InterestEvent(uint64 _epoch, uint192 _amount, uint256 _curveVal);

  uint256 internal _protocolFee = 100_000_000_000_000;

  function setUp() public virtual override {
    super.setUp();
    vm.prank(vaultOwner);
    vaultController.borrowUSDA(_vaultId, _borrowAmount);
  }

  function testCalculateInterestZero() public {
    assertEq(vaultController.calculateInterest(), 0);
  }

  function testCallExternalCalls() public {
    _borrowAmount = _borrowAmount + vaultController.getBorrowingFee(uint192(_borrowAmount));
    vm.warp(block.timestamp + 1);
    uint256 _curveValue = uint256(curveMaster.getValueAt(address(0x00), 0));
    uint192 _e18FactorIncrease =
      _safeu192(_truncate(_truncate((1 ether * _curveValue) / (365 days + 6 hours)) * 1 ether));
    uint192 _newIF = 1 ether + _e18FactorIncrease;
    uint256 _valueBefore = _borrowAmount;
    uint256 _valueAfter = _borrowAmount * _newIF / 1 ether;
    uint192 _protocolAmount = _safeu192(_truncate(uint256(_valueAfter - _valueBefore) * _protocolFee));
    uint256 _donate = _valueAfter - _valueBefore - _protocolAmount;

    vm.expectCall(address(usdaToken), abi.encodeWithSelector(IUSDA.vaultControllerDonate.selector, _donate));
    vm.expectCall(
      address(usdaToken), abi.encodeWithSelector(IUSDA.vaultControllerMint.selector, governance, _protocolAmount)
    );
    vm.expectEmit(true, true, true, true);
    emit InterestEvent(uint64(block.timestamp), _e18FactorIncrease, _curveValue);

    vaultController.calculateInterest();
  }
}

contract UnitVaultControllerVaultSummaries is VaultBase, ExponentialNoError {
  function testVaultSummaries() public {
    IVaultController.VaultSummary[] memory _summary = vaultController.vaultSummaries(1, 1);

    uint256 _borrowPowerWithoutDiscount0 =
      _safeu192(_truncate(_truncate(_safeu192(anchoredViewEth.currentValue() * _vaultDeposit * WETH_LTV))));
    assertEq(_summary.length, 1);
    assertEq(_summary[0].id, _vaultId);
    assertEq(_summary[0].borrowingPower, _borrowPowerWithoutDiscount0);
    assertEq(_summary[0].vaultLiability, vaultController.vaultLiability(_vaultId));
    assertEq(_summary[0].tokenAddresses[0], WETH_ADDRESS);
    assertEq(_summary[0].tokenBalances[0], _vaultDeposit);
  }

  function testVaultSummariesAll() public {
    IVaultController.VaultSummary[] memory _summary = vaultController.vaultSummaries(1, 3);
    assertEq(_summary.length, 3);

    uint256 _borrowPowerWithoutDiscount0 =
      _safeu192(_truncate(_truncate(_safeu192(anchoredViewEth.currentValue() * _vaultDeposit * WETH_LTV))));
    assertEq(_summary[0].id, _vaultId);
    assertEq(_summary[0].borrowingPower, _borrowPowerWithoutDiscount0);
    assertEq(_summary[0].vaultLiability, vaultController.vaultLiability(_vaultId));
    assertEq(_summary[0].tokenAddresses[0], WETH_ADDRESS);
    assertEq(_summary[0].tokenBalances[0], _vaultDeposit);

    uint256 _borrowPowerWithoutDiscount1 =
      _safeu192(_truncate(_truncate(_safeu192(anchoredViewEth.currentValue() * (_vaultDeposit * 2) * WETH_LTV))));
    assertEq(_summary[1].id, _vaultId2);
    assertEq(_summary[1].borrowingPower, _borrowPowerWithoutDiscount1);
    assertEq(_summary[1].vaultLiability, vaultController.vaultLiability(_vaultId2));
    assertEq(_summary[1].tokenAddresses[0], WETH_ADDRESS);
    assertEq(_summary[1].tokenBalances[0], _vaultDeposit * 2);

    uint256 _borrowPowerWithoutDiscount2 =
      _safeu192(_truncate(_truncate((wbtcPrice * 10 ** 10 * _wbtcDeposit * OTHER_LTV))));
    assertEq(_summary[2].id, _vaultIdWbtc);
    assertEq(_summary[2].borrowingPower, _borrowPowerWithoutDiscount2);
    assertEq(_summary[2].vaultLiability, vaultController.vaultLiability(_vaultIdWbtc));
    assertEq(_summary[2].tokenAddresses[1], WBTC_ADDRESS);
    assertEq(_summary[2].tokenBalances[1], _wbtcDeposit);
  }

  function testVaultSummariesBigEnd() public {
    IVaultController.VaultSummary[] memory _summary = vaultController.vaultSummaries(1, 1_000_000);
    assertEq(_summary.length, 3);

    uint256 _borrowPowerWithoutDiscount0 =
      _safeu192(_truncate(_truncate(_safeu192(anchoredViewEth.currentValue() * _vaultDeposit * WETH_LTV))));
    assertEq(_summary[0].id, _vaultId);
    assertEq(_summary[0].borrowingPower, _borrowPowerWithoutDiscount0);
    assertEq(_summary[0].vaultLiability, vaultController.vaultLiability(_vaultId));
    assertEq(_summary[0].tokenAddresses[0], WETH_ADDRESS);
    assertEq(_summary[0].tokenBalances[0], _vaultDeposit);

    uint256 _borrowPowerWithoutDiscount1 =
      _safeu192(_truncate(_truncate(_safeu192(anchoredViewEth.currentValue() * (_vaultDeposit * 2) * WETH_LTV))));
    assertEq(_summary[1].id, _vaultId2);
    assertEq(_summary[1].borrowingPower, _borrowPowerWithoutDiscount1);
    assertEq(_summary[1].vaultLiability, vaultController.vaultLiability(_vaultId2));
    assertEq(_summary[1].tokenAddresses[0], WETH_ADDRESS);
    assertEq(_summary[1].tokenBalances[0], _vaultDeposit * 2);

    uint256 _borrowPowerWithoutDiscount2 =
      _safeu192(_truncate(_truncate((wbtcPrice * 10 ** 10 * _wbtcDeposit * OTHER_LTV))));
    assertEq(_summary[2].id, _vaultIdWbtc);
    assertEq(_summary[2].borrowingPower, _borrowPowerWithoutDiscount2);
    assertEq(_summary[2].vaultLiability, vaultController.vaultLiability(_vaultIdWbtc));
    assertEq(_summary[2].tokenAddresses[1], WBTC_ADDRESS);
    assertEq(_summary[2].tokenBalances[1], _wbtcDeposit);
  }
}

contract UnitVaultControllerEnabledTokens is Base {
  address[] public arrayOfTokens = [address(1), address(2), address(3), address(4)];
  uint256[] public arrayOfLtv = [WETH_LTV, UNI_LTV, WBTC_LTV, OTHER_LTV];
  address[] public arrayOfOracles = [address(5), address(6), address(7), address(8)];

  function setUp() public virtual override {
    super.setUp();

    for (uint256 _i; _i < arrayOfTokens.length; _i++) {
      vm.mockCall(
        address(arrayOfTokens[_i]), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18))
      );
    }

    // register a few tokens
    vm.startPrank(governance);
    for (uint256 _i = 0; _i < arrayOfTokens.length; _i++) {
      vaultController.registerErc20(
        arrayOfTokens[_i], arrayOfLtv[_i], arrayOfOracles[_i], LIQUIDATION_INCENTIVE, type(uint256).max, 0
      );
    }
    vm.stopPrank();
  }

  function testEnabledTokens() public {
    address[] memory _enabledTokens = vaultController.getEnabledTokens();
    assertEq(arrayOfTokens.length, _enabledTokens.length);
    assertEq(arrayOfTokens, _enabledTokens);

    for (uint256 _i = 0; _i < arrayOfTokens.length; _i++) {
      assertEq(arrayOfTokens[_i], vaultController.enabledTokens(_i));
    }
  }

  function testGetCollateralsInfoWith5Items() public {
    IVaultController.CollateralInfo[] memory _collateralsInfo =
      vaultController.getCollateralsInfo(0, arrayOfTokens.length + 1);
    assertEq(_collateralsInfo.length, arrayOfTokens.length);

    for (uint256 _i = 0; _i < _collateralsInfo.length; _i++) {
      assertEq(_collateralsInfo[_i].ltv, arrayOfLtv[_i]);
      assertEq(_collateralsInfo[_i].liquidationIncentive, LIQUIDATION_INCENTIVE);
      assertEq(address(_collateralsInfo[_i].oracle), arrayOfOracles[_i]);
    }
  }

  function testGetCollateralsInfoWith2Items() public {
    IVaultController.CollateralInfo[] memory _collateralsInfo = vaultController.getCollateralsInfo(0, 3);
    assertEq(_collateralsInfo.length, 3);

    for (uint256 _i = 0; _i < _collateralsInfo.length; _i++) {
      assertEq(_collateralsInfo[_i].ltv, arrayOfLtv[_i]);
      assertEq(_collateralsInfo[_i].liquidationIncentive, LIQUIDATION_INCENTIVE);
      assertEq(address(_collateralsInfo[_i].oracle), arrayOfOracles[_i]);
    }
  }
}
