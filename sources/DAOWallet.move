// SPDX-License-Identifier: Apache-2.0

module daowallet::DAOWallet {
    use std::vector;
    use std::string::{String, utf8};
    use sui::coin::Coin;
    use sui::object::{ID, new};
    use sui::transfer::{self, public_transfer};
    use sui::vec_map::{self, VecMap};
    use sui::tx_context::{self, TxContext};
    use sui::balance::Balance;
    use sui::sui::SUI;

    struct Wallet has key {
        id: ID,
        owner: address,
        name: String,
        description: String,
        approval_threshold: u8,
        cancellation_threshold: u8,
        sui_balance: Balance<SUI>,
        locked_balance: u64,
        members: VecMap<address, bool>,
        donation_nft_name: String,
        donation_nft_description: String,
        donation_nft_url: String,
        token_proposals: vector<TokenProposal>,
        nft_proposals: vector<NFTProposal>
    }

    struct Member has key {
        id: ID,
        wallet: object::ID,
    }

    const PENDING_STATUS: u8 = 1;
    const EXECUTED_STATUS: u8 = 2;
    const CANCELLED_STATUS: u8 = 3;

    struct Proposal has store {
        id: ID,
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
        id: ID,
        name: String,
        description: String,
        image_url: String,
        creator: String,
    }

    public entry fun create_wallet(
        name: vector<u8>, description: vector<u8>, approval_threshold: u8, cancellation_threshold: u8,
        donation_nft_name: vector<u8>, donation_nft_description: vector<u8>, donation_nft_url: vector<u8>,
        ctx: &mut TxContext
    ) {
        let creator = tx_context::sender(ctx);
        let wallet = Wallet {
            id: new(ctx),
            owner: creator,
            name: utf8(name),
            description: utf8(description),
            approval_threshold,
            cancellation_threshold,
            sui_balance: Balance::zero(),
            locked_balance: 0,
            members: VecMap::empty(),
            donation_nft_name: utf8(donation_nft_name),
            donation_nft_description: utf8(donation_nft_description),
            donation_nft_url: utf8(donation_nft_url),
            token_proposals: vector::empty(),
            nft_proposals: vector::empty(),
        };

        transfer::transfer(Member {
            id: new(ctx),
            wallet: object::id(&wallet),
        }, creator);

        vec_map::insert(&mut wallet.members, creator, true);
        transfer::share_object(wallet)
    }

    public entry fun add_member(wallet: &mut Wallet, new_member: address, ctx: &mut TxContext) {
        vec_map::insert(&mut wallet.members, new_member, true);
        transfer::transfer(Member {
            id: new(ctx),
            wallet: object::id(wallet),
        }, new_member);
    }

    public entry fun donate(wallet: &mut Wallet, sui: Coin<SUI>, ctx: &mut TxContext) {
        coin::put(&mut wallet.sui_balance, sui);
        let nft = Collectible {
            id: new(ctx),
            name: wallet.donation_nft_name.clone(),
            description: wallet.donation_nft_description.clone(),
            image_url: wallet.donation_nft_url.clone(),
            creator: wallet.name.clone(),
        };
        transfer::transfer(nft, tx_context::sender(ctx));
    }

    public entry fun create_token_proposal(wallet: &mut Wallet, to: address, amount: u64, ctx: &mut TxContext) {
        let token_proposal = TokenProposal {
            proposal: Proposal {
                id: new(ctx),
                creator: tx_context::sender(ctx),
                votes: VecMap::empty(),
                approval_votes: 1,
                cancellation_votes: 0,
                status: PENDING_STATUS,
            },
            to,
            amount,
        };
        wallet.locked_balance += amount;
        vec_map::insert(&mut token_proposal.proposal.votes, tx_context::sender(ctx), true);
        vector::push_back(&mut wallet.token_proposals, token_proposal);
    }

    public entry fun approve_token_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext) {
        assert!(proposal_id < vector::length(&mut wallet.token_proposals), 1);
        let token_proposal = vector::borrow_mut(&mut wallet.token_proposals, proposal_id);

        let proposal = &mut token_proposal.proposal;
        let sender = tx_context::sender(ctx);
        proposal.approval_votes += 1;
        vec_map::insert(&mut proposal.votes, sender, true);

        let total_members = vec_map::size(&wallet.members);
        if total_members > 0 {
            let approval_percentage = (100 * proposal.approval_votes) / total_members as u64;
            if approval_percentage > wallet.approval_threshold as u64 {
                proposal.status = EXECUTED_STATUS;
                let coin = coin::take(&mut wallet.sui_balance, token_proposal.amount, ctx);
                public_transfer(coin, token_proposal.to);
                wallet.locked_balance -= token_proposal.amount;
            }
        }
    }

    public entry fun reject_token_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext) {
        assert!(proposal_id < vector::length(&mut wallet.token_proposals), 1);
        let token_proposal = vector::borrow_mut(&mut wallet.token_proposals, proposal_id);

        let proposal = &mut token_proposal.proposal;
        let sender = tx_context::sender(ctx);
        proposal.cancellation_votes += 1;
        vec_map::insert(&mut proposal.votes, sender, false);

        let total_members = vec_map::size(&wallet.members);
        if total_members > 0 {
            let cancellation_percentage = (100 * proposal.cancellation_votes) / total_members as u64;
            if cancellation_percentage > wallet.cancellation_threshold as u64 {
                proposal.status = CANCELLED_STATUS;
                wallet.locked_balance -= token_proposal.amount;
            }
        }
    }
}
