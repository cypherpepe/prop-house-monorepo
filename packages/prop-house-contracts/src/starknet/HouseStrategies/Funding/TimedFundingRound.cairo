# SPDX-License-Identifier: GPL-3.0

%lang starknet

# Standard Library
from starkware.starknet.common.syscalls import get_caller_address, get_block_timestamp
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_lt, uint256_le, uint256_eq
from starkware.cairo.common.cairo_keccak.keccak import finalize_keccak
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import (
    assert_lt,
    assert_le,
    assert_nn,
    assert_nn_le,
    assert_not_zero,
)

# External Libraries
from openzeppelin.security.safemath.library import SafeUint256

# Interfaces
from src.starknet.Interfaces.IVotingStrategy import IVotingStrategy
from src.starknet.Interfaces.IExecutionStrategy import IExecutionStrategy
from src.starknet.Interfaces.IVotingStrategyRegistry import IVotingStrategyRegistry

# Types
from src.starknet.lib.general_address import Address
from src.starknet.lib.proposal_info import ProposalInfo
from src.starknet.lib.proposal_vote import ProposalVote
from src.starknet.lib.round_state import RoundState

# Libraries
from src.starknet.lib.array_2d import Array2D, Immutable2DArray
from src.starknet.lib.merkle_tree import MerkleTree
from src.starknet.lib.proposal_utils import ProposalUtils
from src.starknet.lib.math_utils import MathUtils

#
# Constants
#

const MAX_WINNERS = 256

const MAX_LOG_N_WINNERS = 8

const VOTING_STRATEGY_REGISTRY = 0x0031bb43c3d12c51a5f4b56595297ce960902cf5be91660f4ec6d6b676e2aa5a

const ETH_TX_AUTH_STRATEGY = 0x0042e5c568c94d100b3ebd4131e85bee11c8d678a2ea34b63c855b154e717b03

const ETH_SIG_AUTH_STRATEGY = 0x7de0e01d32c750081ca7f267532cc38e2ca3ab490359a077c322c3e9f4cb6bd2

#
# Storage
#

@storage_var
func round_id_store() -> (id : felt):
end

@storage_var
func round_state_store() -> (state : felt):
end

@storage_var
func proposal_period_start_timestamp_store() -> (timestamp : felt):
end

@storage_var
func proposal_period_end_timestamp_store() -> (timestamp : felt):
end

@storage_var
func vote_period_end_timestamp_store() -> (timestamp : felt):
end

@storage_var
func winner_count_store() -> (count : felt):
end

@storage_var
func next_proposal_nonce_store() -> (nonce : felt):
end

@storage_var
func proposal_vote_power_store(proposal_id : felt) -> (power : Uint256):
end

@storage_var
func spent_voting_power_store(voter_address : Address) -> (power : Uint256):
end

@storage_var
func proposer_address_registry_store(proposal_id : felt) -> (proposer_address : Address):
end

@storage_var
func cancelled_proposals_store(proposal_id : felt) -> (cancelled : felt):
end

@storage_var
func voting_strategy_hashes_store(index : felt) -> (strategy_hash : felt):
end

@storage_var
func execution_strategy_store() -> (execution_strategy_address : felt):
end

#
# Events
#

@event
func proposal_created(
    proposal_id : felt,
    proposer_address : Address,
    metadata_uri_len : felt,
    metadata_uri : felt*,
):
end

@event
func vote_created(proposal_id : felt, voter_address : Address, voting_power : Uint256):
end

