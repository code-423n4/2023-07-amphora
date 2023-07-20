// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IWUSDA is IERC20 {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted when a deposit is made
   * @param _from The address which made the deposit
   * @param _to The address which received the deposit
   * @param _usdaAmount The amount sent, denominated in the underlying
   * @param _wusdaAmount The amount sent, denominated in the wrapped
   */
  event Deposit(address indexed _from, address indexed _to, uint256 _usdaAmount, uint256 _wusdaAmount);

  /**
   * @notice Emitted when a withdraw is made
   * @param _from The address which made the withdraw
   * @param _to The address which received the withdraw
   * @param _usdaAmount The amount sent, denominated in the underlying
   * @param _wusdaAmount The amount sent, denominated in the wrapped
   */
  event Withdraw(address indexed _from, address indexed _to, uint256 _usdaAmount, uint256 _wusdaAmount);

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
    //////////////////////////////////////////////////////////////*/

  /// @notice The reference to the usda token.
  function USDA() external view returns (address _usda);

  /// @notice The reference to the wrapped token.
  /// @return _usdaAddress The address of the underlying 'wrapped' token ie) usda.
  function underlying() external view returns (address _usdaAddress);

  /// @notice The total amount of underlying held by this contract.
  /// @return _usdaAmount The total _usdaAmount held by this contract.
  function totalUnderlying() external view returns (uint256 _usdaAmount);

  /// @param _owner The account address.
  /// @return _redeemableUSDA The usda balance redeemable by the owner.
  function balanceOfUnderlying(address _owner) external view returns (uint256 _redeemableUSDA);

  /// @param _usdaAmount The amount of usda tokens.
  /// @return _wusdaAmount The amount of wUSDA tokens exchangeable.
  function underlyingToWrapper(uint256 _usdaAmount) external view returns (uint256 _wusdaAmount);

  /// @param _wusdaAmount The amount of wUSDA tokens.
  /// @return _usdaAmount The amount of usda tokens exchangeable.
  function wrapperToUnderlying(uint256 _wusdaAmount) external view returns (uint256 _usdaAmount);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Transfers usda amount from {msg.sender} and mints wusda amount.
  ///
  /// @param _wusdaAmount The amount of wusda to mint.
  /// @return _usdaAmount The amount of usda deposited.
  function mint(uint256 _wusdaAmount) external returns (uint256 _usdaAmount);

  /// @notice Transfers usda amount from {msg.sender} and mints wusda amount,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @param _wusdaAmount The amount of wusda to mint.
  /// @return _usdaAmount The amount of usda deposited.
  function mintFor(address _to, uint256 _wusdaAmount) external returns (uint256 _usdaAmount);

  /// @notice Burns wusda from {msg.sender} and transfers usda amount back.
  ///
  /// @param _wusdaAmount The amount of _wusdaAmount to burn.
  /// @return _usdaAmount The amount of usda withdrawn.
  function burn(uint256 _wusdaAmount) external returns (uint256 _usdaAmount);

  /// @notice Burns wusda amount from {msg.sender} and transfers usda amount back,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @param _wusdaAmount The amount of _wusdaAmount to burn.
  /// @return _usdaAmount The amount of _usdaAmount withdrawn.
  function burnTo(address _to, uint256 _wusdaAmount) external returns (uint256 _usdaAmount);

  /// @notice Burns all wusda from {msg.sender} and transfers usda back.
  ///
  /// @return _usdaAmount The amount of usda withdrawn.
  function burnAll() external returns (uint256 _usdaAmount);

  /// @notice Burns all wusda from {msg.sender} and transfers usda back,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @return _usdaAmount The amount of _usdaAmount withdrawn.
  function burnAllTo(address _to) external returns (uint256 _usdaAmount);

  /// @notice Transfers usda amount from {msg.sender} and mints wusda amount.
  ///
  /// @param _usdaAmount The amount of _usdaAmount to deposit.
  /// @return _wusdaAmount The amount of _wusdaAmount minted.
  function deposit(uint256 _usdaAmount) external returns (uint256 _wusdaAmount);

  /// @notice Transfers usda amount from {msg.sender} and mints wusda amount,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @param _usdaAmount The amount of _usdaAmount to deposit.
  /// @return _wusdaAmount The amount of _wusdaAmount minted.
  function depositFor(address _to, uint256 _usdaAmount) external returns (uint256 _wusdaAmount);

  /// @notice Burns wusda amount from {msg.sender} and transfers usda amount back.
  ///
  /// @param _usdaAmount The amount of _usdaAmount to withdraw.
  /// @return _wusdaAmount The amount of burnt _wusdaAmount.
  function withdraw(uint256 _usdaAmount) external returns (uint256 _wusdaAmount);

  /// @notice Burns wusda amount from {msg.sender} and transfers usda amount back,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @param _usdaAmount The amount of _usdaAmount to withdraw.
  /// @return _wusdaAmount The amount of burnt _wusdaAmount.
  function withdrawTo(address _to, uint256 _usdaAmount) external returns (uint256 _wusdaAmount);

  /// @notice Burns all wusda from {msg.sender} and transfers usda amount back.
  ///
  /// @return _wusdaAmount The amount of burnt.
  function withdrawAll() external returns (uint256 _wusdaAmount);

  /// @notice Burns all wusda from {msg.sender} and transfers usda amount back,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @return _wusdaAmount The amount of burnt.
  function withdrawAllTo(address _to) external returns (uint256 _wusdaAmount);
}
