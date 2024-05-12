// SPDX-License-Identifier: Apache-2.0

use std::address; use std::tx_context::{self, TxContext}; use sui::coin::{self, Coin}; use sui::object::{self, UID}; use sui::transfer; use sui::vec_map::{self, VecMap}; use sui::balance::{self, Balance}; use sui::sui::SUI;

struct Wallet store key { id: UID, owner: address::Address, name: String, description: String, approval_threshold: u8, cancellation_threshold: u8, sui: Balance, locked_balance: u64, members: VecMap<address::Address, bool>, donation_nft_name: String, donation_nft_description: String, donation_nft_url: String, token_proposals: Vec, nft_proposals: Vec, }

struct Member store key { id: UID, wallet: object::ID, }

const PENDING_STATUS: u8 = 1; const EXECUTED_STATUS: u8 = 2; const CANCELLED_STATUS: u8 = 3;

struct Proposal store { id: UID, creator: address::Address, votes: VecMap<address::Address, bool>, approval_votes: u64, cancellation_votes: u64, status: u8, //1: pending, 2: executed, 3: cancelled }

struct TokenProposal store { proposal: Proposal, to: address::Address, amount: u64, }

struct NFTProposal store { proposal: Proposal, to: address::Address, amount: u64, }

struct Collectible store key { id: UID, name: String, description: String, image_url: String, creator: String, }

module daowallet::DAOWallet { use std::vector; use std::string::{Self, String}; use sui::coin::{Self, Coin}; use sui::object::{Self, UID}; use sui::transfer; use sui::vec_map::{Self, VecMap}; use sui::tx_context::{Self, TxContext}; use sui::balance::{Self, Balance}; use sui::sui::SUI;
public entry fun create_wallet(
    name: vector<u8>,
    description: vector<u8>,
    approval_threshold: u8,
    cancellation_threshold: u8,
    donation_nft_name: vector<u8>,
    donation_nft_description: vector<u8>,
    donation_nft_url: vector<u8>,
    ctx: &mut TxContext
) {
    let creator = tx_context.sender(ctx);
    assert!(name.len() > 0, 1);
    assert!(description.len() > 0, 2);
    assert!(approval_threshold > 0, 3);
    assert!(cancellation_threshold > 0, 4);

    let wallet = Wallet {
        id: object::new(ctx),
        owner: creator,
        name: string::utf8(name),
        description: string::utf8(description),
        approval_threshold,
        cancellation_threshold,
        sui: balance::zero<SUI>(),
        locked_balance: 0,
        members: vec_map::empty(),
        donation_nft_name: string::utf8(donation_nft_name),
        donation_nft_description: string::utf8(donation_nft_description),
        donation_nft_url: string::utf8(donation_nft_url),
        token_proposals: vector::empty(),
        nft_proposals: vector::empty(),
    };

    transfer::transfer(Member {
        id: object::new(ctx),
        wallet: object::id(&wallet),
    }, creator);

    vec_map::insert(&mut wallet.members, creator, true);
    transfer::share_object(wallet);
}

public entry fun add_member(wallet: &mut Wallet, new_member: address::Address, ctx: &mut TxContext) {
    assert!(vec_map::size(&wallet.members) < u32::max_value() as usize, 5);
    vec_map::insert(&mut wallet.members, new_member, true);
    transfer::transfer(Member {
        id: object::new(ctx),
        wallet: object::id(wallet),
    }, new_member);
}

public entry fun donate(wallet: &mut Wallet, sui: Coin<SUI>, ctx: &mut TxContext) {
    assert!(coin::get_balance(&wallet.sui) >= sui, 6);
    coin::put(&mut wallet.sui, sui);

    let nft = Collectible {
        id: object::new(ctx),
        name: wallet.donation_nft_name,
        description: wallet.donation_nft_description,
        image_url: wallet.donation_nft_url,
        creator: wallet.name,
    };

    transfer::transfer(nft, tx_context.sender(ctx));
}

public entry fun create_token_proposal(wallet: &mut Wallet, to: address::Address, amount: u64, ctx: &mut TxContext) {
    assert!(vec_map::contains_key(&wallet.members, &to), 7);
    assert!(amount > 0, 8);
    let token_proposal = TokenProposal {
        proposal: Proposal {
            id: object::new(ctx),
            creator: tx_context.sender(ctx),
            votes: vec_map::empty(),
            approval_votes: 1,
            cancellation_votes: 0,
            status: PENDING_STATUS,
        },
        to,
        amount,
    };
    wallet.locked_balance += amount;
    vec_map::insert(&mut token_proposal.proposal.votes, tx_context.sender(ctx), true);
    vector::push_back(&mut wallet.token_proposals, token_proposal);
}

public entry fun approve_token_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext) {
    assert!(proposal_id < vector::length(&wallet.token_proposals), 9);
    let token_proposal = vector::borrow_mut(&mut wallet.token_proposals, proposal_id);

    let proposal = &mut token_proposal.proposal;
    let sender = tx_context.sender(ctx);
    assert!(vec_map::contains_key(&proposal.votes, &sender), 10);
    proposal.approval_votes += 1;
    vec_map::insert(&mut proposal.votes, sender, true);

    let total_members = vec_map::size(&wallet.members);
    if 100 * proposal.approval_votes / total_members > wallet.approval_threshold as u64 {
        proposal.status = EXECUTED_STATUS;
        let coin = coin::take(&mut wallet.sui, token_proposal.amount, ctx);
        transfer::public_transfer(coin, token_proposal.to);
        wallet.locked_balance -= token_proposal.amount;
    }
}

public entry fun reject_token_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext) {
    assert!(proposal_id < vector::length(&wallet.token_proposals), 11);
    let token_proposal = vector::borrow_mut(&mut wallet.token_proposals, proposal_id);

    let proposal = &mut token_proposal.proposal;
    let sender = tx_context.sender(ctx);
    assert!(vec_map::contains_key(&proposal.votes, &sender), 12);
    proposal.cancellation_votes += 1;
    vec_map::insert(&mut proposal.votes, sender, false);

    let total_members = vec_map::size(&wallet.members);
    if 100 * proposal.cancellation_votes / total_members > wallet.cancellation_threshold as u64 {
        proposal.status = CANCELLED_STATUS;
        wallet.locked_balance -= token_proposal.amount;
    }
}
 

}