#
# Constructor
#

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    house_strategy_params_len : felt,
    house_strategy_params : felt*,
    voting_strategy_hashes_len : felt,
    voting_strategy_hashes : felt*,
    execution_strategies_len : felt,
    execution_strategies : felt*,
):
    alloc_locals

    let (
        round_id,
        proposal_period_start_timestamp,
        proposal_period_duration,
        vote_period_duration,
        winner_count,
    ) = decode_param_array(house_strategy_params_len, house_strategy_params)

    # Sanity checks. Message cancellation is required on error.
    let (current_timestamp) = get_block_timestamp()
    with_attr error_message("Invalid constructor parameters"):
        assert_le(current_timestamp, proposal_period_start_timestamp)
        assert_not_zero(round_id)
        assert_not_zero(proposal_period_duration)
        assert_not_zero(vote_period_duration)
        assert_not_zero(winner_count)
        assert_le(winner_count, MAX_WINNERS)

        # This strategy only supports a single execution strategy
        assert execution_strategies_len = 1
    end

    let proposal_period_end_timestamp = proposal_period_start_timestamp + proposal_period_duration
    let vote_period_end_timestamp = proposal_period_end_timestamp + vote_period_duration

    # Initialize the storage variables
    round_id_store.write(round_id)
    proposal_period_start_timestamp_store.write(proposal_period_start_timestamp)
    proposal_period_end_timestamp_store.write(proposal_period_end_timestamp)
    vote_period_end_timestamp_store.write(vote_period_end_timestamp)
    winner_count_store.write(winner_count)
    execution_strategy_store.write(execution_strategies[0])

    unchecked_add_voting_strategy_hashes(
        voting_strategy_hashes_len, voting_strategy_hashes, 0
    )

    # The first proposal in a round will have a proposal ID of 1.
    next_proposal_nonce_store.write(1)

    return ()
end

#
# Business logic
#

# Casts votes on one or more proposals
@external
func cast_votes{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr : felt}(
    voter_address : Address,
    proposal_votes_len : felt,
    proposal_votes : ProposalVote*,
    user_voting_strategy_params_len : felt,
    user_voting_strategy_params : felt*,
) -> ():
    alloc_locals

    # Verify that the caller is the auth strategy contract
    assert_valid_auth_strategy()

    # Verify that the funding round is active
    assert_round_active()

    # The snapshot timestamp is the end of the proposal submission period
    let (snapshot_timestamp) = proposal_period_end_timestamp_store.read()
    let vote_period_start_timestamp = snapshot_timestamp + 1
    let (vote_period_end_timestamp) = vote_period_end_timestamp_store.read()

    let (current_timestamp) = get_block_timestamp()

    # Ensure the round is still open for voting
    with_attr error_message("Vote period has ended"):
        assert_lt(current_timestamp, vote_period_end_timestamp)
    end

    # Ensure the vote period has started
    with_attr error_message("Vote period has not started yet"):
        assert_le(vote_period_start_timestamp, current_timestamp)
    end

    let (user_voting_power) = get_user_voting_power(
        snapshot_timestamp,
        voter_address,
        user_voting_strategy_params_len,
        user_voting_strategy_params,
    )
    let (no_voting_power) = uint256_eq(Uint256(0, 0), user_voting_power)

    with_attr error_message("No voting power for user"):
        assert no_voting_power = FALSE
    end

    let (spent_voting_power) = spent_voting_power_store.read(voter_address)
    let (remaining_voting_power) = SafeUint256.sub_le(user_voting_power, spent_voting_power)

    # Cast votes on each of the provided proposals
    cast_proposal_votes(
        voter_address,
        snapshot_timestamp,
        0,
        proposal_votes_len,
        proposal_votes,
        user_voting_power,
        remaining_voting_power,
    )
    return ()
end

