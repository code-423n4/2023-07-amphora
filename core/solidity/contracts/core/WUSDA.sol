// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import {IWUSDA} from '@interfaces/core/IWUSDA.sol';

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ERC20, IERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
// solhint-disable-next-line max-line-length
import {ERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol';

/**
 * @title wUSDA (Wrapped usda).
 *
 * @notice A fixed-balance ERC-20 wrapper for the usda rebasing token.
 *
 *      Users deposit usda into this contract and are minted wUSDA.
 *
 *      Each account's wUSDA balance represents the fixed percentage ownership
 *      of usda's market cap.
 *
 *      For exusdae: 100K wUSDA => 1% of the usda market cap
 *        when the usda supply is 100M, 100K wUSDA will be redeemable for 1M usda
 *        when the usda supply is 500M, 100K wUSDA will be redeemable for 5M usda
 *        and so on.
 *
 *      We call wUSDA the 'wrapper' token and usda the 'underlying' or 'wrapped' token.
 */
contract WUSDA is IWUSDA, ERC20, ERC20Permit {
  using SafeERC20 for IERC20;

  //--------------------------------------------------------------------------
  // Constants

  /// @notice The maximum wUSDA supply.
  uint256 public constant MAX_wUSDA_SUPPLY = 10_000_000 * (10 ** 18); // 10 M

  //--------------------------------------------------------------------------
  // Attributes

  /// @notice The reference to the usda token.
  address public immutable USDA;

  //--------------------------------------------------------------------------

  /// @param _usdaToken The usda ERC20 token address.
  /// @param _name The wUSDA ERC20 name.
  /// @param _symbol The wUSDA ERC20 symbol.
  constructor(address _usdaToken, string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC20Permit(_name) {
    USDA = _usdaToken;
  }

  //--------------------------------------------------------------------------
  // wUSDA write methods

  /// @notice Transfers usda amount from {msg.sender} and mints wusda amount.
  ///
  /// @param _wusdaAmount The amount of wusda to mint.
  /// @return _usdaAmount The amount of usda deposited.
  function mint(uint256 _wusdaAmount) external override returns (uint256 _usdaAmount) {
    _usdaAmount = _wUSDAToUSDA(_wusdaAmount, _usdaSupply());
    _deposit(_msgSender(), _msgSender(), _usdaAmount, _wusdaAmount);
  }

  /// @notice Transfers usda amount from {msg.sender} and mints wusda amount,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @param _wusdaAmount The amount of wusda to mint.
  /// @return _usdaAmount The amount of usda deposited.
  function mintFor(address _to, uint256 _wusdaAmount) external override returns (uint256 _usdaAmount) {
    _usdaAmount = _wUSDAToUSDA(_wusdaAmount, _usdaSupply());
    _deposit(_msgSender(), _to, _usdaAmount, _wusdaAmount);
  }

  /// @notice Burns wusda from {msg.sender} and transfers usda amount back.
  ///
  /// @param _wusdaAmount The amount of _wusdaAmount to burn.
  /// @return _usdaAmount The amount of usda withdrawn.
  function burn(uint256 _wusdaAmount) external override returns (uint256 _usdaAmount) {
    _usdaAmount = _wUSDAToUSDA(_wusdaAmount, _usdaSupply());
    _withdraw(_msgSender(), _msgSender(), _usdaAmount, _wusdaAmount);
  }

  /// @notice Burns wusda amount from {msg.sender} and transfers usda amount back,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @param _wusdaAmount The amount of _wusdaAmount to burn.
  /// @return _usdaAmount The amount of _usdaAmount withdrawn.
  function burnTo(address _to, uint256 _wusdaAmount) external override returns (uint256 _usdaAmount) {
    _usdaAmount = _wUSDAToUSDA(_wusdaAmount, _usdaSupply());
    _withdraw(_msgSender(), _to, _usdaAmount, _wusdaAmount);
  }

  /// @notice Burns all wusda from {msg.sender} and transfers usda back.
  ///
  /// @return _usdaAmount The amount of usda withdrawn.
  function burnAll() external override returns (uint256 _usdaAmount) {
    uint256 _wusdaAmount = balanceOf(_msgSender());
    _usdaAmount = _wUSDAToUSDA(_wusdaAmount, _usdaSupply());
    _withdraw(_msgSender(), _msgSender(), _usdaAmount, _wusdaAmount);
  }

  /// @notice Burns all wusda from {msg.sender} and transfers usda back,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @return _usdaAmount The amount of _usdaAmount withdrawn.
  function burnAllTo(address _to) external override returns (uint256 _usdaAmount) {
    uint256 _wusdaAmount = balanceOf(_msgSender());
    _usdaAmount = _wUSDAToUSDA(_wusdaAmount, _usdaSupply());
    _withdraw(_msgSender(), _to, _usdaAmount, _wusdaAmount);
  }

  /// @notice Transfers usda amount from {msg.sender} and mints wusda amount.
  ///
  /// @param _usdaAmount The amount of _usdaAmount to deposit.
  /// @return _wusdaAmount The amount of _wusdaAmount minted.
  function deposit(uint256 _usdaAmount) external override returns (uint256 _wusdaAmount) {
    _wusdaAmount = _usdaToWUSDA(_usdaAmount, _usdaSupply());
    _deposit(_msgSender(), _msgSender(), _usdaAmount, _wusdaAmount);
  }

  /// @notice Transfers usda amount from {msg.sender} and mints wusda amount,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @param _usdaAmount The amount of _usdaAmount to deposit.
  /// @return _wusdaAmount The amount of _wusdaAmount minted.
  function depositFor(address _to, uint256 _usdaAmount) external override returns (uint256 _wusdaAmount) {
    _wusdaAmount = _usdaToWUSDA(_usdaAmount, _usdaSupply());
    _deposit(_msgSender(), _to, _usdaAmount, _wusdaAmount);
  }

  /// @notice Burns wusda amount from {msg.sender} and transfers usda amount back.
  ///
  /// @param _usdaAmount The amount of _usdaAmount to withdraw.
  /// @return _wusdaAmount The amount of burnt _wusdaAmount.
  function withdraw(uint256 _usdaAmount) external override returns (uint256 _wusdaAmount) {
    _wusdaAmount = _usdaToWUSDA(_usdaAmount, _usdaSupply());
    _withdraw(_msgSender(), _msgSender(), _usdaAmount, _wusdaAmount);
  }

  /// @notice Burns wusda amount from {msg.sender} and transfers usda amount back,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @param _usdaAmount The amount of _usdaAmount to withdraw.
  /// @return _wusdaAmount The amount of burnt _wusdaAmount.
  function withdrawTo(address _to, uint256 _usdaAmount) external override returns (uint256 _wusdaAmount) {
    _wusdaAmount = _usdaToWUSDA(_usdaAmount, _usdaSupply());
    _withdraw(_msgSender(), _to, _usdaAmount, _wusdaAmount);
  }

  /// @notice Burns all wusda from {msg.sender} and transfers usda amount back.
  ///
  /// @return _wusdaAmount The amount of burnt.
  function withdrawAll() external override returns (uint256 _wusdaAmount) {
    _wusdaAmount = balanceOf(_msgSender());
    uint256 _usdaAmount = _wUSDAToUSDA(_wusdaAmount, _usdaSupply());
    _withdraw(_msgSender(), _msgSender(), _usdaAmount, _wusdaAmount);
  }

  /// @notice Burns all wusda from {msg.sender} and transfers usda amount back,
  ///         to the specified beneficiary.
  ///
  /// @param _to The beneficiary wallet.
  /// @return _wusdaAmount The amount of burnt.
  function withdrawAllTo(address _to) external override returns (uint256 _wusdaAmount) {
    _wusdaAmount = balanceOf(_msgSender());
    uint256 _usdaAmount = _wUSDAToUSDA(_wusdaAmount, _usdaSupply());
    _withdraw(_msgSender(), _to, _usdaAmount, _wusdaAmount);
  }

  //--------------------------------------------------------------------------
  // wUSDA view methods

  /// @return _usdaAddress The address of the underlying 'wrapped' token ie) usda.
  function underlying() external view override returns (address _usdaAddress) {
    _usdaAddress = USDA;
  }

  /// @return _usdaAmount The total _usdaAmount held by this contract.
  function totalUnderlying() external view override returns (uint256 _usdaAmount) {
    _usdaAmount = _wUSDAToUSDA(totalSupply(), _usdaSupply());
  }

  /// @param _owner The account address.
  /// @return _redeemableUSDA The usda balance redeemable by the owner.
  function balanceOfUnderlying(address _owner) external view override returns (uint256 _redeemableUSDA) {
    _redeemableUSDA = _wUSDAToUSDA(balanceOf(_owner), _usdaSupply());
  }

  /// @param _usdaAmount The amount of usda tokens.
  /// @return _wusdaAmount The amount of wUSDA tokens exchangeable.
  function underlyingToWrapper(uint256 _usdaAmount) external view override returns (uint256 _wusdaAmount) {
    _wusdaAmount = _usdaToWUSDA(_usdaAmount, _usdaSupply());
  }

  /// @param _wusdaAmount The amount of wUSDA tokens.
  /// @return _usdaAmount The amount of usda tokens exchangeable.
  function wrapperToUnderlying(uint256 _wusdaAmount) external view override returns (uint256 _usdaAmount) {
    _usdaAmount = _wUSDAToUSDA(_wusdaAmount, _usdaSupply());
  }

  //--------------------------------------------------------------------------
  // Private methods

  /// @notice Internal helper function to handle deposit state change.
  /// @param _from The initiator wallet.
  /// @param _to The beneficiary wallet.
  /// @param _usdaAmount The amount of _usdaAmount to deposit.
  /// @param _wusdaAmount The amount of _wusdaAmount to mint.
  function _deposit(address _from, address _to, uint256 _usdaAmount, uint256 _wusdaAmount) private {
    IERC20(USDA).safeTransferFrom(_from, address(this), _usdaAmount);
    _mint(_to, _wusdaAmount);

    emit Deposit(_from, _to, _usdaAmount, _wusdaAmount);
  }

  /// @notice Internal helper function to handle withdraw state change.
  /// @param _from The initiator wallet.
  /// @param _to The beneficiary wallet.
  /// @param _usdaAmount The amount of _usdaAmount to withdraw.
  /// @param _wusdaAmount The amount of _wusdaAmount to burn.
  function _withdraw(address _from, address _to, uint256 _usdaAmount, uint256 _wusdaAmount) private {
    _burn(_from, _wusdaAmount);
    IERC20(USDA).safeTransfer(_to, _usdaAmount);

    emit Withdraw(_from, _to, _usdaAmount, _wusdaAmount);
  }

  /// @notice Queries the current total supply of usda.
  /// @return _totalUsdaSupply The current usda supply.
  function _usdaSupply() private view returns (uint256 _totalUsdaSupply) {
    _totalUsdaSupply = IERC20(USDA).totalSupply();
  }

  //--------------------------------------------------------------------------
  // Pure methods

  /// @notice Converts _usdaAmount to wUSDA amount.
  /// @param _usdaAmount The amount of usda tokens.
  /// @param _totalUsdaSupply The total usda supply.
  /// @return _wusdaAmount The amount of wUSDA tokens exchangeable.
  function _usdaToWUSDA(uint256 _usdaAmount, uint256 _totalUsdaSupply) private pure returns (uint256 _wusdaAmount) {
    _wusdaAmount = (_usdaAmount * MAX_wUSDA_SUPPLY) / _totalUsdaSupply;
  }

  /// @notice Converts _wusdaAmount amount to _usdaAmount.
  /// @param _wusdaAmount The amount of wUSDA tokens.
  /// @param _totalUsdaSupply The total usda supply.
  /// @return _usdaAmount The amount of usda tokens exchangeable.
  function _wUSDAToUSDA(uint256 _wusdaAmount, uint256 _totalUsdaSupply) private pure returns (uint256 _usdaAmount) {
    _usdaAmount = (_wusdaAmount * _totalUsdaSupply) / MAX_wUSDA_SUPPLY;
  }
}
