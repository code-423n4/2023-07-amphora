// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IVaultController} from '@interfaces/core/IVaultController.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBaseRewardPool} from '@interfaces/utils/IBaseRewardPool.sol';
import {ICVX} from '@interfaces/utils/ICVX.sol';

/// @title Vault Interface
interface IVault {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/
  /**
   * @notice Emited after depositing a token
   * @param _token The address of the token to deposit
   * @param _amount The amount to deposit
   */

  event Deposit(address _token, uint256 _amount);

  /**
   * @notice Emited after withdrawing a token
   * @param _token The address of the token to withdraw
   * @param _amount The amount to withdraw
   */
  event Withdraw(address _token, uint256 _amount);

  /**
   * @notice Emited when claiming a reward
   * @param _token The address of the token that was claimed
   * @param _amount The amount that was claimed
   */
  event ClaimedReward(address _token, uint256 _amount);

  /**
   * Emited when staking a crvLP token on convex manually
   * @param _token The address of the token to stake
   * @param _amount The amount to stake
   */
  event Staked(address _token, uint256 _amount);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/
  /**
   * @notice Thrown when trying to deposit a token that is not registered
   */
  error Vault_TokenNotRegistered();

  /**
   * @notice Thrown when trying to deposit 0 amount
   */
  error Vault_AmountZero();

  /// @notice Thrown when trying to withdraw more than it's possible
  error Vault_OverWithdrawal();

  /// @notice Thrown when trying to repay more than is needed
  error Vault_RepayTooMuch();

  /// @notice Thrown when _msgSender is not the minter of the vault
  error Vault_NotMinter();

  /// @notice Thrown when _msgSender is not the controller of the vault
  error Vault_NotVaultController();

  /// @notice Thrown when depositing and staking on convex fails
  error Vault_DepositAndStakeOnConvexFailed();

  /// @notice Thrown when trying to withdraw and unstake from convex
  error Vault_WithdrawAndUnstakeOnConvexFailed();

  /// @notice Thrown when trying to claim rewards with a non CurveLPStakedOnConvex token
  error Vault_TokenNotCurveLP();

  /// @notice Thrown when trying to stake with 0 balance
  error Vault_TokenZeroBalance();

  /// @notice Thrown when a crvLP token can not be staked
  error Vault_TokenCanNotBeStaked();

  /// @notice Thrown when a token is already staked and trying to stake again
  error Vault_TokenAlreadyStaked();

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
    //////////////////////////////////////////////////////////////*/
  /// @title VaultInfo struct
  /// @notice this struct is used to store the vault metadata
  /// this should reduce the cost of minting by ~15,000
  /// by limiting us to max 2**96-1 vaults
  struct VaultInfo {
    uint96 id;
    address minter;
  }

  struct Reward {
    IERC20 token;
    uint256 amount;
  }

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns the struct containing the vault information
   * @return _id Id of the vault
   * @return _minter Minter of the vault
   */
  function vaultInfo() external view returns (uint96 _id, address _minter);

  /**
   * @notice Returns the vault's balance of a token
   * @param _token The address of the token
   * @return _balance The token's balance of the vault
   */
  function balances(address _token) external view returns (uint256 _balance);

  /**
   * @notice Returns if the token in staked
   * @param _token The address of the token
   * @return _isStaked True if the token is staked
   */
  function isTokenStaked(address _token) external view returns (bool _isStaked);

  /**
   * @notice Returns the current vault base liability
   * @return _liability The current vault base liability of the vault
   */
  function baseLiability() external view returns (uint256 _liability);

  /**
   * @notice Returns the minter's address of the vault
   * @return _minter The minter's address
   */
  function minter() external view returns (address _minter);

  /**
   * @notice Returns the id of the vault
   * @return _id The id of the vault
   */
  function id() external view returns (uint96 _id);

  /**
   * @notice Returns the vault controller
   * @return _vaultController The vault controller
   */
  function CONTROLLER() external view returns (IVaultController _vaultController);

  /// @notice Returns the CRV token address
  /// @return _crv The CRV token address
  function CRV() external view returns (IERC20 _crv);

  /// @notice Returns the CVX token address
  /// @return _cvx The CVX token address
  function CVX() external view returns (ICVX _cvx);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Used to deposit a token to the vault
   * @param _token The address of the token to deposit
   * @param _amount The amount of the token to deposit
   */
  function depositERC20(address _token, uint256 _amount) external;

  /**
   * @notice Used to withdraw a token from the vault. This can only be called by the minter
   * @dev The withdraw will be denied if ones vault would become insolvent
   * @param _token The address of the token
   * @param _amount The amount of the token to withdraw
   */
  function withdrawERC20(address _token, uint256 _amount) external;

  /// @notice Let's the user manually stake their crvLP
  /// @dev    This can be called if the convex pool didn't exist when the token was registered
  ///         and was later updated
  /// @param _tokenAddress The address of erc20 crvLP token
  function stakeCrvLPCollateral(address _tokenAddress) external;

  /// @notice Returns true when user can manually stake their token balance
  /// @param _token The address of the token to check
  /// @return _canStake Returns true if the token can be staked manually
  function canStake(address _token) external view returns (bool _canStake);

  /// @notice Claims available rewards from multiple tokens
  /// @dev    Transfers a percentage of the crv and cvx rewards to claim AMPH tokens
  /// @param _tokenAddresses The addresses of the erc20 tokens
  function claimRewards(address[] memory _tokenAddresses) external;

  /// @notice Returns an array of tokens and amounts available for claim
  /// @param _tokenAddress The address of erc20 token
  /// @return _rewards The array of tokens and amount available for claim
  function claimableRewards(address _tokenAddress) external view returns (Reward[] memory _rewards);

  /**
   * @notice Function used by the VaultController to transfer tokens
   * @param _token The address of the token to transfer
   * @param _to The address of the person to send the coins to
   * @param _amount The amount of coins to move
   */
  function controllerTransfer(address _token, address _to, uint256 _amount) external;

  /**
   * @notice function used by the VaultController to withdraw from convex
   * callable by the VaultController only
   * @param _rewardPool pool to withdraw
   * @param _amount amount of coins to withdraw
   */
  function controllerWithdrawAndUnwrap(IBaseRewardPool _rewardPool, uint256 _amount) external;

  /**
   * @notice Modifies a vault's liability. Can only be called by VaultController
   * @param _increase True to increase liability, false to decrease
   * @param _baseAmount The change amount in base liability
   * @return _liability The new base liability
   */
  function modifyLiability(bool _increase, uint256 _baseAmount) external returns (uint256 _liability);
}