# Recursively casts votes on each proposal in the `proposal_votes` array
func cast_proposal_votes{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr : felt}(
    voter_address : Address,
    snapshot_timestamp : felt,
    current_index : felt,
    proposal_votes_len : felt,
    proposal_votes : ProposalVote*,
    user_voting_power_total : Uint256,
    user_voting_power_remaining : Uint256,
) -> ():
    alloc_locals

    if (current_index) == (proposal_votes_len):
        return ()
    end

    let proposal_vote = proposal_votes[current_index]

    let (proposer_address) = proposer_address_registry_store.read(proposal_votes.proposal_id)
    with_attr error_message("Proposal does not exist"):
        assert_not_zero(proposer_address.value)
    end

    let (has_been_cancelled) = cancelled_proposals_store.read(proposal_vote.proposal_id)

    # Make sure proposal has not been cancelled
    with_attr error_message("Proposal has been cancelled"):
        assert has_been_cancelled = FALSE
    end

    let (no_proposal_voting_power) = uint256_eq(Uint256(0, 0), proposal_vote.voting_power)

    # Make sure provided voting power is greater than zero
    with_attr error_message("Voting power must be greater than zero"):
        assert no_proposal_voting_power = FALSE
    end

    let (has_enough_voting_power) = uint256_le(proposal_vote.voting_power, user_voting_power_remaining)

    with_attr error_message("Not enough voting power remaining for user"):
        assert has_enough_voting_power = TRUE
    end

    let (previous_proposal_voting_power) = proposal_vote_power_store.read(proposal_vote.proposal_id)
    let (new_proposal_voting_power) = SafeUint256.add(proposal_vote.voting_power, previous_proposal_voting_power)

    let (new_remaining_voting_power) = SafeUint256.sub_le(user_voting_power_remaining, proposal_vote.voting_power)
    let (new_spent_voting_power) = SafeUint256.sub_le(user_voting_power_total, new_remaining_voting_power)

    proposal_vote_power_store.write(proposal_vote.proposal_id, new_proposal_voting_power)
    spent_voting_power_store.write(voter_address, new_spent_voting_power)

    # Emit event
    vote_created.emit(proposal_vote.proposal_id, voter_address, proposal_vote.voting_power)

    return cast_proposal_votes(
        voter_address,
        snapshot_timestamp,
        current_index + 1,
        proposal_votes_len,
        proposal_votes,
        user_voting_power_total,
        new_remaining_voting_power,
    )
end

# Submits a proposal to the funding round
# TODO: Create an L1 handler as a mechanism to bypass the spam protection filter
@external
func propose{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr : felt}(
    proposer_address : Address,
    metadata_uri_string_len : felt,
    metadata_uri_len : felt,
    metadata_uri : felt*,
) -> ():
    alloc_locals

    # Verify that the caller is the auth strategy contract
    assert_valid_auth_strategy()

    # Verify that the funding round is active
    assert_round_active()

    let (current_timestamp) = get_block_timestamp()
    let (proposal_period_start_timestamp) = proposal_period_start_timestamp_store.read()
    let (proposal_period_end_timestamp) = proposal_period_end_timestamp_store.read()

    # Ensure the proposal period period is still open
    with_attr error_message("Proposal period has ended"):
        assert_lt(current_timestamp, proposal_period_end_timestamp)
    end

    # Ensure the proposal period has started
    with_attr error_message("Proposal period has not started yet"):
        assert_le(proposal_period_start_timestamp, current_timestamp)
    end

    let (proposal_id) = next_proposal_nonce_store.read()

    # Store the proposal
    proposer_address_registry_store.write(proposal_id, proposer_address)

    # Emit event
    proposal_created.emit(
        proposal_id,
        proposer_address,
        metadata_uri_len,
        metadata_uri,
    )

    # Increase the proposal nonce
    next_proposal_nonce_store.write(proposal_id + 1)

    return ()
end

