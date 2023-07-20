// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ChainlinkFeeds} from './ChainlinkFeeds.sol';
import {PoolAddresses} from './PoolAddresses.sol';
import {TokenAddresses} from './TokenAddresses.sol';
import {CurvePools} from './CurvePools.sol';

contract TestConstants is ChainlinkFeeds, PoolAddresses, TokenAddresses, CurvePools {
  // Curve rewards contract addresses
  address public constant USDT_LP_REWARDS_ADDRESS = 0x8B55351ea358e5Eda371575B031ee24F462d503e;
  address public constant GEAR_LP_REWARDS_ADDRESS = 0x502Cc0d946e79CeA4DaafCf21F374C6bce763067;
  address public constant THREE_CRV_LP_REWARDS_ADDRESS = 0x689440f2Ff927E1f24c72F1087E1FAF471eCe1c8;

  // CONVEX BOOSTER
  address public constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

  // VIRTUAL BALANCE REWARD POOL
  address public constant GEAR_LP_VIRTUAL_REWARDS_CONTRACT = 0x3605AF97DFD67A6C73CfC517B9481a2fe4Bf050b;
  address public constant GEAR_VIRTUAL_REWARDS_OPERATOR_CONTRACT = 0x4D3cC2D219bDB74973fB9Fa2F7157E29bcccBa05;

  // STAKED CONTRACT
  address public constant USDT_LP_STAKED_CONTRACT = 0xBC89cd85491d81C6AD2954E6d0362Ee29fCa8F53;
  address public constant THREE_CRV_LP_STAKED_CONTRACT = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;

  // LTV
  uint256 public constant WETH_LTV = 0.85 ether;
  uint256 public constant UNI_LTV = 0.75 ether;
  uint256 public constant AAVE_LTV = 0.75 ether;
  uint256 public constant DYDX_LTV = 0.75 ether;
  uint256 public constant OTHER_LTV = 0.75 ether;
  uint256 public constant WBTC_LTV = 0.8 ether;

  // LIQ INC
  uint256 public constant LIQUIDATION_INCENTIVE = 0.05 ether;

  // CAP
  uint256 public constant AAVE_CAP = 500 ether;
  uint256 public constant DYDX_CAP = 50 ether;

  // MISC
  address public constant SUSD_TOKEN_STATE = 0x05a9CBe762B36632b3594DA4F082340E0e5343e8;
  address public constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
  address public constant UNI_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  address public constant UNI_V3_NFP_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
  address public constant UNI_V3_SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

  // SCRIPTS
  address public constant VAULT_CONTROLLER_ADDRESS = address(0);
  address public constant USDA_ADDRESS = address(0);
}
