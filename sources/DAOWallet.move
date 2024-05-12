// SPDX-License-Identifier: Apache-2.0

module daowallet::DAOWallet {
    use std::vector;
    use std::string::{Self, String};

    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::vec_map::{Self, VecMap};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::event;

    struct Wallet has key {
        id: UID,
        owner: address,
        name: String,
        description: String,
        approval_threshold: u8,
        cancellation_threshold: u8,
        sui: Balance<SUI>,
        locked_balance: u64,
        members: VecMap<address, bool>,
        donation_nft_name: String,
        donation_nft_description: String,
        donation_nft_url: String,
        token_proposals: vector<TokenProposal>,
        nft_proposals: vector<NFTProposal>
    }

    struct Member has key {
        id: UID,
        wallet: object::ID,
    }

    const PENDING_STATUS: u8 = 1;
    const EXECUTED_STATUS: u8 = 2;
    const CANCELLED_STATUS: u8 = 3;

    struct Proposal has store {
        id: UID,
        creator: address,
        votes: VecMap<address, bool>,
        approval_votes: u64,
        cancellation_votes: u64,
        status: u8, // 1: pending, 2: executed, 3: cancelled
    }

    struct TokenProposal has store {
        proposal: Proposal,
        to: address,
        amount: u64,
    }

    struct NFTProposal has store {
        proposal: Proposal,
        to: address,
        nft_id: UID,
    }

    struct Collectible has key, store {
        id: UID,
        name: String,
        description: String,
        image_url: String,
        creator: String,
    }

    struct CollectibleMinted has copy, drop {
      minter: address,
      collectible_id: UID,
    }

    struct TokenProposalExecuted has copy, drop {
      proposal_id: UID,
    }

    struct TokenProposalCancelled has copy, drop {
      proposal_id: UID,
    }

    struct NFTProposalExecuted has copy, drop {
      proposal_id: UID,
    }

    struct NFTProposalCancelled has copy, drop {
      proposal_id: UID,
    }

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
        let creator = tx_context::sender(ctx);
        // create multisig resource
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

        transfer::transfer(
            Member {
                id: object::new(ctx),
                wallet: object::id(&wallet),
            },
            creator
        );