# Finalizes the round, counts the proposal votes, and send the corresponding result to the L1 execution strategy contract
@external
func finalize_round{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr : SignatureBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
}():
    alloc_locals

    # Verify that the funding round is active
    assert_round_active()

    let (current_timestamp) = get_block_timestamp()
    let (vote_period_end_timestamp) = vote_period_end_timestamp_store.read()

    # Ensure that voting is complete
    with_attr error_message("Vote period has not ended"):
        assert_lt(vote_period_end_timestamp, current_timestamp)
    end

    let (num_winners) = winner_count_store.read()

    let (next_unused_proposal_nonce) = next_proposal_nonce_store.read()

    # If nonce 1 is unused, no proposals were received
    if next_unused_proposal_nonce == 1:
        return ()
    end

    let (active_submissions : ProposalInfo*) = alloc()
    let (active_submissions_len) = populate_proposal_info_arr(next_unused_proposal_nonce, 1, 0, active_submissions)

    let (winners) = ProposalUtils.select_winners(num_winners, active_submissions_len, active_submissions)
    let (winners_len) = MathUtils.min(num_winners, active_submissions_len)

    let (keccak_ptr : felt*) = alloc()
    let keccak_ptr_start = keccak_ptr

    let (leaves : Uint256*) = alloc()
    ProposalUtils.generate_leaves{keccak_ptr=keccak_ptr}(winners_len, winners, leaves, 0)

    # TODO: Pass in winning assets to this function and validate them against a hash of the awards
    # That way, we only need to store the hash of the awards.
    let (merkle_root) = MerkleTree.get_merkle_root{keccak_ptr=keccak_ptr}(
        winners_len, leaves, 0, MAX_LOG_N_WINNERS,
    )
    finalize_keccak(keccak_ptr_start, keccak_ptr)

    let (round_id)= round_id_store.read()

    let (execution_params : felt*) = alloc()
    assert execution_params[0] = round_id
    assert execution_params[1] = merkle_root.low
    assert execution_params[2] = merkle_root.high

    let (execution_strategy_address) = execution_strategy_store.read()
    let execution_params_len = 3

    IExecutionStrategy.execute(
        contract_address=execution_strategy_address,
        execution_params_len=execution_params_len,
        execution_params=execution_params,
    )

    # Flag the round as having been executed
    round_state_store.write(RoundState.EXECUTED)

    return ()
end

# Cancels the funding round. Only callable by the round initiator.
@external
func cancel_round{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr : SignatureBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
}():
    alloc_locals

    # Verify that the caller is the auth strategy contract
    assert_valid_auth_strategy() # TODO: Add initiator_cancel block in `authenticate` if statement.

    # Verify that the funding round is active
    assert_round_active()

    # TODO: Send message to L1 to unlock funds.

    # Flag the round as having been cancelled
    round_state_store.write(RoundState.CANCELLED)

    return ()
end

# Cancels a proposal. Only callable by the proposal creator.
@external
func cancel_proposal{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr : felt}(
    proposal_id : felt, execution_params_len : felt, execution_params : felt*
):
    alloc_locals

    # Verify that the caller is the auth strategy contract
    assert_valid_auth_strategy() # TODO: Add cancel block in `authenticate` if statement.

    # Verify that the funding round is active
    assert_round_active()

    let (has_been_cancelled) = cancelled_proposals_store.read(proposal_id)

    # Make sure proposal has not already been cancelled
    with_attr error_message("Proposal already cancelled"):
        assert has_been_cancelled = 0
    end

    let (proposer_address) = proposer_address_registry_store.read(proposal_id)
    with_attr error_message("Invalid proposal id"):
        assert_not_zero(proposer_address.value)
    end

    # Flag this proposal as cancelled
    cancelled_proposals_store.write(proposal_id, 1)

    return ()
end

#
# View functions
#

# Fetches proposal information for a specific proposal id
@view
func get_proposal_info{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr : felt
}(proposal_id : felt) -> (proposal_info : ProposalInfo):
    let (proposal_address) = proposer_address_registry_store.read(proposal_id)
    let (voting_power) = proposal_vote_power_store.read(proposal_id)

    return (
        ProposalInfo(proposal_id=proposal_id, proposer_address=proposal_address, voting_power=voting_power),
    )
end

#
#  Internal Functions
#

