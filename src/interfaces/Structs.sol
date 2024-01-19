// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

struct OrderDescription {
    bytes destinationAccount;
    bytes32 destinationChain;
    bytes destinationAsset;
    bytes32 sourceChain;
    address sourceAsset;
    uint256 minBond;
    uint64 timeout;
    address sourceEvaluationContract;
    bytes evaluationContext;
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

struct Signature {
    bytes32 r;
    bytes32 s;
    uint8 v;
}