        vec_map::insert(&mut wallet.members, creator, true);
        transfer::share_object(wallet);
    }

    public entry fun add_member(wallet: &mut Wallet, new_member: address, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == wallet.owner, 0);
        vec_map::insert(&mut wallet.members, new_member, true);
        transfer::transfer(
            Member {
                id: object::new(ctx),
                wallet: object::id(wallet),
            },
            new_member
        );
    }

    public entry fun donate(wallet: &mut Wallet, sui: Coin<SUI>, ctx: &mut TxContext) {
        coin::put(&mut wallet.sui, sui);
        let nft = Collectible {
            id: object::new(ctx),
            name: wallet.donation_nft_name,
            description: wallet.donation_nft_description,
            image_url: wallet.donation_nft_url,
            creator: wallet.name,
        };
        transfer::transfer(nft, tx_context::sender(ctx));
        event::emit(CollectibleMinted { minter: tx_context::sender(ctx), collectible_id: object::id(&nft) });
    }

    public entry fun create_token_proposal(
        wallet: &mut Wallet,
        to: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(amount <= balance::value(&wallet.sui), 0);
        let token_proposal = TokenProposal {
            proposal: Proposal {
                id: object::new(ctx),
                creator: tx_context::sender(ctx),
                votes: vec_map::empty(),
                approval_votes: 1,
                cancellation_votes: 0,
                status: PENDING_STATUS,
            },
            to,
            amount,
        };
        wallet.locked_balance = wallet.locked_balance + amount;
        vec_map::insert(&mut token_proposal.proposal.votes, tx_context::sender(ctx), true);
        vector::push_back(&mut wallet.token_proposals, token_proposal);
    }

    public entry fun approve_token_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext) {
        let token_proposal = vector::borrow_mut(&mut wallet.token_proposals, proposal_id);
        let proposal = &mut token_proposal.proposal;
        assert!(is_member(wallet, tx_context::sender(ctx)), 0);
        assert!(proposal.status == PENDING_STATUS, 1);
        assert!(!vec_map::contains(&proposal.votes, &tx_context::sender(ctx)), 2);

        proposal.approval_votes = proposal.approval_votes + 1;
        vec_map::insert(&mut proposal.votes, tx_context::sender(ctx), true);

        let total_members = vec_map::size(&wallet.members);
        if (100 * proposal.approval_votes / total_members > (wallet.approval_threshold as u64)) {
            proposal.status = EXECUTED_STATUS;
            let coin = coin::take(&mut wallet.sui, token_proposal.amount, ctx);
            transfer::public_transfer(coin, token_proposal.to);
            wallet.locked_balance = wallet.locked_balance - token_proposal.amount;
            event::emit(TokenProposalExecuted { proposal_id: object::id(&proposal) });
        }
    }

    public entry fun reject_token_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext) {
        let token_proposal = vector::borrow_mut(&mut wallet.token_proposals, proposal_id);
        let proposal = &mut token_proposal.proposal;
        assert!(is_member(wallet, tx_context::sender(ctx)), 0);
        assert!(proposal.status == PENDING_STATUS, 1);
        assert!(!vec_map::contains(&proposal.votes, &tx_context::sender(ctx)), 2);

        proposal.cancellation_votes = proposal.cancellation_votes + 1;
        vec_map::insert(&mut proposal.votes, tx_context::sender(ctx), false);

        let total_members = vec_map::size(&wallet.members);
        if (100 * proposal.cancellation_votes / total_members > (wallet.cancellation_threshold as u64)) {
            proposal.status = CANCELLED_STATUS;
            wallet.locked_balance = wallet.locked_balance - token_proposal.amount;
            event::emit(TokenProposalCancelled { proposal_id: object::id(&proposal) });
        }
    }

    public entry fun create_nft_proposal(
        wallet: &mut Wallet,
        to: address,
        nft_id: UID,
        ctx: &mut TxContext
    ) {
        assert!(object::owner_address(&id(nft_id)) == object::id(&wallet), 0);
        let nft_proposal = NFTProposal {
            proposal: Proposal {
                id: object::new(ctx),
                creator: tx_context::sender(ctx),
                votes: vec_map::empty(),
                approval_votes: 1,
                cancellation_votes: 0,
                status: PENDING_STATUS,
            },
            to,
            nft_id,
        };
        vec_map::insert(&mut nft_proposal.proposal.votes, tx_context::sender(ctx), true);
        vector::push_back(&mut wallet.nft_proposals, nft_proposal);
    }

    public entry fun approve_nft_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext) {
        let nft_proposal = vector::borrow_mut(&mut wallet.nft_proposals, proposal_id);
        let proposal = &mut nft_proposal.proposal;
        assert!(is_member(wallet, tx_context::sender(ctx)), 0);
        assert!(proposal.status == PENDING_STATUS, 1);
        assert!(!vec_map::contains(&proposal.votes, &tx_context::sender(ctx)), 2);

        proposal.approval_votes = proposal.approval_votes + 1;
        vec_map::insert(&mut proposal.votes, tx_context::sender(ctx), true);

        let total_members = vec_map::size(&wallet.members);
        if (100 * proposal.approval_votes / total_members > (wallet.approval_threshold as u64)) {
            proposal.status = EXECUTED_STATUS;
            transfer::public_transfer(object::remove<Collectible>(&mut nft_proposal.nft_id), nft_proposal.to);
            event::emit(NFTProposalExecuted { proposal_id: object::id(&proposal) });
        }
    }

    public entry fun reject_nft_proposal(wallet: &mut Wallet, proposal_id: u64, ctx: &mut TxContext) {
        let nft_proposal = vector::borrow_mut(&mut wallet.nft_proposals, proposal_id);
        let proposal = &mut nft_proposal.proposal;
        assert!(is_member(wallet, tx_context::sender(ctx)), 0);
        assert!(proposal.status == PENDING_STATUS, 1);
        assert!(!vec_map::contains(&proposal.votes, &tx_context::sender(ctx)), 2);

        proposal.cancellation_votes = proposal.cancellation_votes + 1;
        vec_map::insert(&mut proposal.votes, tx_context::sender(ctx), false);

        let total_members = vec_map::size(&wallet.members);
        if (100 * proposal.cancellation_votes / total_members > (wallet.cancellation_threshold as u64)) {
            proposal.status = CANCELLED_STATUS;
            event::emit(NFTProposalCancelled { proposal_id: object::id(&proposal) });
        }
    }

    public fun is_member(wallet: &Wallet, member: address): bool {
        vec_map::contains(&wallet.members, &member)
    }
}