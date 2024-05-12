// SPDX-License-Identifier: Apache-2.0

module daowallet::DAOWallet{
  use std::vector;
  use std::string::{Self, String};

  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID};
  use sui::transfer;
  use sui::vec_map::{Self, VecMap};
  use sui::tx_context::{Self, TxContext};
  use sui::balance::{Self, Balance};
  use sui::sui::SUI;

  struct Wallet has key{
    id: UID,
    owner: address,
    name: String,
    description: String,
    approval_threshold: u8,
    cancellation_threshold: u8,
    sui:Balance<SUI>,
    lockedbalance: u64,
    members: VecMap<address, bool>,
    donation_nft_name: String,
    donation_nft_description: String,
    donation_nft_url: String,
    tokenProposals: vector<TokenProposal>,
    nftProposals: vector<NFTProposal>
  }

  struct Member has key{
    id: UID,
    wallet: object::ID,
  }

  const PendingStatus: u8 = 1;
  const ExecutedStatus: u8 = 2;
  const CancelledStatus: u8 = 3;

  struct Proposal has store {
    id: UID,
    creator: address,
    votes: VecMap<address, bool>,
    approval_votes: u64,
    cancellation_votes: u64,
    status: u8, //1: pending, 2: executed, 3: cancelled
  }

  struct TokenProposal has store {
    proposal: Proposal,
    to: address,
    amount: u64,
  }

  struct NFTProposal has store {
    proposal: Proposal,
    to: address,
    amount: u64,
  }

  struct Collectible has key, store {
        id: UID,
        name: String,
        description: String,
        image_url: String,
        creator: String,
    }

  

  public entry fun create_wallet(
    name:vector<u8>, description:vector<u8>, approval_threshold: u8, cancellation_threshold: u8, donation_nft_name: vector<u8>,
    donation_nft_description: vector<u8>, donation_nft_url: vector<u8>,
    ctx: &mut TxContext
    ) {

        let creator = tx_context::sender(ctx);
        // create multisig resource
        let wallet = Wallet {
            id: object::new(ctx),
            owner: creator,
            name: string::utf8(name),
            description: string::utf8(description),
            approval_threshold,
            cancellation_threshold,
            sui:balance::zero<SUI>(),
            lockedbalance: 0,
            members: vec_map::empty(),
            donation_nft_name: string::utf8(donation_nft_name),
            donation_nft_description: string::utf8(donation_nft_description),
            donation_nft_url: string::utf8(donation_nft_url),
            tokenProposals: vector::empty(),
            nftProposals: vector::empty(),
        };
        // while (!vector::is_empty(&participants)) {
        //     let participant = vector::pop_back(&mut participants);
        //     vec_map::insert(&mut wallet.participants, participant, true);
        // };

        transfer::transfer(Member {
          id: object::new(ctx),
          wallet: object::id(&wallet),
        },creator);

        vec_map::insert(&mut wallet.members, creator, true);
        transfer::share_object(wallet)
  }

  public entry fun add_member(wallet: &mut Wallet,new_member: address, ctx: &mut TxContext){
    vec_map::insert(&mut wallet.members, new_member, true);
    transfer::transfer(Member {
      id: object::new(ctx),
      wallet: object::id(wallet),
    },new_member);
  }

  public entry fun donate(wallet: &mut Wallet,sui: Coin<SUI>,ctx: &mut TxContext){
    coin::put(&mut wallet.sui, sui);
    let nft = Collectible {
      id: object::new(ctx),
      name: wallet.donation_nft_name,
      description: wallet.donation_nft_description,
      image_url: wallet.donation_nft_url,
      creator: wallet.name,
    };
    transfer::transfer(nft,tx_context::sender(ctx));
  }

  public entry fun create_token_praposal(wallet: &mut Wallet, to: address, amount: u64, ctx: &mut TxContext){
    let tokenProposal = TokenProposal {
      proposal: Proposal {
        id: object::new(ctx),
        creator: tx_context::sender(ctx),
        votes: vec_map::empty(),
        approval_votes:1,
        cancellation_votes:0,
        status: PendingStatus,
      },
      to: to,
      amount: amount,
    };
    wallet.lockedbalance = wallet.lockedbalance + amount;
    vec_map::insert(&mut tokenProposal.proposal.votes, tx_context::sender(ctx), true);
    vector::push_back(&mut wallet.tokenProposals, tokenProposal);
  }

  public entry fun approve_token_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext){
    assert!(proposal_id < vector::length(&mut wallet.tokenProposals),1);
    let tokenProposal = vector::borrow_mut(&mut wallet.tokenProposals, proposal_id);

    let proposal = &mut tokenProposal.proposal;
    let sender = tx_context::sender(ctx);
    // assert!(vec_map::contains(&proposal.votes,&sender),2);
    proposal.approval_votes = proposal.approval_votes + 1;
    vec_map::insert(&mut proposal.votes, tx_context::sender(ctx), true);

    let totalMembers = vec_map::size(&wallet.members);
    if (100 * proposal.approval_votes / totalMembers > (wallet.approval_threshold as u64)){
      proposal.status = ExecutedStatus;
      let coin = coin::take(&mut wallet.sui, tokenProposal.amount, ctx);
      transfer::public_transfer(coin, tokenProposal.to);
      wallet.lockedbalance = wallet.lockedbalance - tokenProposal.amount;
    }
  }

  public entry fun reject_token_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext){
    assert!(proposal_id < vector::length(&mut wallet.tokenProposals),1);
    let tokenProposal = vector::borrow_mut(&mut wallet.tokenProposals, proposal_id);

    let proposal = &mut tokenProposal.proposal;
    let sender = tx_context::sender(ctx);
    // assert!(vec_map::contains(&proposal.votes,&sender),2);
    proposal.cancellation_votes = proposal.cancellation_votes + 1;
    vec_map::insert(&mut proposal.votes, tx_context::sender(ctx), false);

    let totalMembers = vec_map::size(&wallet.members);
    if (100 * proposal.cancellation_votes / totalMembers > (wallet.cancellation_threshold as u64)){
      proposal.status = CancelledStatus;
      wallet.lockedbalance = wallet.lockedbalance - tokenProposal.amount;
    }
  }

}