// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

enum OrderStatus {
    Unfilled,
    Claimed,
    Filled,
    Challenged,
    Fraud
}


struct Asset {
    uint256 amount;
    address asset;
}

struct OrderFill {
    bytes32 orderHash;
    bytes32 sourceChain;
    bytes32 destinationChain;
    bytes destinationAccount;
    bytes destinationAsset;
    uint256 destinationAmount;
    uint64 timeout;
}

// Todo: compacting?
/// @param relevantDate Is used as the optimistic payout by date if disputed is false. If disputed is true it is the date when the proof has to be delivered by.
struct OrderContext {
    uint256 bond;
    uint256 sourceAmount;
    address sourceAsset;
    address orderOwner;
    address claimer;
    address disputer;
    uint64 relevantDate;
}

struct SignedOrder {
    bytes order;
    bytes signature;
}