# Inserts voting strategy hashes to storage
func unchecked_add_voting_strategy_hashes{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(voting_strategy_hashes_len : felt, voting_strategy_hashes : felt*, index : felt):
    if voting_strategy_hashes_len == 0:
        # List is empty
        return ()
    else:
        # Store voting parameter
        voting_strategy_hashes_store.write(index, voting_strategy_hashes[0])

        unchecked_add_voting_strategy_hashes(voting_strategy_hashes_len - 1, &voting_strategy_hashes[1], index + 1)
        return ()
    end
end

func get_auth_strategy(index : felt) -> (strategy_addr: felt):
    let (data_address) = get_label_location(strategies)
    return ([data_address + index])

    strategies:
    dw ETH_TX_AUTH_STRATEGY
    dw ETH_SIG_AUTH_STRATEGY
end

func is_valid_auth_strategy(caller_address : felt, curr_index : felt, num_strategies : felt) -> (is_valid : felt):
    if num_strategies == curr_index:
        return (FALSE)
    end

    let (strategy_addr) = get_auth_strategy(curr_index)
    if caller_address == strategy_addr:
        return (TRUE)
    end
    return is_valid_auth_strategy(caller_address, curr_index + 1, num_strategies)
end

# Throws if the caller address is not a member of the set of whitelisted auth strategies
func assert_valid_auth_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals

    let (caller_address) = get_caller_address()
    let (is_valid) = is_valid_auth_strategy(caller_address, 0, 2)
    with_attr error_message("Invalid auth strategy"):
        assert_not_zero(is_valid)
    end
    return ()
end

# Throws if the round is not in an active state
func assert_round_active{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    ):
    let (round_state) = round_state_store.read()

    # Ensure the round is active
    with_attr error_message("Round not active"):
        assert round_state = RoundState.ACTIVE
    end

    return ()
end

# Computes the voting power of a user.
func get_user_voting_power{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    current_timestamp : felt,
    voter_address : Address,
    user_voting_strategy_params_len : felt,
    user_voting_strategy_params : felt*,
) -> (user_voting_power : Uint256):
    alloc_locals

    # TODO: Support multiple voting strategies
    let (voting_strategy_hash) = voting_strategy_hashes_store.read(0)
    let (voting_strategy, voting_strategy_params_len, voting_strategy_params) = IVotingStrategyRegistry.get_voting_strategy(
        contract_address=VOTING_STRATEGY_REGISTRY,
        strategy_hash=voting_strategy_hash,
    )

    let (user_voting_power) = IVotingStrategy.get_voting_power(
        contract_address=voting_strategy,
        timestamp=current_timestamp,
        voter_address=voter_address,
        params_len=voting_strategy_params_len,
        params=voting_strategy_params,
        user_params_len=user_voting_strategy_params_len,
        user_params=user_voting_strategy_params,
    )
    return (user_voting_power)
end

# Decodes the array of house strategy params
func decode_param_array{range_check_ptr}(strategy_params_len : felt, strategy_params : felt*) -> (
    round_id : felt,
    proposal_period_start_timestamp : felt,
    proposal_period_duration : felt,
    vote_period_duration : felt,
    winner_count : felt,
):
    assert_nn_le(5, strategy_params_len)
    return (
        strategy_params[0],
        strategy_params[1],
        strategy_params[2],
        strategy_params[3],
        strategy_params[4],
    )
end

# Slices the provided proposal info array, returning the portion of it from `start` to `start + size`
func populate_proposal_info_arr{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    next_unused_proposal_nonce : felt,
    current_proposal_id : felt,
    current_index : felt,
    acc: ProposalInfo*,
) -> (proposal_info_len : felt):
    if current_proposal_id == next_unused_proposal_nonce:
        return (current_index + 1)
    end

    let (has_been_cancelled) = cancelled_proposals_store.read(current_proposal_id)
    if has_been_cancelled == TRUE:
        return populate_proposal_info_arr(next_unused_proposal_nonce, current_proposal_id + 1, current_index, acc)
    end

    let (proposer_address) = proposer_address_registry_store.read(current_proposal_id)
    let (voting_power) = proposal_vote_power_store.read(current_proposal_id)

    assert acc[current_index] = ProposalInfo(proposal_id=current_proposal_id, proposer_address=proposer_address,voting_power=voting_power)

    return populate_proposal_info_arr(next_unused_proposal_nonce, current_proposal_id + 1, current_index + 1, acc)
end
