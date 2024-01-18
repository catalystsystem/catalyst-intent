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

struct OrderContext {
    address claimer;
    uint256 sourceAssetsClaimed;
    address sourceAsset;
}

struct Signature {
    bytes32 r;
    bytes32 s;
    uint8 v;
}