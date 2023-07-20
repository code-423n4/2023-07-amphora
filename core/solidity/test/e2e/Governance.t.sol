// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import {CommonE2EBase, IVault, console, GovernorCharlie} from '@test/e2e/Common.sol';
import {IUSDA} from '@interfaces/core/IUSDA.sol';
import {Proposal} from '@contracts/utils/GovernanceStructs.sol';

contract GovernanceImplementationForTest {}

contract E2EGovernance is CommonE2EBase {
  GovernorCharlie public gov;

  function setUp() public override {
    super.setUp();
    gov = GovernorCharlie(address(governor));
  }

  function testVaultControllerOwner() public {
    assertEq(vaultController.owner(), address(governor));
  }

  function testUSDAOwner() public {
    assertEq(usdaToken.owner(), address(governor));
  }

  function testCanDelegateVotes() public {
    uint256 _transferAmount = 80_000 ether;
    vm.prank(frank);
    amphToken.transfer(eric, _transferAmount);

    uint256 _votesBefore = amphToken.getCurrentVotes(eric);
    vm.prank(eric);
    amphToken.delegate(andy);

    assertEq(amphToken.getCurrentVotes(andy), _votesBefore + _transferAmount);
  }

  function testMakeOptimisticProposals() public {
    // Delegate votes to andy
    vm.prank(frank);
    amphToken.transfer(eric, 8_000_000 ether);
    vm.prank(eric);
    amphToken.delegate(andy);

    vm.prank(frank);
    amphToken.delegate(frank);
    vm.roll(block.number + 1);

    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    string[] memory _signatures = new string[](1);
    bytes[] memory _calldatas = new bytes[](1);

    _targets[0] = address(governor);
    _values[0] = 0;
    _signatures[0] = 'setWhitelistAccountExpiration(address,uint256)';
    _calldatas[0] = abi.encode(bob, block.timestamp + gov.maxWhitelistPeriod());
    vm.prank(frank);
    uint256 _proposalId = gov.propose(_targets, _values, _signatures, _calldatas, 'test proposal');
    assertEq(_proposalId, 1);

    vm.roll(block.number + gov.votingDelay() + 1);

    vm.prank(andy);
    gov.castVoteWithReason(_proposalId, 1, 'good proposal');

    vm.prank(frank);
    gov.castVoteWithReason(_proposalId, 1, 'good proposal');

    vm.roll(block.number + gov.votingPeriod());
    vm.prank(andy);
    gov.queue(_proposalId);
    vm.warp(block.timestamp + gov.proposalTimelockDelay());

    vm.prank(andy);
    gov.execute(_proposalId);

    assertTrue(gov.isWhitelisted(bob));

    // Create an optimistic proposal

    _targets[0] = address(governor);
    _values[0] = 0;
    _signatures[0] = 'setWhitelistAccountExpiration(address,uint256)';
    _calldatas[0] = abi.encode(eric, block.timestamp + gov.maxWhitelistPeriod());

    vm.prank(bob);
    _proposalId = gov.proposeEmergency(_targets, _values, _signatures, _calldatas, 'whitelist eric');

    Proposal memory _proposal = gov.getProposal(_proposalId);

    assertEq(_proposal.quorumVotes, gov.optimisticQuorumVotes());
    assertEq(_proposal.startBlock, block.number + gov.optimisticVotingDelay());
    assertEq(_proposal.endBlock, block.number + gov.optimisticVotingDelay() + gov.votingPeriod());
    assertEq(_proposal.delay, gov.proposalTimelockDelay());
  }
}
