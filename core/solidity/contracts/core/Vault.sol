// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IUSDA} from '@interfaces/core/IUSDA.sol';
import {IVault} from '@interfaces/core/IVault.sol';
import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IAMPHClaimer} from '@interfaces/core/IAMPHClaimer.sol';
import {IBooster} from '@interfaces/utils/IBooster.sol';
import {IBaseRewardPool} from '@interfaces/utils/IBaseRewardPool.sol';
import {IVirtualBalanceRewardPool} from '@interfaces/utils/IVirtualBalanceRewardPool.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Context} from '@openzeppelin/contracts/utils/Context.sol';
import {SafeERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import {ICVX} from '@interfaces/utils/ICVX.sol';

/// @notice Vault contract, our implementation of maker-vault like vault
/// @dev Major differences:
/// 1. multi-collateral
/// 2. generate interest in USDA
contract Vault is IVault, Context {
  using SafeERC20Upgradeable for IERC20;

  /// @dev The CVX token
  ICVX public immutable CVX;

  /// @dev The CRV token
  IERC20 public immutable CRV;

  /// @dev The vault controller
  IVaultController public immutable CONTROLLER;

  /// @dev Metadata of vault, aka the id & the minter's address
  VaultInfo public vaultInfo;

  /// @dev This is the unscaled liability of the vault.
  /// The number is meaningless on its own, and must be combined with the factor taken from
  /// the vaultController in order to find the true liabilitiy
  uint256 public baseLiability;

  /// @dev Keeps track of the accounting of the collateral deposited
  mapping(address => uint256) public balances;

  /// @dev Keeps track of the tokens that are staked on convex
  mapping(address => bool) public isTokenStaked;

  /// @notice Checks if _msgSender is the controller of the vault
  modifier onlyVaultController() {
    if (_msgSender() != address(CONTROLLER)) revert Vault_NotVaultController();
    _;
  }

  /// @notice Checks if _msgSender is the minter of the vault
  modifier onlyMinter() {
    if (_msgSender() != vaultInfo.minter) revert Vault_NotMinter();
    _;
  }

  /// @dev Must be called by VaultController, else it will not be registered as a vault in system
  /// @param _id Unique id of the vault, ever increasing and tracked by VaultController
  /// @param _minter Address of the person who created this vault
  /// @param _controllerAddress Address of the VaultController
  /// @param _cvx Address of CVX token
  /// @param _crv Address of CRV token
  constructor(uint96 _id, address _minter, address _controllerAddress, IERC20 _cvx, IERC20 _crv) {
    vaultInfo = VaultInfo(_id, _minter);
    CONTROLLER = IVaultController(_controllerAddress);
    CVX = ICVX(address(_cvx));
    CRV = _crv;
  }

  /// @notice Returns the minter of the vault
  /// @return _minter The address of minter
  function minter() external view override returns (address _minter) {
    _minter = vaultInfo.minter;
  }

  /// @notice Returns the id of the vault
  /// @return _id The id of the vault
  function id() external view override returns (uint96 _id) {
    _id = vaultInfo.id;
  }

  /// @notice Used to deposit a token to the vault
  /// @dev    Deposits and stakes on convex if token is of type CurveLPStakedOnConvex
  /// @param _token The address of the token to deposit
  /// @param _amount The amount of the token to deposit
  function depositERC20(address _token, uint256 _amount) external override onlyMinter {
    if (CONTROLLER.tokenId(_token) == 0) revert Vault_TokenNotRegistered();
    if (_amount == 0) revert Vault_AmountZero();
    SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), _msgSender(), address(this), _amount);
    if (CONTROLLER.tokenCollateralType(_token) == IVaultController.CollateralType.CurveLPStakedOnConvex) {
      uint256 _poolId = CONTROLLER.tokenPoolId(_token);
      /// If it's type CurveLPStakedOnConvex then pool id can't be 0
      IBooster _booster = CONTROLLER.BOOSTER();
      if (isTokenStaked[_token]) {
        /// In this case the user's balance is already staked so we only stake the newly deposited amount
        _depositAndStakeOnConvex(_token, _booster, _amount, _poolId);
      } else {
        /// In this case the user's balance isn't staked so we stake the amount + his balance for the specific tokenv
        isTokenStaked[_token] = true;
        _depositAndStakeOnConvex(_token, _booster, balances[_token] + _amount, _poolId);
      }
    }
    balances[_token] += _amount;
    CONTROLLER.modifyTotalDeposited(vaultInfo.id, _amount, _token, true);
    emit Deposit(_token, _amount);
  }

  /// @notice Withdraws an erc20 token from the vault
  /// @dev    This can only be called by the minter
  ///         The withdraw will be denied if ones vault would become insolvent
  ///         If the withdraw token is of CurveLPStakedOnConvex then unstake and withdraw directly to user
  /// @param _tokenAddress The address of erc20 token
  /// @param _amount The amount of erc20 token to withdraw
  function withdrawERC20(address _tokenAddress, uint256 _amount) external override onlyMinter {
    if (CONTROLLER.tokenId(_tokenAddress) == 0) revert Vault_TokenNotRegistered();
    if (isTokenStaked[_tokenAddress]) {
      if (!CONTROLLER.tokenCrvRewardsContract(_tokenAddress).withdrawAndUnwrap(_amount, false)) {
        revert Vault_WithdrawAndUnstakeOnConvexFailed();
      }
    }
    // reduce balance
    balances[_tokenAddress] -= _amount;
    // check if the account is solvent
    if (!CONTROLLER.checkVault(vaultInfo.id)) revert Vault_OverWithdrawal();
    // transfer the token to the owner
    SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(_tokenAddress), _msgSender(), _amount);
    // modify total deposited
    CONTROLLER.modifyTotalDeposited(vaultInfo.id, _amount, _tokenAddress, false);
    emit Withdraw(_tokenAddress, _amount);
  }

  /// @notice Let's the user manually stake their crvLP
  /// @dev    This can be called if the convex pool didn't exist when the token was registered
  ///         and was later updated
  /// @param _tokenAddress The address of erc20 crvLP token
  function stakeCrvLPCollateral(address _tokenAddress) external override onlyMinter {
    uint256 _poolId = CONTROLLER.tokenPoolId(_tokenAddress);
    if (_poolId == 0) revert Vault_TokenCanNotBeStaked();
    if (balances[_tokenAddress] == 0) revert Vault_TokenZeroBalance();
    if (isTokenStaked[_tokenAddress]) revert Vault_TokenAlreadyStaked();

    isTokenStaked[_tokenAddress] = true;

    IBooster _booster = CONTROLLER.BOOSTER();
    _depositAndStakeOnConvex(_tokenAddress, _booster, balances[_tokenAddress], _poolId);

    emit Staked(_tokenAddress, balances[_tokenAddress]);
  }

  /// @notice Returns true when user can manually stake their token balance
  /// @param _token The address of the token to check
  /// @return _canStake Returns true if the token can be staked manually
  function canStake(address _token) external view override returns (bool _canStake) {
    uint256 _poolId = CONTROLLER.tokenPoolId(_token);
    if (_poolId != 0 && balances[_token] != 0 && !isTokenStaked[_token]) _canStake = true;
  }

  /// @notice Claims available rewards from multiple tokens
  /// @dev    Transfers a percentage of the crv and cvx rewards to claim AMPH tokens
  /// @param _tokenAddresses The addresses of the erc20 tokens
  function claimRewards(address[] memory _tokenAddresses) external override onlyMinter {
    uint256 _totalCrvReward;
    uint256 _totalCvxReward;

    IAMPHClaimer _amphClaimer = CONTROLLER.claimerContract();
    for (uint256 _i; _i < _tokenAddresses.length;) {
      IVaultController.CollateralInfo memory _collateralInfo = CONTROLLER.tokenCollateralInfo(_tokenAddresses[_i]);
      if (_collateralInfo.tokenId == 0) revert Vault_TokenNotRegistered();
      if (_collateralInfo.collateralType != IVaultController.CollateralType.CurveLPStakedOnConvex) {
        revert Vault_TokenNotCurveLP();
      }

      IBaseRewardPool _rewardsContract = _collateralInfo.crvRewardsContract;
      uint256 _crvReward = _rewardsContract.earned(address(this));

      if (_crvReward != 0) {
        // Claim the CRV reward
        _totalCrvReward += _crvReward;
        _rewardsContract.getReward(address(this), false);
        _totalCvxReward += _calculateCVXReward(_crvReward);
      }

      // Loop and claim all virtual rewards
      uint256 _extraRewards = _rewardsContract.extraRewardsLength();
      for (uint256 _j; _j < _extraRewards;) {
        IVirtualBalanceRewardPool _virtualReward = _rewardsContract.extraRewards(_j);
        IERC20 _rewardToken = _virtualReward.rewardToken();
        uint256 _earnedReward = _virtualReward.earned(address(this));
        if (_earnedReward != 0) {
          _virtualReward.getReward();
          _rewardToken.transfer(_msgSender(), _earnedReward);
          emit ClaimedReward(address(_rewardToken), _earnedReward);
        }
        unchecked {
          ++_j;
        }
      }
      unchecked {
        ++_i;
      }
    }

    if (_totalCrvReward > 0 || _totalCvxReward > 0) {
      if (address(_amphClaimer) != address(0)) {
        // Approve amounts for it to be taken
        (uint256 _takenCVX, uint256 _takenCRV, uint256 _claimableAmph) =
          _amphClaimer.claimable(address(this), this.id(), _totalCvxReward, _totalCrvReward);
        if (_claimableAmph != 0) {
          CRV.approve(address(_amphClaimer), _takenCRV);
          CVX.approve(address(_amphClaimer), _takenCVX);

          // Claim AMPH tokens depending on how much CRV and CVX was claimed
          _amphClaimer.claimAmph(this.id(), _totalCvxReward, _totalCrvReward, _msgSender());

          _totalCvxReward -= _takenCVX;
          _totalCrvReward -= _takenCRV;
        }
      }

      if (_totalCvxReward > 0) CVX.transfer(_msgSender(), _totalCvxReward);
      if (_totalCrvReward > 0) CRV.transfer(_msgSender(), _totalCrvReward);

      emit ClaimedReward(address(CRV), _totalCrvReward);
      emit ClaimedReward(address(CVX), _totalCvxReward);
    }
  }

  /// @notice Returns an array of all the available rewards the user can claim
  /// @param _tokenAddress The address of the token collateral to check rewards for
  /// @return _rewards The array of all the available rewards
  function claimableRewards(address _tokenAddress) external view override returns (Reward[] memory _rewards) {
    if (CONTROLLER.tokenId(_tokenAddress) == 0) revert Vault_TokenNotRegistered();
    if (CONTROLLER.tokenCollateralType(_tokenAddress) != IVaultController.CollateralType.CurveLPStakedOnConvex) {
      revert Vault_TokenNotCurveLP();
    }

    IBaseRewardPool _rewardsContract = CONTROLLER.tokenCrvRewardsContract(_tokenAddress);
    IAMPHClaimer _amphClaimer = CONTROLLER.claimerContract();

    uint256 _rewardsAmount = _rewardsContract.extraRewardsLength();

    uint256 _crvReward = _rewardsContract.earned(address(this));
    uint256 _cvxReward = _calculateCVXReward(_crvReward);

    // +3 for CRV, CVX and AMPH
    _rewards = new Reward[](_rewardsAmount+3);
    _rewards[0] = Reward(CRV, _crvReward);
    _rewards[1] = Reward(CVX, _cvxReward);

    uint256 _i;
    for (_i; _i < _rewardsAmount;) {
      IVirtualBalanceRewardPool _virtualReward = _rewardsContract.extraRewards(_i);
      IERC20 _rewardToken = _virtualReward.rewardToken();
      uint256 _earnedReward = _virtualReward.earned(address(this));
      _rewards[_i + 2] = Reward(_rewardToken, _earnedReward);

      unchecked {
        ++_i;
      }
    }

    uint256 _takenCVX;
    uint256 _takenCRV;
    uint256 _claimableAmph;
    // if claimer is not set, nothing will happen (and variables are already in zero)
    if (address(_amphClaimer) != address(0)) {
      // claimer is set, proceed
      (_takenCVX, _takenCRV, _claimableAmph) = _amphClaimer.claimable(address(this), this.id(), _cvxReward, _crvReward);
      _rewards[_i + 2] = Reward(_amphClaimer.AMPH(), _claimableAmph);
    }

    _rewards[0].amount = _crvReward - _takenCRV;
    if (_cvxReward > 0) _rewards[1].amount = _cvxReward - _takenCVX;
  }

  /// @notice Function used by the VaultController to transfer tokens
  /// @dev Callable by the VaultController only
  /// @param _token The token to transfer
  /// @param _to The address to send the tokens to
  /// @param _amount The amount of tokens to move
  function controllerTransfer(address _token, address _to, uint256 _amount) external override onlyVaultController {
    SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(_token), _to, _amount);
    balances[_token] -= _amount;
  }

  /// @notice Function used by the VaultController to withdraw from convex
  /// @dev Callable by the VaultController only
  /// @param _rewardPool The pool to withdraw
  /// @param _amount The amount of tokens to withdraw
  function controllerWithdrawAndUnwrap(
    IBaseRewardPool _rewardPool,
    uint256 _amount
  ) external override onlyVaultController {
    if (!_rewardPool.withdrawAndUnwrap(_amount, false)) revert Vault_WithdrawAndUnstakeOnConvexFailed();
  }

  /// @notice Function used by the VaultController to reduce a vault's liability
  /// @dev Callable by the VaultController only
  /// @param _increase True to increase, false to decrease
  /// @param _baseAmount The change in base liability
  /// @return _newLiability The new liability
  function modifyLiability(
    bool _increase,
    uint256 _baseAmount
  ) external override onlyVaultController returns (uint256 _newLiability) {
    if (_increase) {
      baseLiability += _baseAmount;
    } else {
      // require statement only valid for repayment
      if (baseLiability < _baseAmount) revert Vault_RepayTooMuch();
      baseLiability -= _baseAmount;
    }
    _newLiability = baseLiability;
  }

  /// @dev Internal function for depositing and staking on convex
  function _depositAndStakeOnConvex(address _token, IBooster _booster, uint256 _amount, uint256 _poolId) internal {
    IERC20(_token).approve(address(_booster), _amount);
    if (!_booster.deposit(_poolId, _amount, true)) revert Vault_DepositAndStakeOnConvexFailed();
  }

  /// @notice Used to calculate the CVX reward for a given CRV amount
  /// @dev This is copied from the CVX mint function
  /// @param _crv The amount of CRV to calculate the CVX reward for
  /// @return _cvxAmount The amount of CVX to get
  function _calculateCVXReward(uint256 _crv) internal view returns (uint256 _cvxAmount) {
    uint256 _supply = CVX.totalSupply();
    uint256 _totalCliffs = CVX.totalCliffs();

    //use current supply to gauge cliff
    //this will cause a bit of overflow into the next cliff range
    //but should be within reasonable levels.
    //requires a max supply check though
    uint256 _cliff = _supply / CVX.reductionPerCliff();
    //mint if below total cliffs
    if (_cliff < _totalCliffs) {
      //for reduction% take inverse of current cliff
      uint256 _reduction = _totalCliffs - _cliff;
      //reduce
      _cvxAmount = (_crv * _reduction) / _totalCliffs;

      //supply cap check
      uint256 _amtTillMax = CVX.maxSupply() - _supply;
      if (_cvxAmount > _amtTillMax) _cvxAmount = _amtTillMax;
    }
  }
}
